//
//  F3SRunner.swift
//  F3SRunner
//
//  Created by Volker Runkel on 09.01.21.
//

import Foundation

class F3SRunner {
    enum TestMode: Int {
        case writeAndRead = 0
        case writeOnly = 1
        case readOnly = 2
    }

    private let toolBundle: Bundle
    private var mode: TestMode = .writeAndRead
        
    typealias F3SRunnerProgressHandler = ((F3SRunner) -> Void)
    
    enum F3SRunnerState : Int {
        case F3SRunnerStateWaiting
        case F3SRunnerStateWriting
        case F3SRunnerStateReading
        case F3SRunnerStateFailed
        case F3SRunnerStateFailedWriting
        case F3SRunnerStateFailedReading
        case F3SRunnerStateCancelled
        case F3SRunnerStateCompleted
    }
    
    var backgroundQueue = DispatchQueue.global(qos: .userInitiated)
    
    var writeTask: VRTask?
    var writeData: String?
    var readTask: VRTask?
    var readData: String?
    var results: F3STestResults?
    
    var state: F3SRunnerState? {
        didSet {
            if self.progressHandler != nil {
                DispatchQueue.main.async {
                    self.progressHandler!(self)
                }
            }
        }
    }
 
    deinit {
        print("Runner deinit")
    }
    
    init(toolBundle: Bundle = .main) {
        self.toolBundle = toolBundle
        self.progressFormatter.format = "x.xx%"
        self.progressFormatter.decimalSeparator = "."
    }
 
    static func runnerWithVolume(at: URL, progressHandler:@escaping F3SRunnerProgressHandler) -> F3SRunner? {
        let runner = F3SRunner()
        runner.volumeURL = at
        runner.progressHandler = progressHandler
        return runner
    }
    
    /*
     
     @property (nonatomic, strong) F3TestResults *results;
     @property (nonatomic, copy) F3SRunnerProgressHandler progressHandler;

     + (F3SRunner *)runnerWithVolumeAtURL:(NSURL *)url progressHandler:(F3SRunnerProgressHandler)handler;

     - (void)run;
     - (void)cancel;
     */
    
    var progressHandler: F3SRunnerProgressHandler?
    var volumeURL: URL?
    var volumeID: String?
    
    //var F3SRunnerState:
    var progress: Double = 0 {
        didSet {
            DispatchQueue.main.async {
                self.progressHandler!(self)
            }
        }
    }
    var progressFormatter = NumberFormatter()
    var info: Dictionary<String, String>?

    func run(mode: TestMode) {
        self.mode = mode
        self.results = nil
        self.writeData = nil
        self.readData = nil
        self.backgroundQueue.async {
            if mode != .readOnly {
                self.state = .F3SRunnerStateWriting
                self.runWriteTask()
            } else {
                self.state = .F3SRunnerStateReading
                self.runReadTask()
            }
        }
    }
    
    func cancel() {
        self.state = .F3SRunnerStateCancelled
        self.writeTask?.terminate()
        self.readTask?.terminate()
    }

    private func runWriteTask() {
        guard let cmdURL = toolBundle.url(forResource: "f3write", withExtension: nil) else {
            self.state = .F3SRunnerStateFailed
            return
        }
        self.writeTask = VRTask(executableURL: cmdURL)
        self.writeTask?.arguments = ["--show-progress=1", self.volumeURL!.path]
        self.writeData = String()
        self.writeTask!.setOutputHandler { [weak self] output in
            self?.writeData?.append(output)
            self?.parseProgressOutput(output: output)
        }

        if !(self.writeTask?.launch() ?? false) {
            self.state = .F3SRunnerStateFailed
            return
        }
        guard self.state != .F3SRunnerStateCancelled else { return }
        let output = self.writeData ?? ""
        guard self.writeTask?.terminationStatus == 0,
              !output.contains("NO DATA"),
              output.contains("Average writing speed:") || output.contains("Average sequential write speed:") else {
            self.state = .F3SRunnerStateFailedWriting
            return
        }
        self.finishedWriting()
    }
    
    func finishedWriting() {
        self.info = nil
        if self.mode == .writeOnly {
            self.progress = 100
            self.state = .F3SRunnerStateCompleted
            return
        }
        self.progress = 0
        self.state = .F3SRunnerStateReading
        self.runReadTask()
    }
    
    func runReadTask() {
        guard let cmdURL = toolBundle.url(forResource: "f3read", withExtension: nil) else {
            self.state = .F3SRunnerStateFailed
            return
        }
        self.readTask = VRTask(executableURL: cmdURL)
        self.readTask?.arguments = ["--show-progress=1", self.volumeURL!.path]
        self.readData = String()
        self.readTask!.setOutputHandler { [weak self] output in
            self?.readData?.append(output)
            self?.parseProgressOutput(output: output)
        }

        if !(self.readTask?.launch() ?? false) {
            self.state = .F3SRunnerStateFailed
            return
        }
        guard self.state != .F3SRunnerStateCancelled else { return }
        let output = self.readData ?? ""
        let hasSummary = output.contains("Average reading speed:") || output.contains("Average sequential read speed:")
        let hasNoData = output.contains("Reading speed not available") || output.contains("NO DATA")
        self.finishedReading(success: self.readTask?.terminationStatus == 0 && hasSummary && !hasNoData)
    }
    
    func finishedReading(success: Bool = true) {
        
        self.results = F3STestResults.testResultsWithRaw(writingData: self.writeData, readingData: self.readData)
        self.results!.volumeID = self.volumeID
        self.progress = 100
        if success {
            self.state = .F3SRunnerStateCompleted
        }
        else {
            self.state = .F3SRunnerStateFailedReading
        }
    }
    
    func parseProgressOutput(output: String) {
        let bs = String(UnicodeScalar(8))
        let cleanOutput1 = output.replacingOccurrences(of: bs, with: "")
        let cleanOutput = cleanOutput1.replacingOccurrences(of: " ", with: "")
        
        if cleanOutput.contains("Removing") {
            var info = Dictionary<String,String>()
            info.updateValue("removing", forKey: "removing")
            self.info = info
            self.progress = 0.0
            return
        }
        
        let components = cleanOutput.components(separatedBy: "--")
        let isValidProgressLine = [components.first?.range(of: "%", options: .caseInsensitive, range: nil, locale: nil)]
        
        if isValidProgressLine.count == 0 {
            return
        }
        
        var info = Dictionary<String,String>()
        if components.count >= 2 {
            info.updateValue(components[1], forKey: "speed")
        }
        if components.count >= 3 {
            info.updateValue(components[2], forKey: "eta")
        }
        self.info = info
        self.progress = (self.progressFormatter.number(from: components.first!)?.doubleValue ?? 0.0)
    }
    
}

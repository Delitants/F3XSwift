import Foundation

@main
struct TestModeTests {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let helpers = URL(fileURLWithPath: CommandLine.arguments[2])
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let bundleURL = root.appendingPathComponent("F3Tools.bundle")
        let resources = bundleURL.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.F3XSwift.ModeTests</string><key>CFBundlePackageType</key><string>BNDL</string></dict></plist>
        """.write(to: bundleURL.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
        let target = root.appendingPathComponent("target")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let eventsURL = target.appendingPathComponent("events.txt")
        func quoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        for name in ["f3write", "f3read"] {
            let args = name == "f3write" ? "--end-at=1 " : ""
            let script = "#!/bin/sh\nprintf '%s\\n' \(quoted(name)) >> \(quoted(eventsURL.path))\nexec \(quoted(helpers.appendingPathComponent(name).path)) \(args)\"$@\"\n"
            let path = resources.appendingPathComponent(name)
            try script.write(to: path, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        }
        guard let bundle = Bundle(url: bundleURL) else { fatalError("Cannot load tool bundle") }
        var failures = 0
        func check(_ name: String, _ passed: Bool) {
            print("\(passed ? "PASS" : "FAIL"): \(name)")
            if !passed { failures += 1 }
        }
        func run(_ mode: F3SRunner.TestMode, expectedState: F3SRunner.F3SRunnerState = .F3SRunnerStateCompleted) throws -> F3SRunner {
            try "".write(to: eventsURL, atomically: true, encoding: .utf8)
            let runner = F3SRunner(toolBundle: bundle)
            runner.volumeURL = target
            runner.progressHandler = { _ in }
            runner.run(mode: mode)
            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline {
                if let state = runner.state, [.F3SRunnerStateCompleted, .F3SRunnerStateFailed,
                    .F3SRunnerStateFailedReading, .F3SRunnerStateFailedWriting, .F3SRunnerStateCancelled].contains(state) { break }
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            check("\(mode) reaches expected terminal state", runner.state == expectedState)
            return runner
        }
        func events() throws -> [String] {
            try String(contentsOf: eventsURL, encoding: .utf8).split(separator: "\n").map(String.init)
        }

        // These tests run real F3 v10.0 against a bounded 1 GiB workspace file.
        let writer = try run(.writeOnly)
        check("write only launches only f3write", try events() == ["f3write"])
        check("write only leaves a test file", fm.fileExists(atPath: target.appendingPathComponent("1.h2w").path))
        check("write only never claims verified results", writer.results == nil)

        let fileURL = target.appendingPathComponent("1.h2w")
        let before = try fm.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
        let reader = try run(.readOnly)
        check("read only launches only f3read", try events() == ["f3read"])
        check("read only verifies existing test data", reader.results?.approved == true && reader.results?.data == "1.00")
        let after = try fm.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
        check("read only leaves test data unchanged", before == after)

        let full = try run(.writeAndRead)
        check("combined mode writes then reads", try events() == ["f3write", "f3read"])
        check("combined mode verifies data", full.results?.approved == true && full.results?.data == "1.00")

        try fm.removeItem(at: fileURL)
        let emptyReader = try run(.readOnly, expectedState: .F3SRunnerStateFailedReading)
        check("read only with no test files never runs writer", try events() == ["f3read"])
        check("missing test data is not approved", emptyReader.results?.approved != true)

        // A summary printed before a helper fails must not start the next phase.
        let failedWriterURL = resources.appendingPathComponent("f3write")
        try "#!/bin/sh\nprintf 'f3write\\n' >> \(quoted(eventsURL.path))\nprintf 'Average sequential write speed: 1 GB/s\\n'\nexit 23\n".write(to: failedWriterURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: failedWriterURL.path)
        let failedWriter = try run(.writeAndRead, expectedState: .F3SRunnerStateFailedWriting)
        check("failed write never starts reader", try events() == ["f3write"])
        check("failed write produces no verified result", failedWriter.results == nil)

        try "#!/bin/sh\nprintf 'f3write\\n' >> \(quoted(eventsURL.path))\nprintf 'Average sequential write speed: NO DATA\\n'\nexit 0\n".write(to: failedWriterURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: failedWriterURL.path)
        let emptyWriter = try run(.writeOnly, expectedState: .F3SRunnerStateFailedWriting)
        check("empty write never starts reader", try events() == ["f3write"])
        check("empty write produces no verified result", emptyWriter.results == nil)

        let largeSummary = """
          Data OK: 2.00 TB (4294967296 sectors)
        Data LOST: 0.00 Bytes (0 sectors)
                       Corrupted: 0.00 Bytes (0 sectors)
                Slightly changed: 0.00 Bytes (0 sectors)
                     Overwritten: 0.00 Bytes (0 sectors)
        Average sequential read speed: 500.00 MB/s
        """
        let largeResult = F3STestResults.testResultsWithRaw(writingData: nil, readingData: largeSummary)
        check("2 TiB summary with more than 32-bit sector count parses", largeResult.approved && largeResult.data == "2.00")
        let damagedSummary = largeSummary.replacingOccurrences(of: "Data LOST: 0.00 Bytes (0 sectors)", with: "Data LOST: 1.00 TB (2147483648 sectors)")
        let damagedResult = F3STestResults.testResultsWithRaw(writingData: nil, readingData: damagedSummary)
        check("large-drive data loss is not approved", !damagedResult.approved)
        print("Failures: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}

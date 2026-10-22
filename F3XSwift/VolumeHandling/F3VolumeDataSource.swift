//
//  F3VolumeDataSource.swift
//  F3XS
//
//  Created by Volker Runkel on 07.01.21.
//

import Foundation
import Cocoa
import DiskArbitration
import Combine

class F3VolumeDataSource: NSObject {
    
    let volumeURL = URL(fileURLWithPath: "/Volumes")
    
    var volumes: Array<F3Volume>?
    @objc dynamic var updated: Int = 0
    
    private var diskObservationSession: DASession?
    private var diskObservationQ: DispatchQueue?
    private var volumeChangeWorkItem: DispatchWorkItem?
    
    override init() {
        super.init()
        self.startObservingDisks()
    }

    static func isUsableVolume(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isVolumeKey, .volumeIsReadOnlyKey, .volumeIsLocalKey, .volumeIsInternalKey]) else {
            return false
        }
        // External SSDs commonly report volumeIsEjectable == false. Identify
        // external storage directly, and keep internal and network volumes out.
        return values.isVolume == true && values.volumeIsReadOnly == false
            && values.volumeIsLocal == true && values.volumeIsInternal == false
    }
    
    func fetchVolumes() {
        let volumeKeys = [URLResourceKey.isVolumeKey, URLResourceKey.isWritableKey, URLResourceKey.volumeIdentifierKey]
        let enumerationOptions : FileManager.DirectoryEnumerationOptions = [FileManager.DirectoryEnumerationOptions.skipsSubdirectoryDescendants , FileManager.DirectoryEnumerationOptions.skipsPackageDescendants , FileManager.DirectoryEnumerationOptions.skipsHiddenFiles]
        
        let enumerator = FileManager.default.enumerator(at: volumeURL, includingPropertiesForKeys: volumeKeys, options: enumerationOptions) { (anURL, error) -> Bool in
            Swift.print(error)
            return true
        }
        
        var url: URL?
        var volumes = Array<F3Volume>()
        url = enumerator?.nextObject() as? URL
        
        while url != nil {
            
            let isUsable = Self.isUsableVolume(at: url!)
            
            let volume : F3Volume = F3Volume(mountPoint: url!, _usable: isUsable, _volumeIdentifier: nil, attributes: nil)
            volumes.append(volume)
            url = enumerator?.nextObject() as? URL
        }
        self.volumes = volumes
        DispatchQueue.main.asyncAfter(deadline: .now()+0.5) {
            self.updated += 1
        }
    }
    
    let _volumeManagerDiskArbitrationCallback : @convention(c) (_ disk: DADisk, _ context: UnsafeMutableRawPointer?) -> Void = { (disk, context) in
        
        let mySelf = Unmanaged<F3VolumeDataSource>.fromOpaque(context!).takeUnretainedValue()
        
        if mySelf.volumeChangeWorkItem != nil {
            mySelf.volumeChangeWorkItem!.cancel()
        }
        
        mySelf.volumeChangeWorkItem = DispatchWorkItem(qos: DispatchQoS.background, flags: DispatchWorkItemFlags.inheritQoS) {
            DispatchQueue.main.asyncAfter(deadline: .now()+1.0) {
                let mySelf = Unmanaged<F3VolumeDataSource>.fromOpaque(context!).takeUnretainedValue()
                mySelf.fetchVolumes()
            }
        }
        
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now()+2.0, execute: mySelf.volumeChangeWorkItem!)
    }
    
    let _diskDescriptionChanged : @convention(c) (_ disk: DADisk, _ keys: CFArray, _ context: UnsafeMutableRawPointer?) -> Void = { (disk, keys, context) in
        let mySelf = Unmanaged<F3VolumeDataSource>.fromOpaque(context!).takeUnretainedValue()
        
        if mySelf.volumeChangeWorkItem != nil {
            mySelf.volumeChangeWorkItem!.cancel()
        }
        
        mySelf.volumeChangeWorkItem = DispatchWorkItem(qos: DispatchQoS.background, flags: DispatchWorkItemFlags.inheritQoS) {
            DispatchQueue.main.asyncAfter(deadline: .now()+1.0) {
                let mySelf = Unmanaged<F3VolumeDataSource>.fromOpaque(context!).takeUnretainedValue()
                mySelf.fetchVolumes()
            }
        }
        
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now()+1.0, execute: mySelf.volumeChangeWorkItem!)
    }
    
    private func startObservingDisks() {
        if self.diskObservationQ == nil || self.diskObservationSession == nil {
            self.diskObservationQ = DispatchQueue(label: "F3XS Disk Observation", qos: .background, attributes: .concurrent, autoreleaseFrequency: .inherit, target: nil)
            self.diskObservationSession = DASessionCreate(kCFAllocatorDefault)
            DASessionSetDispatchQueue(self.diskObservationSession!, self.diskObservationQ)
        }
        
        DARegisterDiskAppearedCallback(self.diskObservationSession!, nil, _volumeManagerDiskArbitrationCallback, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        DARegisterDiskDisappearedCallback(self.diskObservationSession!, nil, _volumeManagerDiskArbitrationCallback, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        
        let descriptionKeys = [kDADiskDescriptionVolumeNameKey]
        DARegisterDiskDescriptionChangedCallback(self.diskObservationSession!, nil, (descriptionKeys as CFArray), _diskDescriptionChanged, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        
    }
    
}

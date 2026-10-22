import Foundation

// Run with the production volume data source, model and results files.
// A writable external SSD that is not marked ejectable must be selectable.
@main
struct VolumeEligibilityTests {
    static func main() throws {
        var failures = 0
        func check(_ name: String, _ actual: Bool, _ expected: Bool) {
            print("\(actual == expected ? "PASS" : "FAIL"): \(name) (actual=\(actual), expected=\(expected))")
            if actual != expected { failures += 1 }
        }

        check("startup volume remains disabled", F3VolumeDataSource.isUsableVolume(at: URL(fileURLWithPath: "/")), false)
        check("ordinary directory remains disabled", F3VolumeDataSource.isUsableVolume(at: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)), false)
        check("missing volume remains disabled", F3VolumeDataSource.isUsableVolume(at: URL(fileURLWithPath: "/Volumes/F3XSwift-missing-volume-9ae358c4")), false)

        for path in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: path)
            let values = try url.resourceValues(forKeys: [.isVolumeKey, .volumeIsReadOnlyKey, .volumeIsLocalKey, .volumeIsInternalKey, .volumeIsEjectableKey])
            print("Volume metadata for \(path): \(values.allValues)")
            guard values.isVolume == true, values.volumeIsReadOnly == false,
                  values.volumeIsLocal == true, values.volumeIsInternal == false else {
                print("ERROR: requested SSD fixture is not a writable local external volume")
                exit(2)
            }
            check("writable external SSD is selectable: \(path)", F3VolumeDataSource.isUsableVolume(at: url), true)
        }
        print("Failures: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}

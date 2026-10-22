# Using F3XSwift SSD

1. Back up the selected drive. For a capacity check covering nearly all usable space, start with an empty volume.
2. Open F3XSwift SSD and select a mounted, writable external volume. Internal and network volumes remain unavailable.
3. Choose **Write + Read**, **Write only**, or **Read only** from the selector beside Test.
4. Press **Test** and grant access to that exact volume in the macOS file panel.
5. Keep the drive connected and the Mac awake until the selected steps finish.

**Write + Read** fills free space with numbered `.h2w` files, then verifies that the files contain the expected data.

**Write only** stops after writing. Its completion message does not certify capacity or data integrity. Leave the test files on the drive and select Read only when ready to verify them.

**Read only** reads existing `.h2w` files. It never starts `f3write` and cannot test previously unwritten free space. It reports failure if no test data is available.

The app does not erase or repartition the device, but a counterfeit drive can overwrite existing files when its true capacity is exceeded. F3 also replaces old numbered F3 test files during a new write run. Use a backup and choose the target carefully.

The engine supports 1 TB, 2 TB and larger volumes with 64-bit counters. Its 1 GiB file size is a file chunk, not the total test limit. Separate partitions are tested independently.

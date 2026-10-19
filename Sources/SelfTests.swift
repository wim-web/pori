import Foundation

func runSelfTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw TransferError(message: message) } }
    func rejects(_ operation: () throws -> Void, _ name: String) throws {
        do { try operation() } catch { return }
        throw TransferError(message: "Expected rejection: \(name)")
    }
    let raw: [[String: Any]] = [["Sid": 65537, "Info": ["StorageDescription": "Internal storage", "FreeSpaceInBytes": Int64(9_000_000_000)]]]
    let storages = try Storage.parse(raw)
    try check(storages.first?.id == 65537 && storages.first?.free == 9_000_000_000, "Storage schema / 64-bit size")
    let files = try RemoteFile.parse([["name": "動画.mp4", "path": "/動画.mp4", "size": Int64(5_000_000_000), "isFolder": false], ["name": "Download", "path": "/Download", "size": 0, "isFolder": true]])
    try check(files[0].isFolder && files[1].size == 5_000_000_000, "Directory ordering / large file")
    try check(try TransferRules.remotePath("/", "日本語 file.pdf") == "/日本語 file.pdf", "Unicode path")
    try rejects({ _ = try TransferRules.remotePath("/", "../escape") }, "Traversal")
    try rejects({ try TransferRules.verifyNoConflicts([["fullpath": "/a", "exists": true]], targets: ["/a"]) }, "Overwrite")
    try rejects({ try TransferRules.verifyNoConflicts([], targets: ["/a"]) }, "Missing collision response")
    try TransferRules.verifyNoConflicts([["fullpath": "/a", "exists": false]], targets: ["/a"])
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pori-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("日本語 ' $ file.txt")
    try Data("test".utf8).write(to: file)
    try TransferRules.validateUpload([file])
    let link = root.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    try rejects({ try TransferRules.validateUpload([link]) }, "Symlink")
    try rejects({ try TransferRules.validateUpload([root]) }, "Nested symlink")
    try rejects({ try TransferRules.validateUpload([file, file]) }, "Duplicate filenames")
    try MainActor.assumeIsolated {
        let model = AppModel()
        model.add([file])
        model.storages = [Storage(id: 65537, name: "Internal", free: 1000), Storage(id: 131073, name: "SD card", free: 1000)]
        model.storageID = 65537
        model.path = "/Download/Books"
        model.selectDestination(.android)
        try check(model.page == .android && model.destination == .android, "Android routes to folder workspace")
        try check(model.queue.count == 1 && model.destinationLabel == "Internal/Download/Books", "Queue retained alongside exact destination")
        model.selectPage(.send)
        try check(model.destination == .airdrop && model.queue.count == 1, "Returning to AirDrop cannot silently send over USB")
        model.selectPage(.android)
        model.storageID = 131073
        try check(model.destination == .android && model.destinationLabel == "SD card/Download/Books", "Storage is part of destination")
        try check(model.destinationFolderName == "Books", "Nested folder button label")
        model.path = "/"
        try check(model.destinationFolderName == "ストレージの先頭", "Root folder button label")
    }
}

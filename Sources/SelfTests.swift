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
    let files = try RemoteFile.parse([["name": "動画.mp4", "path": "/動画.mp4", "size": Int64(5_000_000_000), "isFolder": false, "objectId": 123], ["name": "Download", "path": "/Download", "size": 0, "isFolder": true]])
    try check(files[0].isFolder && files[1].size == 5_000_000_000, "Directory ordering / large file")
    try check(files[1].objectId == 123, "Decode object identity for move preflight")
    try check(try TransferRules.remotePath("/", "日本語 file.pdf") == "/日本語 file.pdf", "Unicode path")
    try rejects({ _ = try TransferRules.remotePath("/", "../escape") }, "Traversal")
    try rejects({ try TransferRules.verifyNoConflicts([["fullpath": "/a", "exists": true]], targets: ["/a"]) }, "Overwrite")
    try rejects({ try TransferRules.verifyNoConflicts([], targets: ["/a"]) }, "Missing collision response")
    try TransferRules.verifyNoConflicts([["fullpath": "/a", "exists": false]], targets: ["/a"])
    let deleteFiles = [RemoteFile(name: "日本語 ' $.txt", path: "/Download/日本語 ' $.txt", size: 10, isFolder: false), RemoteFile(name: "Folder", path: "/Download/Folder", size: 0, isFolder: true)]
    let deletion = try TransferRules.deletionTargets(Set(deleteFiles.map(\.path)), files: deleteFiles, parent: "/Download")
    try check(deletion.count == 2 && deletion[0].path == deleteFiles[0].path && deletion[1].isFolder, "Exact selected files and folders for deletion")
    try check(try TransferRules.editingPath("/Download", name: "日本語 folder") == "/Download/日本語 folder", "New folder remains under selected parent")
    for invalid in ["", "   ", ".", "..", "a/b", "a\\b", "line\nbreak", "null\0char"] {
        try rejects({ _ = try TransferRules.editingPath("/Download", name: invalid) }, "Invalid name")
    }
    try rejects({ _ = try TransferRules.editingPath("/Download/..", name: "x") }, "Unnormalized parent")
    for target in deleteFiles {
        try check(try TransferRules.renameTarget([target.path], files: deleteFiles, parent: "/Download").path == target.path, "Files and folders can be renamed")
    }
    try rejects({ _ = try TransferRules.renameTarget([], files: deleteFiles, parent: "/Download") }, "Empty rename selection")
    try rejects({ _ = try TransferRules.renameTarget(Set(deleteFiles.map(\.path)), files: deleteFiles, parent: "/Download") }, "Multiple rename selection")
    try rejects({ _ = try TransferRules.renameTarget([deleteFiles[0].path], files: deleteFiles, parent: "/Pictures") }, "Rename from wrong parent")
    let moving = [RemoteFile(name: "Folder", path: "/From/Folder", size: 0, isFolder: true, objectId: 11)]
    try TransferRules.validateMove(moving, from: "/From", to: "/To")
    try TransferRules.validateMove(moving, from: "/From", to: "/")
    for invalid in ["/From", "/From/Folder", "/From/Folder/Nested", "relative", "/To/../From"] {
        try rejects({ try TransferRules.validateMove(moving, from: "/From", to: invalid) }, "Invalid move destination")
    }
    try rejects({ try TransferRules.validateMove(deleteFiles, from: "/Download", to: "/To") }, "Missing object IDs")
    try rejects({ _ = try TransferRules.deletionTargets([], files: deleteFiles, parent: "/Download") }, "Empty deletion")
    try rejects({ _ = try TransferRules.deletionTargets(["/Download/missing"], files: deleteFiles, parent: "/Download") }, "Stale selection")
    try rejects({ _ = try TransferRules.deletionTargets([deleteFiles[0].path], files: deleteFiles, parent: "/Pictures") }, "Wrong parent")
    let rootTarget = RemoteFile(name: "..", path: "/", size: 0, isFolder: true)
    try rejects({ _ = try TransferRules.deletionTargets(["/"], files: [rootTarget], parent: "/") }, "Root deletion")
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

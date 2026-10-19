import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Page: String { case send, android, activity }
enum Destination { case android, airdrop }
struct Storage: Identifiable {
    let id: UInt32
    let name: String
    let free: Int64
    static func parse(_ raw: Any) throws -> [Storage] {
        guard let values = raw as? [[String: Any]] else { throw TransferError(message: "ストレージ情報を読み取れませんでした。") }
        return try values.map {
            guard let id = $0["Sid"] as? NSNumber, let info = $0["Info"] as? [String: Any] else { throw TransferError(message: "ストレージ情報が不正です。") }
            return Storage(id: id.uint32Value, name: info["StorageDescription"] as? String ?? "内部ストレージ", free: (info["FreeSpaceInBytes"] as? NSNumber)?.int64Value ?? 0)
        }
    }
}
struct RemoteFile: Identifiable, Decodable {
    let name: String
    let path: String
    let size: Int64
    let isFolder: Bool
    var id: String { path }
    var icon: String { isFolder ? "folder.fill" : fileIcon(name) }
    static func parse(_ raw: Any) throws -> [RemoteFile] {
        if raw is NSNull { return [] }
        let data = try JSONSerialization.data(withJSONObject: raw)
        let files = try JSONDecoder().decode([RemoteFile].self, from: data)
        return files.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
struct QueuedFile: Identifiable {
    let url: URL
    let size: Int64
    let folder: Bool
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var icon: String { folder ? "folder.fill" : fileIcon(name) }
}
struct Activity: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let success: Bool?
    let date = Date()
}
func fileIcon(_ name: String) -> String {
    let ext = (name as NSString).pathExtension.lowercased()
    if ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(ext) { return "photo" }
    if ["mov", "mp4", "mkv", "avi"].contains(ext) { return "film" }
    if ["mp3", "wav", "flac", "m4a"].contains(ext) { return "music.note" }
    if ["zip", "tar", "gz"].contains(ext) { return "doc.zipper" }
    return "doc.text"
}
func byteString(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

enum TransferRules {
    static func deletionTargets(_ selection: Set<String>, files: [RemoteFile], parent: String) throws -> [RemoteFile] {
        let targets = files.filter { selection.contains($0.id) }
        guard !selection.isEmpty, targets.count == selection.count,
              parent.hasPrefix("/"), (parent as NSString).standardizingPath == parent else {
            throw TransferError(message: "削除対象を確認できません。一覧を更新して選び直してください。")
        }
        for file in targets {
            guard file.path == (try remotePath(parent, file.name)) else {
                throw TransferError(message: "現在のフォルダ以外の項目は削除できません。")
            }
        }
        return targets
    }
    static func remotePath(_ parent: String, _ name: String) throws -> String {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else { throw TransferError(message: "扱えないファイル名です。") }
        return parent == "/" ? "/" + name : parent + "/" + name
    }
    static func validateUpload(_ urls: [URL]) throws {
        var names = Set<String>()
        for url in urls {
            guard names.insert(url.lastPathComponent).inserted else { throw TransferError(message: "同名のファイルが複数選ばれています。名前を変えてから送ってください。") }
            try validateItem(url)
            if (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
                var scanError: Error?
                guard let scan = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey], errorHandler: { _, error in scanError = error; return false }) else { throw TransferError(message: "フォルダを読み取れません。") }
                for case let child as URL in scan { try validateItem(child) }
                if let scanError { throw scanError }
            }
        }
    }
    private static func validateItem(_ url: URL) throws {
        let info = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
        guard info.isSymbolicLink != true, info.isRegularFile == true || info.isDirectory == true else { throw TransferError(message: "シンボリックリンクや特殊ファイルはUSB転送できません：\(url.lastPathComponent)") }
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw TransferError(message: "読み取り権限がありません：\(url.lastPathComponent)") }
    }
    static func verifyNoConflicts(_ raw: Any, targets: [String]) throws {
        guard let rows = raw as? [[String: Any]], rows.count == targets.count else { throw TransferError(message: "転送先の存在確認ができませんでした。") }
        var seen = Set<String>()
        for row in rows {
            guard let path = row["fullpath"] as? String, let exists = row["exists"] as? Bool, targets.contains(path), seen.insert(path).inserted else { throw TransferError(message: "転送先の確認結果が不正です。") }
            if exists { throw TransferError(message: "転送先に同名の項目があります：\((path as NSString).lastPathComponent)\n名前を変えるか、別のフォルダを選んでください。") }
        }
    }
}

@MainActor final class AppModel: ObservableObject {
    @Published var page: Page = .send
    @Published var destination: Destination = .airdrop
    @Published var queue: [QueuedFile] = []
    @Published var activities: [Activity] = []
    @Published var connected = false
    @Published var deviceName = "Android"
    @Published var storages: [Storage] = []
    @Published var storageID: UInt32 = 0
    @Published var path = "/"
    @Published var files: [RemoteFile] = []
    @Published var selectedRemote = Set<String>()
    @Published var search = ""
    @Published var busyUSB = false
    @Published var busyAirDrop = false
    @Published var transferring = false
    @Published var deleting = false
    @Published var confirmingDeletion = false
    @Published var progress: Double?
    @Published var progressText = ""
    @Published var status = "ファイルを追加して、送り先を選んでください。"
    @Published var errorMessage: String?
    @Published var showError = false
    let backend = MTPBackend()
    let airDrop = AirDropSender()
    private var cancelRequested = false
    var busy: Bool { busyUSB || busyAirDrop || confirmingDeletion }
    var selectedStorage: Storage? { storages.first { $0.id == storageID } }
    var filteredFiles: [RemoteFile] { search.isEmpty ? files : files.filter { $0.name.localizedCaseInsensitiveContains(search) } }
    var destinationFolderName: String { path == "/" ? "ストレージの先頭" : (path as NSString).lastPathComponent }
    var destinationLabel: String { "\(selectedStorage?.name ?? "Android")\(path)" }

    func selectPage(_ next: Page) {
        page = next
        if next == .android { destination = .android }
        if next == .send { destination = .airdrop }
    }
    func selectDestination(_ target: Destination) {
        destination = target
        page = target == .android ? .android : .send
    }

    init() {
        backend.onProgress = { [weak self] data in
            guard let self else { return }
            if let name = data["name"] as? String { self.progressText = name }
            if let bulk = data["bulkFileSize"] as? [String: Any], let total = bulk["total"] as? NSNumber, total.doubleValue > 0,
               let sent = bulk["sent"] as? NSNumber {
                self.progress = min(1, max(0, sent.doubleValue / total.doubleValue))
            }
        }
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
    func record(_ title: String, _ detail: String, success: Bool?) {
        activities.insert(Activity(title: title, detail: detail, success: success), at: 0)
        activities = Array(activities.prefix(50))
    }
    func chooseFiles() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "送るファイルを選択"
        panel.prompt = "追加"
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { add(panel.urls) }
    }
    func add(_ urls: [URL]) {
        guard !busy else { return }
        do {
            var additions: [QueuedFile] = []
            for url in urls where url.isFileURL {
                let url = url.standardizedFileURL
                guard !queue.contains(where: { $0.url == url }), !additions.contains(where: { $0.url == url }) else { continue }
                let info = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                additions.append(QueuedFile(url: url, size: Int64(info.fileSize ?? 0), folder: info.isDirectory == true))
            }
            queue += additions
            if !additions.isEmpty { status = "\(queue.count)項目を送る準備ができました。" }
        } catch { report(error) }
    }
    func receiveDrop(_ providers: [NSItemProvider], target: Destination? = nil) -> Bool {
        guard !busy else { return false }
        let dropDestination = target ?? (page == .android ? .android : .airdrop)
        let accepted = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !accepted.isEmpty else { return false }
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in accepted {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let value = item as? URL { url = value }
                else { url = nil }
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self, !self.busy else { return }
            self.selectDestination(dropDestination)
            self.add(urls)
        }
        return true
    }

    func send() {
        guard !queue.isEmpty, !busy else { return }
        if destination == .airdrop { sendAirDrop() } else { upload() }
    }
    func sendToAndroid() {
        guard !queue.isEmpty, !busy else { return }
        selectDestination(.android)
        upload()
    }
    private func sendAirDrop() {
        let urls = queue.map(\.url)
        guard urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            report(TransferError(message: "移動または削除されたファイルがあります。追加し直してください。")); return
        }
        busyAirDrop = true
        status = "AirDropの画面で送り先を選んでください。"
        airDrop.send(urls) { [weak self] result in
            guard let self else { return }
            self.busyAirDrop = false
            switch result {
            case .success:
                // macOS can call didShareItems after cancelling its AirDrop panel.
                // This callback is not proof of delivery; retain the queue.
                self.status = "AirDrop画面を閉じました。受信結果は送り先の端末で確認してください。"
                self.record("AirDrop画面を表示", "\(urls.count)項目 · 受信完了はこのアプリでは確認できません", success: nil)
            case .failure(let error):
                let e = error as NSError
                if e.code == NSUserCancelledError || e.code == -128 {
                    self.status = "AirDropをキャンセルしました。"
                } else {
                    self.status = "AirDropの送信が完了しませんでした。"
                    self.record("AirDrop未完了", error.localizedDescription, success: false)
                    self.report(error)
                }
            }
        }
    }

    func connect() {
        guard !busy else { return }
        busyUSB = true
        status = "Androidに接続しています…"
        backend.stop()
        Task {
            defer { busyUSB = false }
            do {
                let raw = try await backend.call("connect")
                let info = (raw as? [String: Any])?["mtpDeviceInfo"] as? [String: Any]
                deviceName = info?["Model"] as? String ?? "Android"
                let newStorages = try Storage.parse(try await backend.call("storages"))
                guard let first = newStorages.first else { throw TransferError(message: "ストレージが見つかりません。端末のロックを解除してください。") }
                storages = newStorages
                storageID = first.id
                path = "/"
                try await loadFolder()
                connected = true
                status = "\(deviceName)に接続しました。"
            } catch { resetUSB(); status = "Androidに接続できませんでした。"; report(error) }
        }
    }
    func disconnect() {
        guard !busy else { return }
        busyUSB = true
        Task {
            _ = try? await backend.call("disconnect")
            resetUSB()
            busyUSB = false
            status = "Androidとの接続を解除しました。"
        }
    }
    func resetUSB() {
        backend.stop()
        connected = false
        files = []
        storages = []
        selectedRemote = []
        storageID = 0
        path = "/"
    }
    private func loadFolder() async throws {
        let raw = try await backend.call("list", ["storageId": storageID, "fullPath": path, "recursive": false, "skipHiddenFiles": false, "skipDisallowedFiles": false])
        files = try RemoteFile.parse(raw)
        selectedRemote = []
    }
    func browse(_ nextPath: String? = nil, storage: UInt32? = nil) {
        guard connected, !busy else { return }
        busyUSB = true
        if let storage { storageID = storage; path = "/" }
        if let nextPath { path = nextPath }
        search = ""
        Task {
            defer { busyUSB = false }
            do { try await loadFolder(); status = "\(files.count)項目" }
            catch { resetUSB(); status = "再接続が必要です。"; report(error) }
        }
    }
    func up() { browse(path == "/" ? "/" : (path as NSString).deletingLastPathComponent) }

    func confirmDeletion(_ selection: Set<String>? = nil) {
        guard connected, !busy else { return }
        let targets: [RemoteFile]
        do { targets = try TransferRules.deletionTargets(selection ?? selectedRemote, files: files, parent: path) }
        catch { report(error); return }
        let sourceStorageID = storageID
        let sourcePath = path
        let sourceDescription = destinationLabel
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = targets.count == 1 ? "「\(targets[0].name)」を削除しますか？" : "\(targets.count)項目をAndroidから削除しますか？"
        alert.informativeText = "\(deviceName) · \(sourceDescription)\n\nゴミ箱には入りません。削除すると元に戻せません。" + (targets.contains(where: \.isFolder) ? "フォルダの中身も削除されます。" : "")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: CGFloat(min(180, max(60, targets.count * 22)))))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: CGFloat(max(60, targets.count * 22))))
        text.string = targets.map(\.path).joined(separator: "\n")
        text.isEditable = false
        text.isSelectable = true
        text.font = .systemFont(ofSize: 12)
        text.textContainerInset = NSSize(width: 7, height: 7)
        text.autoresizingMask = [.width]
        scroll.documentView = text
        alert.accessoryView = scroll
        alert.addButton(withTitle: "キャンセル")
        alert.addButton(withTitle: "削除する")
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = ""
        alert.buttons[1].hasDestructiveAction = true
        confirmingDeletion = true
        let response = alert.runModal()
        confirmingDeletion = false
        guard response == .alertSecondButtonReturn else { return }
        guard connected, !busy, storageID == sourceStorageID, path == sourcePath else {
            report(TransferError(message: "接続先が変わりました。削除対象を選び直してください。")); return
        }
        busyUSB = true
        deleting = true
        status = "\(targets.count)項目を削除しています…"
        Task {
            defer { busyUSB = false; deleting = false }
            let requestedPaths = Set(targets.map(\.path))
            do {
                let result = try await backend.call("delete", ["storageId": sourceStorageID, "Files": targets.map(\.path)])
                guard result as? Bool == true else { throw TransferError(message: "削除結果を確認できませんでした。") }
                // Some MTP engines return success before processing every requested item.
                // Re-read the directory before reporting completion; never retry deletion automatically.
                try await loadFolder()
                let remaining = requestedPaths.intersection(files.map(\.path))
                guard remaining.isEmpty else { throw TransferError(message: "\(remaining.count)項目が残っています。一覧を確認してください。") }
                status = "\(targets.count)項目をAndroidから削除しました。"
                record("Androidから削除", "\(targets.count)項目 · \(sourceDescription)", success: true)
            } catch {
                let failure = error.localizedDescription
                do { try await loadFolder() } catch { resetUSB() }
                status = "削除の完了を確認できませんでした。"
                record("削除結果の確認が必要", "\(sourceDescription) · 一部が削除されている可能性があります。", success: false)
                report(TransferError(message: "\(failure)\n\n一部の項目が削除されている可能性があります。再実行する前に一覧を確認してください。"))
            }
        }
    }

    private func upload() {
        guard connected else { report(TransferError(message: "先にAndroidへUSB接続してください。")); return }
        let urls = queue.map(\.url)
        let destinationPath = path
        let destinationStorageID = storageID
        let destinationDescription = destinationLabel
        busyUSB = true
        cancelRequested = false
        transferring = true
        progress = nil
        progressText = "転送先を確認しています…"
        Task {
            defer { busyUSB = false; transferring = false; progress = nil }
            var writing = false
            do {
                // Validate folders off the UI thread; never follow symbolic links.
                try await Task.detached { try TransferRules.validateUpload(urls) }.value
                guard !cancelRequested else { throw TransferError(message: "送信を中止しました。") }
                let targets = try urls.map { try TransferRules.remotePath(destinationPath, $0.lastPathComponent) }
                let existing = try await backend.call("exists", ["storageId": destinationStorageID, "Files": targets])
                try TransferRules.verifyNoConflicts(existing, targets: targets)
                guard !cancelRequested else { throw TransferError(message: "送信を中止しました。") }
                writing = true
                status = "Androidへ送信しています…"
                _ = try await backend.call("upload", ["storageId": destinationStorageID, "sources": urls.map(\.path), "destination": destinationPath, "preprocessFiles": true])
                queue.removeAll { urls.contains($0.url) }
                record("Androidへ送信", "\(urls.count)項目 → \(destinationDescription)", success: true)
                status = "\(urls.count)項目を\(destinationDescription)に送りました。"
                // A refresh failure must not turn an already completed transfer into a failed one.
                do { try await loadFolder() }
                catch {
                    resetUSB()
                    status = "送信は完了しました。一覧を更新するには再接続してください。"
                    report(error)
                }
            } catch {
                if writing {
                    record("USB送信未完了", "転送途中のファイルが残る場合があります。", success: false)
                    resetUSB()
                }
                status = "送信を完了できませんでした。"
                report(error)
            }
        }
    }

    func download() {
        guard connected, !busy else { return }
        let selection = files.filter { selectedRemote.contains($0.id) }
        guard !selection.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.title = "Macの保存先を選択"
        panel.message = "選んだ場所に新しいPoriフォルダを作って保存します。"
        panel.prompt = "ここに保存"
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"
        let dest = parent.appendingPathComponent("Pori-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(4))", isDirectory: true)
        busyUSB = true
        transferring = true
        progress = nil
        progressText = "保存の準備をしています…"
        Task {
            defer { busyUSB = false; transferring = false; progress = nil }
            do {
                try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false)
                _ = try await backend.call("download", ["storageId": storageID, "sources": selection.map(\.path), "destination": dest.path, "preprocessFiles": true])
                status = "\(selection.count)項目をMacに保存しました。"
                record("Macに保存", "\(selection.count)項目 → \(dest.lastPathComponent)", success: true)
                NSWorkspace.shared.activateFileViewerSelecting([dest])
            } catch {
                record("USB保存未完了", "\(dest.lastPathComponent)に転送途中のファイルが残る場合があります。", success: false)
                resetUSB()
                status = "保存を完了できませんでした。"
                report(error)
            }
        }
    }
    func cancel() { cancelRequested = true; resetUSB() }
}

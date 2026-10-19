import AppKit
import Foundation

struct TransferError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor final class MTPBackend {
    private var process: Process?
    private var input: FileHandle?
    private var nextID = 0
    private var pending: CheckedContinuation<Any, Error>?
    private var pendingID = 0
    private var timeout: DispatchWorkItem?
    private var timeoutSeconds: Double = 30
    private var generation = UUID()
    var onProgress: (([String: Any]) -> Void)?

    private func start() throws {
        if process?.isRunning == true { return }
        let bundle = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = bundle.appendingPathComponent("Contents/MacOS/mtp-helper")
        task.arguments = [bundle.appendingPathComponent("Contents/Frameworks/kalam.dylib").path]
        let stdin = Pipe(), stdout = Pipe()
        task.standardInput = stdin
        task.standardOutput = stdout
        task.standardError = FileHandle.nullDevice
        generation = UUID()
        let run = generation
        try task.run()
        process = task
        input = stdin.fileHandleForWriting
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let handle = stdout.fileHandleForReading
            var buffer = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let end = buffer.firstIndex(of: 10) {
                    let line = Data(buffer[..<end])
                    buffer.removeSubrange(...end)
                    DispatchQueue.main.async { self?.receive(line, run: run) }
                }
            }
            DispatchQueue.main.async {
                guard let self, self.generation == run else { return }
                self.stop(reason: "USB接続が終了しました。端末を確認して再接続してください。")
            }
        }
    }

    func call(_ command: String, _ payload: [String: Any] = [:]) async throws -> Any {
        guard pending == nil else { throw TransferError(message: "ほかのUSB操作が進行中です。") }
        try start()
        nextID += 1
        pendingID = nextID
        timeoutSeconds = ["upload", "download", "delete"].contains(command) ? 120 : 30
        var bytes = try JSONSerialization.data(withJSONObject: ["id": nextID, "command": command, "payload": payload])
        bytes.append(10)
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            armTimeout()
            do { try input?.write(contentsOf: bytes) }
            catch { stop(reason: "転送エンジンに接続できませんでした。") }
        }
    }

    private func armTimeout() {
        timeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.stop(reason: "端末からの応答がありません。ロック解除とUSB設定を確認して再接続してください。")
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: work)
    }

    private func receive(_ data: Data, run: UUID) {
        guard run == generation,
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              message["id"] as? Int == pendingID, pending != nil,
              let result = message["result"] as? [String: Any] else { return }
        armTimeout()
        if message["event"] as? String != "done" {
            if let info = result["data"] as? [String: Any] { onProgress?(info) }
            return
        }
        timeout?.cancel()
        let continuation = pending
        pending = nil
        if let error = result["error"] as? String, !error.isEmpty {
            continuation?.resume(throwing: TransferError(message: Self.friendlyError(result["errorType"] as? String ?? "", detail: error)))
        } else {
            continuation?.resume(returning: result["data"] ?? NSNull())
        }
    }

    static func friendlyError(_ kind: String, detail: String) -> String {
        switch kind {
        case "ErrorMtpDetectFailed": return "Androidが見つかりません。USBで接続し、端末のUSB設定を「ファイル転送」にしてください。OpenMTPなどほかの転送アプリは終了してください。"
        case "ErrorMultipleDevice": return "Androidは1台ずつ接続してください。"
        case "ErrorAllowStorageAccess", "ErrorDeviceLocked", "ErrorDeviceSetup", "ErrorNoStorage": return "Androidのロックを解除し、USBの「ファイル転送」を許可してください。ほかの転送アプリが開いている場合は終了してください。"
        case "ErrorDeviceChanged": return "接続端末が変わりました。再接続してください。"
        case "ErrorStorageFull": return "Androidの空き容量が不足しています。"
        default: return "USB操作に失敗しました。\n\(detail)"
        }
    }

    func stop(reason: String = "操作を中止しました。転送途中のファイルが残る場合があります。") {
        timeout?.cancel()
        generation = UUID()
        let old = process
        process = nil
        try? input?.close()
        input = nil
        if old?.isRunning == true {
            old?.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if let old, old.isRunning { kill(old.processIdentifier, SIGKILL) }
            }
        }
        let continuation = pending
        pending = nil
        continuation?.resume(throwing: TransferError(message: reason))
    }
}

@MainActor final class AirDropSender: NSObject, NSSharingServiceDelegate {
    private var service: NSSharingService?
    private var completion: ((Result<Void, Error>) -> Void)?
    var isPresenting: Bool { service != nil }

    func send(_ urls: [URL], completion: @escaping (Result<Void, Error>) -> Void) {
        guard service == nil else { return }
        guard let next = NSSharingService(named: .sendViaAirDrop), next.canPerform(withItems: urls) else {
            completion(.failure(TransferError(message: "このMacではAirDropを利用できません。Wi-FiとBluetoothを確認してください。")))
            return
        }
        self.completion = completion
        service = next
        next.delegate = self
        next.perform(withItems: urls)
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { finish(.success(())) }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) { finish(.failure(error)) }
    func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any], sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible })
    }
    private func finish(_ result: Result<Void, Error>) {
        let callback = completion
        completion = nil
        service = nil
        callback?(result)
    }
}

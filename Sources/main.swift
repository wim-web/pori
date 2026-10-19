import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMenus()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1050, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Pori"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.setFrameAutosaveName("PoriMainWindow")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--file"), args.indices.contains(i + 1) { model.add([URL(fileURLWithPath: args[i + 1])]) }
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) { model.add(filenames.map { URL(fileURLWithPath: $0) }); window?.makeKeyAndOrderFront(nil); sender.reply(toOpenOrPrint: .success) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window?.makeKeyAndOrderFront(nil); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.transferring || model.deleting {
            let alert = NSAlert()
            alert.messageText = model.deleting ? "削除処理中に終了しますか？" : "転送を中止して終了しますか？"
            alert.informativeText = model.deleting ? "一部の項目がすでに削除されている可能性があります。" : "転送途中のファイルが残る場合があります。"
            alert.addButton(withTitle: model.deleting ? "処理を続ける" : "転送を続ける")
            alert.addButton(withTitle: "中止して終了")
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
        }
        model.backend.stop()
        return .terminateNow
    }
    private func setupMenus() {
        let menu = NSMenu()
        let app = NSMenuItem(); menu.addItem(app)
        let appMenu = NSMenu(); app.submenu = appMenu
        let about = NSMenuItem(title: "Poriについて", action: #selector(showAbout), keyEquivalent: ""); about.target = self; appMenu.addItem(about)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Poriを隠す", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Poriを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = NSMenuItem(); menu.addItem(file); let fileMenu = NSMenu(title: "ファイル"); file.submenu = fileMenu
        let add = NSMenuItem(title: "ファイルを追加…", action: #selector(addFiles), keyEquivalent: "o"); add.target = self; fileMenu.addItem(add)
        fileMenu.addItem(withTitle: "ウインドウを閉じる", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let edit = NSMenuItem(); menu.addItem(edit); let editMenu = NSMenu(title: "編集"); edit.submenu = editMenu
        for (title, action, key) in [("取り消す", "undo:", "z"), ("カット", "cut:", "x"), ("コピー", "copy:", "c"), ("ペースト", "paste:", "v"), ("すべて選択", "selectAll:", "a")] { editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }
        NSApp.mainMenu = menu
    }
    @objc private func addFiles() { model.chooseFiles() }
    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Pori", .applicationVersion: "0.1.0", .credits: NSAttributedString(string: "Macとデバイスの間を、すっと。\nUSB engine: OpenMTP / Kalam (MIT)\nlibusb (LGPL-2.1+)\nライセンスはアプリ内Resources/Licensesに同梱。")])
    }
}

if CommandLine.arguments.contains("--self-test") {
    do { try runSelfTests(); print("All self-tests passed"); exit(0) }
    catch { fputs("Self-test failed: \(error)\n", stderr); exit(1) }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}

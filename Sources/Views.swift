import SwiftUI
import UniformTypeIdentifiers

private let poriTint = Color(nsColor: NSColor(name: "PoriAccent", dynamicProvider: { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 0.40, green: 0.76, blue: 0.67, alpha: 1)
        : NSColor(srgbRed: 0.12, green: 0.48, blue: 0.43, alpha: 1)
}))

struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 208)
            Divider()
            VStack(spacing: 0) {
                Group {
                    switch model.page {
                    case .send: SendView(model: model)
                    case .android: AndroidView(model: model)
                    case .activity: ActivityView(model: model)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(poriTint)
        .frame(minWidth: 880, minHeight: 650)
        .alert("確認してください", isPresented: $model.showError) {
            Button("閉じる", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.right.circle.fill").font(.system(size: 29)).foregroundStyle(poriTint)
                Text("Pori").font(.system(size: 25, weight: .semibold, design: .rounded))
            }.padding(.bottom, 34)
            Text("ライブラリ").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 9)
            nav("iPhone / AirDrop", icon: "paperplane", page: .send)
            nav("転送の履歴", icon: "clock", page: .activity)
            Text("デバイス").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 28).padding(.bottom, 9)
            nav("Androidと転送", icon: "smartphone", page: .android)
            HStack(spacing: 6) {
                Circle().fill(model.connected ? poriTint : Color.secondary.opacity(0.4)).frame(width: 5, height: 5)
                Text(model.connected ? model.deviceName : "USB未接続").lineLimit(1)
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 38).padding(.top, 5)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                Text("端末から端末へ")
            }.font(.system(size: 11)).foregroundStyle(.secondary)
            Text("Pori 0.1 · プレビュー版").font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 8)
        }.padding(.horizontal, 16).padding(.top, 58).padding(.bottom, 24).background(SidebarMaterial())
    }
    private func nav(_ title: String, icon: String, page: Page) -> some View {
        Button { model.selectPage(page) } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).frame(width: 17)
                Text(title).font(.system(size: 12, weight: model.page == page ? .semibold : .regular)).lineLimit(1)
                Spacer()
                if page == model.page && page != .activity && !model.queue.isEmpty { Text("\(model.queue.count)").font(.system(size: 10)).padding(.horizontal, 6).padding(.vertical, 2).background(.primary.opacity(0.07), in: Capsule()) }
            }.padding(.horizontal, 10).padding(.vertical, 11)
                .foregroundStyle(model.page == page ? poriTint : .primary)
                .background(model.page == page ? poriTint.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.bottom, 3)
    }
    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                if model.busyUSB || model.busyAirDrop { ProgressView().controlSize(.small).scaleEffect(0.7) }
                else { Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(poriTint) }
                Text(model.status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 8)
                if model.busyUSB && !model.transferring { Button("中止") { model.cancel() }.controlSize(.small) }
            }.padding(.horizontal, 26).padding(.vertical, 13)
        }
    }
}

struct PageHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow).font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(poriTint)
            Text(title).font(.system(size: 27, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

struct SendView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            PageHeading(eyebrow: "TRANSFER", title: "ファイルを送る", subtitle: "Macから、手元のデバイスへ。")
            HStack(spacing: 14) {
                destinationCard(.android, name: model.connected ? model.deviceName : "Android", icon: "smartphone", method: "USB", detail: model.connected ? "接続済み · \(model.selectedStorage?.name ?? "")" : "ケーブルでつないで転送")
                destinationCard(.airdrop, name: "iPhone / iPad", icon: "airplayvideo", method: "AirDrop", detail: "送信時に近くのデバイスを選択")
            }
            FileQueueView(model: model, target: .airdrop)
            bottom
        }.padding(.horizontal, 34).padding(.top, 56).padding(.bottom, 24)
    }

    private func destinationCard(_ target: Destination, name: String, icon: String, method: String, detail: String) -> some View {
        let selected = model.destination == target
        return Button { model.selectDestination(target) } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: icon).font(.system(size: 24, weight: .light)).foregroundStyle(selected ? poriTint : .secondary)
                    Spacer()
                    Text(method).font(.system(size: 9, weight: .semibold)).padding(.horizontal, 7).padding(.vertical, 3).background(.primary.opacity(0.05), in: Capsule())
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? poriTint : Color.secondary.opacity(0.35))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? poriTint.opacity(0.055) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? poriTint.opacity(0.7) : Color.primary.opacity(0.09), lineWidth: selected ? 1.5 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).disabled(model.busy)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { model.receiveDrop($0, target: target) }
    }
    private var bottom: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("次にAirDropの選択画面が開きます").font(.system(size: 11, weight: .medium))
                Text("iPhone側へのアプリ追加は不要です").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.send() } label: { Label("AirDropを開く", systemImage: "arrow.up.right") }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.queue.isEmpty || model.busy)
        }
    }
}

struct FileQueueView: View {
    @ObservedObject var model: AppModel
    let target: Destination
    var compact = false
    @State private var dropTargeted = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(compact ? "Macから送るファイル" : "送るファイル").font(.system(size: 12, weight: .semibold)).lineLimit(1).layoutPriority(1)
                if !model.queue.isEmpty { Text("\(model.queue.count)項目").font(.system(size: 11)).foregroundStyle(.secondary) }
                Spacer()
                if !compact && !model.queue.isEmpty {
                    Button("すべて外す") { model.queue.removeAll() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary).disabled(model.busy)
                }
            }.padding(16)
            Divider()
            if model.queue.isEmpty {
                VStack(spacing: 11) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: compact ? 26 : 33, weight: .light)).foregroundStyle(poriTint).padding(.bottom, 3)
                    Text(compact ? "ここにドロップ" : "ここにファイルをドロップ").font(.system(size: compact ? 13 : 15, weight: .medium))
                    Text(compact ? "ファイル・フォルダを追加" : "フォルダもまとめて追加できます").font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("ファイルを選ぶ") { model.chooseFiles() }.controlSize(.large).padding(.top, 4).disabled(model.busy)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.vertical, compact ? 20 : 30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.queue) { file in
                            HStack(spacing: 12) {
                                Image(systemName: file.icon).font(.system(size: 21)).foregroundStyle(poriTint).frame(width: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(file.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                                    Text(file.folder ? "フォルダ" : byteString(file.size)).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { model.queue.removeAll { $0.id == file.id } } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(model.busy).accessibilityLabel("\(file.name)を外す")
                            }.padding(.horizontal, 17).padding(.vertical, 12)
                            Divider().padding(.leading, 58)
                        }
                    }
                }.frame(maxHeight: .infinity)
                HStack {
                    Button { model.chooseFiles() } label: { Label("追加", systemImage: "plus") }.buttonStyle(.plain).font(.system(size: 11)).disabled(model.busy)
                    Spacer()
                    if compact {
                        Button("すべて外す") { model.queue.removeAll() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary).disabled(model.busy)
                    }
                }.padding(14)
            }
        }
        .frame(minHeight: compact ? 180 : 225, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(dropTargeted ? poriTint : Color.primary.opacity(0.09), lineWidth: dropTargeted ? 2 : 1))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { model.receiveDrop($0, target: target) }
    }
}

struct AndroidView: View {
    @ObservedObject var model: AppModel
    @State private var browserDropTargeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                PageHeading(eyebrow: "ANDROID · USB", title: model.connected ? model.deviceName : "Androidと転送", subtitle: "送り先のフォルダを開いたまま、Macからファイルを送れます。")
                Spacer()
                if model.connected { Button("接続解除") { model.disconnect() }.disabled(model.busy) }
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Label("Androidの保存先", systemImage: "folder").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        if model.connected {
                            Button { model.browse() } label: { Image(systemName: "arrow.clockwise") }.help("再読み込み").disabled(model.busy)
                        }
                    }
                    if model.connected { browser } else { connectionPrompt }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(browserDropTargeted ? poriTint : Color.primary.opacity(0.09), lineWidth: browserDropTargeted ? 2 : 1))
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $browserDropTargeted) { model.receiveDrop($0, target: .android) }
                VStack(alignment: .leading, spacing: 16) {
                    FileQueueView(model: model, target: .android, compact: true)
                    destinationSummary
                }.frame(width: 255)
            }
            if model.transferring {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(model.progressText).font(.system(size: 11)).lineLimit(1)
                        Spacer()
                        if let progress = model.progress { Text("\(Int(progress * 100))%").font(.system(size: 11)).monospacedDigit() }
                        Button("中止") { model.cancel() }.controlSize(.small)
                    }
                    if let progress = model.progress { ProgressView(value: progress) }
                    else { ProgressView().progressViewStyle(.linear) }
                }
            }
        }.padding(.horizontal, 28).padding(.top, 56).padding(.bottom, 24)
    }
    private var connectionPrompt: some View {
        VStack(spacing: 15) {
            Spacer()
            Image(systemName: "cable.connector").font(.system(size: 36, weight: .ultraLight)).foregroundStyle(poriTint)
            Text("Androidを接続").font(.system(size: 16, weight: .medium))
            Text("USBでつなぎ、端末のロックを解除して\n「ファイル転送」を選んでください。")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
            Button(model.busyUSB ? "接続しています…" : "USB接続する") { model.connect() }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.busy)
            Text("OpenMTPなど、ほかの転送アプリは終了してください。")
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var browser: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("ストレージ", selection: Binding(get: { model.storageID }, set: { model.browse(storage: $0) })) {
                ForEach(model.storages) { Text($0.name).tag($0.id) }
            }.labelsHidden().disabled(model.busy)
            HStack(spacing: 8) {
                Button { model.up() } label: { Image(systemName: "chevron.up") }.help("ひとつ上のフォルダ").disabled(model.path == "/" || model.busy)
                Button { model.browse("/") } label: { Image(systemName: "house") }.help("ストレージの先頭").disabled(model.path == "/" || model.busy)
                Text(model.path).font(.system(size: 12)).lineLimit(1).truncationMode(.middle).help(model.path).accessibilityLabel("開いているフォルダ：\(model.path)")
                Spacer(minLength: 0)
            }
            TextField("このフォルダを検索", text: $model.search).textFieldStyle(.roundedBorder).disabled(model.busy)
            Table(model.filteredFiles, selection: $model.selectedRemote) {
                TableColumn("名前") { file in
                    HStack(spacing: 8) {
                        Image(systemName: file.icon).foregroundStyle(poriTint).frame(width: 18)
                        Text(file.name).lineLimit(1)
                    }.padding(.vertical, 4)
                }.width(min: 120, ideal: 240)
                TableColumn("サイズ") { file in Text(file.isFolder ? "—" : byteString(file.size)).foregroundStyle(.secondary) }.width(75)
            }
            .contextMenu(forSelectionType: String.self) { selected in
                if let folder = selectedFolder(selected) { Button("フォルダを開く") { model.browse(folder.path) } }
                Button("Macに保存") { model.selectedRemote = selected; model.download() }.disabled(selected.isEmpty || model.busy)
            } primaryAction: { selected in
                if let folder = selectedFolder(selected) { model.browse(folder.path) }
            }
            .disabled(model.busy)
            .overlay {
                if model.filteredFiles.isEmpty && !model.busyUSB {
                    Text(model.search.isEmpty ? "このフォルダは空です" : "一致するファイルはありません").foregroundStyle(.secondary).font(.system(size: 12))
                }
            }
            if let folder = selectedFolder(model.selectedRemote) {
                Button { model.browse(folder.path) } label: { Label("選択したフォルダを開く", systemImage: "folder.badge.plus") }.disabled(model.busy)
            } else {
                Text("フォルダをダブルクリックして保存先を選択").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button { model.download() } label: { Label("Macに保存", systemImage: "arrow.down.to.line") }.disabled(model.selectedRemote.isEmpty || model.busy)
                Spacer(minLength: 4)
                if let storage = model.selectedStorage { Text("空き \(byteString(storage.free))").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        }
    }
    private func selectedFolder(_ selected: Set<String>) -> RemoteFile? {
        guard selected.count == 1 else { return nil }
        return model.files.first { selected.contains($0.id) && $0.isFolder }
    }
    private var destinationSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("開いているフォルダへ送信", systemImage: "arrow.turn.down.left").font(.system(size: 11, weight: .medium))
            if model.connected {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.selectedStorage?.name ?? "Android").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(model.path).font(.system(size: 12, weight: .medium)).lineLimit(2).truncationMode(.middle).textSelection(.enabled).help(model.destinationLabel)
                }
            } else {
                Text("接続後、左側で保存先を選べます").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Button { model.sendToAndroid() } label: {
                Label(model.connected ? "「\(model.destinationFolderName)」へ送る" : "Androidへ送る", systemImage: "arrow.up.right")
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large)
                .help(model.connected ? "\(model.destinationLabel)へ送信" : "先にAndroidを接続してください")
                .disabled(!model.connected || model.queue.isEmpty || model.busy)
        }
    }
}

struct ActivityView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            PageHeading(eyebrow: "ACTIVITY", title: "転送の履歴", subtitle: "今回の起動中に行った転送が表示されます。")
            if model.activities.isEmpty {
                Spacer()
                VStack(spacing: 13) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 35, weight: .light)).foregroundStyle(poriTint)
                    Text("まだ転送はありません").font(.system(size: 15, weight: .medium))
                    Button("ファイルを送る") { model.selectPage(.send) }.controlSize(.large)
                }.frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.activities) { item in
                            HStack(alignment: .top, spacing: 13) {
                                Image(systemName: item.success == nil ? "paperplane" : item.success == true ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(item.success == false ? .orange : poriTint).font(.system(size: 19))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title).font(.system(size: 13, weight: .medium))
                                    Text(item.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.date, style: .time).font(.system(size: 10)).foregroundStyle(.secondary)
                            }.padding(.vertical, 17)
                            Divider()
                        }
                    }
                }
            }
        }.padding(.horizontal, 34).padding(.top, 56).padding(.bottom, 24)
    }
}

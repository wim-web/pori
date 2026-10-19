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
            nav("ファイルを送る", icon: "paperplane", page: .send)
            nav("転送の履歴", icon: "clock", page: .activity)
            Text("デバイス").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 28).padding(.bottom, 9)
            nav("Androidのファイル", icon: "smartphone", page: .android)
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
        Button { model.page = page } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).frame(width: 17)
                Text(title).font(.system(size: 12, weight: model.page == page ? .semibold : .regular))
                Spacer()
                if page == .send && !model.queue.isEmpty { Text("\(model.queue.count)").font(.system(size: 10)).padding(.horizontal, 6).padding(.vertical, 2).background(.primary.opacity(0.07), in: Capsule()) }
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
    @State private var dropTargeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            PageHeading(eyebrow: "TRANSFER", title: "ファイルを送る", subtitle: "Macから、手元のデバイスへ。")
            HStack(spacing: 14) {
                destinationCard(.android, name: model.connected ? model.deviceName : "Android", icon: "smartphone", method: "USB", detail: model.connected ? "接続済み · \(model.selectedStorage?.name ?? "")" : "ケーブルでつないで転送")
                destinationCard(.airdrop, name: "iPhone / iPad", icon: "airplayvideo", method: "AirDrop", detail: "送信時に近くのデバイスを選択")
            }
            VStack(spacing: 0) {
                HStack {
                    Text("送るファイル").font(.system(size: 12, weight: .semibold))
                    if !model.queue.isEmpty { Text("\(model.queue.count)項目").font(.system(size: 11)).foregroundStyle(.secondary) }
                    Spacer()
                    if !model.queue.isEmpty {
                        Button("すべて外す") { model.queue.removeAll() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary).disabled(model.busy)
                    }
                }.padding(16)
                Divider()
                if model.queue.isEmpty {
                    VStack(spacing: 11) {
                        Image(systemName: "tray.and.arrow.down").font(.system(size: 33, weight: .light)).foregroundStyle(poriTint).padding(.bottom, 3)
                        Text("ここにファイルをドロップ").font(.system(size: 15, weight: .medium))
                        Text("フォルダもまとめて追加できます").font(.system(size: 11)).foregroundStyle(.secondary)
                        Button("ファイルを選ぶ") { model.chooseFiles() }.controlSize(.large).padding(.top, 4).disabled(model.busy)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.vertical, 30)
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
                    }.padding(14)
                }
            }
            .frame(minHeight: 225, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(dropTargeted ? poriTint : Color.primary.opacity(0.09), lineWidth: dropTargeted ? 2 : 1))
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { model.receiveDrop($0) }
            bottom
        }.padding(.horizontal, 34).padding(.top, 56).padding(.bottom, 24)
    }

    private func destinationCard(_ target: Destination, name: String, icon: String, method: String, detail: String) -> some View {
        let selected = model.destination == target
        return Button { model.destination = target } label: {
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
    @ViewBuilder private var bottom: some View {
        if model.transferring {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(model.progressText).font(.system(size: 12)).lineLimit(1)
                    Spacer()
                    if let progress = model.progress { Text("\(Int(progress * 100))%").font(.system(size: 11)).monospacedDigit() }
                    Button("中止") { model.cancel() }.controlSize(.small)
                }
                if let progress = model.progress { ProgressView(value: progress) }
                else { ProgressView().progressViewStyle(.linear) }
            }
        } else {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    if model.destination == .airdrop {
                        Text("次にAirDropの選択画面が開きます").font(.system(size: 11, weight: .medium))
                        Text("iPhone側へのアプリ追加は不要です").font(.system(size: 10)).foregroundStyle(.secondary)
                    } else if model.connected {
                        Text("保存先：\(model.path)").font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        Button("保存先を変更") { model.page = .android }.buttonStyle(.plain).foregroundStyle(poriTint).font(.system(size: 10))
                    } else {
                        Text("AndroidのUSB設定を「ファイル転送」に").font(.system(size: 11, weight: .medium))
                        Text("OpenMTPなど、ほかの転送アプリは終了してください").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if model.destination == .android && !model.connected {
                    Button("USB接続する") { model.connect() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.busy)
                } else {
                    Button { model.send() } label: { Label(model.destination == .airdrop ? "AirDropを開く" : "Androidへ送る", systemImage: "arrow.up.right") }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.queue.isEmpty || model.busy)
                }
            }
        }
    }
}

struct AndroidView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                PageHeading(eyebrow: "USB CONNECTION", title: model.connected ? model.deviceName : "Androidのファイル", subtitle: model.connected ? "フォルダを開いて、送り先を選べます。" : "USBでつないで、ファイルをやり取り。")
                Spacer()
                if model.connected { Button("接続解除") { model.disconnect() }.disabled(model.busy) }
            }
            if !model.connected {
                Spacer()
                VStack(spacing: 17) {
                    Image(systemName: "cable.connector").font(.system(size: 43, weight: .ultraLight)).foregroundStyle(poriTint)
                    Text("Androidをつないでください").font(.system(size: 18, weight: .medium))
                    Text("端末のロックを解除し、USB設定で「ファイル転送」を選択。\nOpenMTPなど、ほかの転送アプリは終了してください。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
                    Button(model.busyUSB ? "接続しています…" : "USB接続する") { model.connect() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.busy)
                }.frame(maxWidth: .infinity)
                Spacer()
            } else {
                HStack(spacing: 12) {
                    Picker("ストレージ", selection: Binding(get: { model.storageID }, set: { model.browse(storage: $0) })) {
                        ForEach(model.storages) { Text($0.name).tag($0.id) }
                    }.labelsHidden().frame(maxWidth: 210)
                    if let storage = model.selectedStorage { Text("空き \(byteString(storage.free))").font(.system(size: 11)).foregroundStyle(.secondary) }
                    Spacer()
                    Button { model.browse() } label: { Image(systemName: "arrow.clockwise") }.help("再読み込み")
                }.disabled(model.busy)
                HStack {
                    Button { model.up() } label: { Image(systemName: "chevron.left") }.disabled(model.path == "/" || model.busy)
                    Text(model.path == "/" ? "ストレージの先頭" : model.path).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    TextField("このフォルダを検索", text: $model.search).textFieldStyle(.roundedBorder).frame(width: 155)
                }
                Table(model.filteredFiles, selection: $model.selectedRemote) {
                    TableColumn("名前") { file in
                        HStack(spacing: 9) {
                            Image(systemName: file.icon).foregroundStyle(poriTint).frame(width: 20)
                            Text(file.name).lineLimit(1)
                        }.padding(.vertical, 4).onTapGesture(count: 2) { if file.isFolder { model.browse(file.path) } }
                    }.width(min: 190, ideal: 360)
                    TableColumn("サイズ") { file in Text(file.isFolder ? "—" : byteString(file.size)).foregroundStyle(.secondary) }.width(85)
                }
                .contextMenu(forSelectionType: String.self) { selected in
                    if selected.count == 1, let file = model.files.first(where: { selected.contains($0.id) }), file.isFolder {
                        Button("開く") { model.browse(file.path) }
                    }
                    Button("Macに保存") { model.selectedRemote = selected; model.download() }.disabled(selected.isEmpty || model.busy)
                } primaryAction: { selected in
                    if selected.count == 1, let file = model.files.first(where: { selected.contains($0.id) }), file.isFolder { model.browse(file.path) }
                }
                .disabled(model.busy)
                .overlay {
                    if model.filteredFiles.isEmpty && !model.busyUSB { Text(model.search.isEmpty ? "このフォルダは空です" : "一致するファイルはありません").foregroundStyle(.secondary).font(.system(size: 12)) }
                }
                if model.transferring {
                    HStack {
                        Text(model.progressText).font(.system(size: 11)).lineLimit(1)
                        if let progress = model.progress { ProgressView(value: progress).frame(width: 140) }
                        else { ProgressView().controlSize(.small) }
                        Button("中止") { model.cancel() }
                    }
                } else {
                    HStack {
                        Button { model.download() } label: { Label("選択項目をMacに保存", systemImage: "arrow.down.to.line") }.disabled(model.selectedRemote.isEmpty || model.busy)
                        Spacer()
                        Button("このフォルダへ送る") { model.destination = .android; model.page = .send }.buttonStyle(.borderedProminent).disabled(model.busy)
                    }
                }
            }
        }.padding(.horizontal, 30).padding(.top, 56).padding(.bottom, 25)
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
                    Button("ファイルを送る") { model.page = .send }.controlSize(.large)
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

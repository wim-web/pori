import SwiftUI

struct MovePickerView: View {
    @ObservedObject var model: AppModel
    let request: MoveRequest
    private var validation: String? {
        do { try TransferRules.validateMove(request.items, from: request.sourceParent, to: model.movePath); return nil }
        catch { return error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("移動先を選択", systemImage: "folder").font(.system(size: 20, weight: .semibold))
            Text("\(request.items.count)項目 · \(request.sourceParent) から移動").font(.system(size: 12)).foregroundStyle(.secondary)
            Text(request.items.map(\.name).joined(separator: "、")).font(.system(size: 11)).lineLimit(2).help(request.items.map(\.path).joined(separator: "\n"))
            HStack {
                Button { model.loadMoveFolder(request, path: (model.movePath as NSString).deletingLastPathComponent) } label: { Image(systemName: "chevron.up") }.disabled(model.movePath == "/" || model.busyUSB).help("ひとつ上へ")
                Button { model.loadMoveFolder(request, path: "/") } label: { Image(systemName: "house") }.disabled(model.movePath == "/" || model.busyUSB).help("ストレージの先頭")
                Text(model.movePath).font(.system(size: 12)).lineLimit(1).truncationMode(.middle).help(model.movePath)
                Spacer()
                if model.busyUSB { ProgressView().controlSize(.small) }
            }
            Text("\(request.storageName) · 同じストレージ内で移動").font(.system(size: 11)).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.moveFolders) { folder in
                        let excluded = request.items.contains { folder.path == $0.path || folder.path.hasPrefix($0.path + "/") }
                        Button { model.loadMoveFolder(request, path: folder.path) } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                Text(folder.name).lineLimit(1)
                                Spacer()
                                if excluded { Text("移動対象").font(.system(size: 10)).foregroundStyle(.secondary) }
                                Image(systemName: "chevron.right").font(.system(size: 10))
                            }.padding(10).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(model.busyUSB || excluded)
                    }
                    if model.moveFolders.isEmpty && !model.busyUSB && model.moveError == nil {
                        Text("サブフォルダはありません").font(.system(size: 12)).foregroundStyle(.secondary).padding(28)
                    }
                }
            }.frame(height: 230).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            if let error = model.moveError { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
            else if let validation { Text(validation).font(.system(size: 11)).foregroundStyle(.secondary) }
            HStack {
                Button("再読み込み") { model.loadMoveFolder(request, path: model.movePath) }.disabled(model.busyUSB)
                Spacer()
                Button("キャンセル") { model.moveRequest = nil }.keyboardShortcut(.cancelAction)
                Button("ここに移動") { model.commitMove(request) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(model.busyUSB || model.moveError != nil || validation != nil)
            }
        }.padding(24).frame(width: 520)
    }
}

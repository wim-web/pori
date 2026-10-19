import SwiftUI

struct NameEditorView: View {
    @ObservedObject var model: AppModel
    let request: NameEditRequest
    @State private var name: String
    @FocusState private var focused: Bool

    init(model: AppModel, request: NameEditRequest) {
        self.model = model
        self.request = request
        _name = State(initialValue: request.initialName)
    }
    private var validationMessage: String? {
        do { _ = try TransferRules.editingPath(request.parent, name: name); return nil }
        catch { return error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(request.title, systemImage: request.source == nil ? "folder.badge.plus" : "pencil")
                .font(.system(size: 20, weight: .semibold))
            Text(request.location).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
            VStack(alignment: .leading, spacing: 8) {
                Text(request.source?.isFolder == false ? "ファイル名（拡張子を含む）" : "フォルダ名").font(.system(size: 12, weight: .medium))
                TextField("名前", text: $name).textFieldStyle(.roundedBorder).focused($focused)
                    .accessibilityLabel("新しい名前")
                if let message = validationMessage {
                    Text(message).font(.system(size: 12)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button("キャンセル") { model.nameEditRequest = nil }.keyboardShortcut(.cancelAction)
                Button(request.action) { model.commitNameEdit(request, name: name) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(validationMessage != nil || name == request.source?.name)
            }
        }
        .padding(26).frame(width: 450)
        .onAppear { focused = true }
    }
}

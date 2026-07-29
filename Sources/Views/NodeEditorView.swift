import SwiftUI

struct NodeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: NodeStore

    let mode: NodeEditorMode
    @State private var name = ""
    @State private var address = ""
    @State private var managementKey = ""
    @State private var didLoad = false

    private var editedNode: ProxyNode? {
        if case let .edit(node) = mode { return node }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(editedNode == nil ? "添加节点" : "编辑节点")
                .font(.title2.bold())

            Form {
                TextField("节点名称", text: $name, prompt: Text("例如：新加坡"))
                TextField("服务地址", text: $address, prompt: Text("https://example.com:8317"))
                SecureField(
                    editedNode == nil ? "Management Key" : "Management Key（留空表示不修改）",
                    text: $managementKey
                )
            }
            .formStyle(.grouped)

            Text("地址可以填写主机、端口或完整 URL；应用会自动补全 `/v0/management`。密钥只保存在 macOS 钥匙串。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if usesInsecureHTTP {
                Label(
                    "HTTP 不会加密 Management Key 和管理数据，仅应在可信内网使用。",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editedNode == nil ? "添加" : "保存") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let node = editedNode {
                name = node.name
                address = node.address
            }
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && URL(string: ProxyNode.normalize(address))?.host != nil
            && (editedNode != nil || !managementKey.isEmpty)
    }

    private var usesInsecureHTTP: Bool {
        URL(string: ProxyNode.normalize(address))?.scheme?.lowercased() == "http"
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let node = editedNode {
            store.update(node, name: cleanName, address: address, key: managementKey)
        } else {
            store.add(name: cleanName, address: address, key: managementKey)
        }
        dismiss()
    }
}

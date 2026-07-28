import SwiftUI

struct ConfigEditorView: View {
    @EnvironmentObject private var store: NodeStore
    let node: ProxyNode

    @State private var yaml = ""
    @State private var savedYAML = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var showSaveConfirmation = false
    @State private var message: PageMessage?

    private let client = ManagementAPIClient()

    var body: some View {
        VStack(spacing: 0) {
            pageToolbar
            Divider()

            if isLoading && yaml.isEmpty {
                ProgressView("正在读取 config.yaml…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: $yaml)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
            }

            if let message {
                MessageBar(message: message)
            }
        }
        .task(id: node.id) { await load() }
        .confirmationDialog(
            "保存整个 config.yaml？",
            isPresented: $showSaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("保存并热重载") { Task { await save() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("CLIProxyAPI 会持久化配置并热重载。错误的 YAML 可能导致节点不可用。")
        }
    }

    private var pageToolbar: some View {
        HStack {
            Label("配置文件", systemImage: "doc.text")
                .font(.headline)
            if yaml != savedYAML {
                Text("有未保存修改")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button("还原") {
                yaml = savedYAML
                message = nil
            }
            .disabled(yaml == savedYAML || isSaving)
            Button {
                Task { await load() }
            } label: {
                Label("重新读取", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading || isSaving)
            Button {
                showSaveConfirmation = true
            } label: {
                Label(isSaving ? "正在保存" : "保存", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(yaml == savedYAML || yaml.isEmpty || isSaving)
        }
        .padding(12)
    }

    @MainActor
    private func load() async {
        guard let key = managementKey else {
            message = .error("尚未保存 Management Key")
            return
        }
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            let value = try await client.fetchConfigYAML(node: node, managementKey: key)
            yaml = value
            savedYAML = value
        } catch {
            message = .error(ManagementAPIClient.friendlyMessage(for: error))
        }
    }

    @MainActor
    private func save() async {
        guard let key = managementKey else {
            message = .error("尚未保存 Management Key")
            return
        }
        isSaving = true
        message = nil
        defer { isSaving = false }
        do {
            try await client.saveConfigYAML(yaml, node: node, managementKey: key)
            savedYAML = yaml
            message = .success("配置已保存，节点正在热重载。")
            await store.refresh(node)
        } catch {
            message = .error(ManagementAPIClient.friendlyMessage(for: error))
        }
    }

    private var managementKey: String? {
        let key = store.key(for: node)
        return key.isEmpty ? nil : key
    }
}

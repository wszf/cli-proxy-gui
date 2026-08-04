import SwiftUI

struct APIKeysView: View {
    @EnvironmentObject private var store: NodeStore
    let node: ProxyNode

    @State private var keys: [String] = []
    @State private var savedKeys: [String] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var revealKeys = false
    @State private var showConfigurationExamples = false
    @State private var showSaveConfirmation = false
    @State private var message: PageMessage?

    private let client = ManagementAPIClient()

    var body: some View {
        VStack(spacing: 0) {
            pageToolbar
            Divider()

            if isLoading && keys.isEmpty {
                ProgressView("正在读取 API Keys…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if keys.isEmpty {
                ContentUnavailableView(
                    "没有 API Key",
                    systemImage: "key",
                    description: Text("添加一个 Key 后保存，客户端即可使用代理接口。")
                )
            } else {
                List {
                    ForEach(keys.indices, id: \.self) { index in
                        HStack {
                            Text("\(index + 1)")
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .trailing)
                            if revealKeys {
                                TextField("API Key", text: $keys[index])
                                    .font(.system(.body, design: .monospaced))
                            } else {
                                SecureField("API Key", text: $keys[index])
                                    .font(.system(.body, design: .monospaced))
                            }
                            Button(role: .destructive) {
                                keys.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("移除")
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if let message {
                MessageBar(message: message)
            }
        }
        .task(id: node.id) { await load() }
        .sheet(isPresented: $showConfigurationExamples) {
            ClientConfigurationExamplesView(node: node, apiKeys: cleanKeys)
        }
        .confirmationDialog(
            "替换节点上的全部 API Keys？",
            isPresented: $showSaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("保存 \(cleanKeys.count) 个 Key") { Task { await save() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("被移除的 Key 会立即失效，使用它们的客户端将无法继续访问。")
        }
    }

    private var pageToolbar: some View {
        HStack {
            Label("API Keys", systemImage: "key")
                .font(.headline)
            if keys != savedKeys {
                Text("有未保存修改")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button {
                showConfigurationExamples = true
            } label: {
                Label("配置示例", systemImage: "doc.on.doc")
            }
            .help("Claude Code 与 Codex 客户端配置示例")
            Toggle("显示", isOn: $revealKeys)
                .toggleStyle(.button)
                .help(revealKeys ? "隐藏 Keys" : "显示 Keys")
            Button {
                keys.append("sk-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
            } label: {
                Label("新增", systemImage: "plus")
            }
            Button {
                Task { await load() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading || isSaving)
            Button("保存") { showSaveConfirmation = true }
                .buttonStyle(.borderedProminent)
                .disabled(keys == savedKeys || isSaving)
        }
        .padding(12)
    }

    private var cleanKeys: [String] {
        keys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    @MainActor
    private func load() async {
        let key = store.key(for: node)
        guard !key.isEmpty else {
            message = .error("尚未保存 Management Key")
            return
        }
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            let values = try await client.fetchAPIKeys(node: node, managementKey: key)
            keys = values
            savedKeys = values
        } catch {
            message = .error(ManagementAPIClient.friendlyMessage(for: error))
        }
    }

    @MainActor
    private func save() async {
        let managementKey = store.key(for: node)
        guard !managementKey.isEmpty else { return }
        isSaving = true
        message = nil
        defer { isSaving = false }
        do {
            try await client.replaceAPIKeys(cleanKeys, node: node, managementKey: managementKey)
            keys = cleanKeys
            savedKeys = cleanKeys
            message = .success("API Keys 已更新。")
            await store.refresh(node)
        } catch {
            message = .error(ManagementAPIClient.friendlyMessage(for: error))
        }
    }
}

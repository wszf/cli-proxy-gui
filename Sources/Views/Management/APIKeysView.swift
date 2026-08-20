import SwiftUI

struct APIKeysView: View {
    @EnvironmentObject private var store: NodeStore
    let node: ProxyNode

    @State private var keys: [String] = []
    @State private var notes: [String] = []
    @State private var savedKeys: [String] = []
    @State private var savedNotes: [String] = []
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
                        HStack(spacing: 10) {
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
                            TextField("备注（仅本机）", text: $notes[index])
                                .frame(minWidth: 160, idealWidth: 220, maxWidth: 300)
                            Button(role: .destructive) {
                                keys.remove(at: index)
                                notes.remove(at: index)
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
            hasKeyChanges ? "替换节点上的全部 API Keys？" : "保存 API Key 备注？",
            isPresented: $showSaveConfirmation,
            titleVisibility: .visible
        ) {
            Button(hasKeyChanges ? "保存 \(cleanKeys.count) 个 Key" : "保存备注") {
                Task { await save() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(hasKeyChanges
                ? "被移除的 Key 会立即失效，使用它们的客户端将无法继续访问。备注仅保存于本机，不会写入节点。"
                : "备注仅保存于本机，不会写入节点。")
        }
    }

    private var pageToolbar: some View {
        HStack {
            Label("API Keys", systemImage: "key")
                .font(.headline)
            if hasUnsavedChanges {
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
                notes.append("")
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
                .disabled(!hasUnsavedChanges || isSaving)
        }
        .padding(12)
    }

    private var cleanEntries: [(key: String, note: String)] {
        keys.enumerated().compactMap { index, rawKey in
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            let note = notes.indices.contains(index)
                ? notes[index].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            return (key: key, note: note)
        }
    }

    private var cleanKeys: [String] {
        cleanEntries.map { $0.key }
    }

    private var hasUnsavedChanges: Bool {
        keys != savedKeys || notes != savedNotes
    }

    private var hasKeyChanges: Bool {
        cleanKeys != savedKeys
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
            let loadedNotes = values.map { APIKeyNoteStore.note(for: node.id, key: $0) }
            keys = values
            notes = loadedNotes
            savedKeys = values
            savedNotes = loadedNotes
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
        let entries = cleanEntries
        let values = entries.map { $0.key }
        let remarks = entries.map { $0.note }
        var notesByKey: [String: String] = [:]
        for entry in entries {
            notesByKey[entry.key] = entry.note
        }

        do {
            try await client.replaceAPIKeys(values, node: node, managementKey: managementKey)
            APIKeyNoteStore.replaceNotes(notesByKey, for: node.id)
            keys = values
            notes = remarks
            savedKeys = values
            savedNotes = remarks
            message = .success("API Keys 已更新，备注已保存到本机。")
            await store.refresh(node)
        } catch {
            message = .error(ManagementAPIClient.friendlyMessage(for: error))
        }
    }
}

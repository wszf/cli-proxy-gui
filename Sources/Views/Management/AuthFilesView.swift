import SwiftUI
import UniformTypeIdentifiers

struct AuthFilesView: View {
    @EnvironmentObject private var store: NodeStore
    let node: ProxyNode

    @State private var files: [AuthFileItem] = []
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var isEnteringJSON = false
    @State private var jsonText = ""
    @State private var importError: String?
    @State private var isUploading = false
    @State private var notes: [String: String] = [:]
    @State private var editingNote: AuthFileItem?
    @State private var noteDraft = ""
    @State private var pendingDelete: AuthFileItem?
    @State private var message: PageMessage?

    private let client = ManagementAPIClient()

    var body: some View {
        VStack(spacing: 0) {
            pageToolbar
            Divider()

            if isLoading && files.isEmpty {
                ProgressView("正在读取认证文件…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if files.isEmpty {
                ContentUnavailableView(
                    "没有认证文件",
                    systemImage: "person.badge.key",
                    description: Text("上传文件或填入 JSON，支持自动转换 Codex auth.json。")
                )
            } else {
                List(files) { file in
                    AuthFileRow(file: file, note: notes[file.name] ?? "") {
                        Task { await toggle(file) }
                    } onDelete: {
                        pendingDelete = file
                    } onEditNote: {
                        noteDraft = notes[file.name] ?? ""
                        editingNote = file
                    }
                }
            }

            if let message {
                MessageBar(message: message)
            }
        }
        .task(id: node.id) {
            editingNote = nil
            noteDraft = ""
            notes = AuthFileNoteStore.notes(for: node.id)
            await load()
        }
        .sheet(item: $editingNote, onDismiss: { noteDraft = "" }) { file in
            VStack(alignment: .leading, spacing: 12) {
                Text("认证备注").font(.headline)
                Text(file.name).font(.callout).textSelection(.enabled)
                TextField("例如：个人账号、工作账号", text: $noteDraft, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                Text("仅保存在本机，不会上传到节点。留空保存可删除备注。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("取消") { editingNote = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("保存") {
                        AuthFileNoteStore.setNote(noteDraft, for: node.id, filename: file.name)
                        notes = AuthFileNoteStore.notes(for: node.id)
                        editingNote = nil
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(width: 460)
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first { Task { await upload(url) } }
            case let .failure(error):
                message = .error(error.localizedDescription)
            }
        }
        .sheet(isPresented: $isEnteringJSON, onDismiss: {
            jsonText = ""
            importError = nil
        }) {
            jsonEntrySheet
        }
        .confirmationDialog(
            "删除认证文件 \(pendingDelete?.name ?? "")？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("永久删除", role: .destructive) {
                guard let file = pendingDelete else { return }
                pendingDelete = nil
                Task { await delete(file) }
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("该凭据会从节点磁盘和运行时认证管理器中移除。")
        }
    }

    private var pageToolbar: some View {
        HStack {
            Label("认证文件", systemImage: "person.badge.key")
                .font(.headline)
            Text("\(files.count) 个")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                isImporting = true
            } label: {
                Label("上传 JSON", systemImage: "square.and.arrow.up")
            }
            .disabled(isUploading)
            Button {
                jsonText = ""
                importError = nil
                isEnteringJSON = true
            } label: {
                Label("填入 JSON", systemImage: "doc.on.clipboard")
            }
            .disabled(isUploading)
            Button {
                Task { await load() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)
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
            files = try await client.fetchAuthFiles(node: node, managementKey: key)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            message = .error(ManagementAPIClient.friendlyMessage(for: error))
        }
    }

    @MainActor
    private func toggle(_ file: AuthFileItem) async {
        guard let key = managementKey else {
            message = .error("尚未保存 Management Key")
            return
        }
        do {
            try await client.setAuthFileDisabled(
                !file.disabled,
                name: file.name,
                node: node,
                managementKey: key
            )
            await load()
            message = .success(file.disabled ? "已启用 \(file.name)" : "已禁用 \(file.name)")
            store.invalidateCredentialQuotas(for: node)
            await store.refresh(node)
        } catch {
            message = .error(ManagementAPIClient.friendlyMessage(for: error))
        }
    }

    private var jsonEntrySheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("填入认证 JSON").font(.headline)
            Text("支持 CLIProxyAPI 凭据、Codex auth.json 和带转义的 JSON 字符串。转换在本机完成，提交后发送到当前节点：\(node.name)。")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: $jsonText)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .frame(minHeight: 240)
                .border(Color.secondary.opacity(0.3))
                .disabled(isUploading)
                .accessibilityLabel("认证 JSON 内容")
            Text("内容包含敏感令牌，请勿分享。关闭窗口后会清空输入；不会清除系统剪贴板。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let importError {
                Text(importError).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("取消") { isEnteringJSON = false }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isUploading)
                Button(isUploading ? "正在导入…" : "转换并导入") {
                    Task { await uploadPastedJSON() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isUploading || jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 600, height: 440)
        .interactiveDismissDisabled(isUploading)
    }

    @MainActor
    private func upload(_ url: URL) async {
        guard !isUploading else { return }
        isUploading = true
        defer { isUploading = false }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            try await importCredentials(Data(contentsOf: url), filename: url.lastPathComponent)
        } catch {
            message = .error(importMessage(for: error))
        }
    }

    @MainActor
    private func uploadPastedJSON() async {
        guard !isUploading else { return }
        isUploading = true
        importError = nil
        defer { isUploading = false }
        do {
            // Unique names avoid unintentionally replacing an existing credential.
            try await importCredentials(Data(jsonText.utf8), filename: "credential-\(UUID().uuidString).json")
            jsonText = ""
            isEnteringJSON = false
        } catch {
            importError = importMessage(for: error)
        }
    }

    @MainActor
    private func importCredentials(_ data: Data, filename: String) async throws {
        guard let key = managementKey else {
            throw AuthImportUIError.missingManagementKey
        }
        let normalized = try AuthJSONImporter.normalize(data)
        try await client.uploadAuthFile(
            data: normalized, filename: filename, node: node, managementKey: key
        )
        await load()
        message = .success("已导入 \(filename)")
        store.invalidateCredentialQuotas(for: node)
        await store.refresh(node)
    }

    private func importMessage(for error: Error) -> String {
        if error is AuthJSONImporter.ImportError || error is AuthImportUIError {
            return error.localizedDescription
        }
        return ManagementAPIClient.friendlyMessage(for: error)
    }

    private enum AuthImportUIError: LocalizedError {
        case missingManagementKey
        var errorDescription: String? { "尚未保存 Management Key" }
    }

    @MainActor
    private func delete(_ file: AuthFileItem) async {
        guard let key = managementKey else {
            message = .error("尚未保存 Management Key")
            return
        }
        do {
            try await client.deleteAuthFile(name: file.name, node: node, managementKey: key)
            AuthFileNoteStore.setNote("", for: node.id, filename: file.name)
            notes = AuthFileNoteStore.notes(for: node.id)
            await load()
            message = .success("已删除 \(file.name)")
            store.invalidateCredentialQuotas(for: node)
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

private struct AuthFileRow: View {
    let file: AuthFileItem
    let note: String
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onEditNote: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(file.isAvailable ? .green : .secondary)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .fontWeight(.medium)
                if !note.isEmpty {
                    Text(note)
                        .font(.callout)
                        .lineLimit(2)
                        .help(note)
                }
                HStack {
                    Text(file.type)
                    Text(file.disabled ? "已禁用" : file.status)
                    if let size = file.size {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(note.isEmpty ? "添加备注" : "编辑备注", action: onEditNote)
                .buttonStyle(.borderless)
            Button(file.disabled ? "启用" : "禁用", action: onToggle)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

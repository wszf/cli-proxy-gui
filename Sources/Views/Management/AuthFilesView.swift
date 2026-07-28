import SwiftUI
import UniformTypeIdentifiers

struct AuthFilesView: View {
    @EnvironmentObject private var store: NodeStore
    let node: ProxyNode

    @State private var files: [AuthFileItem] = []
    @State private var isLoading = false
    @State private var isImporting = false
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
                    description: Text("可以上传 CLIProxyAPI 支持的 JSON 凭据文件。")
                )
            } else {
                List(files) { file in
                    AuthFileRow(file: file) {
                        Task { await toggle(file) }
                    } onDelete: {
                        pendingDelete = file
                    }
                }
            }

            if let message {
                MessageBar(message: message)
            }
        }
        .task(id: node.id) { await load() }
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

    @MainActor
    private func upload(_ url: URL) async {
        guard let key = managementKey else {
            message = .error("尚未保存 Management Key")
            return
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
                message = .error("所选文件不是有效的 JSON。")
                return
            }
            try await client.uploadAuthFile(
                data: data,
                filename: url.lastPathComponent,
                node: node,
                managementKey: key
            )
            await load()
            message = .success("已上传 \(url.lastPathComponent)")
            store.invalidateCredentialQuotas(for: node)
            await store.refresh(node)
        } catch {
            message = .error(ManagementAPIClient.friendlyMessage(for: error))
        }
    }

    @MainActor
    private func delete(_ file: AuthFileItem) async {
        guard let key = managementKey else {
            message = .error("尚未保存 Management Key")
            return
        }
        do {
            try await client.deleteAuthFile(name: file.name, node: node, managementKey: key)
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
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(file.isAvailable ? .green : .secondary)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .fontWeight(.medium)
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
            Button(file.disabled ? "启用" : "禁用", action: onToggle)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

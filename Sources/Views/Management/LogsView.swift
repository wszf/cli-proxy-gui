import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var store: NodeStore
    let node: ProxyNode

    @State private var lines: [String] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var isFileLoggingDisabled = false
    @State private var showClearConfirmation = false
    @State private var message: PageMessage?

    private let client = ManagementAPIClient()

    private var displayedLines: [String] {
        guard !searchText.isEmpty else { return lines }
        return lines.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            pageToolbar
            Divider()

            if isLoading && lines.isEmpty {
                ProgressView("正在读取日志…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lines.isEmpty {
                ContentUnavailableView(
                    isFileLoggingDisabled ? "文件日志未开启" : "没有日志",
                    systemImage: isFileLoggingDisabled ? "doc.badge.gearshape" : "text.alignleft",
                    description: Text(
                        isFileLoggingDisabled
                            ? "请在“配置”中开启 logging-to-file 后再查看运行日志。"
                            : "节点尚未产生日志。"
                    )
                )
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Text(displayedLines.joined(separator: "\n"))
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }

            if let message {
                MessageBar(message: message)
            }
        }
        .task(id: node.id) { await load() }
        .confirmationDialog(
            "清空节点日志？",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空全部日志", role: .destructive) { Task { await clear() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已轮转的日志会被删除，当前日志文件会被截断，此操作不可撤销。")
        }
    }

    private var pageToolbar: some View {
        HStack {
            Label("运行日志", systemImage: "text.alignleft")
                .font(.headline)
            Text("\(displayedLines.count) 行")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            TextField("搜索日志", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            Button {
                Task { await load() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)
            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label("清空", systemImage: "trash")
            }
            .disabled(lines.isEmpty)
        }
        .padding(12)
    }

    @MainActor
    private func load() async {
        let key = store.key(for: node)
        guard !key.isEmpty else {
            message = .error("尚未保存 Management Key")
            return
        }
        isLoading = true
        isFileLoggingDisabled = false
        message = nil
        defer { isLoading = false }
        do {
            lines = try await client.fetchLogs(node: node, managementKey: key).lines
        } catch {
            if case let APIError.httpStatus(code, detail) = error,
               code == 400,
               detail?.localizedCaseInsensitiveContains("logging to file disabled") == true {
                lines = []
                isFileLoggingDisabled = true
                message = nil
            } else {
                message = .error(ManagementAPIClient.friendlyMessage(for: error))
            }
        }
    }

    @MainActor
    private func clear() async {
        let key = store.key(for: node)
        guard !key.isEmpty else { return }
        do {
            try await client.clearLogs(node: node, managementKey: key)
            lines = []
            message = .success("节点日志已清空。")
        } catch {
            message = .error(ManagementAPIClient.friendlyMessage(for: error))
        }
    }
}

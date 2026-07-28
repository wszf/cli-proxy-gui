import SwiftUI

struct NodeDashboardView: View {
    @EnvironmentObject private var store: NodeStore
    let node: ProxyNode
    @State private var section: NodeManagementSection = .overview

    private var snapshot: NodeSnapshot { store.snapshot(for: node) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("管理模块", selection: $section) {
                ForEach(NodeManagementSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)
            Divider()

            switch section {
            case .overview:
                overview
            case .configuration:
                ConfigEditorView(node: node)
            case .authFiles:
                AuthFilesView(node: node)
            case .apiKeys:
                APIKeysView(node: node)
            case .logs:
                LogsView(node: node)
            case .usage:
                TokenUsageView(node: node)
            }
        }
        .navigationTitle(node.name)
        .toolbar {
            Button {
                store.openManagementPage(for: node)
            } label: {
                Label("打开完整管理页", systemImage: "safari")
            }

            Button {
                store.presentedEditor = .edit(node)
            } label: {
                Label("编辑节点", systemImage: "pencil")
            }

            Button {
                Task { await store.refresh(node) }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if case let .offline(message) = snapshot.state {
                    offlineBanner(message)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: 14)],
                    spacing: 14
                ) {
                    MetricCard(
                        title: "认证文件",
                        value: snapshot.authFileCount.map(String.init) ?? "—",
                        symbol: "person.badge.key"
                    )
                    MetricCard(
                        title: "API Keys",
                        value: snapshot.apiKeyCount.map(String.init) ?? "—",
                        symbol: "key"
                    )
                    MetricCard(
                        title: "上游提供商",
                        value: snapshot.providerCount.map(String.init) ?? "—",
                        symbol: "point.3.connected.trianglepath.dotted"
                    )
                    MetricCard(
                        title: "路由策略",
                        value: snapshot.routingStrategy ?? "—",
                        symbol: "arrow.triangle.branch"
                    )
                }

                GroupBox("连接信息") {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                        DetailRow(label: "服务地址", value: node.address)
                        DetailRow(label: "服务版本", value: snapshot.version ?? "未报告")
                        DetailRow(label: "构建日期", value: snapshot.buildDate ?? "未报告")
                        DetailRow(
                            label: "最后检查",
                            value: snapshot.lastChecked?.formatted(date: .abbreviated, time: .standard) ?? "尚未检查"
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
            }
            .padding(28)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    StatusIndicator(state: snapshot.state)
                    Text(statusText)
                        .font(.headline)
                }
                Text(node.address)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            if snapshot.state == .checking {
                ProgressView()
            }
        }
    }

    private var statusText: String {
        switch snapshot.state {
        case .idle: "等待检查"
        case .checking: "正在连接"
        case .online: "节点在线"
        case .offline: "节点离线"
        }
    }

    private func offlineBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private enum NodeManagementSection: String, CaseIterable, Identifiable {
    case overview
    case configuration
    case authFiles
    case apiKeys
    case logs
    case usage

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "概览"
        case .configuration: "配置"
        case .authFiles: "认证"
        case .apiKeys: "API Keys"
        case .logs: "日志"
        case .usage: "用量"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .configuration: "doc.text"
        case .authFiles: "person.badge.key"
        case .apiKeys: "key"
        case .logs: "text.alignleft"
        case .usage: "chart.xyaxis.line"
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        GroupBox {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer()
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
            .padding(8)
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

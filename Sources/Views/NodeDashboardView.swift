import SwiftUI

struct NodeDashboardView: View {
    @EnvironmentObject private var store: NodeStore
    let node: ProxyNode
    @State private var section: NodeManagementSection = .overview

    private var snapshot: NodeSnapshot { store.snapshot(for: node) }
    private var credentialQuotas: [CredentialQuotaSummary] { store.quotas(for: node) }
    private var credentialQuotaState: CredentialQuotaLoadState { store.quotaState(for: node) }

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

                primaryMetrics
                credentialHealth
                runtimeStatus
                pluginStatus

                GroupBox("连接信息") {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                        DetailRow(label: "服务地址", value: node.address)
                        DetailRow(label: "服务版本", value: snapshot.version ?? "未报告")
                        DetailRow(label: "最新版本", value: snapshot.latestVersion ?? "未能检查")
                        DetailRow(label: "构建日期", value: snapshot.buildDate ?? "未报告")
                        DetailRow(
                            label: "连接延迟",
                            value: snapshot.latencyMilliseconds.map { "\($0) ms" } ?? "—"
                        )
                        DetailRow(
                            label: "API Keys",
                            value: snapshot.apiKeyCount.map(String.init) ?? "—"
                        )
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
            if snapshot.state == .online {
                HStack(spacing: 8) {
                    if let latency = snapshot.latencyMilliseconds {
                        HeaderBadge(
                            title: "\(latency) ms",
                            symbol: "waveform.path.ecg",
                            color: latency < 500 ? .green : .orange
                        )
                    }
                    HeaderBadge(
                        title: secureConnection ? "HTTPS" : "HTTP",
                        symbol: secureConnection ? "lock.fill" : "lock.open.fill",
                        color: secureConnection ? .green : .orange
                    )
                    if snapshot.hasUpdate, let latest = snapshot.latestVersion {
                        HeaderBadge(
                            title: "可升级 \(latest)",
                            symbol: "arrow.up.circle.fill",
                            color: .blue
                        )
                    }
                }
            }
            if snapshot.state == .checking {
                ProgressView()
            }
        }
    }

    private var primaryMetrics: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180), spacing: 14)],
            spacing: 14
        ) {
            MetricCard(
                title: "健康凭证",
                value: credentialValue,
                subtitle: credentialSubtitle,
                symbol: "person.badge.shield.checkmark"
            )
            MetricCard(
                title: "可用模型",
                value: snapshot.availableModelCount.map(String.init) ?? "—",
                subtitle: snapshot.availableModelCount == nil ? "需要有效 API Key" : "来自 /v1/models",
                symbol: "square.stack.3d.up"
            )
            MetricCard(
                title: "24 小时请求",
                value: snapshot.dailyUsage?.requests.formatted() ?? "—",
                subtitle: snapshot.dailyUsage == nil ? "CAP 插件不可用" : "Token 用量追踪",
                symbol: "arrow.up.arrow.down"
            )
            MetricCard(
                title: "失败率",
                value: snapshot.dailyUsage.map {
                    String(format: "%.1f%%", $0.failureRate * 100)
                } ?? "—",
                subtitle: snapshot.dailyUsage.map {
                    "\($0.failedRequests.formatted()) 次失败"
                } ?? "暂无统计",
                symbol: "exclamationmark.triangle"
            )
            MetricCard(
                title: "24 小时 Tokens",
                value: snapshot.dailyUsage?.totalTokens.formatted(
                    .number.notation(.compactName)
                ) ?? "—",
                subtitle: "输入、输出与推理合计",
                symbol: "sum"
            )
            MetricCard(
                title: "活动插件",
                value: snapshot.plugins.map { "\($0.active) / \($0.installed)" } ?? "—",
                subtitle: snapshot.plugins?.globallyEnabled == false ? "插件系统已关闭" : "启用 / 已安装",
                symbol: "puzzlepiece.extension"
            )
        }
    }

    @ViewBuilder
    private var credentialHealth: some View {
        if !snapshot.credentialProviders.isEmpty {
            GroupBox {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 170), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(snapshot.credentialProviders) { provider in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(provider.available == provider.total ? .green : .orange)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(provider.provider)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Text("\(provider.available) 可用 / \(provider.total) 总数")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
                .padding(6)

                Divider()
                    .padding(.vertical, 6)

                credentialQuotaContent
            } label: {
                Label("凭证健康", systemImage: "person.badge.key")
            }
        }
    }

    @ViewBuilder
    private var credentialQuotaContent: some View {
        if credentialQuotaState == .loading {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在读取账号额度…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        } else if credentialQuotas.isEmpty {
            Text("当前没有可读取额度的 Codex、Claude 或 Kimi 凭证")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: 12)],
                spacing: 12
            ) {
                ForEach(credentialQuotas) { quota in
                    CredentialQuotaCard(quota: quota)
                }
            }
            .padding(6)
        }
    }

    private var runtimeStatus: some View {
        GroupBox {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 10)],
                spacing: 10
            ) {
                RuntimeBadge(title: "Debug", enabled: snapshot.runtime.debug)
                RuntimeBadge(title: "请求日志", enabled: snapshot.runtime.requestLogging)
                RuntimeBadge(title: "文件日志", enabled: snapshot.runtime.fileLogging)
                RuntimeBadge(title: "内置用量统计", enabled: snapshot.runtime.usageStatistics)
                RuntimeBadge(title: "全局代理", enabled: snapshot.runtime.proxyConfigured)
                RuntimeBadge(title: "TLS", enabled: snapshot.runtime.tlsEnabled)
                RuntimeValueBadge(
                    title: "路由",
                    value: snapshot.routingStrategy ?? "未报告",
                    symbol: "arrow.triangle.branch"
                )
                RuntimeValueBadge(
                    title: "请求重试",
                    value: snapshot.runtime.requestRetry.map(String.init) ?? "未报告",
                    symbol: "arrow.clockwise"
                )
            }
            .padding(6)
        } label: {
            Label("运行配置", systemImage: "switch.2")
        }
    }

    @ViewBuilder
    private var pluginStatus: some View {
        if let plugins = snapshot.plugins {
            GroupBox {
                HStack(spacing: 12) {
                    Image(systemName: plugins.tokenTrackerActive
                        ? "checkmark.circle.fill"
                        : "exclamationmark.circle.fill")
                        .foregroundStyle(plugins.tokenTrackerActive ? .green : .orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CAP Token Usage Tracker")
                            .fontWeight(.medium)
                        Text(plugins.tokenTrackerActive
                            ? "插件已注册并有效启用"
                            : "插件未安装、未注册或未有效启用")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(plugins.active) 个活动插件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            } label: {
                Label("插件状态", systemImage: "puzzlepiece.extension")
            }
        }
    }

    private var secureConnection: Bool {
        URL(string: node.address)?.scheme?.lowercased() == "https"
            || snapshot.runtime.tlsEnabled == true
    }

    private var credentialValue: String {
        guard let available = snapshot.availableAuthFileCount,
              let total = snapshot.authFileCount
        else {
            return "—"
        }
        return "\(available) / \(total)"
    }

    private var credentialSubtitle: String {
        let disabled = snapshot.disabledAuthFileCount ?? 0
        let unavailable = snapshot.unavailableAuthFileCount ?? 0
        return "\(disabled) 禁用 · \(unavailable) 异常"
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
    var subtitle: String? = nil
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
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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

private struct HeaderBadge: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.1), in: Capsule())
    }
}

private struct RuntimeBadge: View {
    let title: String
    let enabled: Bool?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(title)
            Spacer()
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(9)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusColor: Color {
        guard let enabled else { return .secondary }
        return enabled ? .green : .secondary
    }

    private var statusText: String {
        guard let enabled else { return "未知" }
        return enabled ? "开启" : "关闭"
    }
}

private struct RuntimeValueBadge: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 10)
            Text(title)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(9)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CredentialQuotaCard: View {
    let quota: CredentialQuotaSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(quota.account)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(accountSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let remaining = quota.lowestRemainingPercent {
                    Text("\(Int(remaining.rounded()))% 最低")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color(for: remaining))
                }
            }

            if let error = quota.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else {
                ForEach(quota.windows) { window in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(window.label)
                                .font(.caption)
                            Spacer()
                            Text("\(Int(window.remainingPercent.rounded()))% 剩余")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(color(for: window.remainingPercent))
                        }
                        ProgressView(value: window.remainingPercent, total: 100)
                            .tint(color(for: window.remainingPercent))
                        if let resetsAt = window.resetsAt {
                            Text("重置：\(resetsAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private var accountSubtitle: String {
        if let plan = quota.plan, !plan.isEmpty {
            return "\(quota.provider) · \(plan)"
        }
        return quota.provider
    }

    private func color(for remaining: Double) -> Color {
        if remaining <= 15 { return .red }
        if remaining <= 35 { return .orange }
        return .green
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

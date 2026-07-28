import Charts
import SwiftUI

struct TokenUsageView: View {
    @EnvironmentObject private var store: NodeStore
    let node: ProxyNode

    @State private var selectedRange: UsageRange = .day
    @State private var stats: TokenUsageSnapshot?
    @State private var costs: TokenUsageCosts?
    @State private var requests: UsageRequestPage?
    @State private var isLoading = false
    @State private var message: PageMessage?
    @State private var dimensionQuery = ""

    private let client = ManagementAPIClient()

    private var modelRows: [ModelUsageRow] {
        ModelUsageRow.aggregate(stats?.groups ?? [])
    }

    private var dimensionGroups: [UsageGroup] {
        (stats?.groups ?? [])
            .filter { $0.matchesDimensionQuery(dimensionQuery) }
            .sorted {
                if $0.totalTokens == $1.totalTokens {
                    return $0.requests > $1.requests
                }
                return $0.totalTokens > $1.totalTokens
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            pageToolbar
            Divider()

            if isLoading && stats == nil {
                ProgressView("正在读取 CAP Token Usage Tracker…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let stats {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        metrics(stats)
                        trendChart(stats)
                        modelUsage
                        dimensionDetails(stats)
                        recentRequests
                    }
                    .padding(18)
                }
            } else {
                ContentUnavailableView {
                    Label("暂无用量数据", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("请确认 cap-token-usage-tracker 已安装、启用，并且节点已经产生调用记录。")
                } actions: {
                    Button("重试") { Task { await load() } }
                }
            }

            if let message {
                MessageBar(message: message)
            }
        }
        .task(id: node.id) { await load() }
        .onChange(of: selectedRange) {
            Task { await load() }
        }
    }

    private var pageToolbar: some View {
        HStack {
            Label("Token 用量", systemImage: "chart.xyaxis.line")
                .font(.headline)
            Text("CAP Token Usage Tracker")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("统计范围", selection: $selectedRange) {
                ForEach(UsageRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .frame(width: 140)
            Button {
                Task { await load() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)
        }
        .padding(12)
    }

    private func metrics(_ stats: TokenUsageSnapshot) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: 12)],
            spacing: 12
        ) {
            UsageMetricCard(
                title: "请求",
                value: stats.summary.requests.formatted(),
                subtitle: "\(stats.summary.failedRequests.formatted()) 次失败",
                symbol: "arrow.up.arrow.down"
            )
            UsageMetricCard(
                title: "总 Tokens",
                value: stats.summary.totalTokens.formatted(.number.notation(.compactName)),
                subtitle: "输入 \(stats.summary.inputTokens.formatted(.number.notation(.compactName))) · 输出 \(stats.summary.outputTokens.formatted(.number.notation(.compactName)))",
                symbol: "sum"
            )
            UsageMetricCard(
                title: "缓存读取",
                value: stats.summary.cacheReadTokens.formatted(.number.notation(.compactName)),
                subtitle: "缓存创建 \(stats.summary.cacheCreationTokens.formatted(.number.notation(.compactName)))",
                symbol: "memorychip"
            )
            UsageMetricCard(
                title: "预估费用",
                value: costs.map { String(format: "$%.4f", $0.summary.totalUSD) } ?? "—",
                subtitle: costs.map { "\($0.summary.pricedRequests)/\($0.summary.requests) 次已定价" } ?? "价格数据不可用",
                symbol: "dollarsign.circle"
            )
        }
    }

    private func trendChart(_ stats: TokenUsageSnapshot) -> some View {
        GroupBox("Token 趋势") {
            if stats.series.isEmpty {
                Text("当前范围没有时间序列数据")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart(stats.series) { point in
                    AreaMark(
                        x: .value("时间", point.hour),
                        y: .value("Tokens", point.totalTokens)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor.opacity(0.55), .accentColor.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("时间", point.hour),
                        y: .value("Tokens", point.totalTokens)
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .chartYAxis {
                    AxisMarks(format: Decimal.FormatStyle().notation(.compactName))
                }
                .frame(height: 210)
                .padding(.top, 8)
            }
        }
    }

    private var modelUsage: some View {
        GroupBox("模型用量") {
            if modelRows.isEmpty {
                Text("没有模型维度数据")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                    GridRow {
                        Text("模型").fontWeight(.semibold)
                        Text("提供商").fontWeight(.semibold)
                        Text("请求").fontWeight(.semibold)
                        Text("失败").fontWeight(.semibold)
                        Text("Tokens").fontWeight(.semibold)
                    }
                    Divider()
                    ForEach(modelRows.prefix(20)) { row in
                        GridRow {
                            Text(row.model).lineLimit(1)
                            Text(row.provider.isEmpty ? "—" : row.provider)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(row.requests.formatted())
                            Text(row.failedRequests.formatted())
                            Text(row.totalTokens.formatted(.number.notation(.compactName)))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
        }
    }

    private func dimensionDetails(_ stats: TokenUsageSnapshot) -> some View {
        GroupBox {
            if stats.groups.isEmpty {
                Text("没有原始维度数据")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("筛选模型、提供商、来源、认证类型…", text: $dimensionQuery)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 360)
                        Text("显示 \(min(dimensionGroups.count, 100)) / \(stats.groups.count) 组")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    if dimensionGroups.isEmpty {
                        ContentUnavailableView.search(text: dimensionQuery)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        ScrollView(.horizontal) {
                            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                                dimensionHeader
                                Divider()
                                ForEach(
                                    Array(dimensionGroups.prefix(100).enumerated()),
                                    id: \.offset
                                ) { _, group in
                                    dimensionRow(group)
                                }
                            }
                            .padding(8)
                        }
                    }
                }
            }
        } label: {
            Label("维度明细", systemImage: "tablecells")
        }
    }

    private var dimensionHeader: some View {
        GridRow {
            dimensionHeading("提供商")
            dimensionHeading("执行器")
            dimensionHeading("模型")
            dimensionHeading("别名")
            dimensionHeading("来源")
            dimensionHeading("认证")
            dimensionHeading("服务层级")
            dimensionHeading("推理强度")
            dimensionHeading("结果")
            dimensionHeading("状态码")
            dimensionHeading("请求")
            dimensionHeading("输入")
            dimensionHeading("输出")
            dimensionHeading("推理")
            dimensionHeading("缓存读取")
            dimensionHeading("缓存创建")
            dimensionHeading("总 Tokens")
            dimensionHeading("平均延迟")
            dimensionHeading("平均 TTFT")
        }
    }

    private func dimensionRow(_ group: UsageGroup) -> some View {
        GridRow {
            dimensionText(group.provider)
            dimensionText(group.executorType)
            dimensionText(group.model)
            dimensionText(group.alias)
            dimensionText(group.source)
            dimensionText(group.authType)
            dimensionText(group.serviceTier)
            dimensionText(group.reasoningEffort)
            Text(group.failed ? "失败" : "成功")
                .foregroundStyle(group.failed ? .red : .green)
            dimensionNumber(group.failureStatus == 0 ? "—" : String(group.failureStatus))
            dimensionNumber(group.requests.formatted())
            dimensionNumber(group.inputTokens.formatted())
            dimensionNumber(group.outputTokens.formatted())
            dimensionNumber(group.reasoningTokens.formatted())
            dimensionNumber(group.cacheReadTokens.formatted())
            dimensionNumber(group.cacheCreationTokens.formatted())
            dimensionNumber(group.totalTokens.formatted())
            dimensionNumber(duration(group.averageLatencyNS))
            dimensionNumber(duration(group.averageTTFTNS))
        }
    }

    private func dimensionHeading(_ title: String) -> some View {
        Text(title)
            .fontWeight(.semibold)
            .lineLimit(1)
    }

    private func dimensionText(_ value: String) -> some View {
        Text(value.isEmpty ? "—" : value)
            .lineLimit(1)
            .foregroundStyle(value.isEmpty ? .tertiary : .primary)
    }

    private func dimensionNumber(_ value: String) -> some View {
        Text(value)
            .fontDesign(.monospaced)
            .lineLimit(1)
    }

    private var recentRequests: some View {
        GroupBox("最近请求") {
            if let requests, !requests.items.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                    GridRow {
                        Text("时间").fontWeight(.semibold)
                        Text("模型").fontWeight(.semibold)
                        Text("结果").fontWeight(.semibold)
                        Text("Tokens").fontWeight(.semibold)
                        Text("延迟").fontWeight(.semibold)
                    }
                    Divider()
                    ForEach(requests.items.prefix(20)) { item in
                        GridRow {
                            Text(shortTime(item.time))
                                .foregroundStyle(.secondary)
                            Text(item.model).lineLimit(1)
                            Text(item.result)
                                .foregroundStyle(item.failed ? .red : .green)
                            Text(item.totalTokens.formatted())
                            Text(duration(item.latencyNS))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            } else {
                Text("没有逐请求明细")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
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
            async let loadedStats = client.fetchTokenUsage(
                range: selectedRange,
                node: node,
                managementKey: key
            )
            async let loadedCosts = client.fetchTokenUsageCosts(range: selectedRange, node: node)
            async let loadedRequests = client.fetchTokenUsageRequests(range: selectedRange, node: node)
            let result = try await loadedStats
            stats = result
            costs = try? await loadedCosts
            requests = try? await loadedRequests
        } catch {
            stats = nil
            costs = nil
            requests = nil
            let text = ManagementAPIClient.friendlyMessage(for: error)
            message = .error(
                text.contains("404")
                    ? "插件未安装、未启用，或当前 CLIProxyAPI 版本不支持该插件。"
                    : text
            )
        }
    }

    private func shortTime(_ rawValue: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: rawValue) else { return rawValue }
        return date.formatted(date: .omitted, time: .standard)
    }

    private func duration(_ nanoseconds: UInt64) -> String {
        let milliseconds = Double(nanoseconds) / 1_000_000
        return milliseconds >= 1000
            ? String(format: "%.2f s", milliseconds / 1000)
            : String(format: "%.0f ms", milliseconds)
    }
}

private struct UsageMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String

    var body: some View {
        GroupBox {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
            .padding(6)
        }
    }
}

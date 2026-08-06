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
    @State private var isLoadingRequests = false
    @State private var message: PageMessage?
    @State private var dimensionQuery = ""
    @State private var requestOffset = 0
    @State private var requestPageSize = 100
    @State private var visibleRequestColumns = Set(RequestDetailColumn.allCases)
    @State private var requestSortColumn: RequestDetailColumn = .time
    @State private var requestSortAscending = false
    @State private var isShowingPriceBook = false
    @State private var trendZoomLevel = 0
    @State private var selectedTrendID: Date?
    @State private var selectedCostTrendID: Date?
    @State private var selectedModel: String?
    @State private var hoveredModel: String?
    @State private var selectedEfficiencyModel: String?
    @State private var showInput = true
    @State private var showOutput = true
    @State private var showCacheRead = true
    @State private var showCacheHitRate = true
    @State private var tokenDisplayMode: TokenDisplayMode = .full
    @State private var displayCurrency: UsageDisplayCurrency = .usd
    @State private var exchangeRate: TokenUsageExchangeRate?
    @State private var isLoadingExchangeRate = false

    private let client = ManagementAPIClient()
    private var modelRows: [ModelUsageRow] {
        ModelUsageRow.aggregate(stats?.groups ?? [])
    }

    private var knownModelNames: [String] {
        let dashboardModels = store.snapshot(for: node).availableModelGroups.flatMap { group in
            group.models.map(\.name)
        }
        return Set(dashboardModels + modelRows.map(\.model)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
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

    private var modelColors: [Color] {
        [.indigo, .mint, .orange, .pink, .teal, .purple, .yellow, .cyan, .red, .green]
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
                        HStack(alignment: .top, spacing: 14) {
                            trendChart(stats)
                            modelUsage
                        }
                        HStack(alignment: .top, spacing: 14) {
                            costChartPanel
                            efficiencyChart
                        }
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
        .task(id: node.id) {
            displayCurrency = .usd
            exchangeRate = nil
            await load()
        }
        .sheet(isPresented: $isShowingPriceBook, onDismiss: {
            Task { await load() }
        }) {
            TokenUsagePriceView(node: node, modelNames: knownModelNames)
                .environmentObject(store)
        }
        .onChange(of: selectedRange) {
            requestOffset = 0
            trendZoomLevel = 0
            selectedTrendID = nil
            selectedCostTrendID = nil
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
                isShowingPriceBook = true
            } label: {
                Label("模型价格", systemImage: "tag")
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

    private func metrics(_ stats: TokenUsageSnapshot) -> some View {
        let requestCount = stats.summary.requests
        let successfulRequests = requestCount >= stats.summary.failedRequests
            ? requestCount - stats.summary.failedRequests
            : 0
        let successRate = requestCount == 0
            ? 0
            : Double(successfulRequests) / Double(requestCount) * 100
        let topModel = modelRows.sorted {
            if $0.requests == $1.requests {
                return $0.totalTokens > $1.totalTokens
            }
            return $0.requests > $1.requests
        }.first

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 215), spacing: 12)],
            spacing: 12
        ) {
            UsageMetricCard(
                title: "总消耗 Token",
                value: formatTokenTotal(stats.summary.totalTokens),
                subtitle: "输入 \(stats.summary.inputTokens.formatted()) · 输出 \(stats.summary.outputTokens.formatted()) · 缓存读取 \(stats.summary.cacheReadTokens.formatted())",
                accessoryTitle: tokenDisplayMode.title,
                accessoryHelp: "切换为 \(tokenDisplayMode.next.title) 单位"
            ) {
                tokenDisplayMode = tokenDisplayMode.next
            }
            UsageMetricCard(
                title: "预估总费用",
                value: displayedTotalCost,
                subtitle: costCoverageText,
                accessoryTitle: displayCurrency.rawValue,
                accessoryHelp: displayCurrency == .usd ? "切换为人民币" : "切换为美元",
                accessoryDisabled: costs == nil || isLoadingExchangeRate
            ) {
                Task { await toggleCurrency() }
            }
            UsageMetricCard(
                title: "总请求次数",
                value: requestCount.formatted(),
                subtitle: String(format: "%.1f%%", successRate)
            )
            UsageMetricCard(
                title: "最常用模型",
                value: topModel?.model ?? "—",
                subtitle: topModel.map {
                    "\($0.requests.formatted()) 次调用 · \($0.totalTokens.formatted()) Tokens"
                } ?? "按调用次数统计",
                badge: topModel.map { modelBadge($0.model) } ?? "AI"
            )
        }
    }

    private var trendPoints: [TokenTrendPoint] {
        guard let stats else { return [] }
        return aggregateTrend(stats.series)
    }

    private var visibleTrendPoints: [TokenTrendPoint] {
        let points = trendPoints
        guard points.count > 8, trendZoomLevel > 0 else { return points }
        let divisor = pow(1.45, Double(trendZoomLevel))
        let count = max(8, Int(Double(points.count) / divisor))
        return Array(points.suffix(count))
    }

    private func trendChart(_ stats: TokenUsageSnapshot) -> some View {
        let points = visibleTrendPoints
        let tokenMaximum = max(points.map { $0.stackTotal }.max() ?? 1, 1)
        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Token 消耗趋势")
                            .font(.headline)
                        Text("输入 / 输出 / 缓存读取 Token 堆叠 · 缓存命中率虚线")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 5) {
                        Button {
                            trendZoomLevel = max(0, trendZoomLevel - 1)
                        } label: {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(trendZoomLevel == 0)
                        Button {
                            trendZoomLevel = min(4, trendZoomLevel + 1)
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(trendZoomLevel >= 4 || points.count <= 8)
                        Button("重置") { trendZoomLevel = 0 }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(trendZoomLevel == 0)
                    }
                }

                HStack(spacing: 14) {
                    chartLegendToggle("输入", color: .indigo, isOn: $showInput)
                    chartLegendToggle("输出", color: .mint, isOn: $showOutput)
                    chartLegendToggle("缓存读取", color: .orange, isOn: $showCacheRead)
                    chartLegendToggle("缓存命中率", color: .pink, isOn: $showCacheHitRate, dashed: true)
                    Spacer()
                }

                if points.isEmpty {
                    Text("当前范围没有时间序列数据")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    Chart {
                        ForEach(points) { point in
                            if showInput {
                                BarMark(
                                    x: .value("时间", point.date),
                                    y: .value("Tokens", point.inputTokens)
                                )
                                .foregroundStyle(Color.indigo)
                                .cornerRadius(3)
                            }
                            if showOutput {
                                BarMark(
                                    x: .value("时间", point.date),
                                    y: .value("Tokens", point.outputTokens)
                                )
                                .foregroundStyle(Color.mint)
                                .cornerRadius(3)
                            }
                            if showCacheRead {
                                BarMark(
                                    x: .value("时间", point.date),
                                    y: .value("Tokens", point.cacheReadTokens)
                                )
                                .foregroundStyle(Color.orange)
                                .cornerRadius(3)
                            }
                            if showCacheHitRate {
                                LineMark(
                                    x: .value("时间", point.date),
                                    y: .value("缓存命中率", point.cacheHitRate / 100 * tokenMaximum)
                                )
                                .foregroundStyle(Color.pink)
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                                PointMark(
                                    x: .value("时间", point.date),
                                    y: .value("缓存命中率", point.cacheHitRate / 100 * tokenMaximum)
                                )
                                .foregroundStyle(Color.pink)
                                .symbolSize(24)
                            }
                        }
                        if let selected = selectedTrendPoint(in: points) {
                            RuleMark(x: .value("时间", selected.date))
                                .foregroundStyle(.secondary.opacity(0.6))
                        }
                    }
                    .chartYScale(domain: 0...tokenMaximum)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                Text(compactNumber(value.as(Double.self) ?? 0))
                            }
                        }
                        AxisMarks(position: .trailing, values: [0, tokenMaximum * 0.25, tokenMaximum * 0.5, tokenMaximum * 0.75, tokenMaximum]) { value in
                            AxisGridLine().foregroundStyle(.clear)
                            AxisTick()
                            AxisValueLabel {
                                let tokenValue = value.as(Double.self) ?? 0
                                Text("\(Int((tokenValue / tokenMaximum * 100).rounded()))%")
                                    .foregroundStyle(Color.pink)
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 6)) { value in
                            AxisGridLine().foregroundStyle(.quaternary)
                            AxisTick()
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(chartTimeLabel(date))
                                }
                            }
                        }
                    }
                    .chartOverlay { proxy in
                        if let plotAnchor = proxy.plotFrame {
                            GeometryReader { geometry in
                                let plotFrame = geometry[plotAnchor]
                                ZStack(alignment: .topLeading) {
                                    Rectangle()
                                        .fill(Color.black.opacity(0.001))
                                        .contentShape(Rectangle())
                                        .onContinuousHover { phase in
                                            switch phase {
                                            case .active(let location):
                                                let relativeX = max(0, min(plotFrame.width, location.x - plotFrame.origin.x))
                                                let ratio = plotFrame.width > 0 ? relativeX / plotFrame.width : 0
                                                let index = min(points.count - 1, max(0, Int((ratio * Double(points.count - 1)).rounded())))
                                                selectedTrendID = points[index].id
                                            case .ended:
                                                selectedTrendID = nil
                                            }
                                        }
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { value in
                                                    let relativeX = max(0, min(plotFrame.width, value.location.x - plotFrame.origin.x))
                                                    let ratio = plotFrame.width > 0 ? relativeX / plotFrame.width : 0
                                                    let index = min(points.count - 1, max(0, Int((ratio * Double(points.count - 1)).rounded())))
                                                    selectedTrendID = points[index].id
                                                }
                                        )
                                    if let selected = selectedTrendPoint(in: points) {
                                        let selectedIndex = points.firstIndex(where: { $0.id == selected.id }) ?? 0
                                        let x = selectedIndex < points.count / 2
                                            ? plotFrame.maxX - 115
                                            : plotFrame.minX + 115
                                        trendTooltip(selected)
                                            .frame(width: 220)
                                            .position(
                                                x: max(plotFrame.minX + 110, min(plotFrame.maxX - 110, x)),
                                                y: plotFrame.minY + 88
                                            )
                                            .allowsHitTesting(false)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 260)
                }
            }
            .padding(8)
        } label: {
            Label("Token 消耗趋势", systemImage: "chart.bar.xaxis")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modelUsage: some View {
        let rows = modelRows
        let total = rows.reduce(UInt64(0)) { $0 &+ $1.totalTokens }
        let activeModel = hoveredModel ?? selectedModel
        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("模型调用占比")
                            .font(.headline)
                        Text("点击模型查看明细")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(rows.count) 个模型")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if rows.isEmpty {
                    Text("没有模型维度数据")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ZStack(alignment: .bottomTrailing) {
                        HStack(alignment: .top, spacing: 18) {
                            ZStack {
                                Chart(rows) { row in
                                    SectorMark(
                                        angle: .value("Tokens", max(1, row.totalTokens)),
                                        innerRadius: .ratio(0.62),
                                        angularInset: 1.5
                                    )
                                    .foregroundStyle(by: .value("模型", row.model))
                                    .opacity(activeModel == nil || activeModel == row.model ? 1 : 0.3)
                                }
                                .chartLegend(.hidden)
                                .chartForegroundStyleScale(
                                    domain: rows.map(\.model),
                                    range: rows.indices.map { modelColors[$0 % modelColors.count] }
                                )
                                .chartOverlay { proxy in
                                    if let plotAnchor = proxy.plotFrame {
                                        GeometryReader { geometry in
                                            let plotFrame = geometry[plotAnchor]
                                            Rectangle()
                                                .fill(Color.black.opacity(0.001))
                                                .contentShape(Rectangle())
                                                .onContinuousHover { phase in
                                                    switch phase {
                                                    case .active(let location):
                                                        hoveredModel = modelAtDonutLocation(
                                                            location,
                                                            plotFrame: plotFrame,
                                                            rows: rows
                                                        )
                                                    case .ended:
                                                        hoveredModel = nil
                                                    }
                                                }
                                        }
                                    }
                                }
                                VStack(spacing: 2) {
                                    Text(compactNumber(Double(total)))
                                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                                    Text("总 Tokens")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .allowsHitTesting(false)
                            }
                            .frame(width: 190, height: 205)

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                    Button {
                                        selectedModel = selectedModel == row.model ? nil : row.model
                                    } label: {
                                        modelLegendRow(
                                            row,
                                            color: modelColors[index % modelColors.count],
                                            total: total
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .help(row.model)
                                    .onHover { hovering in
                                        hoveredModel = hovering ? row.model : nil
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let activeModel,
                           let row = rows.first(where: { $0.model == activeModel }) {
                            modelTooltip(row, total: total)
                                .frame(width: 230)
                                .padding(10)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .padding(8)
        } label: {
            Label("模型调用占比", systemImage: "chart.pie.fill")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var costTrendPoints: [CostTrendPoint] {
        aggregateCostTrend(costs?.series ?? [])
    }

    @ViewBuilder
    private var costChartPanel: some View {
        if let costs {
            costTrend(costs)
        } else {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("费用趋势")
                        .font(.headline)
                    Text("当前节点没有返回价格时间序列，请确认插件版本和价格簿接口。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
                .padding(8)
            } label: {
                Label("费用趋势", systemImage: "chart.line.uptrend.xyaxis")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var efficiencyRows: [EfficiencyRow] {
        modelRows
            .filter { $0.requests > 0 }
            .map(EfficiencyRow.init)
            .sorted { $0.totalTokens > $1.totalTokens }
    }

    private func costTrend(_ costs: TokenUsageCosts) -> some View {
        let points = costTrendPoints
        let maximum = max(points.map(\.totalUSD).max() ?? 0, 0.0001)
        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("费用趋势")
                            .font(.headline)
                        Text("后端价格簿逐请求精确计算")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(currency(costs.summary.totalUSD, code: costs.currency))
                            .font(.subheadline.weight(.semibold))
                        Text("价格覆盖 \(costs.summary.pricedRequests.formatted()) / \(costs.summary.requests.formatted())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if points.isEmpty {
                    Text("当前范围没有费用时间序列")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    Chart {
                        ForEach(points) { point in
                            AreaMark(
                                x: .value("时间", point.date),
                                y: .value("费用", point.totalUSD)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.indigo.opacity(0.28), .indigo.opacity(0.03)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            LineMark(
                                x: .value("时间", point.date),
                                y: .value("费用", point.totalUSD)
                            )
                            .foregroundStyle(Color.indigo)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            PointMark(
                                x: .value("时间", point.date),
                                y: .value("费用", point.totalUSD)
                            )
                            .foregroundStyle(Color.indigo)
                            .symbolSize(selectedCostTrendID == point.id ? 65 : 28)
                        }
                        if let selected = selectedCostTrendPoint(in: points) {
                            RuleMark(x: .value("时间", selected.date))
                                .foregroundStyle(.secondary.opacity(0.6))
                        }
                    }
                    .chartYScale(domain: 0...maximum)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                Text(currency(value.as(Double.self) ?? 0, code: costs.currency))
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 6)) { value in
                            AxisGridLine().foregroundStyle(.quaternary)
                            AxisTick()
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(chartTimeLabel(date))
                                }
                            }
                        }
                    }
                    .chartOverlay { proxy in
                        if let plotAnchor = proxy.plotFrame {
                            GeometryReader { geometry in
                                let plotFrame = geometry[plotAnchor]
                                ZStack(alignment: .topLeading) {
                                    Rectangle()
                                        .fill(Color.black.opacity(0.001))
                                        .contentShape(Rectangle())
                                        .onContinuousHover { phase in
                                            switch phase {
                                            case .active(let location):
                                                let relativeX = max(0, min(plotFrame.width, location.x - plotFrame.origin.x))
                                                let ratio = plotFrame.width > 0 ? relativeX / plotFrame.width : 0
                                                let index = min(points.count - 1, max(0, Int((ratio * Double(points.count - 1)).rounded())))
                                                selectedCostTrendID = points[index].id
                                            case .ended:
                                                selectedCostTrendID = nil
                                            }
                                        }
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { value in
                                                    let relativeX = max(0, min(plotFrame.width, value.location.x - plotFrame.origin.x))
                                                    let ratio = plotFrame.width > 0 ? relativeX / plotFrame.width : 0
                                                    let index = min(points.count - 1, max(0, Int((ratio * Double(points.count - 1)).rounded())))
                                                    selectedCostTrendID = points[index].id
                                                }
                                        )
                                    if let selected = selectedCostTrendPoint(in: points) {
                                        let selectedIndex = points.firstIndex(where: { $0.id == selected.id }) ?? 0
                                        let x = selectedIndex < points.count / 2
                                            ? plotFrame.maxX - 115
                                            : plotFrame.minX + 115
                                        costTooltip(selected, currency: costs.currency)
                                            .frame(width: 220)
                                            .position(
                                                x: max(plotFrame.minX + 110, min(plotFrame.maxX - 110, x)),
                                                y: plotFrame.minY + 82
                                            )
                                            .allowsHitTesting(false)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 260)
                }
            }
            .padding(8)
        } label: {
            Label("费用趋势", systemImage: "chart.line.uptrend.xyaxis")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var efficiencyChart: some View {
        let rows = efficiencyRows
        let maximumTokens = max(rows.map(\.averageTokens).max() ?? 1, 1)
        let maximumLatency = max(rows.map(\.averageLatencySeconds).max() ?? 1, 1)
        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("模型效率")
                            .font(.headline)
                        Text("平均 Token / 请求 × 平均响应延迟")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(rows.count) 个模型")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if rows.isEmpty {
                    Text("没有足够的模型请求数据")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    Chart {
                        ForEach(rows) { row in
                            PointMark(
                                x: .value("平均 Token / 请求", row.averageTokens),
                                y: .value("平均响应延迟", row.averageLatencySeconds)
                            )
                            .foregroundStyle(by: .value("模型", row.model))
                            .symbolSize(180)
                            .opacity(selectedEfficiencyModel == nil || selectedEfficiencyModel == row.model ? 1 : 0.35)
                        }
                    }
                    .chartLegend(.hidden)
                    .chartForegroundStyleScale(
                        domain: rows.map(\.model),
                        range: rows.indices.map { modelColors[$0 % modelColors.count] }
                    )
                    .chartXScale(domain: 0...maximumTokens * 1.1)
                    .chartYScale(domain: 0...maximumLatency * 1.1)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5)) { value in
                            AxisGridLine().foregroundStyle(.quaternary)
                            AxisTick()
                            AxisValueLabel {
                                Text(compactNumber(value.as(Double.self) ?? 0))
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                Text(duration(seconds: value.as(Double.self) ?? 0))
                            }
                        }
                    }
                    .chartOverlay { proxy in
                        if let plotAnchor = proxy.plotFrame {
                            GeometryReader { geometry in
                                let plotFrame = geometry[plotAnchor]
                                ZStack(alignment: .topLeading) {
                                    Rectangle()
                                        .fill(Color.black.opacity(0.001))
                                        .contentShape(Rectangle())
                                        .onContinuousHover { phase in
                                            switch phase {
                                            case .active(let location):
                                                let x = plotFrame.width > 0
                                                    ? max(0, min(1, (location.x - plotFrame.origin.x) / plotFrame.width)) * maximumTokens * 1.1
                                                    : 0
                                                let y = plotFrame.height > 0
                                                    ? max(0, min(1, (plotFrame.maxY - location.y) / plotFrame.height)) * maximumLatency * 1.1
                                                    : 0
                                                selectedEfficiencyModel = nearestEfficiencyModel(toX: x, y: y, rows: rows)
                                            case .ended:
                                                selectedEfficiencyModel = nil
                                            }
                                        }
                                    if let selectedEfficiencyModel,
                                       let row = rows.first(where: { $0.model == selectedEfficiencyModel }) {
                                        let x = row.averageTokens < maximumTokens * 0.55
                                            ? plotFrame.maxX - 120
                                            : plotFrame.minX + 120
                                        efficiencyTooltip(row)
                                            .frame(width: 230)
                                            .position(
                                                x: max(plotFrame.minX + 115, min(plotFrame.maxX - 115, x)),
                                                y: plotFrame.minY + 72
                                            )
                                            .allowsHitTesting(false)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 260)

                    HStack(spacing: 10) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            Button {
                                selectedEfficiencyModel = selectedEfficiencyModel == row.model ? nil : row.model
                            } label: {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(modelColors[index % modelColors.count])
                                        .frame(width: 8, height: 8)
                                    Text(row.model)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(row.model)
                            .onHover { hovering in
                                selectedEfficiencyModel = hovering ? row.model : nil
                            }
                        }
                    }
                }
            }
            .padding(8)
        } label: {
            Label("模型效率", systemImage: "chart.scatter")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func aggregateTrend(_ source: [UsageSeriesPoint]) -> [TokenTrendPoint] {
        struct Accumulator {
            var date: Date
            var requests: UInt64 = 0
            var failedRequests: UInt64 = 0
            var inputTokens: UInt64 = 0
            var outputTokens: UInt64 = 0
            var cacheReadTokens: UInt64 = 0
            var cacheCreationTokens: UInt64 = 0
            var totalTokens: UInt64 = 0
        }

        var values: [Date: Accumulator] = [:]
        for point in source {
            guard let date = parseDate(point.hour) else { continue }
            let bucket = bucketDate(date)
            var value = values[bucket, default: Accumulator(date: bucket)]
            value.requests &+= point.requests
            value.failedRequests &+= point.failedRequests
            value.inputTokens &+= point.inputTokens
            value.outputTokens &+= point.outputTokens
            value.cacheReadTokens &+= point.cacheReadTokens
            value.cacheCreationTokens &+= point.cacheCreationTokens
            value.totalTokens &+= point.totalTokens
            values[bucket] = value
        }
        return values.values.sorted { $0.date < $1.date }.map {
            TokenTrendPoint(
                date: $0.date,
                requests: $0.requests,
                failedRequests: $0.failedRequests,
                inputTokens: $0.inputTokens,
                outputTokens: $0.outputTokens,
                cacheReadTokens: $0.cacheReadTokens,
                cacheCreationTokens: $0.cacheCreationTokens,
                totalTokens: $0.totalTokens
            )
        }
    }

    private func aggregateCostTrend(_ source: [TokenUsageCostSeriesPoint]) -> [CostTrendPoint] {
        struct Accumulator {
            var date: Date
            var requests: UInt64 = 0
            var pricedRequests: UInt64 = 0
            var inputUSD = 0.0
            var outputUSD = 0.0
            var cacheReadUSD = 0.0
            var cacheCreationUSD = 0.0
            var totalUSD = 0.0
        }

        var values: [Date: Accumulator] = [:]
        for point in source {
            guard let date = parseDate(point.hour) else { continue }
            let bucket = bucketDate(date)
            var value = values[bucket, default: Accumulator(date: bucket)]
            value.requests &+= point.requests
            value.pricedRequests &+= point.pricedRequests
            value.inputUSD += point.inputUSD
            value.outputUSD += point.outputUSD
            value.cacheReadUSD += point.cacheReadUSD
            value.cacheCreationUSD += point.cacheCreationUSD
            value.totalUSD += point.totalUSD
            values[bucket] = value
        }
        return values.values.sorted { $0.date < $1.date }.map {
            CostTrendPoint(
                date: $0.date,
                requests: $0.requests,
                pricedRequests: $0.pricedRequests,
                inputUSD: $0.inputUSD,
                outputUSD: $0.outputUSD,
                cacheReadUSD: $0.cacheReadUSD,
                cacheCreationUSD: $0.cacheCreationUSD,
                totalUSD: $0.totalUSD
            )
        }
    }

    private func bucketDate(_ date: Date) -> Date {
        let seconds: TimeInterval
        switch selectedRange {
        case .day: seconds = 60 * 60
        case .week: seconds = 6 * 60 * 60
        case .month, .retention: seconds = 24 * 60 * 60
        }
        return Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / seconds) * seconds)
    }

    private func parseDate(_ rawValue: String) -> Date? {
        ISO8601DateFormatter().date(from: rawValue)
    }

    @ViewBuilder
    private func chartLegendToggle(
        _ title: String,
        color: Color,
        isOn: Binding<Bool>,
        dashed: Bool = false
    ) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: dashed ? 18 : 10, height: dashed ? 3 : 10)
                    .overlay {
                        if dashed {
                            Rectangle()
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(isOn.wrappedValue ? .primary : .tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func selectedTrendPoint(in points: [TokenTrendPoint]) -> TokenTrendPoint? {
        guard let selectedTrendID else { return nil }
        return points.first { $0.id == selectedTrendID }
    }

    private func trendTooltip(_ point: TokenTrendPoint) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(point.date.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
            chartTooltipRow("输入", compactNumber(Double(point.inputTokens)), color: .indigo)
            chartTooltipRow("输出", compactNumber(Double(point.outputTokens)), color: .mint)
            chartTooltipRow("缓存读取", compactNumber(Double(point.cacheReadTokens)), color: .orange)
            chartTooltipRow("缓存命中率", String(format: "%.1f%%", point.cacheHitRate), color: .pink)
            chartTooltipRow("总 Tokens", compactNumber(Double(point.stackTotal)))
            chartTooltipRow("请求次数", point.requests.formatted())
        }
        .padding(10)
        .frame(minWidth: 190, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 8, y: 3)
    }

    private func modelLegendRow(_ row: ModelUsageRow, color: Color, total: UInt64) -> some View {
        let percentage = total == 0 ? 0 : Double(row.totalTokens) / Double(total) * 100
        return HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.model)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("\(row.requests.formatted()) 次 · \(compactNumber(Double(row.totalTokens)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(String(format: "%.1f%%", percentage))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func modelTooltip(_ row: ModelUsageRow, total: UInt64) -> some View {
        let percentage = total == 0 ? 0 : Double(row.totalTokens) / Double(total) * 100
        return VStack(alignment: .leading, spacing: 5) {
            Text(row.model)
                .font(.headline)
                .lineLimit(1)
            chartTooltipRow("请求次数", row.requests.formatted())
            chartTooltipRow("总 Tokens", row.totalTokens.formatted())
            chartTooltipRow("占比", String(format: "%.2f%%", percentage))
            chartTooltipRow("平均延迟", duration(row.averageLatencyNS))
        }
        .padding(10)
        .frame(minWidth: 210, maxWidth: 230, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 8, y: 3)
    }

    private func selectedCostTrendPoint(in points: [CostTrendPoint]) -> CostTrendPoint? {
        guard let selectedCostTrendID else { return nil }
        return points.first { $0.id == selectedCostTrendID }
    }

    private func costTooltip(_ point: CostTrendPoint, currency currencyCode: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(point.date.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
            chartTooltipRow("精确费用", currency(point.totalUSD, code: currencyCode))
            chartTooltipRow("输入", currency(point.inputUSD, code: currencyCode))
            chartTooltipRow("输出", currency(point.outputUSD, code: currencyCode))
            chartTooltipRow("缓存读取", currency(point.cacheReadUSD, code: currencyCode))
            chartTooltipRow("价格覆盖", "\(point.pricedRequests.formatted()) / \(point.requests.formatted())")
        }
        .padding(10)
        .frame(minWidth: 190, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 8, y: 3)
    }

    private func efficiencyTooltip(_ row: EfficiencyRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(row.model)
                .font(.headline)
                .lineLimit(1)
            chartTooltipRow("平均 Token / 请求", row.averageTokens.formatted(.number.precision(.fractionLength(0))))
            chartTooltipRow("平均响应延迟", duration(seconds: row.averageLatencySeconds))
            chartTooltipRow("请求次数", row.requests.formatted())
            chartTooltipRow("总 Tokens", row.totalTokens.formatted())
        }
        .padding(10)
        .frame(minWidth: 210, maxWidth: 230, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 8, y: 3)
    }

    private func chartTooltipRow(_ title: String, _ value: String, color: Color? = nil) -> some View {
        HStack(spacing: 7) {
            if let color {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 10)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption)
    }

    private func nearestEfficiencyModel(toX x: Double, y: Double, rows: [EfficiencyRow]) -> String? {
        rows.min { lhs, rhs in
            let left = pow((lhs.averageTokens - x) / max(x, 1), 2)
                + pow((lhs.averageLatencySeconds - y) / max(y, 1), 2)
            let right = pow((rhs.averageTokens - x) / max(x, 1), 2)
                + pow((rhs.averageLatencySeconds - y) / max(y, 1), 2)
            return left < right
        }?.model
    }

    private func modelAtDonutLocation(
        _ location: CGPoint,
        plotFrame: CGRect,
        rows: [ModelUsageRow]
    ) -> String? {
        let deltaX = location.x - plotFrame.midX
        let deltaY = location.y - plotFrame.midY
        let outerRadius = min(plotFrame.width, plotFrame.height) / 2
        let distance = hypot(deltaX, deltaY)
        guard distance >= outerRadius * 0.58, distance <= outerRadius else { return nil }

        var clockwiseAngle = atan2(deltaX, -deltaY)
        if clockwiseAngle < 0 {
            clockwiseAngle += 2 * .pi
        }

        let weights = rows.map { Double(max(UInt64(1), $0.totalTokens)) }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return nil }
        let target = clockwiseAngle / (2 * .pi) * totalWeight
        var accumulated = 0.0
        for (index, weight) in weights.enumerated() {
            accumulated += weight
            if target <= accumulated {
                return rows[index].model
            }
        }
        return rows.last?.model
    }

    private var displayedTotalCost: String {
        guard let costs else { return "—" }
        return currency(costs.summary.totalUSD, code: costs.currency)
    }

    private var costCoverageText: String {
        guard let costs else { return "等待精确费用数据" }
        var value = "价格覆盖 \(costs.summary.pricedRequests.formatted()) / \(costs.summary.requests.formatted()) · 未定价 \(costs.summary.unpricedRequests.formatted())"
        if displayCurrency == .cny, let exchangeRate {
            value += String(format: " · 1 USD = %.4f CNY", exchangeRate.rate)
            if exchangeRate.stale {
                value += " · 缓存汇率"
            }
        }
        return value
    }

    private func formatTokenTotal(_ value: UInt64) -> String {
        switch tokenDisplayMode {
        case .full:
            return value.formatted()
        case .thousands:
            return scaledNumber(Double(value) / 1_000) + "k"
        case .millions:
            return scaledNumber(Double(value) / 1_000_000) + "m"
        }
    }

    private func scaledNumber(_ value: Double) -> String {
        value.formatted(
            .number
                .grouping(.automatic)
                .precision(.fractionLength(0...2))
        )
    }

    private func modelBadge(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "AI" }
        return String(trimmed.prefix(2)).uppercased()
    }

    @MainActor
    private func toggleCurrency() async {
        if displayCurrency == .cny {
            displayCurrency = .usd
            return
        }
        isLoadingExchangeRate = true
        defer { isLoadingExchangeRate = false }
        do {
            let loadedRate: TokenUsageExchangeRate
            if let exchangeRate {
                loadedRate = exchangeRate
            } else {
                loadedRate = try await client.fetchTokenUsageExchangeRate(node: node)
            }
            exchangeRate = loadedRate
            displayCurrency = .cny
        } catch {
            displayCurrency = .usd
            message = .error("人民币汇率不可用：\(ManagementAPIClient.friendlyMessage(for: error))")
        }
    }

    private func compactNumber(_ value: Double) -> String {
        let absolute = abs(value)
        if absolute >= 1_000_000_000 {
            return String(format: "%.1fB", value / 1_000_000_000)
        }
        if absolute >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if absolute >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    private func currency(_ value: Double, code: String) -> String {
        let sourceCode = code.uppercased()
        let convertedValue: Double
        let shownCode: String
        if sourceCode == "USD", displayCurrency == .cny, let exchangeRate {
            convertedValue = value * exchangeRate.rate
            shownCode = "CNY"
        } else {
            convertedValue = value
            shownCode = sourceCode
        }
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .currency
        formatter.currencyCode = shownCode
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = convertedValue < 1 ? 4 : 2
        return formatter.string(from: NSNumber(value: convertedValue))
            ?? "\(shownCode) \(String(format: "%.2f", convertedValue))"
    }

    private func chartTimeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = selectedRange == .day ? "M/d HH:mm" : "M/d"
        return formatter.string(from: date)
    }

    private func duration(seconds: Double) -> String {
        seconds >= 1
            ? String(format: "%.1f s", seconds)
            : String(format: "%.0f ms", seconds * 1000)
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
        GroupBox {
            if let requests, !requests.items.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Text("逐请求记录，支持当前页排序与列显示设置，默认最新优先")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(requests.total.formatted()) 条请求 · 价格簿 #\((requests.priceBookRevision ?? 0).formatted())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("每页行数", selection: $requestPageSize) {
                            ForEach([25, 50, 100, 200, 500], id: \.self) { size in
                                Text("\(size)").tag(size)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 82)
                        .onChange(of: requestPageSize) { _, _ in
                            requestOffset = 0
                            Task { await changeRequestPage(by: 0) }
                        }
                        requestColumnMenu
                        Button("上一页") {
                            Task { await changeRequestPage(by: -1) }
                        }
                        .disabled(!requests.hasPreviousPage || isLoadingRequests)
                        if let range = requests.displayedRange {
                            Text("\(range.lowerBound)–\(range.upperBound) / \(requests.total)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Button("下一页") {
                            Task { await changeRequestPage(by: 1) }
                        }
                        .disabled(!requests.hasNextPage || isLoadingRequests)
                    }

                    ScrollView(.horizontal) {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                            GridRow {
                                ForEach(orderedRequestColumns) { column in
                                    requestColumnHeader(column)
                                }
                            }
                            Divider()
                            ForEach(sortedRequestItems(requests.items)) { item in
                                GridRow {
                                    ForEach(orderedRequestColumns) { column in
                                        requestCell(item, column: column)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Divider()
                    HStack {
                        Spacer()
                        if isLoadingRequests {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("费用按当前价格簿逐请求估算")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            } else {
                Text("没有逐请求明细")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        } label: {
            Label("请求明细", systemImage: "list.bullet.rectangle")
        }
    }

    private var orderedRequestColumns: [RequestDetailColumn] {
        RequestDetailColumn.allCases.filter(visibleRequestColumns.contains)
    }

    private var requestColumnMenu: some View {
        Menu("列设置", systemImage: "rectangle.3.group") {
            Button("全部显示") {
                visibleRequestColumns = Set(RequestDetailColumn.allCases)
            }
            Divider()
            ForEach(RequestDetailColumn.allCases) { column in
                Toggle(
                    column.title,
                    isOn: Binding(
                        get: { visibleRequestColumns.contains(column) },
                        set: { visible in
                            if visible {
                                visibleRequestColumns.insert(column)
                            } else if visibleRequestColumns.count > 1 {
                                visibleRequestColumns.remove(column)
                            }
                        }
                    )
                )
            }
        }
    }

    private func requestColumnHeader(_ column: RequestDetailColumn) -> some View {
        Button {
            if requestSortColumn == column {
                requestSortAscending.toggle()
            } else {
                requestSortColumn = column
                requestSortAscending = column != .time
            }
        } label: {
            HStack(spacing: 4) {
                Text(column.title)
                if requestSortColumn == column {
                    Image(systemName: requestSortAscending ? "arrow.up" : "arrow.down")
                        .font(.caption2)
                }
            }
            .fontWeight(.semibold)
            .frame(width: column.width, alignment: column.alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func requestCell(_ item: UsageRequestItem, column: RequestDetailColumn) -> some View {
        requestCellContent(item, column: column)
            .frame(width: column.width, alignment: column.alignment)
            .lineLimit(1)
    }

    @ViewBuilder
    private func requestCellContent(_ item: UsageRequestItem, column: RequestDetailColumn) -> some View {
        switch column {
        case .time:
            Text(shortTime(item.time)).foregroundStyle(.secondary)
        case .model:
            Text(item.model.isEmpty ? "未标记模型" : item.model).help(item.model)
        case .source:
            Text(item.source.isEmpty ? "—" : item.source)
        case .serviceTier:
            Text(item.serviceTier.isEmpty ? "—" : item.serviceTier)
        case .priceServiceTier:
            Text(nonBlank(item.estimatedCost?.priceServiceTier))
                .foregroundStyle(item.estimatedCost?.priceServiceTier == nil ? .secondary : .primary)
        case .result:
            Text(item.result)
                .foregroundStyle(item.failed ? Color.red : Color.green)
                .fontWeight(.medium)
        case .ttft:
            Text(duration(item.ttftNS)).fontDesign(.monospaced)
        case .generation:
            Text(duration(item.effectiveGenerationNS)).fontDesign(.monospaced)
        case .tps:
            Text(String(format: "%.2f", item.tps)).fontDesign(.monospaced)
        case .reasoningEffort:
            Text(nonBlank(item.reasoningEffort))
        case .input:
            requestNumber(item.inputTokens)
        case .output:
            requestNumber(item.outputTokens)
        case .reasoning:
            requestNumber(item.reasoningTokens)
        case .cacheRead:
            requestNumber(item.cacheReadTokens)
        case .cacheCreation:
            requestNumber(item.cacheCreationTokens)
        case .totalTokens:
            requestNumber(item.totalTokens)
        case .cacheHit:
            Text(item.effectiveCacheHit ? "命中" : "未命中")
                .foregroundStyle(item.effectiveCacheHit ? Color.green : Color.secondary)
        case .estimatedCost:
            if let cost = item.estimatedCost, cost.priced {
                Text(currency(cost.totalUSD, code: "USD"))
                    .fontDesign(.monospaced)
                    .help(requestCostBreakdown(cost))
            } else {
                Text("未定价").foregroundStyle(.secondary)
            }
        case .priceSource:
            Text(item.estimatedCost?.priced == true ? nonBlank(item.estimatedCost?.source) : "—")
        }
    }

    private func requestNumber(_ value: UInt64) -> some View {
        Text(value.formatted()).fontDesign(.monospaced)
    }

    private func requestCostBreakdown(_ cost: UsageRequestEstimatedCost) -> String {
        var parts = [
            "输入 \(currency(cost.inputUSD, code: "USD"))",
            "输出 \(currency(cost.outputUSD, code: "USD"))",
            "缓存读取 \(currency(cost.cacheReadUSD, code: "USD"))",
            "缓存创建 \(currency(cost.cacheCreationUSD, code: "USD"))"
        ]
        if let tier = cost.priceServiceTier, !tier.isEmpty {
            parts.append("计价 Tier \(tier)")
        }
        if let threshold = cost.tierThreshold, threshold > 0 {
            parts.append("Context Tier > \(threshold.formatted())")
        }
        return parts.joined(separator: " · ")
    }

    private func sortedRequestItems(_ items: [UsageRequestItem]) -> [UsageRequestItem] {
        items.sorted { lhs, rhs in
            let comparison = compareRequestItems(lhs, rhs, column: requestSortColumn)
            if comparison == .orderedSame {
                return requestSortAscending ? lhs.sequence < rhs.sequence : lhs.sequence > rhs.sequence
            }
            return requestSortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    private func compareRequestItems(
        _ lhs: UsageRequestItem,
        _ rhs: UsageRequestItem,
        column: RequestDetailColumn
    ) -> ComparisonResult {
        switch column {
        case .time:
            return compareValues(requestDate(lhs.time) ?? .distantPast, requestDate(rhs.time) ?? .distantPast)
        case .model:
            return compareValues(lhs.model, rhs.model)
        case .source:
            return compareValues(lhs.source, rhs.source)
        case .serviceTier:
            return compareValues(lhs.serviceTier, rhs.serviceTier)
        case .priceServiceTier:
            return compareValues(
                lhs.estimatedCost?.priceServiceTier ?? "",
                rhs.estimatedCost?.priceServiceTier ?? ""
            )
        case .result:
            return compareValues(lhs.result, rhs.result)
        case .ttft:
            return compareValues(lhs.ttftNS, rhs.ttftNS)
        case .generation:
            return compareValues(lhs.effectiveGenerationNS, rhs.effectiveGenerationNS)
        case .tps:
            return compareValues(lhs.tps, rhs.tps)
        case .reasoningEffort:
            return compareValues(lhs.reasoningEffort ?? "", rhs.reasoningEffort ?? "")
        case .input:
            return compareValues(lhs.inputTokens, rhs.inputTokens)
        case .output:
            return compareValues(lhs.outputTokens, rhs.outputTokens)
        case .reasoning:
            return compareValues(lhs.reasoningTokens, rhs.reasoningTokens)
        case .cacheRead:
            return compareValues(lhs.cacheReadTokens, rhs.cacheReadTokens)
        case .cacheCreation:
            return compareValues(lhs.cacheCreationTokens, rhs.cacheCreationTokens)
        case .totalTokens:
            return compareValues(lhs.totalTokens, rhs.totalTokens)
        case .cacheHit:
            return compareValues(lhs.effectiveCacheHit ? 1 : 0, rhs.effectiveCacheHit ? 1 : 0)
        case .estimatedCost:
            return compareValues(
                lhs.estimatedCost?.priced == true ? lhs.estimatedCost?.totalUSD ?? 0 : -1,
                rhs.estimatedCost?.priced == true ? rhs.estimatedCost?.totalUSD ?? 0 : -1
            )
        case .priceSource:
            return compareValues(lhs.estimatedCost?.source ?? "", rhs.estimatedCost?.source ?? "")
        }
    }

    private func compareValues<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    private func nonBlank(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "—" : trimmed
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
            async let loadedRequests = client.fetchTokenUsageRequests(
                range: selectedRange,
                node: node,
                offset: requestOffset,
                limit: requestPageSize
            )
            let result = try await loadedStats
            stats = result
            costs = try? await loadedCosts
            requests = try? await loadedRequests
            if let requests {
                requestOffset = requests.offset
            }
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

    @MainActor
    private func changeRequestPage(by pageDelta: Int) async {
        let targetOffset = max(0, requestOffset + pageDelta * requestPageSize)
        isLoadingRequests = true
        defer { isLoadingRequests = false }
        do {
            let page = try await client.fetchTokenUsageRequests(
                range: selectedRange,
                node: node,
                offset: targetOffset,
                limit: requestPageSize
            )
            requests = page
            requestOffset = page.offset
        } catch {
            message = .error(ManagementAPIClient.friendlyMessage(for: error))
        }
    }

    private func shortTime(_ rawValue: String) -> String {
        guard let date = requestDate(rawValue) else { return rawValue }
        return date.formatted(date: .numeric, time: .standard)
    }

    private func requestDate(_ rawValue: String) -> Date? {
        if let date = try? Date(
            rawValue,
            strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        ) {
            return date
        }
        return try? Date(rawValue, strategy: Date.ISO8601FormatStyle())
    }

    private func duration(_ nanoseconds: UInt64) -> String {
        let milliseconds = Double(nanoseconds) / 1_000_000
        return milliseconds >= 1000
            ? String(format: "%.2f s", milliseconds / 1000)
            : String(format: "%.0f ms", milliseconds)
    }
}

private enum RequestDetailColumn: String, CaseIterable, Identifiable {
    case time
    case model
    case source
    case serviceTier
    case priceServiceTier
    case result
    case ttft
    case generation
    case tps
    case reasoningEffort
    case input
    case output
    case reasoning
    case cacheRead
    case cacheCreation
    case totalTokens
    case cacheHit
    case estimatedCost
    case priceSource

    var id: String { rawValue }

    var title: String {
        switch self {
        case .time: "时间"
        case .model: "模型名称"
        case .source: "来源"
        case .serviceTier: "请求 Tier"
        case .priceServiceTier: "计价 Tier"
        case .result: "结果"
        case .ttft: "首字延迟"
        case .generation: "生成时间"
        case .tps: "TPS"
        case .reasoningEffort: "思考强度"
        case .input: "输入"
        case .output: "输出"
        case .reasoning: "思考"
        case .cacheRead: "缓存读取"
        case .cacheCreation: "缓存创建"
        case .totalTokens: "总 Token 数"
        case .cacheHit: "缓存命中"
        case .estimatedCost: "预估费用"
        case .priceSource: "价格来源"
        }
    }

    var width: CGFloat {
        switch self {
        case .time: 170
        case .model: 180
        case .source: 130
        case .serviceTier, .priceServiceTier, .reasoningEffort: 100
        case .result: 125
        case .ttft, .generation: 95
        case .tps, .cacheHit: 80
        case .input, .output, .reasoning, .cacheRead, .cacheCreation, .totalTokens: 110
        case .estimatedCost: 115
        case .priceSource: 105
        }
    }

    var alignment: Alignment {
        switch self {
        case .ttft, .generation, .tps, .input, .output, .reasoning,
             .cacheRead, .cacheCreation, .totalTokens, .estimatedCost:
            .trailing
        default:
            .leading
        }
    }
}

private struct TokenTrendPoint: Identifiable {
    let date: Date
    let requests: UInt64
    let failedRequests: UInt64
    let inputTokens: UInt64
    let outputTokens: UInt64
    let cacheReadTokens: UInt64
    let cacheCreationTokens: UInt64
    let totalTokens: UInt64

    var id: Date { date }
    var stackTotal: Double {
        Double(inputTokens) + Double(outputTokens) + Double(cacheReadTokens)
    }
    var cacheHitRate: Double {
        TokenUsageMetrics.cacheHitRate(
            inputTokens: inputTokens,
            cacheReadTokens: cacheReadTokens
        )
    }
}

private struct CostTrendPoint: Identifiable {
    let date: Date
    let requests: UInt64
    let pricedRequests: UInt64
    let inputUSD: Double
    let outputUSD: Double
    let cacheReadUSD: Double
    let cacheCreationUSD: Double
    let totalUSD: Double

    var id: Date { date }
}

private struct EfficiencyRow: Identifiable {
    let model: String
    let requests: UInt64
    let totalTokens: UInt64
    let averageTokens: Double
    let averageLatencySeconds: Double

    var id: String { model }
    var bubbleSize: Double {
        max(80, min(600, sqrt(Double(requests)) * 24))
    }

    init(_ row: ModelUsageRow) {
        model = row.model
        requests = row.requests
        totalTokens = row.totalTokens
        averageTokens = row.averageTokens
        averageLatencySeconds = Double(row.averageLatencyNS) / 1_000_000_000
    }
}

private enum TokenDisplayMode {
    case full
    case thousands
    case millions

    var title: String {
        switch self {
        case .full: "完整"
        case .thousands: "k"
        case .millions: "m"
        }
    }

    var next: TokenDisplayMode {
        switch self {
        case .full: .thousands
        case .thousands: .millions
        case .millions: .full
        }
    }
}

private enum UsageDisplayCurrency: String {
    case usd = "USD"
    case cny = "CNY"
}

private struct UsageMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let badge: String?
    let accessoryTitle: String?
    let accessoryHelp: String
    let accessoryDisabled: Bool
    let action: (() -> Void)?

    init(
        title: String,
        value: String,
        subtitle: String,
        badge: String? = nil,
        accessoryTitle: String? = nil,
        accessoryHelp: String = "",
        accessoryDisabled: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.badge = badge
        self.accessoryTitle = accessoryTitle
        self.accessoryHelp = accessoryHelp
        self.accessoryDisabled = accessoryDisabled
        self.action = action
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.indigo.opacity(0.8))
                        .frame(width: 7, height: 7)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let accessoryTitle, let action {
                        Button(action: action) {
                            Text(accessoryTitle)
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(accessoryDisabled)
                        .help(accessoryHelp)
                    }
                }

                HStack(spacing: 10) {
                    if let badge {
                        Text(badge)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.indigo)
                            .frame(width: 36, height: 36)
                            .background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                    }
                    Text(value)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .help(value)
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        }
    }
}

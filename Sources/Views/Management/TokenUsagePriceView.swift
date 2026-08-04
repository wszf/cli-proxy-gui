import SwiftUI

struct TokenUsagePriceView: View {
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss

    let node: ProxyNode
    let modelNames: [String]

    @State private var priceBook: TokenUsagePriceBook?
    @State private var drafts: [ModelPriceDraft] = []
    @State private var newModelName = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var isSyncing = false
    @State private var message: PageMessage?

    private let client = ManagementAPIClient()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading && priceBook == nil {
                ProgressView("正在读取模型价格…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if priceBook != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summary
                        priceExplanation
                        addModelRow
                        priceRows
                    }
                    .padding(20)
                }
            } else {
                ContentUnavailableView {
                    Label("无法读取模型价格", systemImage: "tag.slash")
                } description: {
                    Text("请确认 cap-token-usage-tracker 已升级到支持价格接口的版本。")
                } actions: {
                    Button("重试") { Task { await load() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            footer

            if let message {
                MessageBar(message: message)
            }
        }
        .frame(minWidth: 980, minHeight: 650)
        .task(id: node.id) { await load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("模型价格")
                    .font(.title2.weight(.semibold))
                Text("cap-token-usage-tracker · \(node.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await syncFromModelsDev() }
            } label: {
                Label(
                    isSyncing ? "同步中…" : "从 Models.dev 同步",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .disabled(isLoading || isSaving || isSyncing || modelNames.isEmpty || managementKey.isEmpty)
            .help(modelNames.isEmpty
                ? "当前没有可同步的 CLIProxyAPI 模型"
                : "优先由 VPS 同步；服务器返回 502/504 时自动切换到客户端同步")
            Button("完成") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    private var summary: some View {
        HStack(spacing: 18) {
            Label("已配置 \(drafts.count) 个模型", systemImage: "number")
            if let lastSync = priceBook?.lastSync {
                Label(
                    "最近同步：匹配 \(lastSync.matched) / \(lastSync.observed)",
                    systemImage: "clock.arrow.circlepath"
                )
            } else {
                Label("尚未同步", systemImage: "clock")
            }
            Spacer()
            if managementKey.isEmpty {
                Label("保存和同步需要 Management Key", systemImage: "lock")
                    .foregroundStyle(.orange)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var priceExplanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("价格单位：USD / 1M Token", systemImage: "info.circle")
                .font(.headline)
            Text("保存后，插件会使用当前价格簿重新估算历史请求费用。手工修改会标记为 manual，后续 Models.dev 同步不会覆盖；已有 Context Tier 会原样保留。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("同步优先在 VPS 上执行；如果 VPS 无法访问 Models.dev，客户端会自动改用 Mac 获取目录，再通过 Management Key 保存结果。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }

    private var addModelRow: some View {
        HStack(spacing: 10) {
            TextField("添加模型 ID，例如 openai/gpt-5", text: $newModelName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { addModel() }
            Button("添加", systemImage: "plus") { addModel() }
                .disabled(newModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var priceRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("模型").frame(width: 270, alignment: .leading)
                Text("Input").frame(width: 110, alignment: .leading)
                Text("Output").frame(width: 110, alignment: .leading)
                Text("Cache Read").frame(width: 110, alignment: .leading)
                Text("Cache Creation").frame(width: 130, alignment: .leading)
                Text("").frame(width: 28)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if drafts.isEmpty {
                Text("当前没有价格条目。可以先同步当前模型，或手动添加模型 ID。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ForEach($drafts) { $draft in
                    ModelPriceDraftRow(draft: $draft) {
                        removeModel(draft.model)
                    }
                    Divider()
                }
            }
        }
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private var footer: some View {
        HStack {
            if let priceBook {
                Text("价格簿修订版 \(priceBook.revision)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button {
                Task { await save() }
            } label: {
                Label(isSaving ? "保存中…" : "保存价格", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(priceBook == nil || isLoading || isSaving || isSyncing || managementKey.isEmpty)
        }
        .padding(14)
    }

    private var managementKey: String {
        store.key(for: node)
    }

    @MainActor
    private func load() async {
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            let loaded = try await client.fetchTokenUsagePrices(node: node)
            apply(loaded)
        } catch {
            priceBook = nil
            drafts = []
            message = .error(priceErrorMessage(for: error))
        }
    }

    @MainActor
    private func syncFromModelsDev() async {
        guard !managementKey.isEmpty else {
            message = .error("尚未保存 Management Key")
            return
        }
        guard !modelNames.isEmpty else {
            message = .error("当前没有可同步的 CLIProxyAPI 模型")
            return
        }
        isSyncing = true
        message = nil
        defer { isSyncing = false }
        do {
            let settings = priceBook?.syncSettings
            let synced = try await client.syncTokenUsagePrices(
                models: modelNames,
                syncSettings: settings,
                node: node,
                managementKey: managementKey
            )
            apply(synced)
            if let lastSync = synced.lastSync {
                message = .success("Models.dev 同步完成：匹配 \(lastSync.matched) 个，未匹配 \(lastSync.unmatched) 个。")
            } else {
                message = .success("Models.dev 同步完成。")
            }
        } catch {
            guard shouldFallbackToClientSync(error), let existing = priceBook else {
                message = .error(priceErrorMessage(for: error))
                return
            }
            do {
                let fallback = try await client.syncTokenUsagePricesFromClient(
                    models: modelNames,
                    existing: existing,
                    syncSettings: existing.syncSettings,
                    node: node,
                    managementKey: managementKey
                )
                apply(fallback.priceBook)
                message = .success(
                    "VPS 无法访问 Models.dev，已改用客户端同步：匹配 (fallback.matched) 个，未匹配 (fallback.unmatched) 个。"
                )
            } catch {
                message = .error(
                    "服务器同步超时，客户端同步也失败：\(priceErrorMessage(for: error))"
                )
            }
        }
    }

    @MainActor
    private func save() async {
        guard let priceBook else { return }
        guard !managementKey.isEmpty else {
            message = .error("尚未保存 Management Key")
            return
        }

        var prices: [String: ModelPrice] = [:]
        for draft in drafts {
            guard let input = priceValue(draft.input),
                  let output = priceValue(draft.output),
                  let cacheRead = priceValue(draft.cacheRead),
                  let cacheCreation = priceValue(draft.cacheCreation)
            else {
                message = .error("模型 \(draft.model) 的价格必须是非负数字。")
                return
            }

            var price = draft.original
            let changed = price.input != input
                || price.output != output
                || price.cacheRead != cacheRead
                || price.cacheCreation != cacheCreation
            price.input = input
            price.output = output
            price.cacheRead = cacheRead
            price.cacheCreation = cacheCreation
            if changed {
                price.source = "manual"
                price.catalogProvider = ""
                price.catalogModel = ""
                price.updatedAt = nil
            }
            prices[draft.model] = price
        }

        isSaving = true
        message = nil
        defer { isSaving = false }
        do {
            let saved = try await client.saveTokenUsagePrices(
                prices: prices,
                syncSettings: priceBook.syncSettings,
                node: node,
                managementKey: managementKey
            )
            apply(saved)
            message = .success("模型价格已保存，历史费用会按新价格重新估算。")
        } catch {
            message = .error(priceErrorMessage(for: error))
        }
    }

    private func addModel() {
        let model = newModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }
        guard !drafts.contains(where: { $0.model.caseInsensitiveCompare(model) == .orderedSame }) else {
            message = .error("模型 \(model) 已存在。")
            return
        }
        drafts.append(ModelPriceDraft(model: model, original: ModelPrice()))
        drafts.sort { $0.model.localizedStandardCompare($1.model) == .orderedAscending }
        newModelName = ""
    }

    private func removeModel(_ model: String) {
        drafts.removeAll { $0.model == model }
    }

    private func apply(_ book: TokenUsagePriceBook) {
        priceBook = book
        drafts = book.prices
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { ModelPriceDraft(model: $0.key, original: $0.value) }
    }

    private func priceValue(_ rawValue: String) -> Double? {
        guard let value = Double(rawValue), value.isFinite, value >= 0 else { return nil }
        return value
    }

    private func priceErrorMessage(for error: Error) -> String {
        let text = ManagementAPIClient.friendlyMessage(for: error)
        if text.contains("404") {
            return "当前 cap-token-usage-tracker 不支持模型价格接口，请升级插件。"
        }
        return text
    }

    private func shouldFallbackToClientSync(_ error: Error) -> Bool {
        guard case let APIError.httpStatus(code, _) = error else { return false }
        return code == 502 || code == 504
    }
}

private struct ModelPriceDraft: Identifiable, Equatable {
    let model: String
    let original: ModelPrice
    var input: String
    var output: String
    var cacheRead: String
    var cacheCreation: String

    var id: String { model }

    init(model: String, original: ModelPrice) {
        self.model = model
        self.original = original
        input = Self.formatted(original.input)
        output = Self.formatted(original.output)
        cacheRead = Self.formatted(original.cacheRead)
        cacheCreation = Self.formatted(original.cacheCreation)
    }

    var source: String {
        switch original.source {
        case "models.dev": "Models.dev"
        case "manual": "手工"
        case "": "—"
        default: original.source
        }
    }

    private static func formatted(_ value: Double) -> String {
        if value == 0 { return "0" }
        return String(format: "%.8f", value)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }
}

private struct ModelPriceDraftRow: View {
    @Binding var draft: ModelPriceDraft
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.model)
                    .font(.system(.callout, design: .monospaced, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(draft.source)
                    if !draft.original.contextTiers.isEmpty {
                        Text("· \(draft.original.contextTiers.count) 个 Context Tier")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(width: 270, alignment: .leading)

            PriceTextField(text: $draft.input)
            PriceTextField(text: $draft.output)
            PriceTextField(text: $draft.cacheRead)
            PriceTextField(text: $draft.cacheCreation)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .frame(width: 28)
            .help("删除此价格条目")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct PriceTextField: View {
    @Binding var text: String

    var body: some View {
        TextField("0", text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.system(.callout, design: .monospaced))
            .frame(width: 110)
    }
}

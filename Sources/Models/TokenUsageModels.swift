import Foundation

enum UsageRange: String, CaseIterable, Identifiable, Sendable {
    case day = "24h"
    case week = "7d"
    case month = "30d"
    case retention

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "24 小时"
        case .week: "7 天"
        case .month: "30 天"
        case .retention: "全部"
        }
    }
}

struct UsageCounters: Codable, Equatable, Sendable {
    let requests: UInt64
    let failedRequests: UInt64
    let inputTokens: UInt64
    let outputTokens: UInt64
    let reasoningTokens: UInt64
    let cachedTokens: UInt64
    let cacheReadTokens: UInt64
    let cacheCreationTokens: UInt64
    let totalTokens: UInt64
    let totalLatencyNS: UInt64
    let totalTTFTNS: UInt64
    let latencySamples: UInt64
    let ttftSamples: UInt64

    private enum CodingKeys: String, CodingKey {
        case requests, failedRequests, inputTokens, outputTokens
        case reasoningTokens, cachedTokens, cacheReadTokens, cacheCreationTokens, totalTokens
        case totalLatencyNS = "totalLatencyNs"
        case totalTTFTNS = "totalTtftNs"
        case latencySamples, ttftSamples
    }

    static let zero = UsageCounters(
        requests: 0,
        failedRequests: 0,
        inputTokens: 0,
        outputTokens: 0,
        reasoningTokens: 0,
        cachedTokens: 0,
        cacheReadTokens: 0,
        cacheCreationTokens: 0,
        totalTokens: 0,
        totalLatencyNS: 0,
        totalTTFTNS: 0,
        latencySamples: 0,
        ttftSamples: 0
    )
}

struct UsageGroup: Codable, Equatable, Sendable {
    let provider: String
    let executorType: String
    let model: String
    let alias: String
    let source: String
    let authType: String
    let serviceTier: String
    let reasoningEffort: String
    let failed: Bool
    let failureStatus: Int
    let requests: UInt64
    let failedRequests: UInt64
    let inputTokens: UInt64
    let outputTokens: UInt64
    let reasoningTokens: UInt64
    let cachedTokens: UInt64
    let cacheReadTokens: UInt64
    let cacheCreationTokens: UInt64
    let totalTokens: UInt64
    let totalLatencyNS: UInt64
    let totalTTFTNS: UInt64
    let latencySamples: UInt64
    let ttftSamples: UInt64
    let averageLatencyNS: UInt64
    let averageTTFTNS: UInt64

    private enum CodingKeys: String, CodingKey {
        case provider, executorType, model, alias, source, authType, serviceTier
        case reasoningEffort, failed, failureStatus, requests, failedRequests
        case inputTokens, outputTokens, reasoningTokens, cachedTokens
        case cacheReadTokens, cacheCreationTokens, totalTokens
        case totalLatencyNS = "totalLatencyNs"
        case totalTTFTNS = "totalTtftNs"
        case latencySamples, ttftSamples
        case averageLatencyNS = "averageLatencyNs"
        case averageTTFTNS = "averageTtftNs"
    }

    func matchesDimensionQuery(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        return [
            provider,
            executorType,
            model,
            alias,
            source,
            authType,
            serviceTier,
            reasoningEffort,
            failed ? "failed 失败" : "success 成功",
            String(failureStatus)
        ]
        .contains { $0.localizedCaseInsensitiveContains(normalized) }
    }
}

struct UsageSeriesPoint: Codable, Equatable, Identifiable, Sendable {
    var id: String { hour }
    let hour: String
    let requests: UInt64
    let failedRequests: UInt64
    let inputTokens: UInt64
    let outputTokens: UInt64
    let reasoningTokens: UInt64
    let cachedTokens: UInt64
    let cacheReadTokens: UInt64
    let cacheCreationTokens: UInt64
    let totalTokens: UInt64
    let totalLatencyNS: UInt64
    let totalTTFTNS: UInt64
    let latencySamples: UInt64
    let ttftSamples: UInt64

    private enum CodingKeys: String, CodingKey {
        case hour, requests, failedRequests, inputTokens, outputTokens
        case reasoningTokens, cachedTokens, cacheReadTokens, cacheCreationTokens, totalTokens
        case totalLatencyNS = "totalLatencyNs"
        case totalTTFTNS = "totalTtftNs"
        case latencySamples, ttftSamples
    }
}

struct TokenUsageSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: UInt32
    let generatedAt: String
    let range: String
    let retainedSince: String
    let lastUsed: String
    let summary: UsageCounters
    let groups: [UsageGroup]
    let series: [UsageSeriesPoint]
}

struct UsageCostAmounts: Codable, Equatable, Sendable {
    let requests: UInt64
    let pricedRequests: UInt64
    let unpricedRequests: UInt64
    let inputUSD: Double
    let outputUSD: Double
    let cacheReadUSD: Double
    let cacheCreationUSD: Double
    let totalUSD: Double

    private enum CodingKeys: String, CodingKey {
        case requests, pricedRequests, unpricedRequests
        case inputUSD = "inputUsd"
        case outputUSD = "outputUsd"
        case cacheReadUSD = "cacheReadUsd"
        case cacheCreationUSD = "cacheCreationUsd"
        case totalUSD = "totalUsd"
    }
}

struct TokenUsageCosts: Codable, Equatable, Sendable {
    let schemaVersion: UInt32
    let generatedAt: String
    let range: String
    let currency: String
    let estimateBasis: String
    let priceBookRevision: UInt64
    let summary: UsageCostAmounts
    let models: [TokenUsageCostModel]
    let series: [TokenUsageCostSeriesPoint]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, generatedAt, range, currency, estimateBasis
        case priceBookRevision, summary, models, series
    }

    init(
        schemaVersion: UInt32 = 1,
        generatedAt: String = "",
        range: String = "",
        currency: String = "USD",
        estimateBasis: String = "",
        priceBookRevision: UInt64 = 0,
        summary: UsageCostAmounts,
        models: [TokenUsageCostModel] = [],
        series: [TokenUsageCostSeriesPoint] = []
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.range = range
        self.currency = currency
        self.estimateBasis = estimateBasis
        self.priceBookRevision = priceBookRevision
        self.summary = summary
        self.models = models
        self.series = series
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(UInt32.self, forKey: .schemaVersion) ?? 1
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        range = try container.decodeIfPresent(String.self, forKey: .range) ?? ""
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        estimateBasis = try container.decodeIfPresent(String.self, forKey: .estimateBasis) ?? ""
        priceBookRevision = try container.decodeIfPresent(UInt64.self, forKey: .priceBookRevision) ?? 0
        summary = try container.decode(UsageCostAmounts.self, forKey: .summary)
        models = try container.decodeIfPresent([TokenUsageCostModel].self, forKey: .models) ?? []
        series = try container.decodeIfPresent([TokenUsageCostSeriesPoint].self, forKey: .series) ?? []
    }
}

struct TokenUsageExchangeRate: Codable, Equatable, Sendable {
    let schemaVersion: UInt32
    let base: String
    let quote: String
    let rate: Double
    let effectiveAt: String
    let fetchedAt: String
    let source: String
    let stale: Bool
}

struct TokenUsageCostModel: Codable, Equatable, Identifiable, Sendable {
    var id: String { "\(provider)::\(model)" }
    let provider: String
    let model: String
    let requests: UInt64
    let pricedRequests: UInt64
    let unpricedRequests: UInt64
    let inputUSD: Double
    let outputUSD: Double
    let cacheReadUSD: Double
    let cacheCreationUSD: Double
    let totalUSD: Double

    private enum CodingKeys: String, CodingKey {
        case provider, model, requests, pricedRequests, unpricedRequests
        case inputUSD = "inputUsd"
        case outputUSD = "outputUsd"
        case cacheReadUSD = "cacheReadUsd"
        case cacheCreationUSD = "cacheCreationUsd"
        case totalUSD = "totalUsd"
    }
}

struct TokenUsageCostSeriesPoint: Codable, Equatable, Identifiable, Sendable {
    var id: String { "\(hour)::\(provider)::\(model)" }
    let hour: String
    let provider: String
    let model: String
    let requests: UInt64
    let pricedRequests: UInt64
    let unpricedRequests: UInt64
    let inputUSD: Double
    let outputUSD: Double
    let cacheReadUSD: Double
    let cacheCreationUSD: Double
    let totalUSD: Double

    private enum CodingKeys: String, CodingKey {
        case hour, provider, model, requests, pricedRequests, unpricedRequests
        case inputUSD = "inputUsd"
        case outputUSD = "outputUsd"
        case cacheReadUSD = "cacheReadUsd"
        case cacheCreationUSD = "cacheCreationUsd"
        case totalUSD = "totalUsd"
    }
}

struct ContextPriceTier: Codable, Equatable, Sendable {
    var threshold: UInt64
    var input: Double
    var output: Double
    var cacheRead: Double
    var cacheCreation: Double

    private enum CodingKeys: String, CodingKey {
        case threshold, input, output
        case cacheRead, cacheCreation
    }

    init(
        threshold: UInt64,
        input: Double = 0,
        output: Double = 0,
        cacheRead: Double = 0,
        cacheCreation: Double = 0
    ) {
        self.threshold = threshold
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheCreation = cacheCreation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threshold = try container.decodeIfPresent(UInt64.self, forKey: .threshold) ?? 0
        input = try container.decodeIfPresent(Double.self, forKey: .input) ?? 0
        output = try container.decodeIfPresent(Double.self, forKey: .output) ?? 0
        cacheRead = try container.decodeIfPresent(Double.self, forKey: .cacheRead) ?? 0
        cacheCreation = try container.decodeIfPresent(Double.self, forKey: .cacheCreation) ?? 0
    }
}

struct ServiceTierPrice: Codable, Equatable, Sendable {
    var input: Double
    var output: Double
    var cacheRead: Double
    var cacheCreation: Double
    var contextTiers: [ContextPriceTier]

    private enum CodingKeys: String, CodingKey {
        case input, output, cacheRead, cacheCreation, contextTiers
    }

    init(
        input: Double = 0,
        output: Double = 0,
        cacheRead: Double = 0,
        cacheCreation: Double = 0,
        contextTiers: [ContextPriceTier] = []
    ) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheCreation = cacheCreation
        self.contextTiers = contextTiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = try container.decodeIfPresent(Double.self, forKey: .input) ?? 0
        output = try container.decodeIfPresent(Double.self, forKey: .output) ?? 0
        cacheRead = try container.decodeIfPresent(Double.self, forKey: .cacheRead) ?? 0
        cacheCreation = try container.decodeIfPresent(Double.self, forKey: .cacheCreation) ?? 0
        contextTiers = try container.decodeIfPresent([ContextPriceTier].self, forKey: .contextTiers) ?? []
    }
}

struct ModelPrice: Codable, Equatable, Sendable {
    var input: Double
    var output: Double
    var cacheRead: Double
    var cacheCreation: Double
    var contextTiers: [ContextPriceTier]
    var serviceTiers: [String: ServiceTierPrice]
    var accountingMode: String
    var source: String
    var catalogProvider: String
    var catalogModel: String
    var updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case input, output
        case cacheRead, cacheCreation, contextTiers, serviceTiers, accountingMode
        case source
        case catalogProvider, catalogModel, updatedAt
    }

    init(
        input: Double = 0,
        output: Double = 0,
        cacheRead: Double = 0,
        cacheCreation: Double = 0,
        contextTiers: [ContextPriceTier] = [],
        serviceTiers: [String: ServiceTierPrice] = [:],
        accountingMode: String = "",
        source: String = "manual",
        catalogProvider: String = "",
        catalogModel: String = "",
        updatedAt: String? = nil
    ) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheCreation = cacheCreation
        self.contextTiers = contextTiers
        self.serviceTiers = serviceTiers
        self.accountingMode = accountingMode
        self.source = source
        self.catalogProvider = catalogProvider
        self.catalogModel = catalogModel
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = try container.decodeIfPresent(Double.self, forKey: .input) ?? 0
        output = try container.decodeIfPresent(Double.self, forKey: .output) ?? 0
        cacheRead = try container.decodeIfPresent(Double.self, forKey: .cacheRead) ?? 0
        cacheCreation = try container.decodeIfPresent(Double.self, forKey: .cacheCreation) ?? 0
        contextTiers = try container.decodeIfPresent([ContextPriceTier].self, forKey: .contextTiers) ?? []
        serviceTiers = try container.decodeIfPresent([String: ServiceTierPrice].self, forKey: .serviceTiers) ?? [:]
        accountingMode = try container.decodeIfPresent(String.self, forKey: .accountingMode) ?? ""
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "manual"
        catalogProvider = try container.decodeIfPresent(String.self, forKey: .catalogProvider) ?? ""
        catalogModel = try container.decodeIfPresent(String.self, forKey: .catalogModel) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

struct PriceSyncMapping: Codable, Equatable, Sendable {
    var source: String
    var target: String
}

struct PriceSyncSettings: Codable, Equatable, Sendable {
    var providerPriority: [String]
    var ignoredSuffixes: [String]
    var mappings: [PriceSyncMapping]

    private enum CodingKeys: String, CodingKey {
        case providerPriority, ignoredSuffixes, mappings
    }

    init(
        providerPriority: [String] = [],
        ignoredSuffixes: [String] = [],
        mappings: [PriceSyncMapping] = []
    ) {
        self.providerPriority = providerPriority
        self.ignoredSuffixes = ignoredSuffixes
        self.mappings = mappings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Older plugin versions and an empty price book may encode mappings as
        // null. Treat null/missing arrays as empty so the rest of the price
        // book remains readable.
        providerPriority = try container.decodeIfPresent([String].self, forKey: .providerPriority) ?? []
        ignoredSuffixes = try container.decodeIfPresent([String].self, forKey: .ignoredSuffixes) ?? []
        mappings = try container.decodeIfPresent([PriceSyncMapping].self, forKey: .mappings) ?? []
    }
}

struct PriceSyncMetadata: Codable, Equatable, Sendable {
    let source: String
    let completedAt: String
    let observed: Int
    let matched: Int
    let created: Int
    let updated: Int
    let skippedManual: Int
    let unmatched: Int
}

struct TokenUsagePriceBook: Codable, Equatable, Sendable {
    let schemaVersion: UInt32
    let revision: UInt64
    var prices: [String: ModelPrice]
    var syncSettings: PriceSyncSettings
    let lastSync: PriceSyncMetadata?

    init(
        schemaVersion: UInt32 = 1,
        revision: UInt64 = 0,
        prices: [String: ModelPrice] = [:],
        syncSettings: PriceSyncSettings = PriceSyncSettings(),
        lastSync: PriceSyncMetadata? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.prices = prices
        self.syncSettings = syncSettings
        self.lastSync = lastSync
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, revision, prices, syncSettings, lastSync
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(UInt32.self, forKey: .schemaVersion) ?? 1
        revision = try container.decodeIfPresent(UInt64.self, forKey: .revision) ?? 0
        prices = try container.decodeIfPresent([String: ModelPrice].self, forKey: .prices) ?? [:]
        syncSettings = try container.decodeIfPresent(PriceSyncSettings.self, forKey: .syncSettings) ?? PriceSyncSettings()
        lastSync = try container.decodeIfPresent(PriceSyncMetadata.self, forKey: .lastSync)
    }
}

struct UsageRequestItem: Codable, Equatable, Identifiable, Sendable {
    var id: UInt64 { sequence }
    let sequence: UInt64
    let time: String
    let provider: String
    let executorType: String
    let model: String
    let alias: String
    let source: String
    let serviceTier: String
    let reasoningEffort: String?
    let failed: Bool
    let failureStatus: Int
    let requests: UInt64
    let inputTokens: UInt64
    let outputTokens: UInt64
    let reasoningTokens: UInt64
    let cacheReadTokens: UInt64
    let cacheCreationTokens: UInt64
    let totalTokens: UInt64
    let result: String
    let latencyNS: UInt64
    let ttftNS: UInt64
    let generationNS: UInt64?
    let tps: Double
    let cacheHit: Bool?
    let estimatedCost: UsageRequestEstimatedCost?

    var effectiveGenerationNS: UInt64 {
        generationNS ?? (latencyNS >= ttftNS ? latencyNS - ttftNS : latencyNS)
    }

    var effectiveCacheHit: Bool {
        cacheHit ?? (cacheReadTokens > 0)
    }

    private enum CodingKeys: String, CodingKey {
        case sequence, time, provider, executorType, model, alias, source, serviceTier, reasoningEffort
        case failed, failureStatus, requests, inputTokens, outputTokens, reasoningTokens
        case cacheReadTokens, cacheCreationTokens, totalTokens, result
        case latencyNS = "latencyNs"
        case ttftNS = "ttftNs"
        case generationNS = "generationNs"
        case tps, cacheHit, estimatedCost
    }
}

struct UsageRequestEstimatedCost: Codable, Equatable, Sendable {
    let priced: Bool
    let source: String?
    let accountingMode: String?
    let priceServiceTier: String?
    let tierThreshold: UInt64?
    let contextTokens: UInt64?
    let billableInputTokens: UInt64?
    let billedCacheReadTokens: UInt64?
    let inputUSD: Double
    let outputUSD: Double
    let cacheReadUSD: Double
    let cacheCreationUSD: Double
    let totalUSD: Double

    private enum CodingKeys: String, CodingKey {
        case priced, source, accountingMode, priceServiceTier, tierThreshold, contextTokens
        case billableInputTokens, billedCacheReadTokens
        case inputUSD = "inputUsd"
        case outputUSD = "outputUsd"
        case cacheReadUSD = "cacheReadUsd"
        case cacheCreationUSD = "cacheCreationUsd"
        case totalUSD = "totalUsd"
    }
}

struct UsageRequestPage: Codable, Equatable, Sendable {
    let generatedAt: String?
    let range: String?
    let priceBookRevision: UInt64?
    let total: Int
    let offset: Int
    let limit: Int
    let items: [UsageRequestItem]

    init(
        total: Int,
        offset: Int,
        limit: Int,
        items: [UsageRequestItem],
        generatedAt: String? = nil,
        range: String? = nil,
        priceBookRevision: UInt64? = nil
    ) {
        self.generatedAt = generatedAt
        self.range = range
        self.priceBookRevision = priceBookRevision
        self.total = total
        self.offset = offset
        self.limit = limit
        self.items = items
    }

    var hasPreviousPage: Bool {
        offset > 0
    }

    var hasNextPage: Bool {
        offset + items.count < total
    }

    var displayedRange: ClosedRange<Int>? {
        guard !items.isEmpty else { return nil }
        return (offset + 1)...(offset + items.count)
    }
}

struct ModelUsageRow: Identifiable, Equatable, Sendable {
    var id: String { model }
    let model: String
    let provider: String
    let requests: UInt64
    let failedRequests: UInt64
    let inputTokens: UInt64
    let outputTokens: UInt64
    let cacheReadTokens: UInt64
    let totalTokens: UInt64
    let totalLatencyNS: UInt64
    let latencySamples: UInt64
    let totalTTFTNS: UInt64
    let ttftSamples: UInt64

    var averageLatencyNS: UInt64 {
        let samples = latencySamples == 0 ? requests : latencySamples
        return samples == 0 ? 0 : totalLatencyNS / samples
    }

    var averageTTFTNS: UInt64 {
        let samples = ttftSamples == 0 ? requests : ttftSamples
        return samples == 0 ? 0 : totalTTFTNS / samples
    }

    var averageTokens: Double {
        requests == 0 ? 0 : Double(totalTokens) / Double(requests)
    }

    static func aggregate(_ groups: [UsageGroup]) -> [ModelUsageRow] {
        struct Accumulator {
            var providers = Set<String>()
            var requests: UInt64 = 0
            var failed: UInt64 = 0
            var input: UInt64 = 0
            var output: UInt64 = 0
            var cacheRead: UInt64 = 0
            var tokens: UInt64 = 0
            var latencyNS: UInt64 = 0
            var latencySamples: UInt64 = 0
            var ttftNS: UInt64 = 0
            var ttftSamples: UInt64 = 0
        }
        var values: [String: Accumulator] = [:]
        for group in groups {
            let name = group.model.isEmpty ? "unknown" : group.model
            var value = values[name, default: Accumulator()]
            if !group.provider.isEmpty { value.providers.insert(group.provider) }
            value.requests &+= group.requests
            value.failed &+= group.failedRequests
            value.input &+= group.inputTokens
            value.output &+= group.outputTokens
            value.cacheRead &+= group.cacheReadTokens
            value.tokens &+= group.totalTokens
            value.latencyNS &+= group.totalLatencyNS
            value.latencySamples &+= group.latencySamples
            value.ttftNS &+= group.totalTTFTNS
            value.ttftSamples &+= group.ttftSamples
            values[name] = value
        }
        return values.map { model, value in
            ModelUsageRow(
                model: model,
                provider: value.providers.sorted().joined(separator: ", "),
                requests: value.requests,
                failedRequests: value.failed,
                inputTokens: value.input,
                outputTokens: value.output,
                cacheReadTokens: value.cacheRead,
                totalTokens: value.tokens,
                totalLatencyNS: value.latencyNS,
                latencySamples: value.latencySamples,
                totalTTFTNS: value.ttftNS,
                ttftSamples: value.ttftSamples
            )
        }
        .sorted {
            if $0.totalTokens == $1.totalTokens {
                return $0.model.localizedStandardCompare($1.model) == .orderedAscending
            }
            return $0.totalTokens > $1.totalTokens
        }
    }
}

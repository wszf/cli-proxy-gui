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
    let currency: String
    let summary: UsageCostAmounts
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
    let tps: Double

    private enum CodingKeys: String, CodingKey {
        case sequence, time, provider, executorType, model, alias, source, serviceTier
        case failed, failureStatus, requests, inputTokens, outputTokens, reasoningTokens
        case cacheReadTokens, cacheCreationTokens, totalTokens, result
        case latencyNS = "latencyNs"
        case ttftNS = "ttftNs"
        case tps
    }
}

struct UsageRequestPage: Codable, Equatable, Sendable {
    let total: Int
    let offset: Int
    let limit: Int
    let items: [UsageRequestItem]
}

struct ModelUsageRow: Identifiable, Equatable, Sendable {
    var id: String { model }
    let model: String
    let provider: String
    let requests: UInt64
    let failedRequests: UInt64
    let totalTokens: UInt64

    static func aggregate(_ groups: [UsageGroup]) -> [ModelUsageRow] {
        struct Accumulator {
            var providers = Set<String>()
            var requests: UInt64 = 0
            var failed: UInt64 = 0
            var tokens: UInt64 = 0
        }
        var values: [String: Accumulator] = [:]
        for group in groups {
            let name = group.model.isEmpty ? "unknown" : group.model
            var value = values[name, default: Accumulator()]
            if !group.provider.isEmpty { value.providers.insert(group.provider) }
            value.requests &+= group.requests
            value.failed &+= group.failedRequests
            value.tokens &+= group.totalTokens
            values[name] = value
        }
        return values.map { model, value in
            ModelUsageRow(
                model: model,
                provider: value.providers.sorted().joined(separator: ", "),
                requests: value.requests,
                failedRequests: value.failed,
                totalTokens: value.tokens
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

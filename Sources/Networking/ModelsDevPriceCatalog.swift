import Foundation

struct ModelsDevCatalogProvider: Decodable, Sendable {
    let id: String?
    let name: String?
    let label: String?
    let models: [String: ModelsDevCatalogModel]

    private enum CodingKeys: String, CodingKey {
        case id, name, label, models
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        models = try container.decodeIfPresent([String: ModelsDevCatalogModel].self, forKey: .models) ?? [:]
    }
}

struct ModelsDevCatalogModel: Decodable, Sendable {
    let id: String?
    let name: String?
    let cost: ModelsDevCatalogCost?

    private enum CodingKeys: String, CodingKey {
        case id, name, cost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        cost = try container.decodeIfPresent(ModelsDevCatalogCost.self, forKey: .cost)
    }
}

struct ModelsDevCatalogCost: Decodable, Sendable {
    let input: Double
    let output: Double
    let cacheRead: Double
    let cacheWrite: Double
    let tiers: [ModelsDevCatalogCostTier]

    private enum CodingKeys: String, CodingKey {
        case input, output, cacheRead, cacheWrite, tiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = try container.decodeIfPresent(Double.self, forKey: .input) ?? 0
        output = try container.decodeIfPresent(Double.self, forKey: .output) ?? 0
        cacheRead = try container.decodeIfPresent(Double.self, forKey: .cacheRead) ?? 0
        cacheWrite = try container.decodeIfPresent(Double.self, forKey: .cacheWrite) ?? 0
        tiers = try container.decodeIfPresent([ModelsDevCatalogCostTier].self, forKey: .tiers) ?? []
    }
}

struct ModelsDevCatalogCostTier: Decodable, Sendable {
    let input: Double
    let output: Double
    let cacheRead: Double
    let cacheWrite: Double
    let tier: ModelsDevCatalogTierKind

    private enum CodingKeys: String, CodingKey {
        case input, output, cacheRead, cacheWrite, tier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = try container.decodeIfPresent(Double.self, forKey: .input) ?? 0
        output = try container.decodeIfPresent(Double.self, forKey: .output) ?? 0
        cacheRead = try container.decodeIfPresent(Double.self, forKey: .cacheRead) ?? 0
        cacheWrite = try container.decodeIfPresent(Double.self, forKey: .cacheWrite) ?? 0
        tier = try container.decodeIfPresent(ModelsDevCatalogTierKind.self, forKey: .tier)
            ?? ModelsDevCatalogTierKind(type: "", size: 0)
    }
}

struct ModelsDevCatalogTierKind: Decodable, Sendable {
    let type: String
    let size: UInt64

    private enum CodingKeys: String, CodingKey {
        case type, size
    }

    init(type: String, size: UInt64) {
        self.type = type
        self.size = size
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        size = try container.decodeIfPresent(UInt64.self, forKey: .size) ?? 0
    }
}

struct ModelsDevSyncResult: Sendable {
    let prices: [String: ModelPrice]
    let observed: Int
    let matched: Int
    let unmatched: Int
}

struct ModelsDevClientSyncResult: Sendable {
    let priceBook: TokenUsagePriceBook
    let observed: Int
    let matched: Int
    let unmatched: Int
    let created: Int
    let updated: Int
    let skippedManual: Int
}

enum ModelsDevPriceMatcher {
    private struct Candidate {
        let provider: String
        let model: String
        let price: ModelPrice
        let rank: Int
    }

    private struct NormalizedSettings {
        let providerPriority: [String]
        let ignoredSuffixes: [String]
        let mappings: [PriceSyncMapping]
    }

    private static let defaultProviderPriority = ["openai", "google", "anthropic"]
    private static let defaultIgnoredSuffixes = [
        "-thinking", "-preview", "-high", "-low",
        "(thinking)", "(xhigh)", "(high)", "(low)"
    ]

    static func match(
        catalog: [String: ModelsDevCatalogProvider],
        models: [String],
        settings: PriceSyncSettings,
        updatedAt: String
    ) -> ModelsDevSyncResult {
        let settings = normalized(settings)
        var priority: [String: Int] = [:]
        for (index, provider) in settings.providerPriority.enumerated() {
            priority[provider] = index
        }

        var candidates: [String: Candidate] = [:]
        for (providerKey, provider) in catalog {
            let providerName = firstNonEmpty(provider.id, provider.name, provider.label, providerKey)
            let normalizedProvider = normalizeCatalogName(providerName)
            let rank = priority[normalizedProvider] ?? settings.providerPriority.count

            for (modelKey, model) in provider.models {
                guard let cost = model.cost else { continue }
                let catalogModel = firstNonEmpty(model.id, modelKey, model.name)
                guard !catalogModel.isEmpty else { continue }
                let comparison = comparisonModelName(catalogModel, settings: settings)
                guard !comparison.isEmpty else { continue }
                let candidate = Candidate(
                    provider: normalizedProvider,
                    model: catalogModel,
                    price: makePrice(cost, provider: normalizedProvider, model: catalogModel, updatedAt: updatedAt),
                    rank: rank
                )
                if let current = candidates[comparison], !isLess(candidate, than: current) {
                    continue
                }
                candidates[comparison] = candidate
            }
        }

        let uniqueModels = Set(models.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter { !$0.isEmpty }
            .sorted()
        var prices: [String: ModelPrice] = [:]
        var unmatched = 0
        for model in uniqueModels {
            guard let candidate = candidates[comparisonModelName(model, settings: settings)] else {
                unmatched += 1
                continue
            }
            prices[model] = candidate.price
        }

        return ModelsDevSyncResult(
            prices: prices,
            observed: uniqueModels.count,
            matched: prices.count,
            unmatched: unmatched
        )
    }

    private static func makePrice(
        _ cost: ModelsDevCatalogCost,
        provider: String,
        model: String,
        updatedAt: String
    ) -> ModelPrice {
        let tiers = cost.tiers.compactMap { tier -> ContextPriceTier? in
            guard tier.tier.type.lowercased() == "context", tier.tier.size > 0 else { return nil }
            return ContextPriceTier(
                threshold: tier.tier.size,
                input: tier.input,
                output: tier.output,
                cacheRead: tier.cacheRead,
                cacheCreation: tier.cacheWrite
            )
        }
        return ModelPrice(
            input: cost.input,
            output: cost.output,
            cacheRead: cost.cacheRead,
            cacheCreation: cost.cacheWrite,
            contextTiers: tiers,
            source: "models.dev",
            catalogProvider: provider,
            catalogModel: model,
            updatedAt: updatedAt
        )
    }

    private static func normalized(_ settings: PriceSyncSettings) -> NormalizedSettings {
        var providers = settings.providerPriority
            .map(normalizeCatalogName)
            .filter { !$0.isEmpty }
        providers = unique(providers)
        if providers.isEmpty { providers = defaultProviderPriority }

        var suffixes = settings.ignoredSuffixes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        suffixes = unique(suffixes)
        if suffixes.isEmpty { suffixes = defaultIgnoredSuffixes }

        let mappings = settings.mappings.compactMap { mapping -> PriceSyncMapping? in
            let source = normalizeCatalogName(mapping.source)
            let target = normalizeCatalogName(mapping.target)
            guard !source.isEmpty, !target.isEmpty else { return nil }
            return PriceSyncMapping(source: source, target: target)
        }

        return NormalizedSettings(
            providerPriority: providers,
            ignoredSuffixes: suffixes,
            mappings: mappings
        )
    }

    private static func comparisonModelName(_ value: String, settings: NormalizedSettings) -> String {
        var value = normalizeCatalogName(value)
        if let mapping = settings.mappings.first(where: { $0.source == value }) {
            value = mapping.target
        }
        while true {
            let previous = value
            if let suffix = settings.ignoredSuffixes.first(where: { value.hasSuffix($0) }) {
                value = String(value.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if value == previous { return value }
        }
    }

    private static func normalizeCatalogName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: "/")
            .last
            .map(String.init) ?? ""
    }

    private static func firstNonEmpty(_ values: String?...) -> String {
        for value in values {
            guard let value else { continue }
            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return ""
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func isLess(_ left: Candidate, than right: Candidate) -> Bool {
        if left.rank != right.rank { return left.rank < right.rank }
        if left.provider != right.provider { return left.provider < right.provider }
        return left.model < right.model
    }
}

import Foundation

struct ProxyNode: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var address: String

    init(id: UUID = UUID(), name: String, address: String) {
        self.id = id
        self.name = name
        self.address = Self.normalize(address)
    }

    var managementBaseURL: URL? {
        URL(string: Self.normalize(address))?
            .appending(path: "v0")
            .appending(path: "management")
    }

    var managementPageURL: URL? {
        URL(string: Self.normalize(address))?.appending(path: "management.html")
    }

    static func normalize(_ rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://") {
            value = "http://" + value
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        for suffix in ["/v0/management", "/management.html"] where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
        }
        return value
    }
}

enum NodeConnectionState: Equatable, Sendable {
    case idle
    case checking
    case online
    case offline(String)
}

struct NodeSnapshot: Equatable, Sendable {
    var state: NodeConnectionState = .idle
    var version: String?
    var latestVersion: String?
    var buildDate: String?
    var latencyMilliseconds: Int?
    var authFileCount: Int?
    var availableAuthFileCount: Int?
    var disabledAuthFileCount: Int?
    var unavailableAuthFileCount: Int?
    var credentialProviders: [CredentialProviderSummary] = []
    var providerCount: Int?
    var apiKeyCount: Int?
    var availableModelCount: Int?
    var availableModelGroups: [AvailableModelGroup] = []
    var routingStrategy: String?
    var plugins: PluginOverview?
    var dailyUsage: DailyUsageOverview?
    var runtime: RuntimeOverview = .empty
    var lastChecked: Date?

    var hasUpdate: Bool {
        guard let version, let latestVersion else { return false }
        return VersionComparison.isNewer(latestVersion, than: version)
    }

    static let empty = NodeSnapshot()
}

struct CredentialProviderSummary: Identifiable, Equatable, Sendable {
    var id: String { provider }
    let provider: String
    let total: Int
    let available: Int
    let disabled: Int
    let unavailable: Int
}

struct PluginOverview: Equatable, Sendable {
    let globallyEnabled: Bool
    let installed: Int
    let active: Int
    let tokenTrackerActive: Bool
}

struct DailyUsageOverview: Equatable, Sendable {
    let requests: UInt64
    let failedRequests: UInt64
    let totalTokens: UInt64

    var failureRate: Double {
        requests == 0 ? 0 : Double(failedRequests) / Double(requests)
    }
}

struct RuntimeOverview: Equatable, Sendable {
    var debug: Bool?
    var requestLogging: Bool?
    var fileLogging: Bool?
    var usageStatistics: Bool?
    var proxyConfigured: Bool?
    var tlsEnabled: Bool?
    var requestRetry: Int?
    var maxRetryInterval: Int?

    static let empty = RuntimeOverview()
}

enum VersionComparison {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = components(candidate)
        let rhs = components(current)
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        let length = max(lhs.count, rhs.count)
        for index in 0..<length {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: "-", maxSplits: 1)
            .first?
            .split(separator: ".")
            .compactMap { Int($0) } ?? []
    }
}

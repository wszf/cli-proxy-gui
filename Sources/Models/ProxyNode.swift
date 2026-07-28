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
    var buildDate: String?
    var authFileCount: Int?
    var providerCount: Int?
    var apiKeyCount: Int?
    var routingStrategy: String?
    var lastChecked: Date?

    static let empty = NodeSnapshot()
}


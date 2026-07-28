import Foundation

struct AuthFileItem: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let type: String
    let status: String
    let disabled: Bool
    let unavailable: Bool
    let size: Int?
    let modified: Date?

    var isAvailable: Bool { !disabled && !unavailable }
}

struct LogPage: Equatable, Sendable {
    let lines: [String]
    let latestTimestamp: Int?
    let nextCursor: String?
}

struct CredentialHealth: Equatable, Sendable {
    let total: Int
    let available: Int
    let disabled: Int
    let unavailable: Int
    let providers: [CredentialProviderSummary]
}

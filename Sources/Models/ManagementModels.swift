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

struct AvailableModelItem: Identifiable, Equatable, Sendable {
    var id: String { name.lowercased() }
    let name: String
    let alias: String?
}

struct AvailableModelGroup: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let models: [AvailableModelItem]
}

struct CredentialQuotaSummary: Identifiable, Equatable, Sendable {
    let id: String
    let provider: String
    let account: String
    let plan: String?
    let windows: [CredentialQuotaWindow]
    let error: String?

    var lowestRemainingPercent: Double? {
        windows.map(\.remainingPercent).min()
    }
}

struct CredentialQuotaWindow: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let remainingPercent: Double
    let resetsAt: Date?
}

enum CredentialQuotaResetCountdown {
    static func text(until resetDate: Date, now: Date = .now) -> String {
        let remaining = resetDate.timeIntervalSince(now)
        guard remaining > 0 else { return "已重置" }
        if remaining >= 86_400 {
            return "\(max(1, Int(remaining / 86_400)))d 后重置"
        }
        if remaining >= 3_600 {
            return "\(max(1, Int(remaining / 3_600)))h 后重置"
        }
        if remaining >= 60 {
            return "\(max(1, Int(remaining / 60)))m 后重置"
        }
        return "即将重置"
    }
}

enum CredentialQuotaLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
}

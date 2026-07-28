import Foundation

struct CredentialQuotaTarget: Sendable {
    let id: String
    let authIndex: String
    let provider: String
    let account: String
    let accountID: String?
    let plan: String?
}

struct CredentialQuotaRequest: Sendable {
    let url: String
    let headers: [String: String]
}

enum CredentialQuotaParser {
    struct UpstreamResponse {
        let statusCode: Int
        let body: Any
        let message: String?
    }

    static func targets(in object: Any) -> [CredentialQuotaTarget] {
        guard let root = object as? [String: Any],
              let files = root["files"] as? [[String: Any]]
        else {
            return []
        }

        let supportedProviders = Set(["codex", "claude", "kimi"])
        return files.compactMap { file in
            let provider = string(file["type"] ?? file["provider"])?.lowercased() ?? ""
            guard supportedProviders.contains(provider),
                  !boolean(file["disabled"]),
                  !boolean(file["unavailable"]),
                  let authIndex = string(file["auth_index"] ?? file["authIndex"])
            else {
                return nil
            }

            let account = firstString(
                in: file,
                keys: ["email", "account", "label", "name"]
            ) ?? authIndex
            let accountID = recursiveString(
                in: file["id_token"],
                keys: ["chatgpt_account_id", "chatgptAccountId"]
            )
            let plan = recursiveString(
                in: file,
                keys: ["plan_type", "planType", "chatgpt_plan_type"]
            )

            return CredentialQuotaTarget(
                id: authIndex,
                authIndex: authIndex,
                provider: provider,
                account: account,
                accountID: accountID,
                plan: plan
            )
        }
    }

    static func upstreamResponse(from data: Data) throws -> UpstreamResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusCode = integer(root["status_code"] ?? root["statusCode"])
        else {
            throw APIError.invalidResponse
        }

        let rawBody = root["body"]
        let body: Any
        if let text = rawBody as? String,
           let bodyData = text.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: bodyData) {
            body = parsed
        } else {
            body = rawBody ?? [:]
        }

        return UpstreamResponse(
            statusCode: statusCode,
            body: body,
            message: errorMessage(in: body)
        )
    }

    static func summary(
        target: CredentialQuotaTarget,
        payload: Any
    ) -> CredentialQuotaSummary {
        let root = payload as? [String: Any] ?? [:]
        let windows: [CredentialQuotaWindow]
        let plan: String?

        switch target.provider {
        case "codex":
            windows = codexWindows(in: root)
            plan = firstString(in: root, keys: ["plan_type", "planType"]) ?? target.plan
        case "claude":
            windows = claudeWindows(in: root)
            plan = target.plan
        case "kimi":
            windows = kimiWindows(in: root)
            plan = target.plan
        default:
            windows = []
            plan = target.plan
        }

        return CredentialQuotaSummary(
            id: target.id,
            provider: target.provider,
            account: target.account,
            plan: plan,
            windows: windows,
            error: nil
        )
    }

    private static func codexWindows(in root: [String: Any]) -> [CredentialQuotaWindow] {
        var result: [CredentialQuotaWindow] = []
        appendCodexWindows(
            from: dictionary(root["rate_limit"] ?? root["rateLimit"]),
            prefix: "",
            to: &result
        )
        appendCodexWindows(
            from: dictionary(root["code_review_rate_limit"] ?? root["codeReviewRateLimit"]),
            prefix: "代码审查 ",
            to: &result
        )

        let additional = array(root["additional_rate_limits"] ?? root["additionalRateLimits"])
        for (index, item) in additional.enumerated() {
            guard let item = item as? [String: Any] else { continue }
            let name = firstString(
                in: item,
                keys: ["limit_name", "limitName", "metered_feature", "meteredFeature"]
            ) ?? "额外额度 \(index + 1)"
            appendCodexWindows(
                from: dictionary(item["rate_limit"] ?? item["rateLimit"]),
                prefix: "\(name) ",
                to: &result
            )
        }
        return result
    }

    private static func appendCodexWindows(
        from rateLimit: [String: Any]?,
        prefix: String,
        to result: inout [CredentialQuotaWindow]
    ) {
        guard let rateLimit else { return }
        let reached = boolean(rateLimit["limit_reached"] ?? rateLimit["limitReached"])
            || rateLimit["allowed"].map { !boolean($0) } == true
        let candidates: [(String, Any?)] = [
            ("主要", rateLimit["primary_window"] ?? rateLimit["primaryWindow"]),
            ("次要", rateLimit["secondary_window"] ?? rateLimit["secondaryWindow"])
        ]

        for (fallbackLabel, rawWindow) in candidates {
            guard let window = dictionary(rawWindow) else { continue }
            let used = number(window["used_percent"] ?? window["usedPercent"])
                ?? (reached ? 100 : nil)
            guard let used else { continue }
            let duration = integer(
                window["limit_window_seconds"] ?? window["limitWindowSeconds"]
            )
            let label = prefix + codexWindowLabel(seconds: duration, fallback: fallbackLabel)
            result.append(
                CredentialQuotaWindow(
                    id: stableID(label),
                    label: label,
                    remainingPercent: clamp(100 - used),
                    resetsAt: resetDate(in: window)
                )
            )
        }
    }

    private static func codexWindowLabel(seconds: Int?, fallback: String) -> String {
        guard let seconds else { return fallback }
        if seconds == 18_000 { return "5 小时" }
        if seconds == 604_800 { return "每周" }
        if (2_419_200...2_678_400).contains(seconds) { return "每月" }
        if seconds % 86_400 == 0 { return "\(seconds / 86_400) 天" }
        if seconds % 3_600 == 0 { return "\(seconds / 3_600) 小时" }
        return fallback
    }

    private static func claudeWindows(in root: [String: Any]) -> [CredentialQuotaWindow] {
        let keys = [
            ("five_hour", "5 小时"),
            ("seven_day", "7 天"),
            ("seven_day_oauth_apps", "7 天 OAuth"),
            ("seven_day_opus", "7 天 Opus"),
            ("seven_day_sonnet", "7 天 Sonnet"),
            ("seven_day_cowork", "7 天 Cowork"),
            ("iguana_necktie", "额外窗口")
        ]
        return keys.compactMap { key, label in
            guard let window = root[key] as? [String: Any],
                  let used = number(window["utilization"])
            else {
                return nil
            }
            return CredentialQuotaWindow(
                id: key,
                label: label,
                remainingPercent: clamp(100 - used),
                resetsAt: date(window["resets_at"] ?? window["resetsAt"])
            )
        }
    }

    private static func kimiWindows(in root: [String: Any]) -> [CredentialQuotaWindow] {
        var records: [[String: Any]] = []
        if let usage = dictionary(root["usage"]) { records.append(usage) }
        for raw in array(root["limits"]) {
            guard let item = raw as? [String: Any] else { continue }
            records.append(dictionary(item["detail"]) ?? item)
        }

        return records.enumerated().compactMap { index, record in
            guard let limit = number(record["limit"]), limit > 0 else { return nil }
            let used = number(record["used"])
                ?? number(record["remaining"]).map { limit - $0 }
                ?? 0
            let label = firstString(in: record, keys: ["name", "title", "scope"])
                ?? "额度 \(index + 1)"
            return CredentialQuotaWindow(
                id: "\(stableID(label))-\(index)",
                label: label,
                remainingPercent: clamp((limit - used) / limit * 100),
                resetsAt: resetDate(in: record)
            )
        }
    }

    private static func resetDate(in object: [String: Any]) -> Date? {
        if let timestamp = number(object["reset_at"] ?? object["resetAt"]), timestamp > 0 {
            return Date(timeIntervalSince1970: timestamp)
        }
        if let seconds = number(
            object["reset_after_seconds"]
                ?? object["resetAfterSeconds"]
                ?? object["reset_in"]
                ?? object["resetIn"]
                ?? object["ttl"]
        ), seconds > 0 {
            return Date().addingTimeInterval(seconds)
        }
        return date(
            object["reset_time"]
                ?? object["resetTime"]
                ?? object["resets_at"]
                ?? object["resetsAt"]
        )
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = string(value) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
            ?? ISO8601DateFormatter().date(from: text)
    }

    private static func errorMessage(in body: Any) -> String? {
        guard let root = body as? [String: Any] else {
            return string(body)
        }
        if let error = root["error"] as? [String: Any] {
            return string(error["message"]) ?? string(error["error"])
        }
        return string(root["message"]) ?? string(root["error"])
    }

    private static func recursiveString(in value: Any?, keys: Set<String>) -> String? {
        guard let value else { return nil }
        if let object = value as? [String: Any] {
            for key in keys {
                if let result = string(object[key]) { return result }
            }
            for nested in object.values {
                if let result = recursiveString(in: nested, keys: keys) { return result }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let result = recursiveString(in: nested, keys: keys) { return result }
            }
        }
        return nil
    }

    private static func firstString(in object: [String: Any], keys: [String]) -> String? {
        keys.lazy.compactMap { string(object[$0]) }.first
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func array(_ value: Any?) -> [Any] {
        value as? [Any] ?? []
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        number(value).map(Int.init)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private static func boolean(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            return ["true", "1", "yes"].contains(value.lowercased())
        }
        return false
    }

    private static func clamp(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    private static func stableID(_ value: String) -> String {
        value.lowercased().replacingOccurrences(
            of: "[^a-z0-9\\p{Han}]+",
            with: "-",
            options: .regularExpression
        )
    }
}

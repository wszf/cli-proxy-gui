import Foundation

struct ManagementAPIClient: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchSnapshot(node: ProxyNode, managementKey: String) async -> NodeSnapshot {
        guard let baseURL = node.managementBaseURL else {
            return NodeSnapshot(state: .offline("节点地址无效"), lastChecked: Date())
        }

        do {
            let startedAt = Date()
            async let configResponse = request(path: "config", baseURL: baseURL, key: managementKey)
            async let authResponse = request(path: "auth-files", baseURL: baseURL, key: managementKey)
            async let latestResponse = try? request(
                path: "latest-version",
                baseURL: baseURL,
                key: managementKey,
                timeout: 4
            )
            async let pluginResponse = try? request(
                path: "plugins",
                baseURL: baseURL,
                key: managementKey,
                timeout: 5
            )
            async let usageResponse = try? fetchTokenUsage(
                range: .day,
                node: node,
                managementKey: managementKey
            )
            let (config, auth) = try await (configResponse, authResponse)
            let latencyMilliseconds = max(1, Int(Date().timeIntervalSince(startedAt) * 1000))
            let configJSON = try JSONSerialization.jsonObject(with: config.data)
            let authJSON = try JSONSerialization.jsonObject(with: auth.data)
            let credentialHealth = JSONMetrics.credentialHealth(in: authJSON)

            let apiKey = JSONMetrics.firstStringInArray(
                keys: ["api-keys", "api_keys"],
                in: configJSON
            )
            let modelCount: Int?
            if let apiKey {
                modelCount = try? await fetchAvailableModelCount(node: node, apiKey: apiKey)
            } else {
                modelCount = nil
            }

            let latestResult = await latestResponse
            let pluginResult = await pluginResponse
            let usageResult = await usageResponse
            let latestJSON = latestResult.flatMap {
                try? JSONSerialization.jsonObject(with: $0.data)
            }
            let pluginJSON = pluginResult.flatMap {
                try? JSONSerialization.jsonObject(with: $0.data)
            }

            return NodeSnapshot(
                state: .online,
                version: header("x-cpa-version", fallback: "x-server-version", in: config.response),
                latestVersion: latestJSON.flatMap {
                    JSONMetrics.string(keys: ["latest-version", "latest_version"], in: $0)
                },
                buildDate: header("x-cpa-build-date", fallback: "x-server-build-date", in: config.response),
                latencyMilliseconds: latencyMilliseconds,
                authFileCount: credentialHealth.total,
                availableAuthFileCount: credentialHealth.available,
                disabledAuthFileCount: credentialHealth.disabled,
                unavailableAuthFileCount: credentialHealth.unavailable,
                credentialProviders: credentialHealth.providers,
                providerCount: JSONMetrics.providerCount(in: configJSON),
                apiKeyCount: JSONMetrics.arrayCount(keys: ["api-keys", "api_keys"], in: configJSON),
                availableModelCount: modelCount,
                routingStrategy: JSONMetrics.string(keys: ["routing-strategy", "routing_strategy"], in: configJSON),
                plugins: pluginJSON.flatMap(JSONMetrics.pluginOverview),
                dailyUsage: usageResult.map {
                    DailyUsageOverview(
                        requests: $0.summary.requests,
                        failedRequests: $0.summary.failedRequests,
                        totalTokens: $0.summary.totalTokens
                    )
                },
                runtime: JSONMetrics.runtimeOverview(in: configJSON),
                lastChecked: Date()
            )
        } catch {
            return NodeSnapshot(
                state: .offline(Self.friendlyMessage(for: error)),
                lastChecked: Date()
            )
        }
    }

    func fetchConfigYAML(node: ProxyNode, managementKey: String) async throws -> String {
        let result = try await request(
            path: "config.yaml",
            node: node,
            key: managementKey,
            accept: "application/yaml, text/yaml, text/plain"
        )
        guard let text = String(data: result.data, encoding: .utf8) else {
            throw APIError.invalidResponse
        }
        return text
    }

    func saveConfigYAML(_ yaml: String, node: ProxyNode, managementKey: String) async throws {
        _ = try await request(
            path: "config.yaml",
            node: node,
            key: managementKey,
            method: "PUT",
            body: Data(yaml.utf8),
            contentType: "application/yaml"
        )
    }

    func fetchAPIKeys(node: ProxyNode, managementKey: String) async throws -> [String] {
        let result = try await request(path: "api-keys", node: node, key: managementKey)
        guard let object = try JSONSerialization.jsonObject(with: result.data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        let values = (object["api-keys"] ?? object["apiKeys"]) as? [Any] ?? []
        return values.map(String.init(describing:))
    }

    func replaceAPIKeys(_ keys: [String], node: ProxyNode, managementKey: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: keys)
        _ = try await request(
            path: "api-keys",
            node: node,
            key: managementKey,
            method: "PUT",
            body: body,
            contentType: "application/json"
        )
    }

    func fetchAuthFiles(node: ProxyNode, managementKey: String) async throws -> [AuthFileItem] {
        let result = try await request(path: "auth-files", node: node, key: managementKey)
        guard let object = try JSONSerialization.jsonObject(with: result.data) as? [String: Any],
              let files = object["files"] as? [[String: Any]]
        else {
            throw APIError.invalidResponse
        }
        return files.compactMap { item in
            guard let name = item["name"] as? String, !name.isEmpty else { return nil }
            return AuthFileItem(
                name: name,
                type: Self.text(item["type"]) ?? Self.text(item["provider"]) ?? "unknown",
                status: Self.text(item["status"]) ?? "unknown",
                disabled: Self.bool(item["disabled"]),
                unavailable: Self.bool(item["unavailable"]),
                size: Self.integer(item["size"]),
                modified: Self.date(item["modified"])
            )
        }
    }

    func setAuthFileDisabled(
        _ disabled: Bool,
        name: String,
        node: ProxyNode,
        managementKey: String
    ) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "disabled": disabled
        ])
        _ = try await request(
            path: "auth-files/status",
            node: node,
            key: managementKey,
            method: "PATCH",
            body: body,
            contentType: "application/json"
        )
    }

    func uploadAuthFile(
        data: Data,
        filename: String,
        node: ProxyNode,
        managementKey: String
    ) async throws {
        _ = try await request(
            path: "auth-files",
            node: node,
            key: managementKey,
            method: "POST",
            body: data,
            contentType: "application/json",
            queryItems: [URLQueryItem(name: "name", value: filename)]
        )
    }

    func deleteAuthFile(name: String, node: ProxyNode, managementKey: String) async throws {
        _ = try await request(
            path: "auth-files",
            node: node,
            key: managementKey,
            method: "DELETE",
            queryItems: [URLQueryItem(name: "name", value: name)]
        )
    }

    func fetchLogs(
        node: ProxyNode,
        managementKey: String,
        limit: Int = 500,
        cursor: String? = nil
    ) async throws -> LogPage {
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor, !cursor.isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let result = try await request(
            path: "logs",
            node: node,
            key: managementKey,
            queryItems: queryItems,
            timeout: 60
        )
        guard let object = try JSONSerialization.jsonObject(with: result.data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        return LogPage(
            lines: object["lines"] as? [String] ?? [],
            latestTimestamp: Self.integer(object["latest-timestamp"]),
            nextCursor: Self.text(object["next-cursor"])
        )
    }

    func clearLogs(node: ProxyNode, managementKey: String) async throws {
        _ = try await request(path: "logs", node: node, key: managementKey, method: "DELETE")
    }

    private func fetchAvailableModelCount(node: ProxyNode, apiKey: String) async throws -> Int {
        let result = try await request(
            path: "v1/models",
            baseURL: try rootURL(for: node),
            key: apiKey,
            timeout: 6
        )
        guard let object = try JSONSerialization.jsonObject(with: result.data) as? [String: Any],
              let models = object["data"] as? [[String: Any]]
        else {
            throw APIError.invalidResponse
        }
        return Set(models.compactMap { Self.text($0["id"]) }).count
    }

    func fetchCredentialQuotas(
        node: ProxyNode,
        managementKey: String
    ) async throws -> [CredentialQuotaSummary] {
        let response = try await request(path: "auth-files", node: node, key: managementKey)
        let object = try JSONSerialization.jsonObject(with: response.data)
        let targets = CredentialQuotaParser.targets(in: object)

        return await withTaskGroup(of: CredentialQuotaSummary.self) { group in
            for target in targets {
                group.addTask {
                    do {
                        return try await fetchCredentialQuota(
                            target,
                            node: node,
                            managementKey: managementKey
                        )
                    } catch {
                        return CredentialQuotaSummary(
                            id: target.id,
                            provider: target.provider,
                            account: target.account,
                            plan: target.plan,
                            windows: [],
                            error: Self.credentialQuotaMessage(for: error)
                        )
                    }
                }
            }

            var summaries: [CredentialQuotaSummary] = []
            for await summary in group {
                summaries.append(summary)
            }
            return summaries.sorted {
                if $0.provider == $1.provider {
                    return $0.account.localizedStandardCompare($1.account) == .orderedAscending
                }
                return $0.provider.localizedStandardCompare($1.provider) == .orderedAscending
            }
        }
    }

    private func fetchCredentialQuota(
        _ target: CredentialQuotaTarget,
        node: ProxyNode,
        managementKey: String
    ) async throws -> CredentialQuotaSummary {
        let request: CredentialQuotaRequest
        switch target.provider {
        case "codex":
            var headers = [
                "Authorization": "Bearer $TOKEN$",
                "Content-Type": "application/json",
                "User-Agent": "codex_cli_rs/0.76.0 (macOS; arm64)"
            ]
            if let accountID = target.accountID {
                headers["Chatgpt-Account-Id"] = accountID
            }
            request = CredentialQuotaRequest(
                url: "https://chatgpt.com/backend-api/wham/usage",
                headers: headers
            )
        case "claude":
            request = CredentialQuotaRequest(
                url: "https://api.anthropic.com/api/oauth/usage",
                headers: [
                    "Authorization": "Bearer $TOKEN$",
                    "Content-Type": "application/json",
                    "anthropic-beta": "oauth-2025-04-20"
                ]
            )
        case "kimi":
            request = CredentialQuotaRequest(
                url: "https://api.kimi.com/coding/v1/usages",
                headers: ["Authorization": "Bearer $TOKEN$"]
            )
        default:
            throw APIError.invalidResponse
        }

        let payload = try JSONSerialization.data(withJSONObject: [
            "auth_index": target.authIndex,
            "method": "GET",
            "url": request.url,
            "header": request.headers
        ])
        let result = try await self.request(
            path: "api-call",
            node: node,
            key: managementKey,
            method: "POST",
            body: payload,
            contentType: "application/json",
            timeout: 15
        )
        let upstream = try CredentialQuotaParser.upstreamResponse(from: result.data)
        guard (200..<300).contains(upstream.statusCode) else {
            throw APIError.httpStatus(upstream.statusCode, upstream.message)
        }

        let parsed = CredentialQuotaParser.summary(target: target, payload: upstream.body)
        guard !parsed.windows.isEmpty else {
            throw APIError.httpStatus(upstream.statusCode, "上游没有返回可识别的额度窗口")
        }
        return parsed
    }

    private static func credentialQuotaMessage(for error: Error) -> String {
        if case let APIError.httpStatus(code, message) = error {
            return message.map { "上游 HTTP \(code)：\($0)" } ?? "上游 HTTP \(code)"
        }
        return friendlyMessage(for: error)
    }

    func fetchTokenUsage(
        range: UsageRange,
        node: ProxyNode,
        managementKey: String
    ) async throws -> TokenUsageSnapshot {
        let result = try await request(
            path: "plugins/cap-token-usage-tracker/stats",
            node: node,
            key: managementKey,
            queryItems: [URLQueryItem(name: "range", value: range.rawValue)]
        )
        return try usageDecoder.decode(TokenUsageSnapshot.self, from: result.data)
    }

    func fetchTokenUsageCosts(range: UsageRange, node: ProxyNode) async throws -> TokenUsageCosts {
        let result = try await request(
            path: "v0/resource/plugins/cap-token-usage-tracker/costs",
            baseURL: try rootURL(for: node),
            key: "",
            queryItems: [URLQueryItem(name: "range", value: range.rawValue)]
        )
        return try usageDecoder.decode(TokenUsageCosts.self, from: result.data)
    }

    func fetchTokenUsageRequests(
        range: UsageRange,
        node: ProxyNode,
        offset: Int = 0,
        limit: Int = 50
    ) async throws -> UsageRequestPage {
        let result = try await request(
            path: "v0/resource/plugins/cap-token-usage-tracker/requests",
            baseURL: try rootURL(for: node),
            key: "",
            queryItems: [
                URLQueryItem(name: "range", value: range.rawValue),
                URLQueryItem(name: "offset", value: String(max(0, offset))),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        )
        return try usageDecoder.decode(UsageRequestPage.self, from: result.data)
    }

    private var usageDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func rootURL(for node: ProxyNode) throws -> URL {
        guard let url = URL(string: ProxyNode.normalize(node.address)) else {
            throw APIError.invalidURL
        }
        return url
    }

    private func request(
        path: String,
        node: ProxyNode,
        key: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil,
        accept: String = "application/json",
        queryItems: [URLQueryItem] = [],
        timeout: TimeInterval = 12
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        guard let baseURL = node.managementBaseURL else {
            throw APIError.invalidURL
        }
        return try await request(
            path: path,
            baseURL: baseURL,
            key: key,
            method: method,
            body: body,
            contentType: contentType,
            accept: accept,
            queryItems: queryItems,
            timeout: timeout
        )
    }

    private func request(
        path: String,
        baseURL: URL,
        key: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil,
        accept: String = "application/json",
        queryItems: [URLQueryItem] = [],
        timeout: TimeInterval = 12
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = timeout
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let serverMessage = Self.errorMessage(from: data)
            throw APIError.httpStatus(http.statusCode, serverMessage)
        }
        return (data, http)
    }

    private func header(_ primary: String, fallback: String, in response: HTTPURLResponse) -> String? {
        response.value(forHTTPHeaderField: primary)
            ?? response.value(forHTTPHeaderField: fallback)
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (object["error"] as? String) ?? (object["message"] as? String)
    }

    static func friendlyMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .invalidURL:
                return "节点地址无效"
            case .invalidResponse:
                return "服务器响应无效"
            case let .httpStatus(code, message):
                if code == 401 { return "Management Key 不正确" }
                if code == 403 { return "远程管理未开启或无权限" }
                return message.map { "HTTP \(code)：\($0)" } ?? "HTTP \(code)"
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "连接超时"
            case .cannotConnectToHost: return "无法连接节点"
            case .serverCertificateUntrusted: return "TLS 证书不受信任"
            default: return urlError.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private static func text(_ value: Any?) -> String? {
        guard let value else { return nil }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text == "<null>" ? nil : text
    }

    private static func bool(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            return ["true", "1", "yes"].contains(value.lowercased())
        }
        return false
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        guard let timestamp = integer(value) else { return nil }
        let seconds = timestamp > 10_000_000_000 ? Double(timestamp) / 1000 : Double(timestamp)
        return Date(timeIntervalSince1970: seconds)
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "节点地址无效"
        case .invalidResponse:
            "服务器返回了无法识别的数据"
        case let .httpStatus(code, message):
            if code == 401 { "Management Key 不正确" }
            else if code == 403 { "远程管理未开启或无权限" }
            else { message.map { "HTTP \(code)：\($0)" } ?? "HTTP \(code)" }
        }
    }
}

enum JSONMetrics {
    static func authFileCount(in object: Any) -> Int? {
        if let dictionary = object as? [String: Any] {
            if let files = dictionary["files"] as? [Any] { return files.count }
            if let total = number(dictionary["total"]) { return total }
        }
        return nil
    }

    static func providerCount(in object: Any) -> Int {
        let providerKeys = [
            "gemini-api-key", "gemini-api-keys",
            "codex-api-key", "codex-api-keys",
            "claude-api-key", "claude-api-keys",
            "vertex-api-key", "vertex-api-keys",
            "xai-api-key", "xai-api-keys",
            "openai-compatibility"
        ]
        return providerKeys.reduce(0) { $0 + (arrayCount(keys: [$1], in: object) ?? 0) }
    }

    static func credentialHealth(in object: Any) -> CredentialHealth {
        guard let dictionary = object as? [String: Any],
              let files = dictionary["files"] as? [[String: Any]]
        else {
            return CredentialHealth(total: 0, available: 0, disabled: 0, unavailable: 0, providers: [])
        }

        struct Counts {
            var total = 0
            var available = 0
            var disabled = 0
            var unavailable = 0
        }
        var totalAvailable = 0
        var totalDisabled = 0
        var totalUnavailable = 0
        var providerCounts: [String: Counts] = [:]

        for file in files {
            let provider = text(file["type"]) ?? text(file["provider"]) ?? "unknown"
            let disabled = boolValue(file["disabled"])
            let unavailable = boolValue(file["unavailable"])
            let available = !disabled && !unavailable

            if available { totalAvailable += 1 }
            if disabled { totalDisabled += 1 }
            if unavailable { totalUnavailable += 1 }

            var counts = providerCounts[provider, default: Counts()]
            counts.total += 1
            if available { counts.available += 1 }
            if disabled { counts.disabled += 1 }
            if unavailable { counts.unavailable += 1 }
            providerCounts[provider] = counts
        }

        let providers = providerCounts.map { provider, counts in
            CredentialProviderSummary(
                provider: provider,
                total: counts.total,
                available: counts.available,
                disabled: counts.disabled,
                unavailable: counts.unavailable
            )
        }
        .sorted {
            if $0.total == $1.total {
                return $0.provider.localizedStandardCompare($1.provider) == .orderedAscending
            }
            return $0.total > $1.total
        }

        return CredentialHealth(
            total: files.count,
            available: totalAvailable,
            disabled: totalDisabled,
            unavailable: totalUnavailable,
            providers: providers
        )
    }

    static func runtimeOverview(in object: Any) -> RuntimeOverview {
        RuntimeOverview(
            debug: bool(keys: ["debug"], in: object),
            requestLogging: bool(keys: ["request-log", "request_log"], in: object),
            fileLogging: bool(keys: ["logging-to-file", "logging_to_file"], in: object),
            usageStatistics: bool(
                keys: ["usage-statistics-enabled", "usage_statistics_enabled"],
                in: object
            ),
            proxyConfigured: string(keys: ["proxy-url", "proxy_url"], in: object).map { !$0.isEmpty },
            tlsEnabled: nestedBool(keys: ["tls", "enable"], in: object),
            requestRetry: integer(keys: ["request-retry", "request_retry"], in: object),
            maxRetryInterval: integer(
                keys: ["max-retry-interval", "max_retry_interval"],
                in: object
            )
        )
    }

    static func pluginOverview(in object: Any) -> PluginOverview? {
        guard let dictionary = object as? [String: Any],
              let plugins = dictionary["plugins"] as? [[String: Any]]
        else {
            return nil
        }
        let globallyEnabled = boolValue(
            dictionary["plugins_enabled"] ?? dictionary["plugins-enabled"]
        )
        let active = plugins.filter {
            boolValue($0["effective_enabled"] ?? $0["effective-enabled"])
        }
        let tracker = active.contains {
            text($0["id"]) == "cap-token-usage-tracker"
        }
        return PluginOverview(
            globallyEnabled: globallyEnabled,
            installed: plugins.count,
            active: active.count,
            tokenTrackerActive: tracker
        )
    }

    static func arrayCount(keys: [String], in object: Any) -> Int? {
        guard let dictionary = object as? [String: Any] else { return nil }
        for key in keys {
            if let array = dictionary[key] as? [Any] { return array.count }
        }
        return nil
    }

    static func string(keys: [String], in object: Any) -> String? {
        guard let dictionary = object as? [String: Any] else { return nil }
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    static func firstStringInArray(keys: [String], in object: Any) -> String? {
        guard let dictionary = object as? [String: Any] else { return nil }
        for key in keys {
            guard let values = dictionary[key] as? [Any] else { continue }
            if let value = values.compactMap(text).first(where: { !$0.isEmpty }) {
                return value
            }
        }
        return nil
    }

    static func bool(keys: [String], in object: Any) -> Bool? {
        guard let dictionary = object as? [String: Any] else { return nil }
        for key in keys where dictionary[key] != nil {
            return boolValue(dictionary[key])
        }
        return nil
    }

    static func integer(keys: [String], in object: Any) -> Int? {
        guard let dictionary = object as? [String: Any] else { return nil }
        for key in keys {
            if let value = number(dictionary[key]) { return value }
        }
        return nil
    }

    private static func nestedBool(keys: [String], in object: Any) -> Bool? {
        guard keys.count == 2,
              let dictionary = object as? [String: Any],
              let nested = dictionary[keys[0]] as? [String: Any],
              nested[keys[1]] != nil
        else {
            return nil
        }
        return boolValue(nested[keys[1]])
    }

    private static func text(_ value: Any?) -> String? {
        guard let value else { return nil }
        let result = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty || result == "<null>" ? nil : result
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            return ["true", "1", "yes"].contains(value.lowercased())
        }
        return false
    }

    private static func number(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}

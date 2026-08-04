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
            let fetchedModelGroups: [AvailableModelGroup]?
            if let apiKey {
                fetchedModelGroups = try? await fetchAvailableModels(node: node, apiKey: apiKey)
            } else {
                fetchedModelGroups = nil
            }
            let modelGroups = fetchedModelGroups ?? []
            let modelCount = fetchedModelGroups.map { groups in
                groups.reduce(0) { $0 + $1.models.count }
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
                availableModelGroups: modelGroups,
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

    private func fetchAvailableModels(
        node: ProxyNode,
        apiKey: String
    ) async throws -> [AvailableModelGroup] {
        let result = try await request(
            path: "v1/models",
            baseURL: try rootURL(for: node),
            key: apiKey,
            timeout: 6
        )
        let object = try JSONSerialization.jsonObject(with: result.data)
        return JSONMetrics.availableModelGroups(in: object)
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

    func fetchTokenUsageExchangeRate(node: ProxyNode) async throws -> TokenUsageExchangeRate {
        let result = try await request(
            path: "v0/resource/plugins/cap-token-usage-tracker/exchange-rate",
            baseURL: try rootURL(for: node),
            key: "",
            timeout: 12
        )
        let rate = try usageDecoder.decode(TokenUsageExchangeRate.self, from: result.data)
        guard rate.base.uppercased() == "USD",
              rate.quote.uppercased() == "CNY",
              rate.rate.isFinite,
              rate.rate > 0 else {
            throw APIError.invalidResponse
        }
        return rate
    }

    func fetchTokenUsagePrices(node: ProxyNode) async throws -> TokenUsagePriceBook {
        let result = try await request(
            path: "v0/resource/plugins/cap-token-usage-tracker/prices",
            baseURL: try rootURL(for: node),
            key: ""
        )
        return try usageDecoder.decode(TokenUsagePriceBook.self, from: result.data)
    }

    func saveTokenUsagePrices(
        prices: [String: ModelPrice],
        syncSettings: PriceSyncSettings,
        node: ProxyNode,
        managementKey: String
    ) async throws -> TokenUsagePriceBook {
        let body = try usageEncoder.encode(
            TokenUsagePriceSavePayload(prices: prices, syncSettings: syncSettings)
        )
        let result = try await request(
            path: "plugins/cap-token-usage-tracker/prices",
            node: node,
            key: managementKey,
            method: "PUT",
            body: body,
            contentType: "application/json"
        )
        return try usageDecoder.decode(TokenUsagePriceBook.self, from: result.data)
    }

    func syncTokenUsagePrices(
        models: [String],
        syncSettings: PriceSyncSettings? = nil,
        node: ProxyNode,
        managementKey: String
    ) async throws -> TokenUsagePriceBook {
        let body = try usageEncoder.encode(
            TokenUsagePriceSyncPayload(
                source: "models.dev",
                models: Array(Set(models.filter { !$0.isEmpty })).sorted(),
                syncSettings: syncSettings
            )
        )
        let result = try await request(
            path: "plugins/cap-token-usage-tracker/prices/sync",
            node: node,
            key: managementKey,
            method: "POST",
            body: body,
            contentType: "application/json",
            timeout: 30
        )
        return try usageDecoder.decode(TokenUsagePriceBook.self, from: result.data)
    }

    /// Performs the Models.dev fetch on the Mac and persists the merged price
    /// book through the protected management endpoint. This is used as a
    /// fallback when the VPS cannot reach Models.dev itself.
    func syncTokenUsagePricesFromClient(
        models: [String],
        existing: TokenUsagePriceBook,
        syncSettings: PriceSyncSettings? = nil,
        node: ProxyNode,
        managementKey: String
    ) async throws -> ModelsDevClientSyncResult {
        let settings = syncSettings ?? existing.syncSettings
        let catalog = try await fetchModelsDevCatalog()
        let updatedAt = ISO8601DateFormatter().string(from: Date())
        let match = ModelsDevPriceMatcher.match(
            catalog: catalog,
            models: models,
            settings: settings,
            updatedAt: updatedAt
        )

        var prices = existing.prices
        var created = 0
        var updated = 0
        var skippedManual = 0
        for (model, price) in match.prices {
            if let current = prices[model], current.source == "manual" {
                skippedManual += 1
                continue
            }
            if prices[model] == nil {
                created += 1
            } else {
                updated += 1
            }
            prices[model] = price
        }

        let saved = try await saveTokenUsagePrices(
            prices: prices,
            syncSettings: settings,
            node: node,
            managementKey: managementKey
        )

        let localSyncMetadata = PriceSyncMetadata(
            source: "models.dev",
            completedAt: updatedAt,
            observed: match.observed,
            matched: match.matched,
            created: created,
            updated: updated,
            skippedManual: skippedManual,
            unmatched: match.unmatched
        )
        let localPriceBook = TokenUsagePriceBook(
            schemaVersion: saved.schemaVersion,
            revision: saved.revision,
            prices: saved.prices,
            syncSettings: saved.syncSettings,
            lastSync: localSyncMetadata
        )
        return ModelsDevClientSyncResult(
            priceBook: localPriceBook,
            observed: match.observed,
            matched: match.matched,
            unmatched: match.unmatched,
            created: created,
            updated: updated,
            skippedManual: skippedManual
        )
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

    private var usageEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    private func fetchModelsDevCatalog() async throws -> [String: ModelsDevCatalogProvider] {
        guard let url = URL(string: "https://models.dev/api.json") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CLIProxyGUI", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode, "Models.dev 返回 HTTP \(http.statusCode)")
        }
        guard data.count <= 16 * 1024 * 1024 else {
            throw APIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode([String: ModelsDevCatalogProvider].self, from: data)
        } catch {
            throw APIError.httpStatus(502, "Models.dev 返回的数据无法解析")
        }
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

private struct TokenUsagePriceSavePayload: Encodable {
    let prices: [String: ModelPrice]
    let syncSettings: PriceSyncSettings
}

private struct TokenUsagePriceSyncPayload: Encodable {
    let source: String
    let models: [String]
    let syncSettings: PriceSyncSettings?
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

    static func availableModelGroups(in object: Any) -> [AvailableModelGroup] {
        let rawModels: [Any]
        if let models = object as? [Any] {
            rawModels = models
        } else if let dictionary = object as? [String: Any],
                  let models = (dictionary["data"] ?? dictionary["models"]) as? [Any]
        {
            rawModels = models
        } else {
            return []
        }

        var seenNames = Set<String>()
        let models = rawModels.compactMap { value -> AvailableModelItem? in
            let name: String?
            let alias: String?
            if let value = value as? String {
                name = text(value)
                alias = nil
            } else if let dictionary = value as? [String: Any] {
                name = text(
                    dictionary["id"]
                        ?? dictionary["name"]
                        ?? dictionary["model"]
                        ?? dictionary["value"]
                )
                let candidate = text(
                    dictionary["alias"]
                        ?? dictionary["display_name"]
                        ?? dictionary["displayName"]
                )
                alias = candidate == name ? nil : candidate
            } else {
                return nil
            }
            guard let name else { return nil }
            let deduplicationKey = name.lowercased()
            guard seenNames.insert(deduplicationKey).inserted else { return nil }
            return AvailableModelItem(name: name, alias: alias)
        }

        struct Definition {
            let id: String
            let label: String
            let patterns: [String]
        }
        let definitions = [
            Definition(id: "gpt", label: "GPT", patterns: ["gpt", "chatgpt"]),
            Definition(id: "claude", label: "Claude", patterns: ["claude"]),
            Definition(id: "gemini", label: "Gemini", patterns: ["gemini", "gai"]),
            Definition(id: "kimi", label: "Kimi", patterns: ["kimi"]),
            Definition(id: "qwen", label: "Qwen", patterns: ["qwen"]),
            Definition(id: "glm", label: "GLM", patterns: ["glm", "chatglm"]),
            Definition(id: "grok", label: "Grok", patterns: ["grok"]),
            Definition(id: "deepseek", label: "DeepSeek", patterns: ["deepseek"]),
            Definition(id: "minimax", label: "MiniMax", patterns: ["minimax", "abab"])
        ]
        var grouped = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, [AvailableModelItem]()) })
        var other: [AvailableModelItem] = []

        for model in models {
            let searchable = "\(model.name) \(model.alias ?? "")".lowercased()
            let definition = definitions.first { definition in
                definition.patterns.contains { searchable.contains($0) }
                    || (definition.id == "gpt"
                        && searchable.range(of: #"\bo[0-9]+\.?"#, options: .regularExpression) != nil)
            }
            if let definition {
                grouped[definition.id, default: []].append(model)
            } else {
                other.append(model)
            }
        }

        var result = definitions.compactMap { definition -> AvailableModelGroup? in
            guard let items = grouped[definition.id], !items.isEmpty else { return nil }
            return AvailableModelGroup(
                id: definition.id,
                label: definition.label,
                models: items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            )
        }
        if !other.isEmpty {
            result.append(AvailableModelGroup(
                id: "other",
                label: "其他",
                models: other.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            ))
        }
        return result
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

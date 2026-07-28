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
            async let configResponse = request(path: "config", baseURL: baseURL, key: managementKey)
            async let authResponse = request(path: "auth-files", baseURL: baseURL, key: managementKey)
            let (config, auth) = try await (configResponse, authResponse)
            let configJSON = try JSONSerialization.jsonObject(with: config.data)
            let authJSON = try JSONSerialization.jsonObject(with: auth.data)

            return NodeSnapshot(
                state: .online,
                version: header("x-cpa-version", fallback: "x-server-version", in: config.response),
                buildDate: header("x-cpa-build-date", fallback: "x-server-build-date", in: config.response),
                authFileCount: JSONMetrics.authFileCount(in: authJSON),
                providerCount: JSONMetrics.providerCount(in: configJSON),
                apiKeyCount: JSONMetrics.arrayCount(keys: ["api-keys", "api_keys"], in: configJSON),
                routingStrategy: JSONMetrics.string(keys: ["routing-strategy", "routing_strategy"], in: configJSON),
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

    private static func number(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}

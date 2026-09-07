import Foundation
import CoreFoundation

/// Normalizes credentials locally; never logs or persists the supplied secrets.
enum AuthJSONImporter {
    enum ImportError: LocalizedError {
        case invalidJSON, expectedObject, missingAccessToken, unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .invalidJSON: "不是有效的 JSON，请检查双引号、逗号和括号。"
            case .expectedObject: "凭据必须是一个 JSON 对象，不能是数组或单独的令牌。"
            case .missingAccessToken: "Codex 凭据缺少有效的 access_token。请复制完整的登录凭据。"
            case .unsupportedFormat: "未识别到凭据类型。请提供 CLIProxyAPI 凭据或包含 tokens 的 Codex auth.json；API Key 请在提供商配置中添加。"
            }
        }
    }

    static func normalize(_ data: Data) throws -> Data {
        var object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            // Also accept a JSON-encoded string copied from another application.
            if let string = object as? String {
                object = try JSONSerialization.jsonObject(with: Data(string.utf8), options: [.fragmentsAllowed])
            }
        } catch {
            throw ImportError.invalidJSON
        }
        guard var credentials = object as? [String: Any] else {
            throw ImportError.expectedObject
        }
        let type = credentials["type"] as? String
        if let tokens = credentials["tokens"] as? [String: Any], type == nil || type == "codex" {
            guard nonempty(tokens["access_token"]) != nil else { throw ImportError.missingAccessToken }
            var converted: [String: Any] = ["type": "codex"]
            for key in ["access_token", "refresh_token", "id_token", "account_id"] {
                if let value = nonempty(tokens[key]) { converted[key] = value }
            }
            for key in ["email", "last_refresh", "expired"] {
                if let value = nonempty(credentials[key]) { converted[key] = value }
            }
            // JWT claims are hints only, not verified identity. The server validates tokens.
            let identity = claims(tokens["id_token"])
            let access = claims(tokens["access_token"])
            if converted["email"] == nil, let email = nonempty(identity["email"]) {
                converted["email"] = email
            }
            if converted["account_id"] == nil {
                let auth = (identity["https://api.openai.com/auth"] as? [String: Any])
                    ?? (access["https://api.openai.com/auth"] as? [String: Any])
                if let account = nonempty(auth?["chatgpt_account_id"]) { converted["account_id"] = account }
            }
            if converted["expired"] == nil, let exp = access["exp"] as? NSNumber,
               CFGetTypeID(exp) != CFBooleanGetTypeID(), exp.doubleValue.isFinite,
               exp.doubleValue > 0, exp.doubleValue < 253_402_300_800 {
                converted["expired"] = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: exp.doubleValue))
            }
            credentials = converted
        } else {
            guard nonempty(credentials["type"]) != nil else { throw ImportError.unsupportedFormat }
            if type == "codex", nonempty(credentials["access_token"]) == nil {
                throw ImportError.missingAccessToken
            }
        }
        return try JSONSerialization.data(withJSONObject: credentials, options: [.sortedKeys])
    }

    private static func nonempty(_ value: Any?) -> String? {
        guard let string = value as? String,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return string
    }

    private static func claims(_ token: Any?) -> [String: Any] {
        guard let token = token as? String else { return [:] }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return [:] }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }
}

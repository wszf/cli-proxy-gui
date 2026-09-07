import XCTest
@testable import CLIProxyGUI

final class AuthJSONImporterTests: XCTestCase {
    private func normalize(_ object: Any) throws -> [String: Any] {
        let input = try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
        let normalized = try AuthJSONImporter.normalize(input)
        let decoded = try JSONSerialization.jsonObject(with: normalized)
        return try XCTUnwrap(decoded as? [String: Any])
    }

    private func jwt(_ claims: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: claims)
        let payload = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "header.\(payload).signature"
    }

    func testConvertsNativeCodexAndDerivesMetadata() throws {
        let identity = try jwt(["email": "test@example.com", "https://api.openai.com/auth": ["chatgpt_account_id": "account"]])
        let access = try jwt(["exp": 1_783_382_400])
        let result = try normalize([
            "OPENAI_API_KEY": NSNull(), "tokens": ["access_token": access, "id_token": identity, "refresh_token": "refresh"],
            "last_refresh": "2026-07-01T00:00:00Z"
        ])
        XCTAssertEqual(result["type"] as? String, "codex")
        XCTAssertEqual(result["access_token"] as? String, access)
        XCTAssertEqual(result["refresh_token"] as? String, "refresh")
        XCTAssertEqual(result["account_id"] as? String, "account")
        XCTAssertEqual(result["email"] as? String, "test@example.com")
        XCTAssertEqual(result["last_refresh"] as? String, "2026-07-01T00:00:00Z")
        XCTAssertNotNil(result["expired"])
        XCTAssertNil(result["tokens"])
        XCTAssertNil(result["OPENAI_API_KEY"])
    }

    func testEncodedJSONString() throws {
        let result = try normalize(#"{"tokens":{"access_token":"access","account_id":"explicit"}}"#)
        XCTAssertEqual(result["type"] as? String, "codex")
        XCTAssertEqual(result["account_id"] as? String, "explicit")
        XCTAssertNil(result["expired"], "Do not invent expiration for opaque tokens")
    }

    func testExistingCredentialsPreserveExtraFields() throws {
        for type in ["codex", "claude", "gemini"] {
            let original: [String: Any] = ["type": type, "access_token": "access", "disabled": true, "custom": ["key": "value"]]
            let result = try normalize(original)
            XCTAssertEqual(result as NSDictionary, original as NSDictionary)
        }
    }

    func testExplicitMetadataTakesPrecedence() throws {
        let result = try normalize([
            "tokens": ["access_token": "opaque", "account_id": "explicit", "id_token": try jwt(["email": "jwt@example.com"])],
            "email": "explicit@example.com", "expired": "2026-10-01T00:00:00Z"
        ])
        XCTAssertEqual(result["email"] as? String, "explicit@example.com")
        XCTAssertEqual(result["expired"] as? String, "2026-10-01T00:00:00Z")
    }

    func testRejectsInvalidInputsWithoutEchoingSecrets() throws {
        for input in ["", "{secret-token", "[]", "null", "42"] {
            XCTAssertThrowsError(try AuthJSONImporter.normalize(Data(input.utf8))) { error in
                XCTAssertFalse(error.localizedDescription.contains("secret-token"))
            }
        }
        for object: [String: Any] in [[:], ["OPENAI_API_KEY": "secret"], ["tokens": [:]], ["tokens": ["access_token": "  "]], ["type": "codex"]] {
            XCTAssertThrowsError(try normalize(object))
        }
    }
}

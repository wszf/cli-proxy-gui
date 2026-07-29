import Foundation
import Security

struct ManagementKeyVault: Codable, Equatable {
    static let currentVersion = 1

    var version = currentVersion
    var keys: [String: String] = [:]

    subscript(nodeID: UUID) -> String? {
        get { keys[nodeID.uuidString] }
        set { keys[nodeID.uuidString] = newValue }
    }
}

@MainActor
enum KeychainStore {
    private static let service = "com.wszf.cli-proxy-gui.management-keys"
    private static let vaultAccount = "management-key-vault-v1"

    static func save(_ value: String, for nodeID: UUID) throws {
        var vault = try loadVaultOrEmpty()
        vault[nodeID] = value
        try writeVault(vault)
        deleteLegacyItem(for: nodeID)
    }

    static func read(for nodeID: UUID) -> String? {
        readAll(for: [nodeID])[nodeID]
    }

    static func readAll(for nodeIDs: [UUID]) -> [UUID: String] {
        var vault = (try? loadVaultOrEmpty()) ?? ManagementKeyVault()
        var values: [UUID: String] = [:]
        var migratedNodeIDs: [UUID] = []

        for nodeID in nodeIDs {
            if let value = vault[nodeID], !value.isEmpty {
                values[nodeID] = value
                continue
            }
            guard let legacyValue = readLegacyItem(for: nodeID), !legacyValue.isEmpty else {
                continue
            }
            vault[nodeID] = legacyValue
            values[nodeID] = legacyValue
            migratedNodeIDs.append(nodeID)
        }

        if !migratedNodeIDs.isEmpty {
            do {
                try writeVault(vault)
                for nodeID in migratedNodeIDs {
                    deleteLegacyItem(for: nodeID)
                }
            } catch {
                // Keep legacy items when migration cannot be completed.
            }
        }
        return values
    }

    static func delete(for nodeID: UUID) {
        if var vault = try? loadVaultOrEmpty() {
            vault[nodeID] = nil
            try? writeVault(vault)
        }
        deleteLegacyItem(for: nodeID)
    }

    private static func loadVaultOrEmpty() throws -> ManagementKeyVault {
        do {
            let data = try readData(account: vaultAccount)
            return try JSONDecoder().decode(ManagementKeyVault.self, from: data)
        } catch let error as KeychainError where error.status == errSecItemNotFound {
            return ManagementKeyVault()
        } catch is DecodingError {
            throw KeychainVaultError.invalidData
        }
    }

    private static func writeVault(_ vault: ManagementKeyVault) throws {
        let data = try JSONEncoder().encode(vault)
        let query = itemQuery(account: vaultAccount)
        let attributes: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
    }

    private static func readLegacyItem(for nodeID: UUID) -> String? {
        guard let data = try? readData(account: nodeID.uuidString) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteLegacyItem(for nodeID: UUID) {
        SecItemDelete(itemQuery(account: nodeID.uuidString) as CFDictionary)
    }

    private static func readData(account: String) throws -> Data {
        var query = itemQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
        guard let data = result as? Data else {
            throw KeychainVaultError.invalidData
        }
        return data
    }

    private static func itemQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "钥匙串错误 \(status)"
    }
}

enum KeychainVaultError: LocalizedError {
    case invalidData

    var errorDescription: String? {
        "钥匙串中的 Management Key 数据无法读取"
    }
}

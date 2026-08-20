import CryptoKit
import Foundation

struct APIKeyNoteVault: Codable, Equatable {
    static let currentVersion = 1

    var version = currentVersion
    var notes: [String: [String: String]] = [:]
}

enum APIKeyNoteStore {
    private static let defaultsKey = "api-key-notes-v1"

    static func note(for nodeID: UUID, key: String) -> String {
        guard let vault = load() else { return "" }
        return vault.notes[nodeID.uuidString]?[fingerprint(for: key)] ?? ""
    }

    static func replaceNotes(_ notes: [String: String], for nodeID: UUID) {
        var vault = load() ?? APIKeyNoteVault()
        var normalized: [String: String] = [:]

        for (rawKey, rawNote) in notes {
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = rawNote.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !note.isEmpty else { continue }
            normalized[fingerprint(for: key)] = note
        }

        if normalized.isEmpty {
            vault.notes[nodeID.uuidString] = nil
        } else {
            vault.notes[nodeID.uuidString] = normalized
        }
        save(vault)
    }

    static func remove(for nodeID: UUID) {
        guard var vault = load() else { return }
        vault.notes[nodeID.uuidString] = nil
        save(vault)
    }

    static func fingerprint(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func load() -> APIKeyNoteVault? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(APIKeyNoteVault.self, from: data)
    }

    private static func save(_ vault: APIKeyNoteVault) {
        guard let data = try? JSONEncoder().encode(vault) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

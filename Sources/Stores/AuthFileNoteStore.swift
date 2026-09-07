import Foundation

/// Local-only metadata, keyed by node and the exact remote filename.
enum AuthFileNoteStore {
    private static let defaultsKey = "auth-file-notes-v1"

    static func notes(for nodeID: UUID) -> [String: String] {
        load()[nodeID.uuidString] ?? [:]
    }

    static func setNote(_ note: String, for nodeID: UUID, filename: String) {
        var vault = load()
        var notes = vault[nodeID.uuidString] ?? [:]
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        notes[filename] = trimmed.isEmpty ? nil : trimmed
        vault[nodeID.uuidString] = notes.isEmpty ? nil : notes
        save(vault)
    }

    static func remove(for nodeID: UUID) {
        var vault = load()
        vault[nodeID.uuidString] = nil
        save(vault)
    }

    private static func load() -> [String: [String: String]] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let vault = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else { return [:] }
        return vault
    }

    private static func save(_ vault: [String: [String: String]]) {
        guard let data = try? JSONEncoder().encode(vault) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

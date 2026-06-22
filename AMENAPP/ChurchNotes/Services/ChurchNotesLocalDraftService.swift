import Foundation

struct ChurchNotesLocalDraft: Codable, Equatable {
    var key: String
    var title: String
    var sermonTitle: String
    var churchName: String
    var pastor: String
    var selectedDate: Date
    var content: String
    var scriptureInput: String
    var scriptureReferences: [String]
    var actionStep: String
    var prayer: String
    var shouldRevisit: Bool
    var worshipSongs: [WorshipSongReference]
    var blocks: [ChurchNoteBlock]
    var noteTags: [String]
    var updatedAt: Date

    var hasMeaningfulContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !sermonTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !churchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !pastor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !scriptureInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !scriptureReferences.isEmpty ||
        !actionStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !prayer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !worshipSongs.isEmpty ||
        !blocks.isEmpty ||
        !noteTags.isEmpty
    }
}

final class ChurchNotesLocalDraftService {
    static let shared = ChurchNotesLocalDraftService()

    private let fileManager: FileManager
    private let legacyDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let directoryURL: URL

    init(fileManager: FileManager = .default, legacyDefaults: UserDefaults = .standard) {
        let baseURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.fileManager = fileManager
        self.legacyDefaults = legacyDefaults
        self.directoryURL = baseURL
            .appendingPathComponent("AMEN", isDirectory: true)
            .appendingPathComponent("ChurchNotesDrafts", isDirectory: true)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    init(directoryURL: URL, fileManager: FileManager = .default, legacyDefaults: UserDefaults = .standard) {
        self.fileManager = fileManager
        self.legacyDefaults = legacyDefaults
        self.directoryURL = directoryURL
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func save(_ draft: ChurchNotesLocalDraft) {
        guard draft.hasMeaningfulContent else {
            clear(key: draft.key)
            return
        }
        guard let data = try? encoder.encode(draft) else { return }
        let url = storageURL(for: draft.key)
        let temporaryURL = url.appendingPathExtension("tmp")
        do {
            try data.write(to: temporaryURL, options: [.atomic, .completeFileProtection])
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
        }
    }

    func load(key: String) -> ChurchNotesLocalDraft? {
        if let data = try? Data(contentsOf: storageURL(for: key)),
           let draft = try? decoder.decode(ChurchNotesLocalDraft.self, from: data) {
            return draft
        }
        return migrateLegacyDraftIfNeeded(key: key)
    }

    func clear(key: String) {
        try? fileManager.removeItem(at: storageURL(for: key))
        legacyDefaults.removeObject(forKey: legacyStorageKey(for: key))
    }

    private func storageURL(for key: String) -> URL {
        directoryURL.appendingPathComponent(sanitizedKey(key)).appendingPathExtension("json")
    }

    private func sanitizedKey(_ key: String) -> String {
        key
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }
            .joined()
    }

    private func legacyStorageKey(for key: String) -> String {
        "amen.churchNotes.localDraft.\(key)"
    }

    private func migrateLegacyDraftIfNeeded(key: String) -> ChurchNotesLocalDraft? {
        let legacyKey = legacyStorageKey(for: key)
        guard let data = legacyDefaults.data(forKey: legacyKey),
              let draft = try? decoder.decode(ChurchNotesLocalDraft.self, from: data) else {
            return nil
        }
        save(draft)
        legacyDefaults.removeObject(forKey: legacyKey)
        return draft
    }
}

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

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let namespace = "amen.churchNotes.localDraft"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ draft: ChurchNotesLocalDraft) {
        guard draft.hasMeaningfulContent else {
            clear(key: draft.key)
            return
        }
        guard let data = try? encoder.encode(draft) else { return }
        defaults.set(data, forKey: storageKey(for: draft.key))
    }

    func load(key: String) -> ChurchNotesLocalDraft? {
        guard let data = defaults.data(forKey: storageKey(for: key)) else { return nil }
        return try? decoder.decode(ChurchNotesLocalDraft.self, from: data)
    }

    func clear(key: String) {
        defaults.removeObject(forKey: storageKey(for: key))
    }

    private func storageKey(for key: String) -> String {
        "\(namespace).\(key)"
    }
}

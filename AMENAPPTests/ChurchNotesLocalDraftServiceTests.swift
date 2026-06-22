import Foundation
import Testing
@testable import AMENAPP

struct ChurchNotesLocalDraftServiceTests {
    @Test("Church Notes drafts persist, restore, and clear from file storage")
    func fileBackedDraftRoundTrip() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChurchNotesDraftServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let service = ChurchNotesLocalDraftService(
            directoryURL: directoryURL,
            legacyDefaults: try #require(UserDefaults(suiteName: "ChurchNotesDraftServiceTests-\(UUID().uuidString)"))
        )
        let draft = makeDraft(key: "new-note")

        service.save(draft)
        let restored = try #require(service.load(key: "new-note"))

        #expect(restored.title == "Sunday notes")
        #expect(restored.blocks.first?.type == .prayer)
        #expect(restored.scriptureReferences == ["Romans 8:28"])

        service.clear(key: "new-note")
        #expect(service.load(key: "new-note") == nil)
    }

    @Test("Church Notes drafts migrate legacy UserDefaults payloads on first restore")
    func legacyUserDefaultsDraftMigratesToFileStorage() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChurchNotesDraftMigrationTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ChurchNotesDraftMigrationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        let draft = makeDraft(key: "legacy-note")
        defaults.set(try JSONEncoder().encode(draft), forKey: "amen.churchNotes.localDraft.legacy-note")

        let service = ChurchNotesLocalDraftService(directoryURL: directoryURL, legacyDefaults: defaults)
        let migrated = try #require(service.load(key: "legacy-note"))

        #expect(migrated.title == draft.title)
        #expect(defaults.data(forKey: "amen.churchNotes.localDraft.legacy-note") == nil)
        #expect(service.load(key: "legacy-note")?.content == draft.content)
    }

    private func makeDraft(key: String) -> ChurchNotesLocalDraft {
        ChurchNotesLocalDraft(
            key: key,
            title: "Sunday notes",
            sermonTitle: "Faith that moves",
            churchName: "AMEN Church",
            pastor: "Pastor Grace",
            selectedDate: Date(timeIntervalSince1970: 1_800_000_000),
            content: "God works all things together.",
            scriptureInput: "Romans 8:28",
            scriptureReferences: ["Romans 8:28"],
            actionStep: "Call James on Tuesday",
            prayer: "Lord, help me follow through.",
            shouldRevisit: true,
            worshipSongs: [],
            blocks: [ChurchNoteBlock(type: .prayer, text: "Help me follow through.")],
            noteTags: ["sermon"],
            updatedAt: Date(timeIntervalSince1970: 1_800_000_030)
        )
    }
}

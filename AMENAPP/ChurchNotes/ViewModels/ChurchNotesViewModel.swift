import Foundation
import SwiftUI

@MainActor
final class ChurchNotesViewModel: ObservableObject {
    @Published var metadata: ChurchNoteMetadata
    @Published var title: String
    @Published var sermonTitle: String
    @Published var content: String
    @Published var attributedText: NSAttributedString
    @Published var blocks: [ChurchNoteBlock]
    @Published var tags: [String]
    @Published var scriptureReferences: [String]
    @Published var worshipSongs: [WorshipSongReference]
    @Published var growthActionStep: String
    @Published var growthPrayer: String
    @Published var revisitMidweek: Bool
    @Published var reviewSummary: ChurchNoteReviewSummary = .empty
    @Published var isReviewMode = false
    @Published var detectedScriptures: [ChurchNoteScriptureReference] = []
    @Published var suggestedScriptures: [ChurchNoteScriptureReference] = []

    let sourceNote: ChurchNote?
    private let reviewService = ChurchNotesReviewSummaryService.shared

    init(note: ChurchNote? = nil) {
        sourceNote = note
        metadata = note.map(ChurchNoteMetadata.init(note:)) ?? ChurchNoteMetadata()
        title = note?.title ?? ""
        sermonTitle = note?.sermonTitle ?? ""
        content = note?.content ?? ""
        if let doc = note?.richTextDocument {
            attributedText = AttributedStringFormatter().decode(document: doc)
        } else {
            attributedText = NSAttributedString(string: note?.content ?? "")
        }
        blocks = note?.blocks ?? []
        tags = note?.tags ?? []
        scriptureReferences = note?.scriptureReferences ?? []
        worshipSongs = note?.worshipSongs ?? []
        growthActionStep = note?.actionStepThisWeek ?? ""
        growthPrayer = note?.prayerFromSermon ?? ""
        revisitMidweek = note?.shouldRevisit ?? false
        refreshDerivedState()
    }

    func updateContent(_ newValue: String) {
        content = newValue
        refreshDerivedState()
    }

    func updateAttributedText(_ newValue: NSAttributedString) {
        attributedText = newValue
        refreshDerivedState()
    }

    func addTag(_ tag: String) {
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        tags.append(tag)
    }

    func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    func addScripture(_ ref: String) {
        guard !ref.isEmpty, !scriptureReferences.contains(ref) else { return }
        scriptureReferences.append(ref)
    }

    func removeScripture(_ ref: String) {
        scriptureReferences.removeAll { $0 == ref }
    }

    func addWorshipSong(_ song: WorshipSongReference) {
        guard !worshipSongs.contains(where: { $0.id == song.id }) else { return }
        worshipSongs.append(song)
    }

    func removeWorshipSong(id: String) {
        worshipSongs.removeAll { $0.id == id }
    }

    func convertSelectionToBlock(_ text: String, type: ChurchNoteBlockType, selectionTags: [String] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        blocks.append(ChurchNoteBlock(type: type, text: trimmed, tags: selectionTags))
        refreshDerivedState()
    }

    func refreshDerivedState() {
        detectedScriptures = ScriptureDetectionService.shared.detectedReferences(in: content)
        suggestedScriptures = ScriptureDetectionService.shared.suggestedReferences(for: content)
        reviewSummary = reviewService.summary(for: attributedText, blocks: blocks)
    }
}

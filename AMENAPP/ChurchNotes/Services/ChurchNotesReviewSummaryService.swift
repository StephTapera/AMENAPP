import Foundation

struct ChurchNotesReviewSummaryService {
    static let shared = ChurchNotesReviewSummaryService()

    func summary(for attributedText: NSAttributedString, blocks: [ChurchNoteBlock]) -> ChurchNoteReviewSummary {
        let base = attributedText.churchNotesReviewSummary()
        return ChurchNoteReviewSummary(
            highlightCount: base.highlightCount,
            prayerCount: blocks.filter { $0.type == .prayer }.count,
            actionCount: blocks.filter { $0.type == .action }.count,
            scriptureCount: blocks.filter { $0.type == .scripture }.count,
            quoteCount: blocks.filter { $0.type == .quote }.count
        )
    }
}

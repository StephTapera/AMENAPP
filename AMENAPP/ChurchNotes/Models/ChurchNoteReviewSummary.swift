import Foundation

struct ChurchNoteReviewSummary: Codable, Hashable {
    var highlightCount: Int
    var prayerCount: Int
    var actionCount: Int
    var scriptureCount: Int
    var quoteCount: Int

    static let empty = ChurchNoteReviewSummary(
        highlightCount: 0,
        prayerCount: 0,
        actionCount: 0,
        scriptureCount: 0,
        quoteCount: 0
    )
}

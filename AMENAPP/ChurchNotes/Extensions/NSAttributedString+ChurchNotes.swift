import Foundation
import UIKit

extension NSAttributedString {
    func churchNotesReviewSummary() -> ChurchNoteReviewSummary {
        var highlightCount = 0
        enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: length)) { value, _, _ in
            if value != nil { highlightCount += 1 }
        }
        return ChurchNoteReviewSummary(
            highlightCount: highlightCount,
            prayerCount: 0,
            actionCount: 0,
            scriptureCount: 0,
            quoteCount: 0
        )
    }
}

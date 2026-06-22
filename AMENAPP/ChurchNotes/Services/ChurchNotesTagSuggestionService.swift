import Foundation

struct ChurchNotesTagSuggestionService {
    static let shared = ChurchNotesTagSuggestionService()

    let suggestedTags = [
        "Faith", "Grace", "Healing", "Waiting", "Forgiveness", "Worship",
        "Obedience", "Prayer", "Hope", "Community", "Stewardship", "Conviction"
    ]

    func suggestions(for text: String, excluding applied: [String]) -> [ChurchNoteTag] {
        let lower = text.lowercased()
        let excluded = Set(applied.map { $0.lowercased() })
        return suggestedTags
            .filter { lower.contains($0.lowercased()) && !excluded.contains($0.lowercased()) }
            .map { ChurchNoteTag(name: $0) }
    }
}

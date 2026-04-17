import Foundation

struct ScriptureDetectionService {
    static let shared = ScriptureDetectionService()

    func detectedReferences(in text: String) -> [ChurchNoteScriptureReference] {
        ChurchNotesScriptureDetector.shared
            .detectReferenceStrings(in: text)
            .map { ChurchNoteScriptureReference(reference: $0) }
    }

    func suggestedReferences(for text: String) -> [ChurchNoteScriptureReference] {
        ScriptureThemeSuggestion
            .suggest(for: text)
            .map { ChurchNoteScriptureReference(reference: $0.reference) }
    }
}

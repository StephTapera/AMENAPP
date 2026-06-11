import Foundation

struct AfterServiceReflectionDraft: Equatable {
    var stoodOut: String
    var application: String
    var prayer: String
    var continueStudy: Bool

    func applying(to note: ChurchNote, now: Date = Date(), calendar: Calendar = .current) -> ChurchNote {
        var updated = note
        updated.permission = .privateNote
        updated.sharedWith = []
        updated.growthReflection = trimmedValue(stoodOut)
        updated.actionStepThisWeek = trimmedValue(application)
        updated.prayerFromSermon = trimmedValue(prayer)
        updated.shouldRevisit = continueStudy
        updated.revisitDate = continueStudy ? calendar.date(byAdding: .day, value: 7, to: now) : nil
        return updated
    }

    private func trimmedValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum ChurchStudyHighlightSharingPolicy {
    static let canPostPublicHighlight = false
    static let publicHighlightLabel = "Public highlights are disabled until the group bridge is reviewed publicly."
}

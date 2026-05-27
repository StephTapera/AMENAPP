import Foundation

enum AmenThreadSummaryState: Equatable {
    case idle
    case loading
    case generating
    case loaded(AmenThreadSummary)
    case empty
    case stale(AmenThreadSummary)
    case error(String)
    case permissionDenied
    case offline(AmenThreadSummary?)
}

struct AmenThreadSummary: Identifiable, Codable, Equatable {
    var id: String
    var threadId: String
    var summary: String
    var topic: String
    var changedSinceLastVisit: [String]
    var decisions: [AmenThreadDecision]
    var openQuestions: [AmenThreadQuestion]
    var followUps: [AmenThreadAction]
    var importantDates: [AmenThreadImportantDate]
    var mediaRefs: [AmenThreadMediaRef]
    var suggestedActions: [ThreadSuggestedAction]
    var generatedAt: Date
    var staleAfter: Date?
    var sourceMessageIds: [String]

    var isStale: Bool {
        guard let staleAfter else { return false }
        return Date() >= staleAfter
    }

    static func empty(threadId: String) -> AmenThreadSummary {
        AmenThreadSummary(
            id: UUID().uuidString,
            threadId: threadId,
            summary: "",
            topic: "No current topic",
            changedSinceLastVisit: [],
            decisions: [],
            openQuestions: [],
            followUps: [],
            importantDates: [],
            mediaRefs: [],
            suggestedActions: [],
            generatedAt: Date(),
            staleAfter: nil,
            sourceMessageIds: []
        )
    }
}

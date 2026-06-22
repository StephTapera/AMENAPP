import Foundation

enum AmenAIReviewState: String, Codable, CaseIterable {
    case idle
    case explaining
    case awaitingUserConfirmation
    case validating
    case moderatingInput
    case generating
    case moderatingOutput
    case draftReady
    case editing
    case regenerating
    case rejected
    case approved
    case failed

    var canPreviewDraft: Bool { self == .draftReady || self == .editing || self == .regenerating }
    var canApprove: Bool { self == .draftReady || self == .editing }
}

enum AmenGeneratedDraftStatus: String, Codable, CaseIterable {
    case draft
    case editing
    case rejected
    case approved
    case expired
    case blocked
}

import Foundation

enum SignalType: String, Codable, CaseIterable, Sendable {
    case noteSaved
    case noteThemeDetected
    case churchSaved
    case churchUnsaved
    case churchViewed
    case visitVerified
    case prayerCreated
    case prayerAnswered
    case prayerReminderActed
    case giftCompleted
    case givingCauseViewed
    case messageSent
    case prayerExtractedFromMessage
    case studyStarted
    case studyCompleted
    case verseReflected
    case wellnessToolUsed
    case crisisSurfaceOpened
    case groupJoined
    case eventRSVPed
    case volunteerMatched
    case sessionRhythmTick
}

enum TierCeiling: String, Codable, CaseIterable, Sendable {
    case s
    case c
    case p
}

struct ContextSignal: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let type: SignalType
    let tierCeiling: TierCeiling
    let subjectRefs: [GraphRef]
    let payload: [String: AnyCodableValue]
    let occurredAt: Date
    let decayHalfLifeDays: Double
    let consentEdgeRequired: ConsentEdge?
}

struct GraphRef: Codable, Hashable, Sendable {
    let nodeType: GraphNodeType
    let nodeID: String
}

enum GraphNodeType: String, Codable, CaseIterable, Sendable {
    case church
    case churchVisit
    case sermon
    case note
    case prayerRequest
    case person
    case group
    case community
    case gift
    case cause
    case event
    case study
    case verse
    case skill
    case interest
    case goal
    case milestone
    case wellnessActivity
    case reflection
}

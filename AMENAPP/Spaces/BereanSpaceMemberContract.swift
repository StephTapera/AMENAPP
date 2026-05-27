// BereanSpaceMemberContract.swift
// AMENAPP — Phase 0: Berean-as-Member Interface Contract
//
// Defines how Berean AI participates as a first-class Space member.
// Agent B owns the runtime implementation of this protocol.
//
// Architecture rules:
//   - Berean reads Space context via SemanticEmbeddingService callables
//     scoped to the Space's memoryNamespace. It never reads raw Firestore
//     messages from other users directly.
//   - Berean posts through the same GUARDIAN pipeline as any member.
//     guardianStatus is set server-side; Berean cannot approve its own posts.
//   - AI model keys never leave Cloud Functions. All invocations go through
//     bereanSpaceInvoke callable (SpacesCallable.bereanSpaceInvoke).
//   - Berean has one calibrated personality per SpaceType.
//     It does NOT roleplay biblical figures; lenses are style modifiers only.
//   - Proactive surfacing is rhythm-aware. Berean only speaks up when
//     AmenSpaceRhythm signals the Space is active and a trigger is present.
//   - Cited recall returns real message/note IDs — never fabricated citations.
//
// Firestore paths Berean MAY read (via callable, not direct client read):
//   spaces/{spaceId}/smartThreads/{threadId}/messages       ← context window
//   spaces/{spaceId}/knowledgeGraph/nodes                   ← topic graph
//   spaces/{spaceId}/prayerRequests                         ← prayer context
//   churchNotes belonging to space members (if shared)      ← sermon context
//
// Firestore paths Berean NEVER reads:
//   /users/{uid}/privateInsights                            ← private boundary
//   /users/{uid}/safety                                     ← private boundary
//   /spaces/{otherSpaceId}/...                              ← cross-space fence

import Foundation
import FirebaseFunctions

// MARK: - Invocation Trigger

/// What caused Berean to be invoked. Drives personality calibration and proactive rules.
enum BereanSpaceTrigger: String, Codable {
    case atMention       = "at_mention"       // user typed @Berean
    case directMessage   = "direct_message"   // user DM'd Berean
    case proactive       = "proactive"        // rhythm-aware proactive surface
    case prayerRequest   = "prayer_request"   // user submitted a prayer request
    case questionDetected = "question_detected" // NLP detected unanswered question
    case summaryRequest  = "summary_request"  // user tapped "Catch me up"
    case citedRecall     = "cited_recall"     // user asked "what did we say about X?"
    case studyPrompt     = "study_prompt"     // reading plan day spawns a question
}

// MARK: - Invocation Request

/// The payload sent to the bereanSpaceInvoke callable.
/// Client constructs this; the callable validates, fetches context, calls the model,
/// passes through GUARDIAN, and writes the response to the room.
struct BereanSpaceInvokeRequest: Codable {
    let spaceId: String
    let roomId: String?             // nil → Space-level DM
    let trigger: BereanSpaceTrigger
    let userMessage: String?        // text of @mention / DM / question (if any)
    let replyToPostId: String?      // non-nil → Berean responds in-thread
    let requestingUserId: String
    let theoLens: String            // BereanTheoLens.rawValue — calibrated per SpaceType
    let contextWindowSize: Int      // max messages to include (capped server-side)

    // Provenance fields (server fills these, but client may suggest)
    var suggestedSourceIds: [String]  // message/note IDs the user thinks are relevant
}

// MARK: - Invocation Response

/// The callable returns this. The actual post is written to Firestore server-side,
/// so clients do NOT write the response themselves — they observe it via snapshot listener.
struct BereanSpaceInvokeResponse: Codable {
    let postId: String              // Firestore ID of the AmenRoomPost Berean created
    let roomId: String
    let spaceId: String
    let guardianStatus: String      // "approved" | "flagged" — always server-set
    let citedSourceIds: [String]    // real message/note IDs Berean cited
    let confidence: Double          // 0..1 — exposed for humble UI language
    let provenanceMetadata: BereanResponseProvenance
}

struct BereanResponseProvenance: Codable {
    let generatedBy: String         // callable version / model tag  SERVER-OWNED
    let sourceIds: [String]         // Firestore IDs of cited sources SERVER-OWNED
    let confidence: Double          // SERVER-OWNED
    let visibility: String          // "space_members"               SERVER-OWNED
    let createdAt: Date             // SERVER-OWNED
    let userId: String              // Berean's system UID            SERVER-OWNED
    let spaceId: String             // SERVER-OWNED
    let safetyStatus: String        // GUARDIAN decision              SERVER-OWNED
}

// MARK: - Cited Recall Request

/// Used for "what did we conclude about X?" queries.
/// Berean searches the Space's memory namespace and returns grounded citations.
struct BereanCitedRecallRequest: Codable {
    let spaceId: String
    let query: String
    let requestingUserId: String
    let maxResults: Int             // capped at 10 server-side
}

struct BereanCitedRecallResult: Codable, Identifiable {
    let id: String
    let spaceId: String
    let query: String
    let summary: String             // Berean's synthesized answer
    let citations: [BereanCitation]
    let confidence: Double
    let generatedAt: Date
    /// Humble qualifier shown when confidence < 0.7
    var humbleCaveat: String? {
        confidence < 0.70 ? "These results are approximate — review the original messages for accuracy." : nil
    }
}

struct BereanCitation: Codable, Identifiable {
    let id: String                  // Firestore post/note ID
    let kind: BereanCitationKind
    let preview: String             // first 200 chars
    let authorDisplayName: String   // scoped name (anonymous if opted-in)
    let timestamp: Date
    let relevanceScore: Double
    let roomId: String?
    let spaceId: String
}

enum BereanCitationKind: String, Codable {
    case roomPost    = "room_post"
    case churchNote  = "church_note"
    case prayerRequest = "prayer_request"
    case studyNote   = "study_note"
    case sermonClip  = "sermon_clip"
}

// MARK: - Proactive Hook Contract

/// Agent F (Rhythm + Attention) calls these hooks to determine whether
/// Berean should surface proactively. All checks are non-blocking; Berean
/// only acts if the rhythm gate AND at least one trigger condition pass.
protocol BereanProactiveGate {
    /// Returns true if the Space is in an active window per its rhythm.
    func isRhythmActive(spaceId: String) async -> Bool

    /// Returns true if an unanswered question has been open > threshold duration.
    func hasUnansweredQuestion(spaceId: String, olderThan seconds: Int) async -> Bool

    /// Returns true if a prayer request has gone unacknowledged.
    func hasSilentPrayerRequest(spaceId: String, olderThan seconds: Int) async -> Bool

    /// Returns true if participation has dropped significantly vs. the Space's baseline.
    func hasParticipationDrop(spaceId: String, dropThreshold: Double) async -> Bool
}

// MARK: - Personality Calibration

/// Maps SpaceType to the default BereanTheoLens for that context.
/// Agent B uses this to pre-select the lens when invoking Berean from a Space.
/// Users can override per-message.
struct BereanSpacePersonality {
    static func defaultLens(for type: AmenSpaceType) -> String {
        switch type {
        case .churchMinistry, .sermonPrep, .leadershipRoom:
            return "wisdom"         // BereanTheoLens.wisdom
        case .prayerGroup, .supportCommunity, .discipleshipCohort:
            return "prayer"         // BereanTheoLens.prayer
        case .bibleStudy, .schoolClassroom:
            return "discernment"    // BereanTheoLens.discernment
        case .familyGroup, .creatorCommunity, .operationsHub, .eventWorkspace:
            return "wisdom"
        }
    }

    /// Whether proactive surfacing is permitted for this SpaceType.
    static func allowsProactiveSurfacing(for type: AmenSpaceType) -> Bool {
        switch type {
        case .supportCommunity:
            // Support/recovery spaces: Berean only responds to explicit @mentions.
            return false
        case .prayerGroup, .familyGroup:
            // These require opt-in via Space settings before proactive is enabled.
            return false
        default:
            return true
        }
    }

    /// Whether AI inference is allowed at all for this SpaceType.
    /// Mirrors AmenSpaceType.aiInferenceAllowed from AmenSpacesIntelligenceModels.
    static func allowsAIInference(for type: AmenSpaceType) -> Bool {
        type.aiInferenceAllowed
    }
}

// MARK: - Client-Side Invocation Service

/// Thin client wrapper that sends the bereanSpaceInvoke callable and returns
/// the response. Agents use this — they do not call Functions.httpsCallable directly.
@MainActor
final class BereanSpaceMemberService {

    static let shared = BereanSpaceMemberService()
    private let functions = Functions.functions()

    private init() {}

    // MARK: - @mention / DM Invoke

    /// Invokes Berean in a Space room via @mention or DM.
    /// The response post is written to Firestore server-side — observe the room's
    /// snapshot listener; do NOT write the response yourself.
    func invoke(
        spaceId: String,
        roomId: String?,
        trigger: BereanSpaceTrigger,
        userMessage: String,
        replyToPostId: String? = nil,
        spaceType: AmenSpaceType
    ) async throws -> BereanSpaceInvokeResponse {

        guard BereanSpacePersonality.allowsAIInference(for: spaceType) else {
            throw BereanSpaceError.aiInferenceDisabled(spaceType: spaceType)
        }

        let request = BereanSpaceInvokeRequest(
            spaceId: spaceId,
            roomId: roomId,
            trigger: trigger,
            userMessage: userMessage,
            replyToPostId: replyToPostId,
            requestingUserId: "",       // filled server-side from auth token
            theoLens: BereanSpacePersonality.defaultLens(for: spaceType),
            contextWindowSize: 20,
            suggestedSourceIds: []
        )

        let encoded = try JSONEncoder().encode(request)
        let dict    = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]

        let result  = try await functions
            .httpsCallable(SpacesCallable.bereanSpaceInvoke.rawValue)
            .call(dict)

        guard let data = result.data as? [String: Any] else {
            throw BereanSpaceError.malformedResponse
        }
        let decoded = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode(BereanSpaceInvokeResponse.self, from: decoded)
    }

    // MARK: - Cited Recall

    /// "What did we say about X?" — Berean searches Space memory and returns
    /// grounded citations from real messages/notes. Never fabricates references.
    func citedRecall(query: String, spaceId: String) async throws -> BereanCitedRecallResult {
        let request = BereanCitedRecallRequest(
            spaceId: spaceId,
            query: query,
            requestingUserId: "",   // server fills from auth
            maxResults: 8
        )

        let encoded = try JSONEncoder().encode(request)
        let dict    = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]

        let result  = try await functions
            .httpsCallable("bereanSpaceCitedRecall")
            .call(dict)

        guard let data = result.data as? [String: Any] else {
            throw BereanSpaceError.malformedResponse
        }
        let decoded = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode(BereanCitedRecallResult.self, from: decoded)
    }
}

// MARK: - Errors

enum BereanSpaceError: LocalizedError {
    case aiInferenceDisabled(spaceType: AmenSpaceType)
    case malformedResponse
    case rateLimited
    case guardianBlocked(reason: String)

    var errorDescription: String? {
        switch self {
        case .aiInferenceDisabled(let type):
            return "AI features are not available in \(type.rawValue) spaces."
        case .malformedResponse:
            return "Berean returned an unexpected response. Please try again."
        case .rateLimited:
            return "You've reached the AI request limit for this space. Please wait a moment."
        case .guardianBlocked(let reason):
            return "This response was held for review: \(reason)"
        }
    }
}

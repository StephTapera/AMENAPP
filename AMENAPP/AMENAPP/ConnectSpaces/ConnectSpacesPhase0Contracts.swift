// ConnectSpacesPhase0Contracts.swift
// AMEN Connect + AMEN Spaces
//
// FROZEN — Phase 0 contracts for the AMEN Connect + AMEN Spaces rebuild.
// Do not edit without Lead Orchestrator authorization and rebroadcast to every agent.
// Frozen on 2026-06-01.

import Foundation

let AmenConnectSpacesContractsVersion = "2026-06-01-v1"

// MARK: - Design Tokens

/// Frozen color tokens for the Liquid Intelligence Layer.
/// SwiftUI implementations should map these hex values into Color assets or local Color helpers.
enum AmenConnectSpacesDesignToken: String, Codable, CaseIterable, Hashable {
    case amenGold = "#D9A441"
    case amenPurple = "#6E4BB5"
    case amenBlue = "#245B8F"
    case amenBlack = "#070607"
}

/// Chrome may use Liquid Glass. Scripture, message bodies, and primary video content stay matte.
enum AmenConnectSpacesGlassSurface: String, Codable, CaseIterable, Hashable {
    case floatingNavigation
    case switcher
    case threadCareDrawer
    case aiSummaryPanel
    case mediaControls
    case commandBar
    case previewOverlay
    case searchBar
}

/// All animation work must route through an adaptive motion policy with reduce-motion fallbacks.
enum AmenConnectSpacesMotionPolicy: String, Codable, CaseIterable, Hashable {
    case adaptive
    case reduced
    case disabled
}

// MARK: - Firestore Contracts

enum AmenConnectSpacesRoomType: String, Codable, CaseIterable, Hashable {
    case smallGroup
    case prayer
    case worship
    case missions
    case staff
    case cohort
    case accountability
}

struct AmenConnectSpacesSpace: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var type: AmenConnectSpacesRoomType
    var memberIds: [String]
    var careSensitivity: Bool
    var createdBy: String
    var createdAt: Date
    var updatedAt: Date
}

enum AmenConnectSpacesMessageIntent: String, Codable, CaseIterable, Hashable {
    case prayerRequest
    case struggling
    case leadSunday
    case volunteerNeed
    case testimony
    case confession
    case grief
    case decision
    case task
    case risk
    case question
    case careFollowUp
}

struct AmenConnectSpacesConvictionCheck: Codable, Hashable {
    var enabled: Bool
    var suggestedPause: Bool
    var warningKinds: [AmenConnectSpacesBeforeShareWarning]
    var checkedAt: Date?
}

enum AmenConnectSpacesBeforeShareWarning: String, Codable, CaseIterable, Hashable {
    case gossip
    case slander
    case divisiveness
    case pii
    case phi
    case financial
}

struct AmenConnectSpacesMessage: Identifiable, Codable, Hashable {
    let id: String
    var body: String
    var authorId: String
    var detectedIntents: [AmenConnectSpacesMessageIntent]
    var convictionCheck: AmenConnectSpacesConvictionCheck
    var careRouted: Bool
    var createdAt: Date
    var updatedAt: Date
}

enum AmenConnectSpacesDerivedItemKind: String, Codable, CaseIterable, Hashable {
    case decision
    case task
    case risk
    case prayer
    case careFollowUp
    case serveSlot
}

enum AmenConnectSpacesItemStatus: String, Codable, CaseIterable, Hashable {
    case open
    case inProgress
    case waiting
    case done
    case archived
}

struct AmenConnectSpacesDerivedItem: Identifiable, Codable, Hashable {
    let id: String
    var kind: AmenConnectSpacesDerivedItemKind
    var title: String
    var owner: String?
    var due: Date?
    var status: AmenConnectSpacesItemStatus
    var sourceMsgId: String
    var createdAt: Date
    var updatedAt: Date
}

enum AmenConnectSpacesSpiritualState: String, Codable, CaseIterable, Hashable {
    case inTheWord
    case inPrayer
    case fasting
    case sabbathRest
    case grieving
    case discerning
    case availableForUrgentPrayer
}

struct AmenConnectSpacesPresence: Identifiable, Codable, Hashable {
    var id: String { userId }
    let userId: String
    var spiritualState: AmenConnectSpacesSpiritualState
    var urgentReachable: Bool
    var sabbathUntil: Date?
    var updatedAt: Date
}

struct AmenConnectSpacesVideoProvenance: Codable, Hashable {
    var humanRecorded: Bool
    var aiEdited: Bool
    var aiGenerated: Bool
    var synthVoice: Bool
    var synthFace: Bool
    var deepfakeRisk: Double
    var verifiedOriginal: Bool
}

struct AmenConnectSpacesScriptureRefProvenance: Identifiable, Codable, Hashable {
    let id: String
    var reference: String
    var translation: String
    var sourceLayer: AmenConnectSpacesScriptureProvenanceLayer
    var verifiedAt: Date
    var confidence: Double
}

enum AmenConnectSpacesScriptureProvenanceLayer: String, Codable, CaseIterable, Hashable {
    case canonicalReference
    case translationSource
    case contextWindow
    case bereanStudySheet
}

struct AmenConnectSpacesTeachingClaim: Identifiable, Codable, Hashable {
    let id: String
    var text: String
    var timestampSeconds: TimeInterval?
    var sourceTranscriptRange: String?
    var opposingFaithfulViews: [String]
}

struct AmenConnectSpacesConnectVideo: Identifiable, Codable, Hashable {
    let id: String
    var provenance: AmenConnectSpacesVideoProvenance
    var teacherId: String
    var transcriptRef: String
    var claims: [AmenConnectSpacesTeachingClaim]
    var scriptureRefs: [AmenConnectSpacesScriptureRefProvenance]
    var sponsored: Bool
    var createdAt: Date
    var updatedAt: Date
}

enum AmenConnectSpacesCommentType: String, Codable, CaseIterable, Hashable {
    case question
    case correction
    case experience
    case citation
    case encouragement
    case respectfulDisagree
}

struct AmenConnectSpacesConnectComment: Identifiable, Codable, Hashable {
    let id: String
    var type: AmenConnectSpacesCommentType
    var body: String
    var authorId: String
    var edificationScore: Double
    var createdAt: Date
}

struct AmenConnectSpacesKnowledgeGraph: Identifiable, Codable, Hashable {
    var id: String { userId }
    let userId: String
    var studied: [String]
    var understood: [String]
    var wrestlingWith: [String]
    var saved: [String]
    var nextUp: [String]
    var updatedAt: Date
}

enum AmenConnectSpacesSurface: String, Codable, CaseIterable, Hashable {
    case spaces
    case connect
    case liquidIntelligenceSearch
    case upload
    case comments
    case directMessage
}

enum AmenConnectSpacesAegisAction: String, Codable, CaseIterable, Hashable {
    case allow
    case label
    case warn
    case routeToCare
    case routeToHumanReview
    case block
}

struct AmenConnectSpacesAegisFlag: Identifiable, Codable, Hashable {
    let id: String
    var capabilityRef: String
    var surface: AmenConnectSpacesSurface
    var severity: String
    var action: AmenConnectSpacesAegisAction
    var subjectRef: String
    var createdAt: Date
}

// MARK: - Callable Proxy Contracts

enum AmenConnectSpacesCallable: String, Codable, CaseIterable, Hashable {
    case createMinistrySpace
    case postMinistryMessage
    case detectMessageIntents
    case routeCareSignal
    case updateSpiritualPresence
    case runConvictionCheck
    case runBeforeShareCheck
    case fetchConnectVideoContext
    case verifyScriptureProvenance
    case recordKnowledgeGraphEvent
    case scoreEdifyingComment
    case runAegisInputGate
    case runAegisOutputGate
    case scanUploadForFamilySafety
    case searchMinistryMemory
}

struct AmenConnectSpacesMinistryMemoryResult: Identifiable, Codable, Hashable {
    let id: String
    var videoId: String
    var timestampSeconds: TimeInterval
    var transcriptExcerpt: String
    var owner: String?
    var actionItemId: String?
    var confidence: Double
}

// MARK: - Aegis Rules

enum AmenConnectSpacesHardSafetyRule: String, Codable, CaseIterable, Hashable {
    case everyAIInputPassesAegis
    case everyAIOutputPassesAegis
    case noScriptureWithoutProvenance
    case syntheticMediaLabelsNonRemovable
    case careSignalsRouteToHumans
    case crisisSignalsNeverAIOnly
    case childSafetyScanBlocksBeforePublish
    case noClientSideModelKeys
}

struct AmenConnectSpacesAegisGateRequest: Codable, Hashable {
    var surface: AmenConnectSpacesSurface
    var capabilityRefs: [String]
    var inputRef: String
    var userId: String
    var spaceId: String?
    var videoId: String?
}

struct AmenConnectSpacesAegisGateDecision: Codable, Hashable {
    var action: AmenConnectSpacesAegisAction
    var flags: [AmenConnectSpacesAegisFlag]
    var humanResourceRefs: [String]
    var canContinue: Bool
}

// MARK: - Orchestration Guardrails

enum AmenConnectSpacesGuardrail: String, Codable, CaseIterable, Hashable {
    case noGitResetHard
    case noBroadFirebaseDeploy
    case oneFindingOneFixOneVerifiedBuild
    case htmlPrototypeBeforeSwiftUI
    case agentsDoNotEditFrozenContracts
}

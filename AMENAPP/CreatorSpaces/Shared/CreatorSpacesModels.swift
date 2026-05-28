import Foundation

// Shared Creator Spaces contracts. These mirror the server-owned Firestore schema;
// provenance and moderation fields are never client-authoritative.

enum CreatorMediaAssetType: String, Codable, CaseIterable, Sendable {
    case presence
    case single
    case video
    case audio
    case creation
}

enum CreatorFrameLayout: String, Codable, CaseIterable, Sendable {
    case pip
    case split
    case stacked
}

enum CreatorMediaModerationStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case approved
    case blocked
}

enum CreatorFeedDistribution: String, Codable, CaseIterable, Sendable {
    case dailyPortion = "daily_portion"
    case profileOnly = "profile_only"
    case roomsOnly = "rooms_only"
}

enum CreatorSpaceRole: String, Codable, CaseIterable, Sendable {
    case owner
    case admin
    case moderator
    case creator
    case member
    case guest
}

enum CreatorSpaceVisibility: String, Codable, CaseIterable, Sendable {
    case `private`
    case inviteOnly = "invite_only"
    case discoverable
    case `public`
}

struct CreatorMediaFrame: Codable, Equatable, Sendable {
    var storagePath: String
    var width: Int
    var height: Int
}

struct CreatorAudioFrame: Codable, Equatable, Sendable {
    var storagePath: String
    var spatial: Bool
}

struct CreatorMediaFrames: Codable, Equatable, Sendable {
    var back: CreatorMediaFrame?
    var front: CreatorMediaFrame?
    var composite: CreatorMediaFrame?
    var audio: CreatorAudioFrame?
    var layout: CreatorFrameLayout

    init(
        back: CreatorMediaFrame? = nil,
        front: CreatorMediaFrame? = nil,
        composite: CreatorMediaFrame? = nil,
        audio: CreatorAudioFrame? = nil,
        layout: CreatorFrameLayout
    ) {
        self.back = back
        self.front = front
        self.composite = composite
        self.audio = audio
        self.layout = layout
    }
}

struct CreatorMediaContext: Codable, Equatable, Sendable {
    var location: String?
    var emotionTags: [String]
    var ambientSignals: [String: String]

    init(location: String? = nil, emotionTags: [String] = [], ambientSignals: [String: String] = [:]) {
        self.location = location
        self.emotionTags = emotionTags
        self.ambientSignals = ambientSignals
    }
}

struct CreatorProvenanceRef: Codable, Equatable, Sendable {
    var ref: String
}

struct CreatorModerationState: Codable, Equatable, Sendable {
    var status: CreatorMediaModerationStatus
    var guardianRef: String?
    var safetyFlags: [String]
}

struct CreatorFeedState: Codable, Equatable, Sendable {
    var distribution: CreatorFeedDistribution
    var scoreInputs: [String: Double]
}

struct CreatorMemoryGraphRef: Codable, Equatable, Sendable {
    var nodeId: String?
}

struct CreatorMediaAsset: Identifiable, Codable, Equatable, Sendable {
    var id: String { assetId }
    var assetId: String
    var authorId: String
    var createdAt: Date
    var type: CreatorMediaAssetType
    var frames: CreatorMediaFrames
    var context: CreatorMediaContext?
    var provenance: CreatorProvenanceRef
    var moderation: CreatorModerationState
    var feed: CreatorFeedState
    var memoryGraph: CreatorMemoryGraphRef?
}

struct CreatorProvenanceEvent: Identifiable, Codable, Equatable, Sendable {
    var id: String { "\(event)-\(ts.timeIntervalSince1970)" }
    var event: String
    var ts: Date
}

struct CreatorEditEvent: Identifiable, Codable, Equatable, Sendable {
    var id: String { "\(tool)-\(ts.timeIntervalSince1970)" }
    var tool: String
    var ts: Date
}

struct CreatorProvenanceLabel: Identifiable, Codable, Equatable, Sendable {
    var id: String { labelId }
    var labelId: String
    var assetId: String
    var capturedOnDevice: Bool
    var sourceCamera: String
    var timestampChain: [CreatorProvenanceEvent]
    var editHistory: [CreatorEditEvent]
    var editedWithAI: Bool
    var aiAssistedPercent: Double?
    var syntheticElementsPresent: Bool?
    var authenticityConfidence: Double?
    var signature: String

    var canShowShotRealBadge: Bool {
        capturedOnDevice && editHistory.isEmpty && !editedWithAI
    }

    var publicDisclosureText: String {
        if canShowShotRealBadge { return "Shot Real" }
        if editedWithAI { return "AI-assisted editing" }
        if !editHistory.isEmpty { return "Edited media" }
        return capturedOnDevice ? "Captured in AMEN" : "Imported media"
    }
}

struct CreatorMemoryNode: Identifiable, Codable, Equatable, Sendable {
    var id: String { nodeId }
    var nodeId: String
    var assetId: String
    var authorId: String
    var edges: CreatorMemoryEdges
    var embeddingRef: String?
}

struct CreatorMemoryEdges: Codable, Equatable, Sendable {
    var people: [String]
    var events: [String]
    var spaces: [String]
    var scriptures: [String]
    var projects: [String]
}

struct CreatorSpace: Identifiable, Codable, Equatable, Sendable {
    var id: String { spaceId }
    var spaceId: String
    var ownerId: String
    var name: String
    var purpose: String
    var visibility: CreatorSpaceVisibility
    var createdAt: Date
    var updatedAt: Date
    var memberCount: Int
    var requiresApproval: Bool
    var paidAccessEnabled: Bool
}

struct CreatorDailyPortionResponse: Codable, Equatable, Sendable {
    var items: [String]
    var exhausted: Bool
    var nextCursor: String?
}

struct CreatorMediaUploadResult: Codable, Equatable, Sendable {
    var assetId: String
    var labelId: String
}

enum CreatorSpacePaidListingKind: String, Codable, CaseIterable, Sendable {
    case subscription
    case eventPass = "event_pass"
    case creatorClass = "class"
    case study
    case mediaPack = "media_pack"
}

struct CreatorSpacePaidListingInput: Equatable, Sendable {
    var spaceId: String
    var title: String
    var description: String
    var kind: CreatorSpacePaidListingKind
    var stripePriceId: String
    var visibility: String
}

struct CreatorSpaceCheckoutResult: Equatable, Sendable {
    var checkoutId: String
    var url: URL?
}

struct CreatorSpaceEntitlementStatus: Equatable, Sendable {
    var accessGranted: Bool
    var status: String
}
struct CreatorRenderableMediaAsset: Identifiable, Equatable {
    var id: String { assetId }
    var assetId: String
    var type: String
    var moderationStatus: String
    var media: PostMediaContainer
}

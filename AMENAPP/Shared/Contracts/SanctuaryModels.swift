// SanctuaryModels.swift
// AMENAPP - Shared/Contracts
//
// FROZEN - SANCTUARY Wave 0 Living Video contracts.
// Do not edit without lead architect approval and a drift update to the TypeScript mirror.
// Frozen on 2026-06-12.
//
// Contract-only: no callables, repositories, routing handlers, or UI live here.

import Foundation

let SanctuaryContractsVersion = "2026-06-12-wave0-v1"

// MARK: - Feature Flags

enum SanctuaryFeatureFlagContract: String, CaseIterable, Sendable {
    case core = "sanctuary_core"
    case layers = "sanctuary_layers"
    case thread = "sanctuary_thread"
    case reactions = "sanctuary_reactions"
    case watchTogether = "sanctuary_watch_together"
    case selah = "sanctuary_selah"
    case askMoment = "sanctuary_ask_moment"
    case journey = "sanctuary_journey"
    case search = "sanctuary_search"

    static let defaultValue = false
}

// MARK: - Shared References

struct SanctuaryUserRef: Codable, Equatable, Hashable, Sendable {
    let uid: String
    let displayName: String?
    let avatarURL: URL?
}

struct SanctuaryC2PAProvenance: Codable, Equatable, Sendable {
    let manifestURL: URL?
    let assertionHash: String?
    let signer: String?
    let verified: Bool
    let capturedAt: Date?
}

struct SanctuaryLayerRef: Codable, Equatable, Hashable, Sendable {
    let id: String
    let type: VideoLayer.LayerType
}

struct SanctuaryLayerBlock: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let kind: BlockKind
    let text: String
    let timestampMs: Int?
    let sourceRef: String?

    enum BlockKind: String, Codable, CaseIterable, Sendable {
        case text
        case scripture
        case note
        case question
        case citation
        case prayer
    }
}

struct SanctuaryInteraction: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let type: InteractionType
    let videoRef: String
    let timestampMs: Int?
    let createdAt: Date
    let metadata: [String: AnyCodableValue]

    enum InteractionType: String, Codable, CaseIterable, Sendable {
        case watchComplete = "watch_complete"
        case highlight
        case question
        case note
        case reaction
        case prayer
    }
}

// MARK: - Living Video

struct LivingVideo: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let mediaURL: URL
    var transcriptStatus: TranscriptStatus
    var scriptureAnchors: [ScriptureAnchor]
    var layerRefs: [SanctuaryLayerRef]
    var provenance: SanctuaryC2PAProvenance
    var contentType: ContentType

    enum TranscriptStatus: String, Codable, CaseIterable, Sendable {
        case pending
        case processing
        case ready
        case failed
    }

    enum ContentType: String, Codable, CaseIterable, Sendable {
        case sermon
        case podcast
        case worship
        case testimony
        case study
        case event
    }
}

struct ScriptureAnchor: Codable, Identifiable, Equatable, Sendable {
    var id: String { "\(verseRef)-\(timestampMs)-\(source.rawValue)" }

    let verseRef: String
    let timestampMs: Int
    let confidence: Double
    let source: Source

    enum Source: String, Codable, CaseIterable, Sendable {
        case ai
        case creator
        case community
    }
}

struct VideoLayer: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let type: LayerType
    let visibility: Visibility
    var blocks: [SanctuaryLayerBlock]

    enum LayerType: String, Codable, CaseIterable, Sendable {
        case creatorNotes = "creator_notes"
        case scripture
        case communityInsights = "community_insights"
        case aiContext = "ai_context"
        case groupPrivate = "group_private"
    }

    enum Visibility: String, Codable, CaseIterable, Sendable {
        case ownerOnly = "owner_only"
        case creator
        case community
        case groupPrivate = "group_private"
        case publicRead = "public_read"
    }
}

struct SacredReaction: Codable, Identifiable, Equatable, Sendable {
    var id: String { "\(userRef.uid)-\(type.rawValue)-\(timestampMs)" }

    let type: ReactionType
    let timestampMs: Int
    let userRef: SanctuaryUserRef

    enum ReactionType: String, Codable, CaseIterable, Sendable {
        case amen
        case convicted
        case encouraged
        case needPrayer = "need_prayer"
        case studyingThis = "studying_this"
        case saved
    }
}

struct WatchRoom: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let hostRef: SanctuaryUserRef
    var memberOrbs: [SanctuaryUserRef]
    var playheadMs: Int
    var state: State

    enum State: String, Codable, CaseIterable, Sendable {
        case playing
        case paused
        case prayer
    }
}

struct SelahCard: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let type: CardType
    let durationMs: Int
    let verseRef: String?
    let prompt: String?

    enum CardType: String, Codable, CaseIterable, Sendable {
        case verse
        case prompt
        case silence
    }
}

struct JourneyNode: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let videoRef: String
    var interactions: [SanctuaryInteraction]
    let themeEmbeddingRef: String
    var linkedNodes: [String]
}

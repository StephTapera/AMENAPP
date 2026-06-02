import Foundation
import SwiftUI

struct AmenTrustBoundaryID: RawRepresentable, Hashable, Codable, Identifiable {
    var rawValue: String
    var id: String { rawValue }

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct ContextGraphNodeID: RawRepresentable, Hashable, Codable, Identifiable {
    var rawValue: String
    var id: String { rawValue }

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

enum NoteNotebookHint: String, CaseIterable, Codable, Hashable {
    case journal
    case meeting
}

enum ContextGraphNodeKind: String, CaseIterable, Codable, Hashable {
    case note
    case document
}

enum ContextGraphEdgeKind: String, CaseIterable, Codable, Hashable {
    case relatedTo
    case scheduledFor
}

enum DocumentNodeKind: String, CaseIterable, Codable, Hashable {
    case lessonPlan
}

typealias IntelligenceProcessorKind = ProvenanceProcessor

enum PineconeNamespace: Hashable, Codable, RawRepresentable {
    case personal(userID: String)
    case conversation(conversationID: String, trustBoundaryID: AmenTrustBoundaryID)
    case creatorPrivate(spaceID: String, creatorUserID: String)

    var rawValue: String {
        switch self {
        case .personal(let userID):
            return "personal:\(userID)"
        case .conversation(let conversationID, let trustBoundaryID):
            return "conversation:\(trustBoundaryID.rawValue):\(conversationID)"
        case .creatorPrivate(let spaceID, let creatorUserID):
            return "creator:\(creatorUserID):\(spaceID)"
        }
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        switch parts.first {
        case "personal" where parts.count == 2:
            self = .personal(userID: parts[1])
        case "conversation" where parts.count == 3:
            self = .conversation(conversationID: parts[2], trustBoundaryID: AmenTrustBoundaryID(rawValue: parts[1]))
        case "creator" where parts.count == 3:
            self = .creatorPrivate(spaceID: parts[2], creatorUserID: parts[1])
        default:
            return nil
        }
    }
}

enum AmenIntelligenceSurface: String, CaseIterable, Codable, Hashable {
    case glassShell
    case personalMemory
    case relationship
    case creatorSpace
    case lifeNavigation
    case collaborativeDocument
}

enum SourceVerificationStatus: String, CaseIterable, Codable, Hashable {
    case verified
    case partial
    case unsupported
    case conflicting
}

enum HumanPreviewActionKind: String, CaseIterable, Codable, Hashable {
    case sendMessage
    case postToSpace
    case scheduleReminder
    case shareDocument
    case mergeNotes
    case createContextEdge
    case startNavigation
    case dismiss
}

struct HumanPreviewAction: Identifiable, Hashable, Codable {
    let id: String
    var kind: HumanPreviewActionKind
    var title: String
    var diffPreview: String
    var targetNodeID: ContextGraphNodeID
    var requiresExplicitConfirmation: Bool
}

enum DetectedNeedKind: String, CaseIterable, Codable, Hashable {
    case unansweredQuestion
    case driftingMember
    case potentialMentor
    case newMemberConfusion
    case reminderCandidate
    case sourceVerificationNeeded
    case leaveNowTravelNudge
    case duplicateThought
}

struct DetectedNeed: Identifiable, Hashable, Codable {
    let id: String
    var kind: DetectedNeedKind
    var explanation: String
    var suggestedAction: HumanPreviewAction?
    var provenance: ProvenanceChain
}

struct MemoryNode: Identifiable, Hashable, Codable {
    let id: ContextGraphNodeID
    var claimText: String
    var tags: [String]
}

struct MemoryRecallResult: Identifiable, Hashable, Codable {
    let id: String
    var memory: MemoryNode
    var relevanceScore: Double
    var provenance: ProvenanceChain
}

enum ProvenanceSourceKind: String, CaseIterable, Codable, Hashable {
    case humanNote
    case conversationMessage
    case document
}

enum ProvenanceProcessor: String, CaseIterable, Codable, Hashable {
    case deterministicParser
}

enum ProvenanceTransformKind: String, CaseIterable, Codable, Hashable {
    case summary
    case contextLinking
    case sourceVerification
}

struct ScriptureReferenceNodePayload: Hashable, Codable {
    var translation: String
    var book: String
    var chapter: Int
    var startVerse: Int
    var endVerse: Int?
}

enum BereanCallableName: String, CaseIterable, Codable, Hashable {
    case summarizeContext
}

struct AmenIntelligenceGlassStyle: Hashable {
    var cornerRadius: CGFloat

    static let chromeBar = AmenIntelligenceGlassStyle(cornerRadius: 24)
    static let floatingBereanPanel = AmenIntelligenceGlassStyle(cornerRadius: 22)
    static let contextCapsule = AmenIntelligenceGlassStyle(cornerRadius: 18)
}

struct ProvenanceOriginalSource: Hashable, Codable {
    var sourceID: String
    var sourceKind: ProvenanceSourceKind
    var title: String
    var authorNodeID: ContextGraphNodeID?
    var sourceURL: URL?
    var sourceTimestamp: Date?
    var scriptureReference: ScriptureReferenceNodePayload?

    init(
        sourceID: String,
        sourceKind: ProvenanceSourceKind,
        title: String,
        authorNodeID: ContextGraphNodeID?,
        sourceURL: URL?,
        sourceTimestamp: Date?,
        scriptureReference: ScriptureReferenceNodePayload? = nil
    ) {
        self.sourceID = sourceID
        self.sourceKind = sourceKind
        self.title = title
        self.authorNodeID = authorNodeID
        self.sourceURL = sourceURL
        self.sourceTimestamp = sourceTimestamp
        self.scriptureReference = scriptureReference
    }
}

struct ProvenanceCaptureRecord: Hashable, Codable {
    var capturedByUserID: String
    var capturedAt: Date
    var deviceID: String?
    var appVersion: String?
    var trustBoundaryID: AmenTrustBoundaryID
}

struct ProvenanceProcessingRecord: Hashable, Codable {
    var processor: ProvenanceProcessor
    var callableProxyName: String?
    var modelName: String?
    var transform: ProvenanceTransformKind
    var processedAt: Date
    var humanReviewed: Bool
}

struct MemoryRankingSignal: Hashable, Codable {
    var name: String
    var weight: Double
    var value: String
}

struct ProvenanceRetrievalRecord: Hashable, Codable {
    var retrievedAt: Date
    var queryID: String
    var namespace: PineconeNamespace
    var rankingSignals: [MemoryRankingSignal]
    var confidence: Double
}

struct FourLayerProvenance: Hashable, Codable {
    var originalSource: ProvenanceOriginalSource?
    var captureRecord: ProvenanceCaptureRecord?
    var processingRecord: ProvenanceProcessingRecord?
    var retrievalRecord: ProvenanceRetrievalRecord?
}

struct ProvenanceChain: Hashable, Codable {
    var claimID: String
    var layers: FourLayerProvenance
    var generatedAt: Date

    var isComplete: Bool {
        layers.originalSource != nil && layers.captureRecord != nil && layers.processingRecord != nil && layers.retrievalRecord != nil
    }
}

extension View {
    func amenIntelligenceGlassChrome(_ style: AmenIntelligenceGlassStyle) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .stroke(AmenTheme.Colors.glassStroke, lineWidth: 0.8)
            }
    }

    func amenIntelligenceMatteContent(cornerRadius: CGFloat) -> some View {
        background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AmenTheme.Colors.borderSoft, lineWidth: 0.8)
            }
    }
}

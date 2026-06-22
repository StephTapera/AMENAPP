import Foundation
import CoreGraphics
import CoreVideo

// MARK: - Scene understanding (all on-device)
public enum VisionSceneType: String, Codable, Sendable {
    case scripture, studyTable, sermonScreen, document, book, travel, unknown
}

public struct DetectedObject: Codable, Sendable, Identifiable {
    public let id: UUID
    public let label: String          // e.g. "A320 safety card", "Bible", "backpack"
    public let confidence: Double     // 0...1
    public let boundingBox: CGRect    // normalized, device-local only

    public init(id: UUID, label: String, confidence: Double, boundingBox: CGRect) {
        self.id = id
        self.label = label
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

public struct SceneContext: Codable, Sendable {
    public let sceneType: VisionSceneType
    public let objects: [DetectedObject]
    public let recognizedText: [String]   // OCR output, on-device
    public let suggestedModes: [VisionMode]
    public let confidence: Double

    public init(sceneType: VisionSceneType,
                objects: [DetectedObject],
                recognizedText: [String],
                suggestedModes: [VisionMode],
                confidence: Double) {
        self.sceneType = sceneType
        self.objects = objects
        self.recognizedText = recognizedText
        self.suggestedModes = suggestedModes
        self.confidence = confidence
    }
}

public enum VisionMode: String, Codable, Sendable, CaseIterable {
    case reading, travelJournal, sermonPrep, offlineStudy
    case continueStudy, crossReferences, originalLanguage, discussionQuestions
}

// MARK: - Reasoning Lens
public enum ReasoningVerb: String, Codable, Sendable, CaseIterable {
    case explain, compare, challenge, teach, simplify, apply, memorize, connect
    case debate, predict                 // PREMIUM-only verbs
    public var isPremiumOnly: Bool { self == .debate || self == .predict }
}

public struct ReasoningRequest: Codable, Sendable {
    public let verb: ReasoningVerb
    public let sceneContext: SceneContext   // derived data ONLY — no image bytes
    public let userIdHash: String           // hashed, never raw uid
    public let mode: VisionMode?

    public init(verb: ReasoningVerb,
                sceneContext: SceneContext,
                userIdHash: String,
                mode: VisionMode?) {
        self.verb = verb
        self.sceneContext = sceneContext
        self.userIdHash = userIdHash
        self.mode = mode
    }
}

public struct ReasoningResult: Codable, Sendable {
    public let verb: ReasoningVerb
    public let paragraphs: [String]
    public let citations: [String]          // verse refs / sources
    public let memoryLinkIds: [String]

    public init(verb: ReasoningVerb,
                paragraphs: [String],
                citations: [String],
                memoryLinkIds: [String]) {
        self.verb = verb
        self.paragraphs = paragraphs
        self.citations = citations
        self.memoryLinkIds = memoryLinkIds
    }
}

// MARK: - MEDIA-GATE (fail-closed)
public enum MediaGateDecision: String, Codable, Sendable { case allow, block }

public protocol MediaGate: Sendable {
    /// Runs on-device. Returns .block on ANY error/ambiguity (fail-closed).
    func evaluate(frame: CVPixelBuffer) async -> MediaGateDecision
}

// MARK: - Services
public protocol VisionIntelligenceService: Sendable {
    /// On-device only. Builds SceneContext from a frame. No network, no persistence of raw image.
    func understand(frame: CVPixelBuffer) async throws -> SceneContext
}

public protocol ReasoningLensService: Sendable {
    /// Sends DERIVED data only to bereanVisionReason (us-east1).
    func reason(_ request: ReasoningRequest) async throws -> ReasoningResult
}

public protocol VisionMemoryLink: Sendable {
    /// Embeds derived text + upserts to Living Memory (Pinecone) via existing path.
    func link(_ context: SceneContext, result: ReasoningResult) async throws -> [String]
}

public protocol VisionEntitlement: Sendable {
    var hasBereanPlus: Bool { get async }   // StoreKit 2 backed
}

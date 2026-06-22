import Foundation

// MARK: - BereanContextProviding
// Retrieval over Living Memory + notes + commitments + Space history
// Every chunk carries provenance — tier filter is mandatory
@MainActor
protocol BereanContextProviding {
    func retrieveContext(query: String, tier: ContentTierFilter, limit: Int) async throws -> [ProvenanceTaggedChunk]
}

struct ContentTierFilter: OptionSet {
    let rawValue: Int
    static let shared    = ContentTierFilter(rawValue: 1 << 0)  // Tier S
    static let connected = ContentTierFilter(rawValue: 1 << 1)  // Tier C
    // Tier P (private/E2EE) NEVER appears here — enforce at impl layer
}

struct ProvenanceTaggedChunk: Codable {
    var content: String
    var source: String          // e.g. "notes", "commitments", "space_history"
    var tier: String            // "S" or "C" — never "P"
    var timestamp: Date
    var humanLabel: String?     // e.g. "your note from May 4"
}

// MARK: - TraditionAwareAnswering

@MainActor
protocol TraditionAwareAnswering {
    func classifyDoctrinalQuestion(_ question: String) async -> DoctrinalClassification
    func buildBalancedAnswer(for classification: DoctrinalClassification, baseAnswer: String) async -> BalancedAnswer
}

struct DoctrinalClassification {
    var isDoctrinal: Bool
    var confidence: Double
    var question: String
}

struct BalancedAnswer: Codable {
    var traditions: [TraditionView]
    var commonGround: String
    var sources: [String]
}

struct TraditionView: Codable {
    var key: TraditionKey
    var perspective: String
}

enum TraditionKey: String, Codable {
    case reformed, catholic, orthodox, wesleyan, pentecostal, anabaptist
}

// MARK: - RoomFirstSynthesizing
// In Spaces, human synthesis structurally precedes Berean's contribution

@MainActor
protocol RoomFirstSynthesizing {
    func synthesizeHumanMessages(_ messages: [String]) async -> RoomSynthesis
}

struct RoomSynthesis {
    var humanSummary: String        // rendered first
    var bereanContribution: String  // rendered second, visually distinct
}

// MARK: - AegisPatternDetecting (extensions for C59/C60)
// Extend existing Aegis registry — C59: Spiritual Abuse, C60: Youth Shield

@MainActor
protocol AegisPatternDetecting {
    // C59: detect manipulation, financial coercion, isolation tactics
    func detectSpiritualAbusePatterns(in content: String, tier: String) async -> AegisC59Signal?
    // C60: enforce youth DM policy
    func checkYouthInteractionPolicy(senderAge: Int?, recipientAge: Int?, dmContent: String) async -> YouthShieldDecision
}

struct AegisC59Signal {
    var patternKind: SpiritualAbuseKind
    var confidence: Double
    var recipientResources: [String]    // gentle surface to recipient only
    var internalSignal: String          // for Aegis registry — never auto-punitive
}

enum SpiritualAbuseKind: String, Codable {
    case manipulationFraming, financialCoercion, isolationTactics
}

struct YouthShieldDecision {
    var allowed: Bool
    var reason: String?
}

// MARK: - FeedTransparencyProviding
// Fail-closed: if no explanation exists, item is ineligible to render

@MainActor
protocol FeedTransparencyProviding {
    func explanation(for feedItemId: String) async -> FeedExplanation?
    // Returns nil means item MUST NOT render
}

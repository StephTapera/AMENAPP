import Foundation

enum SmartDetectedEntityType: String, Codable, CaseIterable, Identifiable {
    case scriptureReference
    case dateTime
    case event
    case location
    case prayerRequest
    case question
    case topic
    case actionItem
    case voiceTranscript
    case studyTheme
    case bereanAction
    case knowledgeNode

    var id: String { rawValue }
}

struct SmartTextRange: Codable, Hashable {
    let start: Int
    let length: Int
}

struct SmartDetectedEntity: Identifiable, Codable, Hashable {
    let id: String
    let type: SmartDetectedEntityType
    let sourceText: String
    let normalizedValue: String
    let confidence: Double
    let range: SmartTextRange
    let createdAt: Date
}

enum SmartMessageActionType: String, Codable, CaseIterable, Identifiable {
    case openScripture
    case askBerean
    case addToCalendar
    case addReminder
    case createPrayerRequest
    case prayNow
    case summarizeThread
    case startStudyMode
    case saveToJournal
    case createTopic
    case searchRelated
    case openKnowledgeGraph
    case transcribeVoice
    case createStudyGuide

    var id: String { rawValue }
}

enum SmartMessagePrivacyLevel: String, Codable, CaseIterable {
    case `private`
    case space
    case publicMetadata
}

struct SmartMessageAction: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let iconSystemName: String
    let actionType: SmartMessageActionType
    let payload: [String: String]
    let requiresConfirmation: Bool
    let privacyLevel: SmartMessagePrivacyLevel
}

struct SmartDiscussionInsight: Codable, Hashable {
    var summary: String
    var keyTakeaways: [String]
    var scriptures: [String]
    var prayerRequests: [String]
    var topics: [String]
    var actionItems: [String]
    var unresolvedQuestions: [String]
    var suggestedNextActions: [SmartMessageAction]
}

struct SmartStudySession: Identifiable, Codable, Hashable {
    let id: String
    let spaceId: String
    let threadId: String
    let title: String
    let scriptures: [String]
    let topics: [String]
    let notes: [String]
    let participants: [String]
    let createdBy: String
    let createdAt: Date
    let updatedAt: Date
}

struct SmartKnowledgeNode: Identifiable, Codable, Hashable {
    let id: String
    let ownerScope: String
    let nodeType: String
    let title: String
    let summary: String
    let scriptureRefs: [String]
    let topics: [String]
    let linkedMessageIds: [String]
    let linkedThreadIds: [String]
    let linkedSpaceIds: [String]
    let createdAt: Date
    let updatedAt: Date
}

struct SmartSearchResult: Identifiable, Codable, Hashable {
    let id: String
    let sourceType: String
    let title: String
    let snippet: String
    let score: Double
    let path: String
}

enum SmartSearchRankingMode: String, Codable, Hashable {
    case vector
    case keywordFallback
    case unknown

    var label: String {
        switch self {
        case .vector: return "Semantic vector ranking"
        case .keywordFallback: return "Keyword fallback"
        case .unknown: return "Search ranking"
        }
    }

    var explanation: String {
        switch self {
        case .vector: return "Results are ranked by configured vector similarity with permission checks applied."
        case .keywordFallback: return "Keyword fallback is active because vector ranking is not configured for this environment."
        case .unknown: return "Amen could not verify the ranking mode for this response."
        }
    }
}

struct SmartSearchResponse: Codable, Hashable {
    let rankingMode: SmartSearchRankingMode
    let results: [SmartSearchResult]
}

struct SmartMessageAnalysisResponse: Codable, Hashable {
    let detectedEntities: [SmartDetectedEntity]
    let suggestedActions: [SmartMessageAction]
}

enum SmartKnowledgeScope: String, Codable, CaseIterable, Identifiable {
    case user
    case space

    var id: String { rawValue }
}

enum SmartMessageSource: Hashable {
    case message(spaceId: String, threadId: String, messageId: String)
    case thread(spaceId: String, threadId: String)
    case space(spaceId: String)
    case local(sourceId: String)
}

enum SmartMessageIntelligenceError: LocalizedError {
    case featureDisabled(String)
    case invalidResponse
    case providerUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .featureDisabled(let feature): return "\(feature) is not enabled."
        case .invalidResponse: return "The smart message response was invalid."
        case .providerUnavailable(let message): return message
        }
    }
}

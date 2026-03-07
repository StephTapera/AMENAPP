//
//  HeyFeedModels.swift
//  AMENAPP
//
//  Hey Feed: User controls for OpenTable feed personalization
//  "Like 'Dear Algo' but for OpenTable" - users control what they see
//

import Foundation
import FirebaseFirestore

// MARK: - Feed Mode

enum FeedMode: String, Codable, CaseIterable {
    case balanced = "balanced"
    case friendsFirst = "friends_first"
    case localCommunity = "local_community"
    case ideasLearning = "ideas_learning"
    case quiet = "quiet"
    
    var displayName: String {
        switch self {
        case .balanced: return "Balanced"
        case .friendsFirst: return "Friends First"
        case .localCommunity: return "Local / Community"
        case .ideasLearning: return "Ideas & Learning"
        case .quiet: return "Quiet"
        }
    }
    
    var description: String {
        switch self {
        case .balanced:
            return "Mix of friends, discovery, and trending"
        case .friendsFirst:
            return "Prioritize people you follow"
        case .localCommunity:
            return "Focus on local and church community"
        case .ideasLearning:
            return "Educational and thought-provoking content"
        case .quiet:
            return "Slow feed, minimal notifications"
        }
    }
    
    var weights: FeedWeights {
        switch self {
        case .balanced:
            return FeedWeights(following: 0.30, local: 0.15, discovery: 0.30, learning: 0.15, recency: 0.10)
        case .friendsFirst:
            return FeedWeights(following: 0.60, local: 0.10, discovery: 0.10, learning: 0.10, recency: 0.10)
        case .localCommunity:
            return FeedWeights(following: 0.20, local: 0.50, discovery: 0.10, learning: 0.10, recency: 0.10)
        case .ideasLearning:
            return FeedWeights(following: 0.15, local: 0.10, discovery: 0.20, learning: 0.45, recency: 0.10)
        case .quiet:
            return FeedWeights(following: 0.40, local: 0.20, discovery: 0.05, learning: 0.25, recency: 0.10)
        }
    }
}

struct FeedWeights {
    let following: Double
    let local: Double
    let discovery: Double
    let learning: Double
    let recency: Double
}

// MARK: - Feed Topic

enum FeedTopic: String, Codable, CaseIterable {
    case faith = "faith"
    case business = "business"
    case tech = "tech"
    case politics = "politics"
    case relationships = "relationships"
    case mentalHealth = "mental_health"
    case culture = "culture"
    case local = "local"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .faith: return "Faith/Spirituality"
        case .business: return "Business"
        case .tech: return "Tech"
        case .politics: return "Politics"
        case .relationships: return "Relationships"
        case .mentalHealth: return "Mental Health"
        case .culture: return "Culture"
        case .local: return "Local"
        case .other: return "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .faith: return "book.closed"
        case .business: return "briefcase"
        case .tech: return "laptopcomputer"
        case .politics: return "building.columns"
        case .relationships: return "heart"
        case .mentalHealth: return "brain.head.profile"
        case .culture: return "theatermasks"
        case .local: return "location"
        case .other: return "ellipsis.circle"
        }
    }
}

// MARK: - Debate Level

enum DebateLevel: String, Codable, CaseIterable {
    case off = "off"
    case low = "low"
    case normal = "normal"
    
    var displayName: String {
        switch self {
        case .off: return "Off"
        case .low: return "Low"
        case .normal: return "Normal"
        }
    }
    
    var description: String {
        switch self {
        case .off: return "Downrank argumentative content"
        case .low: return "Some debate, but calm"
        case .normal: return "Normal debate tolerance"
        }
    }
    
    var controversyPenalty: Double {
        switch self {
        case .off: return 50.0  // Heavy penalty
        case .low: return 25.0  // Moderate penalty
        case .normal: return 5.0  // Light penalty
        }
    }
}

// MARK: - Sensitivity Filter

enum SensitivityFilter: String, Codable, CaseIterable {
    case strict = "strict"
    case balanced = "balanced"
    case off = "off"
    
    var displayName: String {
        switch self {
        case .strict: return "Strict"
        case .balanced: return "Balanced"
        case .off: return "Off"
        }
    }
    
    var description: String {
        switch self {
        case .strict: return "Filter harassment, hate, graphic content"
        case .balanced: return "Basic safety filters"
        case .off: return "Minimal filtering (reports only)"
        }
    }
    
    var riskThreshold: Double {
        switch self {
        case .strict: return 0.3  // Show only low-risk content
        case .balanced: return 0.6  // Moderate risk tolerance
        case .off: return 0.9  // Only block highest risk
        }
    }
}

// MARK: - Refresh Pacing

enum RefreshPacing: String, Codable, CaseIterable {
    case normal = "normal"
    case slow = "slow"
    
    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .slow: return "Slow"
        }
    }
    
    var description: String {
        switch self {
        case .normal: return "Refresh freely"
        case .slow: return "Reduce compulsive refreshing"
        }
    }
    
    var minimumRefreshInterval: TimeInterval {
        switch self {
        case .normal: return 5.0  // 5 seconds
        case .slow: return 30.0  // 30 seconds
        }
    }
}

// MARK: - Hey Feed Preferences

struct HeyFeedPreferences: Codable {
    var mode: FeedMode
    var pinnedTopics: Set<FeedTopic>
    var blockedTopics: Set<FeedTopic>
    var debateLevel: DebateLevel
    var sensitivityFilter: SensitivityFilter
    var refreshPacing: RefreshPacing
    
    // Per-author actions
    var mutedAuthors: Set<String>
    var boostedAuthors: Set<String>  // "More like this" authors
    
    // Per-post actions
    var hiddenPosts: Set<String>
    var boostedPosts: Set<String>
    
    var lastUpdated: Date
    
    init() {
        self.mode = .balanced
        self.pinnedTopics = [.faith]  // Default: Faith pinned
        self.blockedTopics = []
        self.debateLevel = .normal
        self.sensitivityFilter = .balanced
        self.refreshPacing = .normal
        self.mutedAuthors = []
        self.boostedAuthors = []
        self.hiddenPosts = []
        self.boostedPosts = []
        self.lastUpdated = Date()
    }
    
    // Firestore conversion
    func toDictionary() -> [String: Any] {
        return [
            "mode": mode.rawValue,
            "pinnedTopics": Array(pinnedTopics).map { $0.rawValue },
            "blockedTopics": Array(blockedTopics).map { $0.rawValue },
            "debateLevel": debateLevel.rawValue,
            "sensitivityFilter": sensitivityFilter.rawValue,
            "refreshPacing": refreshPacing.rawValue,
            "mutedAuthors": Array(mutedAuthors),
            "boostedAuthors": Array(boostedAuthors),
            "hiddenPosts": Array(hiddenPosts),
            "boostedPosts": Array(boostedPosts),
            "lastUpdated": Timestamp(date: lastUpdated)
        ]
    }
    
    static func fromDictionary(_ dict: [String: Any]) -> HeyFeedPreferences? {
        var prefs = HeyFeedPreferences()
        
        if let modeStr = dict["mode"] as? String,
           let mode = FeedMode(rawValue: modeStr) {
            prefs.mode = mode
        }
        
        if let pinnedArray = dict["pinnedTopics"] as? [String] {
            prefs.pinnedTopics = Set(pinnedArray.compactMap { FeedTopic(rawValue: $0) })
        }
        
        if let blockedArray = dict["blockedTopics"] as? [String] {
            prefs.blockedTopics = Set(blockedArray.compactMap { FeedTopic(rawValue: $0) })
        }
        
        if let debateStr = dict["debateLevel"] as? String,
           let debate = DebateLevel(rawValue: debateStr) {
            prefs.debateLevel = debate
        }
        
        if let sensitivityStr = dict["sensitivityFilter"] as? String,
           let sensitivity = SensitivityFilter(rawValue: sensitivityStr) {
            prefs.sensitivityFilter = sensitivity
        }
        
        if let pacingStr = dict["refreshPacing"] as? String,
           let pacing = RefreshPacing(rawValue: pacingStr) {
            prefs.refreshPacing = pacing
        }
        
        if let mutedArray = dict["mutedAuthors"] as? [String] {
            prefs.mutedAuthors = Set(mutedArray)
        }
        
        if let boostedArray = dict["boostedAuthors"] as? [String] {
            prefs.boostedAuthors = Set(boostedArray)
        }
        
        if let hiddenArray = dict["hiddenPosts"] as? [String] {
            prefs.hiddenPosts = Set(hiddenArray)
        }
        
        if let boostedPostsArray = dict["boostedPosts"] as? [String] {
            prefs.boostedPosts = Set(boostedPostsArray)
        }
        
        if let timestamp = dict["lastUpdated"] as? Timestamp {
            prefs.lastUpdated = timestamp.dateValue()
        }
        
        return prefs
    }
}

// MARK: - Why Am I Seeing This

struct FeedReason: Identifiable {
    let id = UUID()
    let type: ReasonType
    let description: String
    
    enum ReasonType {
        case followedAuthor
        case topicMatch
        case engagement
        case local
        case recency
        case discovery
        case boosted
    }
    
    var icon: String {
        switch type {
        case .followedAuthor: return "person.circle"
        case .topicMatch: return "tag"
        case .engagement: return "hand.thumbsup"
        case .local: return "location"
        case .recency: return "clock"
        case .discovery: return "sparkles"
        case .boosted: return "arrow.up.circle"
        }
    }
}

// MARK: - Post Safety Metadata

struct PostSafetyMetadata: Codable {
    var riskScore: Double  // 0.0-1.0
    var riskReasons: [SafetyRiskReason]
    var isLimitedVisibility: Bool
    var moderationNotes: String?
    
    enum SafetyRiskReason: String, Codable {
        case pii = "pii"
        case toxicity = "toxicity"
        case harassment = "harassment"
        case hate = "hate"
        case selfHarm = "self_harm"
        case sexual = "sexual"
        case violence = "violence"
        case spam = "spam"
        case scam = "scam"
        case misinformation = "misinformation"
    }
    
    init() {
        self.riskScore = 0.0
        self.riskReasons = []
        self.isLimitedVisibility = false
        self.moderationNotes = nil
    }
}

// MARK: - User Feed Signals

struct UserFeedSignal: Codable {
    let userId: String
    let postId: String
    let signalType: SignalType
    let timestamp: Date
    
    enum SignalType: String, Codable {
        case moreLikeThis = "more_like_this"
        case lessLikeThis = "less_like_this"
        case hideTopic = "hide_topic"
        case muteAuthor = "mute_author"
        case boost = "boost"
        case report = "report"
    }
}

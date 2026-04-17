//
//  VerseDrawerModels.swift
//  AMENAPP
//
//  Liquid Glass Scripture Drawer - Core Models
//  Two-stage verse attachment system with smart search
//

import Foundation

// MARK: - Drawer State

enum VerseDrawerState {
    case hidden
    case mini
    case expanded
}

// MARK: - Search Context Models

/// Represents different search modes for intelligent verse discovery
enum VerseSearchMode: String, CaseIterable, Identifiable {
    case all = "All"
    case topics = "Topics"
    case people = "People"
    case seasonal = "Seasonal"
    case recent = "Recent"
    case saved = "Saved"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .all: return "sparkles"
        case .topics: return "tag.fill"
        case .people: return "person.2.fill"
        case .seasonal: return "calendar"
        case .recent: return "clock.fill"
        case .saved: return "bookmark.fill"
        }
    }
}

/// Topic tags for semantic verse search
enum VerseTopic: String, CaseIterable {
    case hope = "Hope"
    case peace = "Peace"
    case strength = "Strength"
    case love = "Love"
    case fear = "Fear"
    case faith = "Faith"
    case wisdom = "Wisdom"
    case joy = "Joy"
    case forgiveness = "Forgiveness"
    case salvation = "Salvation"
    case prayer = "Prayer"
    case grief = "Grief"
    case healing = "Healing"
    case encouragement = "Encouragement"
    case identity = "Identity"
    case waiting = "Waiting"
    case worship = "Worship"
    case resurrection = "Resurrection"
    
    var keywords: [String] {
        switch self {
        case .hope: return ["hope", "future", "plans", "prosper", "expectation"]
        case .peace: return ["peace", "calm", "rest", "tranquil", "still"]
        case .strength: return ["strength", "power", "courage", "strong", "mighty"]
        case .love: return ["love", "beloved", "charity", "affection"]
        case .fear: return ["fear", "afraid", "terror", "anxious", "worry"]
        case .faith: return ["faith", "believe", "trust", "confidence"]
        case .wisdom: return ["wisdom", "understanding", "knowledge", "discernment"]
        case .joy: return ["joy", "rejoice", "gladness", "delight", "happy"]
        case .forgiveness: return ["forgive", "pardon", "mercy", "grace"]
        case .salvation: return ["salvation", "saved", "redeemed", "deliverance"]
        case .prayer: return ["prayer", "pray", "intercession", "petition"]
        case .grief: return ["grief", "mourn", "sorrow", "lament", "loss"]
        case .healing: return ["heal", "restore", "recovery", "wholeness"]
        case .encouragement: return ["encourage", "comfort", "strengthen", "support"]
        case .identity: return ["identity", "chosen", "beloved", "child of God"]
        case .waiting: return ["wait", "patience", "endure", "persevere"]
        case .worship: return ["worship", "praise", "adoration", "glory"]
        case .resurrection: return ["resurrection", "risen", "eternal life", "victory"]
        }
    }
}

/// Biblical people for person-based search
enum BiblicalPerson: String, CaseIterable {
    case jesus = "Jesus"
    case paul = "Paul"
    case david = "David"
    case moses = "Moses"
    case peter = "Peter"
    case mary = "Mary"
    case john = "John"
    case abraham = "Abraham"
    case solomon = "Solomon"
    case daniel = "Daniel"
    case joseph = "Joseph"
    case esther = "Esther"
    case ruth = "Ruth"
    case elijah = "Elijah"
    
    var searchTerms: [String] {
        switch self {
        case .jesus: return ["Jesus", "Christ", "Lord", "Savior", "Messiah"]
        case .paul: return ["Paul", "Saul"]
        case .david: return ["David"]
        case .moses: return ["Moses"]
        case .peter: return ["Peter", "Simon Peter"]
        case .mary: return ["Mary"]
        case .john: return ["John"]
        case .abraham: return ["Abraham", "Abram"]
        case .solomon: return ["Solomon"]
        case .daniel: return ["Daniel"]
        case .joseph: return ["Joseph"]
        case .esther: return ["Esther"]
        case .ruth: return ["Ruth"]
        case .elijah: return ["Elijah"]
        }
    }
}

/// Seasonal/date-based verse mappings
enum SeasonalContext: String, CaseIterable {
    case christmas = "Christmas"
    case easter = "Easter"
    case goodFriday = "Good Friday"
    case palmSunday = "Palm Sunday"
    case advent = "Advent"
    case pentecost = "Pentecost"
    case newYear = "New Year"
    case thanksgiving = "Thanksgiving"
    
    var keywords: [String] {
        switch self {
        case .christmas: return ["birth", "nativity", "born", "manger", "bethlehem"]
        case .easter: return ["resurrection", "risen", "tomb", "crucifixion", "life"]
        case .goodFriday: return ["cross", "crucified", "death", "sacrifice"]
        case .palmSunday: return ["jerusalem", "hosanna", "triumphant entry"]
        case .advent: return ["coming", "prepare", "messiah", "waiting"]
        case .pentecost: return ["holy spirit", "pentecost", "fire", "tongues"]
        case .newYear: return ["new", "beginning", "fresh start", "renewal"]
        case .thanksgiving: return ["thanks", "grateful", "praise", "blessing"]
        }
    }
}

// MARK: - Smart Search Result

/// Enhanced verse result with relevance scoring and metadata
struct SmartVerseResult: Identifiable, Equatable {
    let id = UUID()
    let verse: BibleVerse
    let relevanceScore: Int
    let matchType: MatchType
    let topics: [VerseTopic]
    
    enum MatchType {
        case exactReference
        case bookChapter
        case phraseMatch
        case topicMatch
        case personMatch
        case seasonalMatch
        case popular
    }
    
    static func == (lhs: SmartVerseResult, rhs: SmartVerseResult) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Quick Suggestions

struct VerseSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let query: String
    let icon: String
    
    static let popular = [
        VerseSuggestion(title: "John 3:16", query: "John 3:16", icon: "heart.fill"),
        VerseSuggestion(title: "Philippians 4:13", query: "Philippians 4:13", icon: "bolt.fill"),
        VerseSuggestion(title: "Jeremiah 29:11", query: "Jeremiah 29:11", icon: "star.fill"),
        VerseSuggestion(title: "Psalm 23", query: "Psalm 23", icon: "leaf.fill"),
        VerseSuggestion(title: "Proverbs 3:5-6", query: "Proverbs 3:5-6", icon: "lightbulb.fill"),
        VerseSuggestion(title: "Romans 8:28", query: "Romans 8:28", icon: "shield.fill")
    ]
    
    static let topical = [
        VerseSuggestion(title: "Peace", query: "peace", icon: "heart.circle.fill"),
        VerseSuggestion(title: "Strength", query: "strength", icon: "figure.strengthtraining.traditional"),
        VerseSuggestion(title: "Hope", query: "hope", icon: "sunrise.fill"),
        VerseSuggestion(title: "Love", query: "love", icon: "heart.fill"),
        VerseSuggestion(title: "Fear not", query: "fear not", icon: "shield.lefthalf.filled"),
        VerseSuggestion(title: "Wisdom", query: "wisdom", icon: "brain.head.profile")
    ]
}

import SwiftUI
import Foundation

// MARK: - Wellness Mood

enum WellnessMood: String, CaseIterable, Identifiable {
    case anxious  = "Anxious"
    case tired    = "Tired"
    case heavy    = "Heavy"
    case numb     = "Numb"
    case grateful = "Grateful"
    case joyful   = "Joyful"
    case other    = "Other"

    var id: String { rawValue }
    var config: WellnessMoodConfig { WellnessMoodRegistry.config(for: self) }
}

// MARK: - Care Choice

enum WellnessCareChoice: String, CaseIterable {
    case talk         = "Talk"
    case sitInSilence = "Sit in silence"
    case showPsalm    = "Show Psalm"
    case findSupport  = "Find support"
}

// MARK: - Mood Config

struct WellnessMoodConfig {
    let verse: String
    let quote: String
    let careOpeningLine: String
    let toolNames: [String]
}

// MARK: - Mood Registry

enum WellnessMoodRegistry {
    static func config(for mood: WellnessMood) -> WellnessMoodConfig {
        switch mood {
        case .anxious:
            return .init(
                verse: "Philippians 4:6",
                quote: "Do not be anxious about anything, but in every situation, by prayer and petition, present your requests to God.",
                careOpeningLine: "You said you're feeling anxious. Want to settle your breathing first, or talk for a moment?",
                toolNames: ["Breathing", "Prayer", "Journaling", "Counseling"]
            )
        case .tired:
            return .init(
                verse: "Matthew 11:28",
                quote: "Come to me, all who are weary and burdened, and I will give you rest.",
                careOpeningLine: "You seem tired. We can keep this light — rest support, or just a quiet space?",
                toolNames: ["Sleep", "Movement", "Prayer", "Breathing"]
            )
        case .heavy:
            return .init(
                verse: "Psalm 34:18",
                quote: "The Lord is near to the brokenhearted and saves the crushed in spirit.",
                careOpeningLine: "You said you're feeling heavy. Want to talk, or would you rather sit quietly with a Psalm?",
                toolNames: ["Prayer", "Journaling", "Breathing", "Counseling"]
            )
        case .numb:
            return .init(
                verse: "Psalm 13:1",
                quote: "How long, Lord? Will you forget me forever? How long will you hide your face from me?",
                careOpeningLine: "Feeling numb can make everything feel distant. Want one small step, or should I stay with you quietly?",
                toolNames: ["Movement", "Journaling", "Breathing", "Groups"]
            )
        case .grateful:
            return .init(
                verse: "Psalm 100:4",
                quote: "Enter his gates with thanksgiving and his courts with praise; give thanks to him and praise his name.",
                careOpeningLine: "You seem grateful today. Want to capture what God has been doing, or sit with it for a moment?",
                toolNames: ["Journaling", "Prayer", "Faith", "Groups"]
            )
        case .joyful:
            return .init(
                verse: "Psalm 118:24",
                quote: "This is the day the Lord has made; let us rejoice and be glad in it.",
                careOpeningLine: "You seem joyful today. Would you like to capture that, share it, or turn it into a short prayer?",
                toolNames: ["Prayer", "Journaling", "Faith", "Groups"]
            )
        case .other:
            return .init(
                verse: "Psalm 139:1",
                quote: "Lord, you have searched me and known me. You know when I sit down and when I rise up.",
                careOpeningLine: "That makes sense. We don't have to label everything. Want a gentle next step, or a quiet space?",
                toolNames: ["Prayer", "Journaling", "Breathing", "Counseling"]
            )
        }
    }
}

// MARK: - Rhythm Context

enum WellnessRhythmContext: String, CaseIterable {
    case morning   = "Morning"
    case afternoon = "Afternoon"
    case night     = "Night"
    case sunday    = "Sunday"
    case lent      = "Lent"

    static var current: WellnessRhythmContext {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        let weekday = calendar.component(.weekday, from: Date())
        if weekday == 1 { return .sunday }
        if hour >= 5 && hour < 12 { return .morning }
        if hour >= 12 && hour < 17 { return .afternoon }
        return .night
    }

    var toolNames: [String] {
        switch self {
        case .morning:   return ["Prayer", "Movement", "Journaling", "Faith"]
        case .afternoon: return ["Movement", "Prayer", "Counseling", "Groups"]
        case .night:     return ["Sleep", "Journaling", "Prayer", "Breathing"]
        case .sunday:    return ["Faith", "Prayer", "Journaling", "Groups"]
        case .lent:      return ["Faith", "Prayer", "Journaling", "Breathing"]
        }
    }

    var contextNote: String {
        switch self {
        case .morning:
            return "Morning — Prayer, movement, and reflection move up. Gentle activation, not pressure."
        case .afternoon:
            return "Afternoon — Movement, counseling, and groups are most practical right now."
        case .night:
            return "After 9 PM — Sleep, journaling, prayer, and breathing move to the top. Fewer choices."
        case .sunday:
            return "Sunday — Sabbath-aware surface. Rest and contemplation over productivity."
        case .lent:
            return "Lent — Lament, confession, and slower contemplative resources come forward."
        }
    }
}

// MARK: - Smart Tool

struct WellnessSmartTool: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let accent: Color
    let memoryLine: String
    let suggestion: String
}

// MARK: - Tool Registry

enum WellnessToolRegistry {
    static let all: [WellnessSmartTool] = [
        .init(
            name: "Breathing",
            icon: "wind",
            accent: Color(red: 0.12, green: 0.52, blue: 0.50),
            memoryLine: "Box-breath · 4 min · Last used recently",
            suggestion: "Start here when your mind is racing."
        ),
        .init(
            name: "Sleep",
            icon: "moon.stars.fill",
            accent: Color(red: 0.28, green: 0.38, blue: 0.62),
            memoryLine: "Wind-down near your usual sleep window",
            suggestion: "Good for nights when you need help settling."
        ),
        .init(
            name: "Prayer",
            icon: "hands.sparkles.fill",
            accent: Color(red: 0.48, green: 0.22, blue: 0.72),
            memoryLine: "Compline ready · Lauds available at dawn",
            suggestion: "Use when you want words, not noise."
        ),
        .init(
            name: "Movement",
            icon: "figure.walk",
            accent: Color(red: 0.22, green: 0.52, blue: 0.38),
            memoryLine: "8-minute gentle session helped recently",
            suggestion: "Best when you feel flat or stuck."
        ),
        .init(
            name: "Journaling",
            icon: "book.fill",
            accent: Color(red: 0.72, green: 0.46, blue: 0.22),
            memoryLine: "Recent entries ready to continue",
            suggestion: "Pick up where you left off."
        ),
        .init(
            name: "Faith",
            icon: "cross.fill",
            accent: Color(red: 0.52, green: 0.28, blue: 0.62),
            memoryLine: "Examen · Lectio · Centering Prayer",
            suggestion: "Contemplative, not performative."
        ),
        .init(
            name: "Counseling",
            icon: "person.fill.checkmark",
            accent: Color(red: 0.22, green: 0.42, blue: 0.72),
            memoryLine: "Filter by specialty, tradition, insurance",
            suggestion: "Therapy, pastoral care, and warmline are separate."
        ),
        .init(
            name: "Groups",
            icon: "person.3.fill",
            accent: Color(red: 0.12, green: 0.52, blue: 0.38),
            memoryLine: "Matched from intake, not a flat directory",
            suggestion: "Peer support without feed mechanics."
        ),
    ]

    static func ranked(mood: WellnessMood, rhythm: WellnessRhythmContext) -> [WellnessSmartTool] {
        let moodNames = mood.config.toolNames
        let rhythmNames = rhythm.toolNames
        var merged: [String] = []
        for name in rhythmNames + moodNames where !merged.contains(name) {
            merged.append(name)
        }
        var result: [WellnessSmartTool] = []
        for name in merged {
            if let tool = all.first(where: { $0.name == name }) {
                result.append(tool)
            }
        }
        for tool in all where !result.contains(where: { $0.name == tool.name }) {
            result.append(tool)
        }
        return Array(result.prefix(6))
    }
}

// MARK: - Groups Intake

enum GroupsIntakeNeed: String, CaseIterable {
    case grief      = "Grief"
    case addiction  = "Addiction"
    case anxiety    = "Anxiety"
    case divorce    = "Divorce"
    case depression = "Depression"
    case other      = "Other"
}

enum GroupsIntakeFormat: String, CaseIterable {
    case inPerson = "In person"
    case online   = "Online"
    case hybrid   = "Hybrid"
    case async    = "Async"
}

enum GroupsIntakePacing: String, CaseIterable {
    case lowPressure    = "Low pressure"
    case structured     = "Structured"
    case accountability = "Accountability"
}

struct GroupsIntakeResult {
    let groupName: String
    let description: String
    let url: String

    static func match(need: GroupsIntakeNeed, format: GroupsIntakeFormat, pacing: GroupsIntakePacing) -> GroupsIntakeResult {
        switch need {
        case .grief:
            if format == .inPerson {
                return .init(groupName: "GriefShare", description: "In-person grief support circles · Christian perspective · workbook included", url: "https://www.griefshare.org")
            }
            return .init(groupName: "GriefShare", description: "Grief support groups near you or online · Christian perspective", url: "https://www.griefshare.org")
        case .addiction:
            return .init(groupName: "Celebrate Recovery", description: "Christ-centered 12-step recovery · hurts, habits, hang-ups · gentle accountability", url: "https://www.celebraterecovery.com")
        case .anxiety:
            if pacing == .lowPressure {
                return .init(groupName: "NAMI Connection", description: "Peer-led anxiety support · low-pressure pace · confidential and welcoming", url: "https://www.nami.org/Support-Education/Support-Groups/NAMI-Connection-Recovery-Support-Group")
            }
            return .init(groupName: "NAMI Connection", description: "Free peer-led mental health support groups · evidence-based", url: "https://www.nami.org/Support-Education/Support-Groups/NAMI-Connection-Recovery-Support-Group")
        case .divorce:
            return .init(groupName: "DivorceCare", description: "Faith-centered healing for separation and divorce · weekly in-person circles", url: "https://www.divorcecare.org")
        case .depression:
            return .init(groupName: "NAMI Connection", description: "Free peer-led support for depression · safe pace · confidential", url: "https://www.nami.org/Support-Education/Support-Groups/NAMI-Connection-Recovery-Support-Group")
        case .other:
            return .init(groupName: "Celebrate Recovery", description: "Open to all hurts, habits, and hang-ups · no pressure · Christ-centered", url: "https://www.celebraterecovery.com")
        }
    }
}

// MARK: - Local Insight Engine

@MainActor
final class WellnessLocalInsightEngine: ObservableObject {
    static let shared = WellnessLocalInsightEngine()

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "wellnessLocalInsightEnabled") }
    }

    // Computed on-device only — never uploaded
    private let insights = [
        "You've returned to breathing a few times this week. It seems to help when things feel heavy.",
        "Journaling in the evenings appears to help you settle. That pattern is yours to keep.",
        "Gentle movement has followed some of your heavier days. A small step is still a step.",
    ]

    var currentInsight: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return insights[(hour / 8) % insights.count]
    }

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "wellnessLocalInsightEnabled") as? Bool ?? true
    }
}

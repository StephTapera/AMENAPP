import Foundation
import FirebaseFirestore

enum WellnessStreakType: String, Codable, CaseIterable {
    case groundingExercises, journaling, counseling, meditation, prayers
    var displayName: String {
        switch self {
        case .groundingExercises: return "Daily Grounding"
        case .journaling: return "Journaling"
        case .counseling: return "Counseling"
        case .meditation: return "Meditation"
        case .prayers: return "Daily Prayer"
        }
    }
    var icon: String {
        switch self {
        case .groundingExercises: return "figure.mind.and.body"
        case .journaling: return "pencil.and.outline"
        case .counseling: return "person.2.fill"
        case .meditation: return "waveform"
        case .prayers: return "hands.sparkles.fill"
        }
    }
}

enum WellnessCheckInMood: String, Codable, CaseIterable {
    case great, good, okay, bad, terrible
    var emoji: String {
        switch self { case .great: return "😊"; case .good: return "🙂"; case .okay: return "😐"; case .bad: return "😔"; case .terrible: return "😢" }
    }
    var displayName: String { rawValue.capitalized }
}

struct WellnessStreak: Identifiable, Codable {
    @DocumentID var id: String?
    var type: WellnessStreakType
    var title: String
    var currentStreak: Int
    var longestStreak: Int
    var totalDays: Int
    var lastEngagedAt: Timestamp?
    var shared: Bool
    var isPublic: Bool
    var badges: [String]
    var startedAt: Timestamp?
}

struct WellnessJournalEntry: Identifiable, Codable {
    @DocumentID var id: String?
    var date: Timestamp?
    var entry: String
    var mood: WellnessCheckInMood?
    var linkedVerse: LinkedVerse?
    var reflection: String?
    var shared: Bool

    struct LinkedVerse: Codable {
        var book: String
        var chapter: Int
        var verse: Int
        var text: String
    }
}

struct StreakBadge: Identifiable {
    let id: String
    let daysRequired: Int
    var displayName: String { "\(daysRequired)-Day Streak" }
    var icon: String {
        switch daysRequired {
        case 7: return "flame.fill"
        case 30: return "star.fill"
        case 100: return "crown.fill"
        default: return "medal.fill"
        }
    }
    static let all: [StreakBadge] = [
        StreakBadge(id: "7dayStreak", daysRequired: 7),
        StreakBadge(id: "14dayStreak", daysRequired: 14),
        StreakBadge(id: "30dayStreak", daysRequired: 30),
        StreakBadge(id: "50dayStreak", daysRequired: 50),
        StreakBadge(id: "100dayStreak", daysRequired: 100)
    ]
    var nextBadge: StreakBadge? { StreakBadge.all.first }
}

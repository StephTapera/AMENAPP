import Foundation
import FirebaseFirestore

enum WellnessContentType: String, Codable, CaseIterable {
    case groundingExercise, article, prayer, tool, meditation, journalPrompt, video
    var displayName: String {
        switch self {
        case .groundingExercise: return "Grounding"
        case .article: return "Article"
        case .prayer: return "Prayer"
        case .tool: return "Tool"
        case .meditation: return "Meditation"
        case .journalPrompt: return "Journal"
        case .video: return "Video"
        }
    }
    var icon: String {
        switch self {
        case .groundingExercise: return "figure.mind.and.body"
        case .article: return "doc.text.fill"
        case .prayer: return "hands.sparkles.fill"
        case .tool: return "wrench.and.screwdriver.fill"
        case .meditation: return "waveform"
        case .journalPrompt: return "pencil.and.outline"
        case .video: return "play.rectangle.fill"
        }
    }
}

enum WellnessDifficulty: String, Codable, CaseIterable {
    case beginner, intermediate, advanced
    var displayName: String { rawValue.capitalized }
    var color: String {
        switch self { case .beginner: return "green"; case .intermediate: return "yellow"; case .advanced: return "red" }
    }
}

enum WellnessCategory: String, Codable, CaseIterable {
    case anxiety, stress, grief, depression, addiction, sleep, identity, relationship
    var displayName: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .anxiety: return "brain.head.profile"
        case .stress: return "bolt.heart.fill"
        case .grief: return "heart.slash.fill"
        case .depression: return "cloud.drizzle.fill"
        case .addiction: return "link.badge.plus"
        case .sleep: return "moon.zzz.fill"
        case .identity: return "person.fill.questionmark"
        case .relationship: return "person.2.fill"
        }
    }
}

struct WellnessContent: Identifiable, Codable {
    @DocumentID var id: String?
    var type: WellnessContentType
    var title: String
    var description: String
    var difficulty: WellnessDifficulty
    var category: [WellnessCategory]
    var tags: [String]
    var durationSeconds: Int?
    var steps: [String]?
    var body: String?
    var audioUrl: String?
    var videoUrl: String?
    var linkedVerses: [LinkedVerse]?
    var engagementViewCount: Int
    var engagementSavedCount: Int
    var engagementHelpfulCount: Int
    var createdAt: Timestamp?
    var guardianModerated: Bool

    struct LinkedVerse: Codable {
        var book: String
        var chapter: Int
        var verse: Int
        var text: String
    }
}

struct WellnessEngagement: Codable {
    var wellnessId: String
    var viewedAt: Date?
    var saved: Bool
    var markedHelpful: Bool
}

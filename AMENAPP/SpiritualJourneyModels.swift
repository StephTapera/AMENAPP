import Foundation

struct SpiritualJourneyStory: Identifiable, Codable {
    let id: String
    let userId: String
    let period: JourneyPeriod
    let generatedAt: Date
    let summary: SpiritualJourneySummary
    let slides: [SpiritualJourneySlide]
    let safeShareCard: SpiritualJourneyShareCard?
    let version: Int
}

enum JourneyPeriod: String, Codable, CaseIterable {
    case weekly
    case monthly
    case quarterly
    case yearly
}

struct SpiritualJourneySummary: Codable {
    let activeDays: Int
    let postsCount: Int
    let commentsCount: Int
    let prayersCount: Int
    let encouragementCount: Int
    let comebackMoments: Int
    let topThemes: [String]
    let emotionProfile: EmotionProfile
    let spiritualTone: SpiritualTone
}

struct EmotionProfile: Codable {
    let joy: Double
    let peace: Double
    let gratitude: Double
    let grief: Double
    let stress: Double
    let doubt: Double
    let perseverance: Double
}

enum SpiritualTone: String, Codable {
    case steady
    case healing
    case returning
    case growing
    case persevering
    case searching
    case burdenedButPresent
}

struct SpiritualJourneySlide: Identifiable, Codable {
    let id: String
    let type: SpiritualJourneySlideType
    let title: String
    let subtitle: String?
    let body: String?
    let accentText: String?
    let metrics: [JourneyMetric]
    let chips: [String]
    let mood: SlideMood
    let scripture: JourneyScripture?
    let shareSafe: Bool
    let animationStyle: SlideAnimationStyle
    let duration: Double
}

enum SpiritualJourneySlideType: String, Codable {
    case intro
    case consistency
    case emotionRhythm
    case topThemes
    case communityImpact
    case hardMoments
    case comeback
    case godMetYouHere
    case seasonSummary
    case blessing
    case outro
}

struct JourneyMetric: Codable {
    let label: String
    let value: String
    let rawValue: Double?
}

struct JourneyScripture: Codable {
    let reference: String
    let text: String
}

enum SlideMood: String, Codable {
    case warm
    case bright
    case reflective
    case deep
    case hopeful
    case calm
}

enum SlideAnimationStyle: String, Codable {
    case riseFade
    case countUp
    case staggerWords
    case radialPulse
    case timelineDraw
    case cinematicReveal
    case softBloom
}

struct SpiritualJourneyShareCard: Codable {
    let title: String
    let subtitle: String
    let highlights: [String]
    let blessing: String
}

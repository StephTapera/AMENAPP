// SeasonsInsightService.swift — Features/Intelligence/Decay
// Groups decayed signals into liturgical and calendar seasons to surface "where you are" insights.
//
// Invariants:
//  • Premium required (SystemCapability.seasonsInsights) + ConsentEdge.graphToBerean
//  • Flag: ctx_seasons_insights_enabled — default false
//  • Reads from ContextBus ring buffer (on-device). No new Firestore reads.
//  • Season boundaries use Gregorian calendar; liturgical mapping is approximate
//    (does not require church-denomination specifics to avoid exclusion)

import Foundation

// MARK: - Season

enum Season: String, Sendable, CaseIterable {
    case advent        = "Advent"
    case christmas     = "Christmas"
    case epiphany      = "Epiphany"
    case lent          = "Lent"
    case holyWeek      = "Holy Week"
    case easter        = "Easter"
    case ordinaryTime  = "Ordinary Time"
    case newYear       = "New Year"
    case summer        = "Summer"
    case autumn        = "Autumn"
}

// MARK: - SeasonInsight

struct SeasonInsight: Sendable {
    let season: Season
    /// The dominant signal type in this season, weighted by decay
    let dominantSignalType: SignalType?
    /// Human-readable reflection prompt
    let reflectionPrompt: String
    let computedAt: Date
}

// MARK: - SeasonsInsightService

final class SeasonsInsightService: ObservableObject, @unchecked Sendable {
    static let shared = SeasonsInsightService()

    @Published private(set) var insight: SeasonInsight? = nil

    private init() {}

    // MARK: - Public API

    /// Computes a seasonal insight from the provided signals.
    /// Call after ContextBus signals are refreshed or on app foreground.
    func refresh(signals: [ContextSignal]) async {
        guard ContextIntelligenceFlags.seasonsInsights else { return }

        let gate = await EntitlementGate.shared.canAccess(.seasonsInsights)
        guard gate.allowed else { return }

        let hasEdge = await MainActor.run { ConsentStore.shared.isEnabled(.graphToBerean) }
        guard hasEdge else { return }

        let currentSeason = Self.currentSeason(for: Date())
        let dominant = DecayEngine.dominantType(in: signals)
        let prompt = reflectionPrompt(for: currentSeason, dominantType: dominant)

        let i = SeasonInsight(
            season: currentSeason,
            dominantSignalType: dominant,
            reflectionPrompt: prompt,
            computedAt: Date()
        )
        await MainActor.run { self.insight = i }
    }

    // MARK: - Season detection

    static func currentSeason(for date: Date) -> Season {
        let cal = Calendar.current
        let month = cal.component(.month, from: date)
        let day   = cal.component(.day, from: date)

        // Approximate liturgical seasons (Western, non-denominational friendly)
        switch (month, day) {
        case (12, 1...24):  return .advent
        case (12, 25...31): return .christmas
        case (1, 1...5):    return .christmas
        case (1, 6...31):   return .epiphany
        case (2, _):        return .epiphany
        case (3, 1...14):   return .lent      // rough Lenten start (40d before Easter)
        case (3, 15...28):  return .lent
        case (3, 29...31):  return .holyWeek
        case (4, 1...7):    return .holyWeek
        case (4, 8...30):   return .easter
        case (5, _):        return .easter
        case (6, _), (7, _), (8, _): return .summer
        case (9, _), (10, _), (11, _): return .autumn
        default:            return .ordinaryTime
        }
    }

    // MARK: - Reflection prompts

    private func reflectionPrompt(for season: Season, dominantType: SignalType?) -> String {
        let seasonPart: String
        switch season {
        case .advent:       seasonPart = "As Advent begins, a time of hopeful waiting"
        case .christmas:    seasonPart = "In the Christmas season, a time of gratitude and wonder"
        case .epiphany:     seasonPart = "In Epiphany, a season of revealing and discovery"
        case .lent:         seasonPart = "In Lent, a season of reflection and renewal"
        case .holyWeek:     seasonPart = "During Holy Week, a time of solemn contemplation"
        case .easter:       seasonPart = "In the Easter season, a time of resurrection joy"
        case .ordinaryTime: seasonPart = "In Ordinary Time, a season of faithful daily living"
        case .newYear:      seasonPart = "At the new year, a time of fresh beginnings"
        case .summer:       seasonPart = "In this summer season, a time of growth and rest"
        case .autumn:       seasonPart = "In autumn, a season of harvest and gratitude"
        }

        guard let sig = dominantType else {
            return "\(seasonPart) — what is God inviting you into?"
        }

        let activityPart: String
        switch sig {
        case .prayerCreated, .prayerAnswered, .prayerReminderActed:
            activityPart = "your prayer life has been especially active"
        case .studyStarted, .studyCompleted:
            activityPart = "you've been leaning into study"
        case .verseReflected:
            activityPart = "Scripture has been speaking to you"
        case .noteSaved, .noteThemeDetected:
            activityPart = "you've been capturing a lot of thoughts"
        case .visitVerified, .churchViewed:
            activityPart = "community and gathering have been on your heart"
        case .giftCompleted, .givingCauseViewed:
            activityPart = "generosity has been a theme"
        default:
            activityPart = "you've been on a meaningful journey"
        }

        return "\(seasonPart) — \(activityPart). What is God saying to you through this?"
    }
}

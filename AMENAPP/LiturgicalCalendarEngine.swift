//
//  LiturgicalCalendarEngine.swift
//  AMENAPP
//
//  Liturgical Calendar Intelligence Engine
//
//  A calendar-aware system that tracks the Christian year as a living rhythm:
//    - Seasons (Advent, Christmas, Lent, Easter, Pentecost, Ordinary Time)
//    - Holidays/Observances (Christmas Day, Good Friday, Easter, etc.)
//    - Lead-up and follow-up windows for each observance
//    - Denomination-sensitive observance models
//    - Region/country-aware adjustments
//    - Church-specific custom calendar overrides
//
//  This is NOT hardcoded UI text — it is a calendar intelligence service.
//
//  Architecture:
//    LiturgicalCalendarEngine (singleton)
//    ├── LiturgicalSeason            (Advent, Lent, Easter, etc.)
//    ├── HolidayObservance           (individual holy day)
//    ├── ObservanceWindow            (lead-up / day-of / follow-up)
//    ├── DenominationProfile         (liturgical, evangelical, etc.)
//    ├── currentSeason()             (what season is it right now)
//    ├── currentObservances()        (what holidays are active/approaching)
//    ├── computeEaster()             (Western Easter calculation)
//    └── calendarForYear()           (full year calendar generation)
//
//  Privacy: No user data involved. Pure calendar computation.
//

import Foundation

// MARK: - Liturgical Season

enum LiturgicalSeasonType: String, Codable, CaseIterable {
    case advent           = "advent"
    case christmas        = "christmas"
    case epiphany         = "epiphany"
    case ordinaryTimeEarly = "ordinary_time_early"  // After Epiphany, before Lent
    case lent             = "lent"
    case holyWeek         = "holy_week"
    case easter           = "easter"               // Easter through Pentecost
    case pentecost        = "pentecost"
    case ordinaryTimeLate = "ordinary_time_late"    // After Pentecost, before Advent

    var displayName: String {
        switch self {
        case .advent:            return "Advent"
        case .christmas:         return "Christmas"
        case .epiphany:          return "Epiphany"
        case .ordinaryTimeEarly: return "Ordinary Time"
        case .lent:              return "Lent"
        case .holyWeek:          return "Holy Week"
        case .easter:            return "Easter Season"
        case .pentecost:         return "Pentecost"
        case .ordinaryTimeLate:  return "Ordinary Time"
        }
    }

    var shortDescription: String {
        switch self {
        case .advent:            return "A season of waiting, hope, and preparation"
        case .christmas:         return "Celebrating the incarnation of Christ"
        case .epiphany:          return "Revelation of Christ to the world"
        case .ordinaryTimeEarly: return "Growing in faith through daily discipleship"
        case .lent:              return "A season of repentance, prayer, and fasting"
        case .holyWeek:          return "Walking with Christ toward the cross"
        case .easter:            return "Celebrating the resurrection and new life"
        case .pentecost:         return "The Holy Spirit empowering the Church"
        case .ordinaryTimeLate:  return "Growing in faith through daily discipleship"
        }
    }

    /// Core theme tags for this season. Used by Berean, prompts, and matching.
    var themeTags: [String] {
        switch self {
        case .advent:            return ["hope", "waiting", "preparation", "anticipation", "prophecy"]
        case .christmas:         return ["incarnation", "joy", "gift", "Emmanuel", "worship"]
        case .epiphany:          return ["revelation", "light", "mission", "nations", "witness"]
        case .ordinaryTimeEarly: return ["discipleship", "growth", "teaching", "community"]
        case .lent:              return ["repentance", "surrender", "fasting", "prayer", "examination"]
        case .holyWeek:          return ["sacrifice", "suffering", "love", "atonement", "cross"]
        case .easter:            return ["resurrection", "renewal", "victory", "hope", "new life"]
        case .pentecost:         return ["Holy Spirit", "boldness", "power", "prayer", "mission"]
        case .ordinaryTimeLate:  return ["discipleship", "growth", "service", "community", "faithfulness"]
        }
    }

    /// Tone mode that Berean should adopt during this season.
    var toneMode: SeasonalToneMode {
        switch self {
        case .advent:            return .contemplative
        case .christmas:         return .celebratory
        case .epiphany:          return .exploratory
        case .ordinaryTimeEarly: return .balanced
        case .lent:              return .reflective
        case .holyWeek:          return .solemn
        case .easter:            return .joyful
        case .pentecost:         return .activating
        case .ordinaryTimeLate:  return .balanced
        }
    }

    /// Whether this is a high-priority season (affects UI behavior).
    var isHighPriority: Bool {
        switch self {
        case .advent, .lent, .holyWeek, .easter, .pentecost:
            return true
        default:
            return false
        }
    }
}

// MARK: - Seasonal Tone Mode

enum SeasonalToneMode: String, Codable {
    case contemplative  // Advent — quiet, anticipatory
    case celebratory    // Christmas — joyful, worshipful
    case exploratory    // Epiphany — curious, outward
    case balanced       // Ordinary Time — steady, growth-focused
    case reflective     // Lent — searching, surrendering
    case solemn         // Holy Week — still, reverent
    case joyful         // Easter — hopeful, alive
    case activating     // Pentecost — bold, prayer-driven

    var bereanToneHint: String {
        switch self {
        case .contemplative: return "Use a quieter, more anticipatory tone. Emphasize waiting and hope."
        case .celebratory:   return "Use a warm, joyful tone. Celebrate the goodness of God."
        case .exploratory:   return "Use a curious, outward-facing tone. Encourage discovery and witness."
        case .balanced:      return "Use a steady, growth-oriented tone. Focus on daily discipleship."
        case .reflective:    return "Use a searching, gentle tone. Encourage examination and surrender."
        case .solemn:        return "Use a still, reverent tone. Minimize noise. Honor the gravity of the moment."
        case .joyful:        return "Use a hopeful, alive tone. Celebrate resurrection and renewal."
        case .activating:    return "Use a bold, prayerful tone. Encourage Spirit-led action and community."
        }
    }
}

// MARK: - Denomination Profile

/// How different traditions observe the Christian calendar.
enum DenominationProfile: String, Codable, CaseIterable {
    case liturgical           = "liturgical"          // Catholic, Anglican, Lutheran, Orthodox
    case evangelical          = "evangelical"          // Baptist, non-denom evangelical
    case reformed             = "reformed"             // Presbyterian, Reformed
    case charismatic          = "charismatic"          // Pentecostal, charismatic
    case nonDenominational    = "non_denominational"   // Simplified observance
    case custom               = "custom"               // Church-specific

    var displayName: String {
        switch self {
        case .liturgical:        return "Liturgical"
        case .evangelical:       return "Evangelical"
        case .reformed:          return "Reformed"
        case .charismatic:       return "Charismatic"
        case .nonDenominational: return "Non-Denominational"
        case .custom:            return "Custom"
        }
    }

    /// Which holidays this tradition typically observes.
    var observedHolidays: Set<HolidayType> {
        switch self {
        case .liturgical:
            return Set(HolidayType.allCases)
        case .evangelical:
            return [.christmas, .goodFriday, .easter, .pentecost, .thanksgiving, .newYearConsecration]
        case .reformed:
            return [.advent, .christmas, .lent, .goodFriday, .easter, .pentecost, .thanksgiving]
        case .charismatic:
            return [.christmas, .goodFriday, .easter, .pentecost, .prayerWeek, .newYearConsecration]
        case .nonDenominational:
            return [.christmas, .goodFriday, .easter, .thanksgiving]
        case .custom:
            return Set(HolidayType.allCases) // All available, church selects
        }
    }
}

// MARK: - Holiday Type

enum HolidayType: String, Codable, CaseIterable {
    // Major observances
    case adventStart          = "advent_start"
    case christmas            = "christmas"
    case epiphany             = "epiphany"
    case ashWednesday         = "ash_wednesday"
    case lentStart            = "lent_start"
    case palmSunday           = "palm_sunday"
    case holyMonday           = "holy_monday"
    case holyTuesday          = "holy_tuesday"
    case holyWednesday        = "holy_wednesday"
    case maundyThursday       = "maundy_thursday"
    case goodFriday           = "good_friday"
    case holySaturday         = "holy_saturday"
    case easter               = "easter"
    case ascension            = "ascension"
    case pentecost            = "pentecost"

    // Additional observances
    case christmasEve         = "christmas_eve"
    case newYearConsecration  = "new_year_consecration"
    case prayerWeek           = "prayer_week"
    case thanksgiving         = "thanksgiving"
    case advent               = "advent"
    case lent                 = "lent"

    var displayName: String {
        switch self {
        case .adventStart:        return "First Sunday of Advent"
        case .christmas:          return "Christmas Day"
        case .christmasEve:       return "Christmas Eve"
        case .epiphany:           return "Epiphany"
        case .ashWednesday:       return "Ash Wednesday"
        case .lentStart:          return "Lent Begins"
        case .palmSunday:         return "Palm Sunday"
        case .holyMonday:         return "Holy Monday"
        case .holyTuesday:        return "Holy Tuesday"
        case .holyWednesday:      return "Holy Wednesday"
        case .maundyThursday:     return "Maundy Thursday"
        case .goodFriday:         return "Good Friday"
        case .holySaturday:       return "Holy Saturday"
        case .easter:             return "Easter Sunday"
        case .ascension:          return "Ascension Day"
        case .pentecost:          return "Pentecost Sunday"
        case .newYearConsecration: return "New Year Consecration"
        case .prayerWeek:         return "Week of Prayer"
        case .thanksgiving:       return "Thanksgiving"
        case .advent:             return "Advent"
        case .lent:               return "Lent"
        }
    }

    /// How many days before the holiday the lead-up window opens.
    var leadUpDays: Int {
        switch self {
        case .christmas, .easter:      return 14
        case .goodFriday:              return 7
        case .pentecost:               return 7
        case .ashWednesday:            return 3
        case .palmSunday:              return 3
        case .christmasEve:            return 7
        case .adventStart:             return 7
        case .thanksgiving:            return 7
        case .newYearConsecration:     return 5
        default:                       return 1
        }
    }

    /// How many days after the holiday the follow-up window stays open.
    var followUpDays: Int {
        switch self {
        case .christmas:  return 7
        case .easter:     return 14
        case .pentecost:  return 7
        case .goodFriday: return 2
        default:          return 1
        }
    }

    /// Priority weight for display ordering. Higher = more important.
    var priorityWeight: Int {
        switch self {
        case .easter:             return 10
        case .goodFriday:         return 9
        case .christmas:          return 9
        case .pentecost:          return 8
        case .palmSunday:         return 7
        case .ashWednesday:       return 7
        case .maundyThursday:     return 7
        case .holySaturday:       return 6
        case .christmasEve:       return 8
        case .adventStart:        return 6
        case .epiphany:           return 5
        case .ascension:          return 5
        case .newYearConsecration: return 5
        case .thanksgiving:       return 4
        case .prayerWeek:         return 4
        default:                  return 3
        }
    }
}

// MARK: - Holiday Observance

/// A concrete holiday instance with a computed date for a given year.
struct HolidayObservance: Identifiable, Codable {
    let id: String
    let type: HolidayType
    let date: Date
    let seasonType: LiturgicalSeasonType
    let leadUpStart: Date
    let followUpEnd: Date
    let scriptureReferences: [String]
    let summary: String
    let denominationTags: [DenominationProfile]

    var isActive: Bool {
        let now = Date()
        return now >= leadUpStart && now <= followUpEnd
    }

    var isDayOf: Bool {
        Calendar.current.isDateInToday(date)
    }

    var isLeadUp: Bool {
        let now = Date()
        return now >= leadUpStart && now < Calendar.current.startOfDay(for: date)
    }

    var isFollowUp: Bool {
        let now = Date()
        let dayAfter = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        return now >= dayAfter && now <= followUpEnd
    }

    /// Days until this observance. Negative = past.
    var daysUntil: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0
    }
}

// MARK: - Liturgical Season Instance

/// A concrete season with start/end dates for a given year.
struct LiturgicalSeason: Identifiable, Codable {
    let id: String
    let type: LiturgicalSeasonType
    let startDate: Date
    let endDate: Date
    let year: Int

    var isCurrent: Bool {
        let now = Date()
        return now >= startDate && now <= endDate
    }

    var daysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0)
    }
}

// MARK: - Observance Window

/// The current window state for a holiday.
enum ObservanceWindow: String, Codable {
    case none       = "none"
    case leadUp     = "lead_up"
    case dayOf      = "day_of"
    case followUp   = "follow_up"
}

// MARK: - Current Calendar State

/// Snapshot of the current liturgical state. Fed into all intelligence layers.
struct LiturgicalState: Codable {
    let currentSeason: LiturgicalSeasonType
    let seasonDisplayName: String
    let toneMode: SeasonalToneMode
    let themeTags: [String]
    let isHighPrioritySeason: Bool
    let activeObservances: [ActiveObservance]
    let upcomingObservances: [UpcomingObservance]
    let computedAt: Date

    struct ActiveObservance: Codable {
        let type: HolidayType
        let name: String
        let window: ObservanceWindow
        let date: Date
        let scriptureReferences: [String]
        let summary: String
        let priorityWeight: Int
    }

    struct UpcomingObservance: Codable {
        let type: HolidayType
        let name: String
        let date: Date
        let daysUntil: Int
        let priorityWeight: Int
    }

    /// Builds a system prompt block for Berean.
    func toBereanSystemPrompt() -> String {
        var lines: [String] = []
        lines.append("--- Liturgical Calendar Context ---")
        lines.append("Current season: \(seasonDisplayName)")
        lines.append("Season description: \(currentSeason.shortDescription)")
        lines.append("Tone: \(toneMode.bereanToneHint)")
        lines.append("")

        if !activeObservances.isEmpty {
            let active = activeObservances.sorted { $0.priorityWeight > $1.priorityWeight }
            for obs in active.prefix(2) {
                switch obs.window {
                case .dayOf:
                    lines.append("TODAY is \(obs.name). This is significant.")
                case .leadUp:
                    lines.append("\(obs.name) is approaching. Help the user prepare their heart.")
                case .followUp:
                    lines.append("\(obs.name) was recently observed. Help the user carry forward what they learned.")
                case .none:
                    break
                }
                if !obs.scriptureReferences.isEmpty {
                    lines.append("Key scriptures: \(obs.scriptureReferences.joined(separator: ", "))")
                }
            }
            lines.append("")
        }

        if !upcomingObservances.isEmpty {
            let next = upcomingObservances.first!
            if next.daysUntil <= 14 {
                lines.append("\(next.name) is in \(next.daysUntil) days.")
            }
        }

        lines.append("")
        lines.append("Weave seasonal awareness naturally. Do not force it into every response.")
        lines.append("If the conversation is about something unrelated, respond normally.")
        lines.append("When relevant, connect the user's situation to the current season.")
        lines.append("Always preserve the option to connect with a real church or community.")
        lines.append("--- End Calendar Context ---")

        return lines.joined(separator: "\n")
    }
}

// MARK: - Liturgical Calendar Engine

final class LiturgicalCalendarEngine {

    static let shared = LiturgicalCalendarEngine()

    /// Cached state for the current moment.
    private var cachedState: LiturgicalState?
    private var cacheDate: Date?
    private let cacheTTL: TimeInterval = 3600 // 1 hour

    /// Denomination profile (default: non-denominational).
    var denominationProfile: DenominationProfile = .nonDenominational

    private init() {}

    // MARK: - Current State

    /// Returns the current liturgical state. Cached for 1 hour.
    func currentState() -> LiturgicalState {
        if let cached = cachedState,
           let cacheTime = cacheDate,
           Date().timeIntervalSince(cacheTime) < cacheTTL {
            return cached
        }

        let state = computeCurrentState()
        cachedState = state
        cacheDate = Date()
        return state
    }

    /// Returns the current liturgical season.
    func currentSeason() -> LiturgicalSeasonType {
        currentState().currentSeason
    }

    /// Returns active observances (in lead-up, day-of, or follow-up).
    func activeObservances() -> [HolidayObservance] {
        let year = Calendar.current.component(.year, from: Date())
        return calendarForYear(year).filter(\.isActive)
    }

    /// Returns upcoming observances within the next N days.
    func upcomingObservances(within days: Int = 30) -> [HolidayObservance] {
        let year = Calendar.current.component(.year, from: Date())
        return calendarForYear(year)
            .filter { $0.daysUntil > 0 && $0.daysUntil <= days }
            .sorted { $0.daysUntil < $1.daysUntil }
    }

    /// Returns whether a specific holiday type is observed by the current profile.
    func isObserved(_ holiday: HolidayType) -> Bool {
        denominationProfile.observedHolidays.contains(holiday)
    }

    // MARK: - Compute Current State

    private func computeCurrentState() -> LiturgicalState {
        let now = Date()
        let year = Calendar.current.component(.year, from: now)
        let seasons = seasonsForYear(year)
        let holidays = calendarForYear(year)

        // Find current season
        let currentSeason = seasons.first(where: \.isCurrent)?.type ?? .ordinaryTimeLate

        // Find active observances
        let active: [LiturgicalState.ActiveObservance] = holidays
            .filter { $0.isActive && isObserved($0.type) }
            .map { obs in
                let window: ObservanceWindow
                if obs.isDayOf { window = .dayOf }
                else if obs.isLeadUp { window = .leadUp }
                else if obs.isFollowUp { window = .followUp }
                else { window = .none }

                return LiturgicalState.ActiveObservance(
                    type: obs.type,
                    name: obs.type.displayName,
                    window: window,
                    date: obs.date,
                    scriptureReferences: obs.scriptureReferences,
                    summary: obs.summary,
                    priorityWeight: obs.type.priorityWeight
                )
            }

        // Find upcoming observances (next 30 days)
        let upcoming: [LiturgicalState.UpcomingObservance] = holidays
            .filter { $0.daysUntil > 0 && $0.daysUntil <= 30 && isObserved($0.type) }
            .sorted { $0.daysUntil < $1.daysUntil }
            .prefix(5)
            .map { obs in
                LiturgicalState.UpcomingObservance(
                    type: obs.type,
                    name: obs.type.displayName,
                    date: obs.date,
                    daysUntil: obs.daysUntil,
                    priorityWeight: obs.type.priorityWeight
                )
            }

        return LiturgicalState(
            currentSeason: currentSeason,
            seasonDisplayName: currentSeason.displayName,
            toneMode: currentSeason.toneMode,
            themeTags: currentSeason.themeTags,
            isHighPrioritySeason: currentSeason.isHighPriority,
            activeObservances: active,
            upcomingObservances: Array(upcoming),
            computedAt: now
        )
    }

    // MARK: - Easter Computation (Computus)

    /// Computes Western Easter date using the Anonymous Gregorian algorithm.
    func computeEaster(year: Int) -> Date {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components) ?? Date()
    }

    // MARK: - Calendar Generation

    /// Generates all holiday observances for a given year.
    func calendarForYear(_ year: Int) -> [HolidayObservance] {
        let cal = Calendar.current
        let easter = computeEaster(year: year)

        func makeDate(month: Int, day: Int) -> Date {
            cal.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
        }

        func offset(_ base: Date, days: Int) -> Date {
            cal.date(byAdding: .day, value: days, to: base) ?? base
        }

        func observance(
            type: HolidayType,
            date: Date,
            season: LiturgicalSeasonType,
            scriptures: [String],
            summary: String,
            denominations: [DenominationProfile] = DenominationProfile.allCases
        ) -> HolidayObservance {
            HolidayObservance(
                id: "\(type.rawValue)_\(year)",
                type: type,
                date: date,
                seasonType: season,
                leadUpStart: offset(date, days: -type.leadUpDays),
                followUpEnd: offset(date, days: type.followUpDays),
                scriptureReferences: scriptures,
                summary: summary,
                denominationTags: denominations
            )
        }

        // Advent: 4 Sundays before Christmas
        let christmas = makeDate(month: 12, day: 25)
        let christmasWeekday = cal.component(.weekday, from: christmas)
        let daysToSunday = (christmasWeekday == 1) ? 28 : (christmasWeekday - 1) + 21
        let adventStart = offset(christmas, days: -daysToSunday)

        return [
            // Advent
            observance(
                type: .adventStart, date: adventStart, season: .advent,
                scriptures: ["Isaiah 9:6", "Luke 1:26-38", "Matthew 1:18-25"],
                summary: "The beginning of Advent — a season of waiting and preparation for Christ's coming."
            ),

            // Christmas
            observance(
                type: .christmasEve, date: makeDate(month: 12, day: 24), season: .christmas,
                scriptures: ["Luke 2:1-20", "Isaiah 9:6", "John 1:14"],
                summary: "The night before Christmas — anticipation of the Savior's birth."
            ),
            observance(
                type: .christmas, date: christmas, season: .christmas,
                scriptures: ["Luke 2:1-20", "Matthew 1:18-25", "John 1:1-14", "Isaiah 7:14"],
                summary: "The birth of Jesus Christ — God made flesh, dwelling among us."
            ),

            // New Year Consecration
            observance(
                type: .newYearConsecration, date: makeDate(month: 1, day: 1), season: .christmas,
                scriptures: ["Joshua 24:15", "Proverbs 16:3", "Jeremiah 29:11", "Psalm 37:5"],
                summary: "A time of consecration and dedication to God for the new year."
            ),

            // Epiphany
            observance(
                type: .epiphany, date: makeDate(month: 1, day: 6), season: .epiphany,
                scriptures: ["Matthew 2:1-12", "Isaiah 60:1-6"],
                summary: "The revelation of Christ to the nations — the visit of the Magi."
            ),

            // Ash Wednesday (46 days before Easter)
            observance(
                type: .ashWednesday, date: offset(easter, days: -46), season: .lent,
                scriptures: ["Joel 2:12-13", "Matthew 6:16-18", "Psalm 51:10"],
                summary: "The beginning of Lent — a call to repentance, fasting, and prayer.",
                denominations: [.liturgical, .reformed]
            ),

            // Palm Sunday (7 days before Easter)
            observance(
                type: .palmSunday, date: offset(easter, days: -7), season: .holyWeek,
                scriptures: ["Matthew 21:1-11", "Mark 11:1-10", "John 12:12-19"],
                summary: "Jesus' triumphal entry into Jerusalem — the beginning of Holy Week."
            ),

            // Holy Week days
            observance(
                type: .holyMonday, date: offset(easter, days: -6), season: .holyWeek,
                scriptures: ["Mark 11:12-19", "John 12:1-11"],
                summary: "Jesus cleanses the temple — righteous confrontation.",
                denominations: [.liturgical]
            ),
            observance(
                type: .holyTuesday, date: offset(easter, days: -5), season: .holyWeek,
                scriptures: ["Matthew 24:1-25:46", "Mark 13:1-37"],
                summary: "Jesus teaches in the temple — parables and prophecy.",
                denominations: [.liturgical]
            ),
            observance(
                type: .holyWednesday, date: offset(easter, days: -4), season: .holyWeek,
                scriptures: ["Matthew 26:14-16", "Luke 22:3-6"],
                summary: "Judas agrees to betray Jesus — the shadow of betrayal.",
                denominations: [.liturgical]
            ),
            observance(
                type: .maundyThursday, date: offset(easter, days: -3), season: .holyWeek,
                scriptures: ["John 13:1-17", "Matthew 26:17-30", "Luke 22:14-23"],
                summary: "The Last Supper — Jesus washes feet and breaks bread."
            ),
            observance(
                type: .goodFriday, date: offset(easter, days: -2), season: .holyWeek,
                scriptures: ["John 19:1-42", "Isaiah 53:1-12", "Matthew 27:32-56", "Luke 23:26-49"],
                summary: "The crucifixion of Jesus Christ — the sacrifice for sin."
            ),
            observance(
                type: .holySaturday, date: offset(easter, days: -1), season: .holyWeek,
                scriptures: ["Matthew 27:57-66", "1 Peter 3:18-20"],
                summary: "The day of silence — Jesus in the tomb. Waiting and grief.",
                denominations: [.liturgical]
            ),

            // Easter
            observance(
                type: .easter, date: easter, season: .easter,
                scriptures: ["Matthew 28:1-10", "Mark 16:1-8", "Luke 24:1-12", "John 20:1-18", "1 Corinthians 15:3-8"],
                summary: "The resurrection of Jesus Christ — death is defeated, hope is alive."
            ),

            // Ascension (39 days after Easter)
            observance(
                type: .ascension, date: offset(easter, days: 39), season: .easter,
                scriptures: ["Acts 1:6-11", "Luke 24:50-53"],
                summary: "Jesus ascends to the Father — the promise of His return.",
                denominations: [.liturgical, .reformed]
            ),

            // Pentecost (49 days after Easter)
            observance(
                type: .pentecost, date: offset(easter, days: 49), season: .pentecost,
                scriptures: ["Acts 2:1-21", "Joel 2:28-32", "John 14:15-26", "John 16:7-15"],
                summary: "The Holy Spirit descends — the Church is empowered."
            ),

            // Thanksgiving (4th Thursday of November — US)
            observance(
                type: .thanksgiving, date: thanksgivingDate(year: year), season: .ordinaryTimeLate,
                scriptures: ["Psalm 100:1-5", "1 Thessalonians 5:18", "Colossians 3:15-17"],
                summary: "A day of gratitude — giving thanks for God's faithfulness."
            )
        ]
    }

    /// Generates liturgical seasons for a given year.
    func seasonsForYear(_ year: Int) -> [LiturgicalSeason] {
        let cal = Calendar.current
        let easter = computeEaster(year: year)

        func makeDate(month: Int, day: Int) -> Date {
            cal.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
        }

        func offset(_ base: Date, days: Int) -> Date {
            cal.date(byAdding: .day, value: days, to: base) ?? base
        }

        let christmas = makeDate(month: 12, day: 25)
        let christmasWeekday = cal.component(.weekday, from: christmas)
        let daysToSunday = (christmasWeekday == 1) ? 28 : (christmasWeekday - 1) + 21
        let adventStart = offset(christmas, days: -daysToSunday)

        let ashWednesday = offset(easter, days: -46)
        let palmSunday = offset(easter, days: -7)
        let pentecostDate = offset(easter, days: 49)

        return [
            LiturgicalSeason(id: "advent_\(year)", type: .advent, startDate: adventStart, endDate: offset(christmas, days: -1), year: year),
            LiturgicalSeason(id: "christmas_\(year)", type: .christmas, startDate: christmas, endDate: makeDate(month: 1, day: 5), year: year),
            LiturgicalSeason(id: "epiphany_\(year)", type: .epiphany, startDate: makeDate(month: 1, day: 6), endDate: makeDate(month: 1, day: 12), year: year),
            LiturgicalSeason(id: "ordinary_early_\(year)", type: .ordinaryTimeEarly, startDate: makeDate(month: 1, day: 13), endDate: offset(ashWednesday, days: -1), year: year),
            LiturgicalSeason(id: "lent_\(year)", type: .lent, startDate: ashWednesday, endDate: offset(palmSunday, days: -1), year: year),
            LiturgicalSeason(id: "holy_week_\(year)", type: .holyWeek, startDate: palmSunday, endDate: offset(easter, days: -1), year: year),
            LiturgicalSeason(id: "easter_\(year)", type: .easter, startDate: easter, endDate: offset(pentecostDate, days: -1), year: year),
            LiturgicalSeason(id: "pentecost_\(year)", type: .pentecost, startDate: pentecostDate, endDate: offset(pentecostDate, days: 7), year: year),
            LiturgicalSeason(id: "ordinary_late_\(year)", type: .ordinaryTimeLate, startDate: offset(pentecostDate, days: 8), endDate: offset(adventStart, days: -1), year: year),
        ]
    }

    // MARK: - Thanksgiving Calculation

    private func thanksgivingDate(year: Int) -> Date {
        let cal = Calendar.current
        // 4th Thursday of November
        var components = DateComponents()
        components.year = year
        components.month = 11
        components.weekday = 5 // Thursday
        components.weekdayOrdinal = 4
        return cal.date(from: components) ?? Date()
    }

    // MARK: - Cache Invalidation

    func invalidateCache() {
        cachedState = nil
        cacheDate = nil
    }
}

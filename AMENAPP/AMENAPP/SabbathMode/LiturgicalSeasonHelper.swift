// LiturgicalSeasonHelper.swift
// AMENAPP — SabbathMode
//
// Pure Swift port of Prototypes/SabbathMode/berean/liturgicalSeason.ts.
// Prefixed with "Sabbath" to avoid collision with the existing
// LiturgicalSeason struct and computeEaster() method in LiturgicalCalendarEngine.swift.
// No external dependencies. Approximate season boundaries — sufficient for
// liturgical context prompts (not canonical church-calendar spec).
// Uses Anonymous Gregorian Easter algorithm (Meeus/Jones/Butcher).

import Foundation

// MARK: - Types

/// Liturgical season identifier for Sabbath Mode Berean prompts.
/// Prefixed "Sabbath" to avoid collision with LiturgicalSeason struct in LiturgicalCalendarEngine.
enum SabbathLiturgicalSeason: String {
    case advent         = "Advent"
    case christmas      = "Christmas"
    case epiphany       = "Epiphany"
    case lent           = "Lent"
    case holyWeek       = "HolyWeek"
    case easter         = "Easter"
    case pentecost      = "Pentecost"
    case ordinaryTime   = "OrdinaryTime"
}

struct SabbathLiturgicalContext {
    let season: SabbathLiturgicalSeason
    let weekNumber: Int?
    let dominantTheme: String
    let suggestedScriptures: [String]
    /// Liturgical color word only — never a hex value.
    let colorSignifier: String
}

// MARK: - Season data (matches SEASON_DATA in liturgicalSeason.ts)

private struct SabbathSeasonData {
    let dominantTheme: String
    let suggestedScriptures: [String]
    let colorSignifier: String
}

private let SABBATH_SEASON_DATA: [SabbathLiturgicalSeason: SabbathSeasonData] = [
    .advent: SabbathSeasonData(
        dominantTheme: "hope and preparation",
        suggestedScriptures: ["Isaiah 40:3-5", "Luke 3:1-6", "Romans 13:11-14", "Matthew 24:36-44"],
        colorSignifier: "purple"
    ),
    .christmas: SabbathSeasonData(
        dominantTheme: "incarnation and joy",
        suggestedScriptures: ["Luke 2:1-20", "John 1:1-14", "Isaiah 9:6-7", "Titus 2:11-14"],
        colorSignifier: "white"
    ),
    .epiphany: SabbathSeasonData(
        dominantTheme: "revelation and light",
        suggestedScriptures: ["Matthew 2:1-12", "Isaiah 60:1-6", "Ephesians 3:1-12", "Luke 2:41-52"],
        colorSignifier: "white"
    ),
    .lent: SabbathSeasonData(
        dominantTheme: "repentance and renewal",
        suggestedScriptures: ["Psalm 51:1-17", "Matthew 4:1-11", "Joel 2:12-13", "2 Corinthians 5:20-21"],
        colorSignifier: "purple"
    ),
    .holyWeek: SabbathSeasonData(
        dominantTheme: "suffering, sacrifice, and surrender",
        suggestedScriptures: ["Isaiah 53:1-12", "Philippians 2:5-11", "John 12:12-16", "Luke 22:39-46"],
        colorSignifier: "red"
    ),
    .easter: SabbathSeasonData(
        dominantTheme: "resurrection and new life",
        suggestedScriptures: ["John 20:1-18", "1 Corinthians 15:1-11", "Romans 6:3-11", "Colossians 3:1-4"],
        colorSignifier: "white"
    ),
    .pentecost: SabbathSeasonData(
        dominantTheme: "the Holy Spirit and the life of the Church",
        suggestedScriptures: ["Acts 2:1-21", "Romans 8:14-17", "John 14:8-17", "Ezekiel 37:1-14"],
        colorSignifier: "red"
    ),
    .ordinaryTime: SabbathSeasonData(
        dominantTheme: "growth, discipleship, and faithful living",
        suggestedScriptures: ["Matthew 5:1-12", "Romans 12:1-2", "Micah 6:8", "James 1:22-25"],
        colorSignifier: "green"
    ),
]

// MARK: - Safe season data accessor

private func sabbathSeasonData(for season: SabbathLiturgicalSeason) -> SabbathSeasonData {
    if let data = SABBATH_SEASON_DATA[season] { return data }
    return SABBATH_SEASON_DATA[.ordinaryTime] ?? SabbathSeasonData(
        dominantTheme: "growth, discipleship, and faithful living",
        suggestedScriptures: ["Micah 6:8"],
        colorSignifier: "green"
    )
}

// MARK: - Easter calculation (Anonymous Gregorian Algorithm — Meeus/Jones/Butcher)

/// Returns Easter Sunday for the given year (Gregorian calendar).
/// Prefixed "sabbath_" to avoid collision with computeEaster() in LiturgicalCalendarEngine.
func sabbathComputeEaster(year: Int) -> Date {
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
    let month = (h + l - 7 * m + 114) / 31  // 1-indexed
    let day   = ((h + l - 7 * m + 114) % 31) + 1

    var comps = DateComponents()
    comps.year  = year
    comps.month = month
    comps.day   = day
    return Calendar(identifier: .gregorian).date(from: comps) ?? Date()
}

// MARK: - Day-delta helper

private func sabbathDaysBetween(_ a: Date, _ b: Date) -> Int {
    let cal = Calendar(identifier: .gregorian)
    let aDay = cal.startOfDay(for: a)
    let bDay = cal.startOfDay(for: b)
    return cal.dateComponents([.day], from: aDay, to: bDay).day ?? 0
}

// MARK: - Advent start

/// Returns the first Sunday of Advent for the given year.
/// Advent begins on the Sunday nearest Nov 30 (4th Sunday before Christmas).
private func sabbathFirstSundayOfAdvent(year: Int) -> Date {
    var comps = DateComponents()
    comps.year  = year
    comps.month = 12
    comps.day   = 25
    let cal = Calendar(identifier: .gregorian)
    let christmas = cal.date(from: comps) ?? Date()
    let dow = cal.component(.weekday, from: christmas) // 1=Sun … 7=Sat
    let daysToLastSundayBeforeChristmas = dow == 1 ? 7 : dow - 1
    let lastSunday = cal.date(byAdding: .day, value: -daysToLastSundayBeforeChristmas, to: christmas)!
    // First Sunday of Advent = 3 weeks before last Sunday before Christmas
    return cal.date(byAdding: .day, value: -21, to: lastSunday)!
}

// MARK: - Main export

/// Determines the approximate liturgical season for a given date.
/// Matches getLiturgicalContext() in Prototypes/SabbathMode/berean/liturgicalSeason.ts exactly.
func getSabbathLiturgicalContext(for date: Date = Date()) -> SabbathLiturgicalContext {
    let cal = Calendar(identifier: .gregorian)
    let year = cal.component(.year, from: date)
    let d = cal.startOfDay(for: date)

    // Easter-relative seasons
    let easter = sabbathComputeEaster(year: year)
    let daysToEaster = sabbathDaysBetween(d, easter)   // positive = before Easter
    let daysAfterEaster = -daysToEaster                  // positive = after Easter

    // Easter season: Easter Sunday through the day before Pentecost (49 days after)
    if daysAfterEaster >= 0 && daysAfterEaster < 49 {
        let data = sabbathSeasonData(for: .easter)
        let weekNum = daysAfterEaster / 7 + 1
        return SabbathLiturgicalContext(
            season: .easter,
            weekNumber: weekNum,
            dominantTheme: data.dominantTheme,
            suggestedScriptures: data.suggestedScriptures,
            colorSignifier: data.colorSignifier
        )
    }

    // Pentecost Sunday (49 days after Easter)
    if daysAfterEaster == 49 {
        let data = sabbathSeasonData(for: .pentecost)
        return SabbathLiturgicalContext(
            season: .pentecost,
            weekNumber: nil,
            dominantTheme: data.dominantTheme,
            suggestedScriptures: data.suggestedScriptures,
            colorSignifier: data.colorSignifier
        )
    }

    // Holy Week: Palm Sunday (7 days before Easter) through Holy Saturday (1 day before)
    if daysToEaster >= 1 && daysToEaster <= 7 {
        let data = sabbathSeasonData(for: .holyWeek)
        return SabbathLiturgicalContext(
            season: .holyWeek,
            weekNumber: nil,
            dominantTheme: data.dominantTheme,
            suggestedScriptures: data.suggestedScriptures,
            colorSignifier: data.colorSignifier
        )
    }

    // Lent: Ash Wednesday (46 days before Easter) through Holy Saturday
    if daysToEaster >= 2 && daysToEaster <= 46 {
        let data = sabbathSeasonData(for: .lent)
        let daysIntoLent = 46 - daysToEaster
        let weekNum = daysIntoLent / 7 + 1
        return SabbathLiturgicalContext(
            season: .lent,
            weekNumber: weekNum,
            dominantTheme: data.dominantTheme,
            suggestedScriptures: data.suggestedScriptures,
            colorSignifier: data.colorSignifier
        )
    }

    // Calendar-relative seasons
    let month = cal.component(.month, from: date)
    let day   = cal.component(.day, from: date)

    // Christmas: Dec 25 – Jan 5
    let isChristmasSeason = (month == 12 && day >= 25) || (month == 1 && day <= 5)
    if isChristmasSeason {
        let data = sabbathSeasonData(for: .christmas)
        return SabbathLiturgicalContext(
            season: .christmas,
            weekNumber: nil,
            dominantTheme: data.dominantTheme,
            suggestedScriptures: data.suggestedScriptures,
            colorSignifier: data.colorSignifier
        )
    }

    // Advent: first Sunday of Advent through Dec 24
    var adventEndComps = DateComponents(); adventEndComps.year = year; adventEndComps.month = 12; adventEndComps.day = 24
    let adventEnd = cal.date(from: adventEndComps)!
    let adventStart = sabbathFirstSundayOfAdvent(year: year)

    if d >= adventStart && d <= adventEnd {
        let data = sabbathSeasonData(for: .advent)
        let daysSinceAdvent = sabbathDaysBetween(adventStart, d)
        let weekNum = min(daysSinceAdvent / 7 + 1, 4)
        return SabbathLiturgicalContext(
            season: .advent,
            weekNumber: weekNum,
            dominantTheme: data.dominantTheme,
            suggestedScriptures: data.suggestedScriptures,
            colorSignifier: data.colorSignifier
        )
    }

    // Epiphany: Jan 6 through Ash Wednesday eve (handled above by Lent check)
    if month == 1 && day >= 6 {
        let data = sabbathSeasonData(for: .epiphany)
        return SabbathLiturgicalContext(
            season: .epiphany,
            weekNumber: nil,
            dominantTheme: data.dominantTheme,
            suggestedScriptures: data.suggestedScriptures,
            colorSignifier: data.colorSignifier
        )
    }

    if month == 2 && daysToEaster > 46 {
        let data = sabbathSeasonData(for: .epiphany)
        return SabbathLiturgicalContext(
            season: .epiphany,
            weekNumber: nil,
            dominantTheme: data.dominantTheme,
            suggestedScriptures: data.suggestedScriptures,
            colorSignifier: data.colorSignifier
        )
    }

    // Ordinary Time: everything else
    let data = sabbathSeasonData(for: .ordinaryTime)
    return SabbathLiturgicalContext(
        season: .ordinaryTime,
        weekNumber: nil,
        dominantTheme: data.dominantTheme,
        suggestedScriptures: data.suggestedScriptures,
        colorSignifier: data.colorSignifier
    )
}

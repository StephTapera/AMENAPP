//
//  LiturgicalSeasonService.swift
//  AMENAPP
//
//  Liturgical Theming Engine — computes the current Western liturgical season
//  from first principles (Computus algorithm + movable/fixed feast arithmetic).
//
//  Design constraints:
//    - Easter date is computed via pure math (Spencer Jones / Meeus-Jones-Butcher
//      Anonymous Gregorian algorithm). No Calendar lookups are used for Easter.
//    - All other season boundaries derive from that Easter anchor or from fixed
//      calendar dates.
//    - Flag: AMENFeatureFlags.shared.liturgicalTheming — consumers check this before
//      applying any seasonal tint. The service always publishes the current season
//      regardless; the flag is a presentation layer concern.
//    - Western calendar only (Eastern calendar support is in contract, wave N+1).
//    - glassTintHex stores the pure hex string; opacity is applied in the view layer.
//

import Foundation
import SwiftUI

// MARK: - LiturgicalSeasonService

@MainActor
final class LiturgicalSeasonService: ObservableObject {

    static let shared = LiturgicalSeasonService()

    @Published private(set) var currentSeason: LiturgicalThemeSeason
    @Published private(set) var currentTheme: SeasonTheme

    private init() {
        let now = Date()
        let season = LiturgicalSeasonService.computeSeason(for: now)
        self.currentSeason = season
        self.currentTheme = LiturgicalSeasonService.computeTheme(for: season)
    }

    // MARK: - Public API

    /// Returns the liturgical season for any given date.
    func season(for date: Date) -> LiturgicalThemeSeason {
        LiturgicalSeasonService.computeSeason(for: date)
    }

    /// Returns the SeasonTheme for a given liturgical season.
    func theme(for season: LiturgicalThemeSeason) -> SeasonTheme {
        LiturgicalSeasonService.computeTheme(for: season)
    }

    // MARK: - Computus (Spencer Jones / Meeus-Jones-Butcher Anonymous Gregorian)
    //
    // Returns (month, day) of Easter Sunday in the Gregorian calendar for the
    // given year. This is pure integer arithmetic — no Calendar, no DateComponents
    // for the Easter date itself.
    //
    // Test anchors:
    //   Easter 2026 = April 5   → month 4, day 5
    //   Easter 2027 = March 28  → month 3, day 28

    static func easterDate(year: Int) -> (month: Int, day: Int) {
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
        return (month: month, day: day)
    }

    // MARK: - Season computation

    static func computeSeason(for date: Date) -> LiturgicalThemeSeason {
        let cal = Calendar(identifier: .gregorian)
        let year = cal.component(.year, from: date)
        let currentDayOfYear = cal.ordinality(of: .day, in: .year, for: date) ?? 1

        // --- Easter and its derived feasts (current year) ---
        let easter = easterDate(year: year)
        let easterDOY = dayOfYear(month: easter.month, day: easter.day, year: year, cal: cal)
        let ashWednesdayDOY = easterDOY - 46
        let palmSundayDOY   = easterDOY - 7
        let pentecostDOY    = easterDOY + 49

        // --- Advent start: 4th Sunday before Dec 25 ---
        // The 4th Sunday before Dec 25 is computed by finding Dec 25's weekday,
        // then stepping back to the nearest Sunday + 3 more weeks.
        let adventStartDOY = adventStartDayOfYear(year: year, cal: cal)

        // --- Fixed season boundaries ---
        // Christmas: Dec 25 → Jan 5 (spans year boundary)
        // Epiphany: Jan 6 → Ash Wednesday

        let jan6DOY = dayOfYear(month: 1, day: 6, year: year, cal: cal)
        let dec25DOY = dayOfYear(month: 12, day: 25, year: year, cal: cal)

        // Jan 1–5: Christmas season (carryover from previous year's Christmas)
        if currentDayOfYear < jan6DOY {
            // Jan 1 – Jan 5 is still the Christmas season
            return .christmas
        }

        // Jan 6 – Ash Wednesday: Epiphany
        if currentDayOfYear >= jan6DOY && currentDayOfYear < ashWednesdayDOY {
            return .epiphany
        }

        // Ash Wednesday – Palm Sunday (exclusive): Lent
        if currentDayOfYear >= ashWednesdayDOY && currentDayOfYear < palmSundayDOY {
            return .lent
        }

        // Palm Sunday – Holy Saturday (Easter - 1): Holy Week
        if currentDayOfYear >= palmSundayDOY && currentDayOfYear < easterDOY {
            return .holyWeek
        }

        // Easter Sunday – Pentecost Saturday (Pentecost + 0): Easter season
        if currentDayOfYear >= easterDOY && currentDayOfYear <= pentecostDOY {
            return .easter
        }

        // Day after Pentecost – Advent start: Ordinary Time II
        // (Ordinary Time I is Jan 6–Ash Wed handled above as Epiphany in this model)
        if currentDayOfYear > pentecostDOY && currentDayOfYear < adventStartDOY {
            return .ordinaryTime
        }

        // Advent: advent start – Dec 24
        if currentDayOfYear >= adventStartDOY && currentDayOfYear < dec25DOY {
            return .advent
        }

        // Dec 25 – Dec 31: Christmas
        if currentDayOfYear >= dec25DOY {
            return .christmas
        }

        // Fallback (should not occur)
        return .ordinaryTime
    }

    // MARK: - Theme registry

    static func computeTheme(for season: LiturgicalThemeSeason) -> SeasonTheme {
        switch season {
        case .advent:
            return SeasonTheme(
                season: .advent,
                glassTintHex: "#3B1F6E",
                iconVariantKey: "advent",
                heyFeedToneKey: "reflective_waiting",
                bereanToneKey: "hopeful_expectation"
            )
        case .christmas:
            return SeasonTheme(
                season: .christmas,
                glassTintHex: "#C8A95A",
                iconVariantKey: "christmas",
                heyFeedToneKey: "joyful_celebration",
                bereanToneKey: "incarnation_wonder"
            )
        case .epiphany:
            return SeasonTheme(
                season: .epiphany,
                glassTintHex: "#F5D06A",
                iconVariantKey: "epiphany",
                heyFeedToneKey: "revelatory_discovery",
                bereanToneKey: "light_to_nations"
            )
        case .lent:
            return SeasonTheme(
                season: .lent,
                glassTintHex: "#7A5C8A",
                iconVariantKey: "lent",
                heyFeedToneKey: "contemplative_depth",
                bereanToneKey: "penitential_searching"
            )
        case .holyWeek:
            return SeasonTheme(
                season: .holyWeek,
                glassTintHex: "#2A2A2A",
                iconVariantKey: "holy_week",
                heyFeedToneKey: "solemn_reverence",
                bereanToneKey: "passion_meditation"
            )
        case .easter:
            return SeasonTheme(
                season: .easter,
                glassTintHex: "#F0C8B4",
                iconVariantKey: "easter",
                heyFeedToneKey: "resurrection_joy",
                bereanToneKey: "risen_lord_proclamation"
            )
        case .pentecost:
            return SeasonTheme(
                season: .pentecost,
                glassTintHex: "#E87040",
                iconVariantKey: "pentecost",
                heyFeedToneKey: "spirit_empowered",
                bereanToneKey: "holy_spirit_gifts"
            )
        case .ordinaryTime:
            return SeasonTheme(
                season: .ordinaryTime,
                glassTintHex: "#4A7A5A",
                iconVariantKey: "ordinary_time",
                heyFeedToneKey: "steady_discipleship",
                bereanToneKey: "faithful_growth"
            )
        }
    }

    // MARK: - Calendar helpers

    /// Returns the day-of-year (1-based) for a given month/day/year using the provided calendar.
    static func dayOfYear(month: Int, day: Int, year: Int, cal: Calendar) -> Int {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        guard let date = cal.date(from: comps),
              let doy = cal.ordinality(of: .day, in: .year, for: date) else {
            return 1
        }
        return doy
    }

    /// Returns the day-of-year for Advent start in `year`.
    ///
    /// Advent starts on the 4th Sunday before December 25.
    /// Algorithm:
    ///   1. Find the weekday of Dec 25 (Sunday = 1 in Gregorian Calendar).
    ///   2. The nearest Sunday on or before Dec 25 is Dec 25 minus (weekday - 1) days.
    ///   3. Advent starts 3 weeks (21 days) before that Sunday.
    static func adventStartDayOfYear(year: Int, cal: Calendar) -> Int {
        var dec25Comps = DateComponents()
        dec25Comps.year = year
        dec25Comps.month = 12
        dec25Comps.day = 25
        guard let dec25 = cal.date(from: dec25Comps) else { return 330 }

        // weekday: 1 = Sunday, 7 = Saturday (Gregorian calendar)
        let weekday = cal.component(.weekday, from: dec25)
        // Days to subtract to reach the Sunday on or before Dec 25
        let daysToSunday = weekday - 1
        // The Sunday before (or on) Dec 25 is the 1st Sunday of Advent start anchor
        // Advent actually starts 3 full weeks before the Sunday nearest to Dec 25.
        // The 4th Sunday before Dec 25 = the Sunday that is <= Dec 25
        //   minus 21 days (3 more weeks back to the FIRST Sunday of Advent).
        // Actually: the FIRST Sunday of Advent is the 4th Sunday before Christmas.
        // The Sunday on/before Dec 25 is the 4th Sunday of Advent.
        // So Advent start = that Sunday - 21 days.
        guard let fourthAdventSunday = cal.date(byAdding: .day, value: -daysToSunday, to: dec25),
              let adventStart = cal.date(byAdding: .day, value: -21, to: fourthAdventSunday) else {
            return 330
        }

        return cal.ordinality(of: .day, in: .year, for: adventStart) ?? 330
    }
}

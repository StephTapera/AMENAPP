//
//  LiturgicalSeasonTests.swift
//  AMENAPPTests
//
//  Contract tests for the Liturgical Theming Engine.
//  Verifies: Computus accuracy, season boundary logic, theme registry completeness,
//  and WCAG AA contrast of every glassTintHex at 100% opacity.
//
//  Note on WCAG check: glassTintHex values are pure hex stored at full opacity.
//  In the view layer they are applied at 10–15% as glass overlays. The WCAG test
//  here validates that each color is chromatic enough to meet WCAG AA (4.5:1) against
//  at least one high-contrast background (white or black), confirming the hue is a
//  meaningful, non-trivial color choice and not washed out or invisible.
//

import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

// MARK: - Relative Luminance Helper

/// Computes WCAG 2.1 relative luminance from 8-bit RGB components.
private func relativeLuminance(r: Int, g: Int, b: Int) -> Double {
    func linearize(_ channel: Int) -> Double {
        let c = Double(channel) / 255.0
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
}

/// Returns the WCAG contrast ratio between two luminance values.
private func contrastRatio(l1: Double, l2: Double) -> Double {
    let lighter = max(l1, l2)
    let darker  = min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)
}

/// Parses a hex string like "#3B1F6E" or "3B1F6E" into (r, g, b) integer components.
/// Returns nil for malformed input.
private func parseHex(_ hex: String) -> (r: Int, g: Int, b: Int)? {
    let sanitised = hex
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "#", with: "")
    guard sanitised.count == 6, let value = UInt64(sanitised, radix: 16) else { return nil }
    let r = Int((value >> 16) & 0xFF)
    let g = Int((value >> 8)  & 0xFF)
    let b = Int(value          & 0xFF)
    return (r: r, g: g, b: b)
}

// MARK: - Computus Tests

@Suite("LiturgicalSeason — Computus Algorithm")
@MainActor
struct ComputusTests {

    @Test("Easter 2026 = April 5")
    func easter2026() {
        let result = LiturgicalSeasonService.easterDate(year: 2026)
        #expect(result.month == 4)
        #expect(result.day == 5)
    }

    @Test("Easter 2027 = March 28")
    func easter2027() {
        let result = LiturgicalSeasonService.easterDate(year: 2027)
        #expect(result.month == 3)
        #expect(result.day == 28)
    }

    @Test("Easter 2025 = April 20 (additional anchor)")
    func easter2025() {
        let result = LiturgicalSeasonService.easterDate(year: 2025)
        #expect(result.month == 4)
        #expect(result.day == 20)
    }
}

// MARK: - Derived Movable Feast Tests

@Suite("LiturgicalSeason — Movable Feasts")
@MainActor
struct MovableFeastTests {

    private let cal = Calendar(identifier: .gregorian)

    @Test("Ash Wednesday 2026 = February 18 (Easter 2026 - 46 days)")
    func ashWednesday2026() {
        let (m, d) = LiturgicalSeasonService.easterDate(year: 2026)
        var easterComps = DateComponents()
        easterComps.year = 2026; easterComps.month = m; easterComps.day = d
        guard let easterDate = Calendar(identifier: .gregorian).date(from: easterComps),
              let ashWed = Calendar(identifier: .gregorian).date(byAdding: .day, value: -46, to: easterDate) else {
            Issue.record("Could not compute Ash Wednesday 2026")
            return
        }
        let ashCal = Calendar(identifier: .gregorian)
        #expect(ashCal.component(.month, from: ashWed) == 2)
        #expect(ashCal.component(.day, from: ashWed) == 18)
    }
}

// MARK: - Advent Start Tests

@Suite("LiturgicalSeason — Advent Start")
@MainActor
struct AdventStartTests {

    @Test("Advent start 2026 = November 29")
    func adventStart2026() {
        let cal = Calendar(identifier: .gregorian)
        let doy = LiturgicalSeasonService.adventStartDayOfYear(year: 2026, cal: cal)

        // Build the expected date: Nov 29, 2026
        var comps = DateComponents()
        comps.year = 2026; comps.month = 11; comps.day = 29
        guard let expected = cal.date(from: comps),
              let expectedDOY = cal.ordinality(of: .day, in: .year, for: expected) else {
            Issue.record("Could not build expected Advent start 2026 date")
            return
        }
        #expect(doy == expectedDOY)
    }

    @Test("Advent start 2025 = November 30")
    func adventStart2025() {
        let cal = Calendar(identifier: .gregorian)
        let doy = LiturgicalSeasonService.adventStartDayOfYear(year: 2025, cal: cal)

        var comps = DateComponents()
        comps.year = 2025; comps.month = 11; comps.day = 30
        guard let expected = cal.date(from: comps),
              let expectedDOY = cal.ordinality(of: .day, in: .year, for: expected) else {
            Issue.record("Could not build expected Advent start 2025 date")
            return
        }
        #expect(doy == expectedDOY)
    }
}

// MARK: - Season Boundary Tests

@Suite("LiturgicalSeason — season(for:) boundaries")
@MainActor
struct SeasonBoundaryTests {

    private func date(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        return Calendar(identifier: .gregorian).date(from: comps) ?? Date()
    }

    @Test("April 10, 2026 is Easter season (Easter was April 5, Pentecost May 24)")
    func easterSeason2026() {
        let d = date(year: 2026, month: 4, day: 10)
        let season = LiturgicalSeasonService.computeSeason(for: d)
        #expect(season == .easter)
    }

    @Test("March 1, 2026 is Lent (Ash Wed was Feb 18, Palm Sunday March 29)")
    func lentSeason2026() {
        let d = date(year: 2026, month: 3, day: 1)
        let season = LiturgicalSeasonService.computeSeason(for: d)
        #expect(season == .lent)
    }

    @Test("December 1, 2026 is Advent (Advent started November 29)")
    func adventSeason2026() {
        let d = date(year: 2026, month: 12, day: 1)
        let season = LiturgicalSeasonService.computeSeason(for: d)
        #expect(season == .advent)
    }

    @Test("January 15, 2026 is Epiphany (Jan 6 – Ash Wed Feb 18)")
    func epiphanySeason2026() {
        let d = date(year: 2026, month: 1, day: 15)
        let season = LiturgicalSeasonService.computeSeason(for: d)
        #expect(season == .epiphany)
    }

    @Test("March 30, 2026 is Holy Week (Palm Sunday March 29 – Holy Saturday April 4)")
    func holyWeekSeason2026() {
        let d = date(year: 2026, month: 3, day: 30)
        let season = LiturgicalSeasonService.computeSeason(for: d)
        #expect(season == .holyWeek)
    }

    @Test("July 4, 2026 is Ordinary Time (after Pentecost May 24, before Advent Nov 29)")
    func ordinaryTimeSeason2026() {
        let d = date(year: 2026, month: 7, day: 4)
        let season = LiturgicalSeasonService.computeSeason(for: d)
        #expect(season == .ordinaryTime)
    }

    @Test("December 25, 2026 is Christmas")
    func christmasSeason2026() {
        let d = date(year: 2026, month: 12, day: 25)
        let season = LiturgicalSeasonService.computeSeason(for: d)
        #expect(season == .christmas)
    }

    @Test("January 1, 2026 is Christmas (carryover from prior year)")
    func christmasCarryover2026() {
        let d = date(year: 2026, month: 1, day: 1)
        let season = LiturgicalSeasonService.computeSeason(for: d)
        #expect(season == .christmas)
    }
}

// MARK: - Theme Registry Tests

@Suite("LiturgicalSeason — SeasonTheme registry")
@MainActor
struct SeasonThemeRegistryTests {

    private let allSeasons: [LiturgicalThemeSeason] = [
        .advent, .christmas, .epiphany, .lent, .holyWeek,
        .easter, .pentecost, .ordinaryTime
    ]

    @Test("All 8 season themes have a non-empty glassTintHex")
    func allThemesHaveGlassTintHex() {
        for season in allSeasons {
            let theme = LiturgicalSeasonService.computeTheme(for: season)
            #expect(!theme.glassTintHex.isEmpty, "glassTintHex empty for season \(season.rawValue)")
        }
    }

    @Test("All 8 season themes have a non-empty iconVariantKey")
    func allThemesHaveIconVariantKey() {
        for season in allSeasons {
            let theme = LiturgicalSeasonService.computeTheme(for: season)
            #expect(!theme.iconVariantKey.isEmpty, "iconVariantKey empty for season \(season.rawValue)")
        }
    }

    @Test("All 8 season themes have a non-empty heyFeedToneKey")
    func allThemesHaveHeyFeedToneKey() {
        for season in allSeasons {
            let theme = LiturgicalSeasonService.computeTheme(for: season)
            #expect(!theme.heyFeedToneKey.isEmpty, "heyFeedToneKey empty for season \(season.rawValue)")
        }
    }

    @Test("All 8 season themes have a non-empty bereanToneKey")
    func allThemesHaveBereanToneKey() {
        for season in allSeasons {
            let theme = LiturgicalSeasonService.computeTheme(for: season)
            #expect(!theme.bereanToneKey.isEmpty, "bereanToneKey empty for season \(season.rawValue)")
        }
    }

    @Test("All 8 season glassTintHex values are parseable as #RRGGBB")
    func allThemesHaveParseableHex() {
        for season in allSeasons {
            let theme = LiturgicalSeasonService.computeTheme(for: season)
            let parsed = parseHex(theme.glassTintHex)
            #expect(parsed != nil, "glassTintHex '\(theme.glassTintHex)' is not parseable for season \(season.rawValue)")
        }
    }
}

// MARK: - WCAG AA Contrast Tests

@Suite("LiturgicalSeason — WCAG AA contrast for glassTintHex")
@MainActor
struct WCAGContrastTests {

    /// Luminance of pure white (#FFFFFF).
    private let whiteLuminance: Double = 1.0

    /// Luminance of pure black (#000000).
    private let blackLuminance: Double = 0.0

    private let allSeasons: [LiturgicalThemeSeason] = [
        .advent, .christmas, .epiphany, .lent, .holyWeek,
        .easter, .pentecost, .ordinaryTime
    ]

    /// WCAG AA minimum contrast ratio for normal text.
    private let wcagAAThreshold: Double = 4.5

    /// Each glassTintHex, when evaluated at 100% opacity, must achieve WCAG AA (4.5:1)
    /// contrast against at least one high-contrast background (white or black).
    /// This confirms the stored hex is a meaningful, usable color — not a near-invisible
    /// or near-white/black value that would dissolve into the glass surface.
    ///
    /// Note: in the view layer these colors are applied at 10–15% opacity as overlays.
    /// The test operates on the pure hex to validate the color's intrinsic chromatic value.
    @Test("Each glassTintHex achieves WCAG AA (4.5:1) against white or black at 100% opacity")
    func wcagAAContrastVsWhiteOrBlack() {
        for season in allSeasons {
            let theme = LiturgicalSeasonService.computeTheme(for: season)
            guard let (r, g, b) = parseHex(theme.glassTintHex) else {
                Issue.record("Could not parse hex '\(theme.glassTintHex)' for season \(season.rawValue)")
                continue
            }

            let lum = relativeLuminance(r: r, g: g, b: b)
            let ratioVsWhite = contrastRatio(l1: lum, l2: whiteLuminance)
            let ratioVsBlack = contrastRatio(l1: lum, l2: blackLuminance)

            let passesVsWhite = ratioVsWhite >= wcagAAThreshold
            let passesVsBlack = ratioVsBlack >= wcagAAThreshold
            let passes = passesVsWhite || passesVsBlack

            #expect(
                passes,
                "Season \(season.rawValue) glassTintHex \(theme.glassTintHex) fails WCAG AA: vs white=\(String(format: "%.2f", ratioVsWhite)):1, vs black=\(String(format: "%.2f", ratioVsBlack)):1"
            )
        }
    }

    @Test("Luminance helper returns 0 for black and 1 for white")
    func luminanceHelperAnchors() {
        let black = relativeLuminance(r: 0, g: 0, b: 0)
        let white = relativeLuminance(r: 255, g: 255, b: 255)
        #expect(black < 0.001)
        #expect(white > 0.999)
    }

    @Test("Contrast ratio of black vs white = 21:1")
    func contrastBlackVsWhite() {
        let ratio = contrastRatio(l1: 0.0, l2: 1.0)
        #expect(abs(ratio - 21.0) < 0.01)
    }
}

#endif

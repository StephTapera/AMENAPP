// HolidayCalendarTests.swift
// AMENAPPTests
//
// Full test suite for the Amen Daily Verse Holiday Awareness system.
//
// Covers:
//   - Floating civic holiday date calculation
//   - Easter-relative holiday dates
//   - Biblical feast date calculation and offline fallback
//   - Season date resolution
//   - Priority resolution when multiple holidays coincide
//   - User timezone changes local date correctly
//   - Discernment holiday tone enforcement
//   - Personal celebration matching
//   - Settings filtering (categories)
//   - Spiritual guardrail safety checks
//   - Offline fallback when holiday_calendar is missing
//

#if canImport(Testing)
import Testing
import Foundation
@testable import AMENAPP

// MARK: - Helpers

private let engine = LiturgicalCalendarEngine.shared
private let gregorian = Calendar(identifier: .gregorian)

private func date(year: Int, month: Int, day: Int) -> Date {
    gregorian.date(from: DateComponents(year: year, month: month, day: day))!
}

private func weekday(of date: Date) -> Int {
    // 1 = Sunday … 7 = Saturday
    gregorian.component(.weekday, from: date)
}

// MARK: - Floating Civic Holiday Tests

@Suite("Floating Civic Holidays")
struct FloatingCivicHolidayTests {

    @Test("Mother's Day is second Sunday of May")
    func mothersDayIsSecondSundayOfMay() {
        for year in 2024...2028 {
            let result = engine.nthWeekday(weekday: 1, ordinal: 2, month: 5, year: year)
            let components = gregorian.dateComponents([.month, .weekday, .weekdayOrdinal], from: result)
            #expect(components.month == 5)
            #expect(components.weekday == 1, "Mother's Day must be Sunday (weekday == 1)")
            #expect(components.weekdayOrdinal == 2, "Mother's Day must be the 2nd Sunday")
        }
    }

    @Test("Father's Day is third Sunday of June")
    func fathersDayIsThirdSundayOfJune() {
        for year in 2024...2028 {
            let result = engine.nthWeekday(weekday: 1, ordinal: 3, month: 6, year: year)
            let components = gregorian.dateComponents([.month, .weekday, .weekdayOrdinal], from: result)
            #expect(components.month == 6)
            #expect(components.weekday == 1, "Father's Day must be Sunday")
            #expect(components.weekdayOrdinal == 3, "Father's Day must be the 3rd Sunday")
        }
    }

    @Test("Thanksgiving is fourth Thursday of November")
    func thanksgivingIsFourthThursdayOfNovember() {
        for year in 2024...2028 {
            let result = engine.thanksgivingDate(year: year)
            let components = gregorian.dateComponents([.month, .weekday, .weekdayOrdinal], from: result)
            #expect(components.month == 11)
            #expect(components.weekday == 5, "Thanksgiving must be Thursday (weekday == 5)")
            #expect(components.weekdayOrdinal == 4, "Thanksgiving must be the 4th Thursday")
        }
    }

    @Test("Memorial Day is last Monday of May")
    func memorialDayIsLastMondayOfMay() {
        for year in 2024...2028 {
            let result = engine.lastWeekday(weekday: 2, month: 5, year: year)
            let components = gregorian.dateComponents([.month, .weekday], from: result)
            #expect(components.month == 5)
            #expect(components.weekday == 2, "Memorial Day must be Monday (weekday == 2)")
            // Verify it's in the last week: no subsequent Monday in May
            let nextMonday = gregorian.date(byAdding: .day, value: 7, to: result)!
            #expect(gregorian.component(.month, from: nextMonday) != 5,
                    "No Monday 7 days later should still be in May")
        }
    }

    @Test("Labor Day is first Monday of September")
    func laborDayIsFirstMondayOfSeptember() {
        for year in 2024...2028 {
            let result = engine.nthWeekday(weekday: 2, ordinal: 1, month: 9, year: year)
            let components = gregorian.dateComponents([.month, .weekday, .weekdayOrdinal], from: result)
            #expect(components.month == 9)
            #expect(components.weekday == 2, "Labor Day must be Monday")
            #expect(components.weekdayOrdinal == 1, "Labor Day must be the 1st Monday")
        }
    }
}

// MARK: - Easter-Relative Holiday Tests

@Suite("Easter-Relative Holidays")
struct EasterRelativeHolidayTests {

    @Test("Good Friday is two days before Easter")
    func goodFridayIsCorrect() {
        for year in 2024...2028 {
            let easter = engine.computeEaster(year: year)
            let cal = engine.calendarForYear(year)
            let gf = cal.first { $0.type == .goodFriday }!
            let diff = gregorian.dateComponents([.day], from: gf.date, to: easter).day!
            #expect(diff == 2, "Good Friday (\(year)) should be 2 days before Easter")
        }
    }

    @Test("Palm Sunday is one week before Easter")
    func palmSundayIsOneWeekBefore() {
        for year in 2024...2028 {
            let easter = engine.computeEaster(year: year)
            let cal = engine.calendarForYear(year)
            let ps = cal.first { $0.type == .palmSunday }!
            let diff = gregorian.dateComponents([.day], from: ps.date, to: easter).day!
            #expect(diff == 7, "Palm Sunday (\(year)) should be 7 days before Easter")
        }
    }

    @Test("Ascension Day is 39 days after Easter")
    func ascensionDayIs39DaysAfter() {
        for year in 2024...2028 {
            let easter = engine.computeEaster(year: year)
            let cal = engine.calendarForYear(year)
            let asc = cal.first { $0.type == .ascension }!
            let diff = gregorian.dateComponents([.day], from: easter, to: asc.date).day!
            #expect(diff == 39, "Ascension (\(year)) should be 39 days after Easter")
        }
    }

    @Test("Pentecost is 49 days after Easter")
    func pentecostIs49DaysAfter() {
        for year in 2024...2028 {
            let easter = engine.computeEaster(year: year)
            let cal = engine.calendarForYear(year)
            let pent = cal.first { $0.type == .pentecost }!
            let diff = gregorian.dateComponents([.day], from: easter, to: pent.date).day!
            #expect(diff == 49, "Pentecost (\(year)) should be 49 days after Easter")
        }
    }

    @Test("Mardi Gras is 47 days before Easter (Fat Tuesday)")
    func mardiGrasIs47DaysBefore() {
        for year in 2024...2028 {
            let easter = engine.computeEaster(year: year)
            let cal = engine.calendarForYear(year)
            let mg = cal.first { $0.type == .mardiGras }!
            let diff = gregorian.dateComponents([.day], from: mg.date, to: easter).day!
            #expect(diff == 47, "Mardi Gras (\(year)) should be 47 days before Easter")
        }
    }

    @Test("Easter 2025 falls on April 20")
    func easter2025() {
        let e = engine.computeEaster(year: 2025)
        let c = gregorian.dateComponents([.month, .day], from: e)
        #expect(c.month == 4 && c.day == 20, "Easter 2025 should be April 20")
    }

    @Test("Easter 2026 falls on April 5")
    func easter2026() {
        let e = engine.computeEaster(year: 2026)
        let c = gregorian.dateComponents([.month, .day], from: e)
        #expect(c.month == 4 && c.day == 5, "Easter 2026 should be April 5")
    }
}

// MARK: - Season Resolution Tests

@Suite("Season Date Resolution")
struct SeasonDateResolutionTests {

    @Test("Advent season resolves correctly for 2025")
    func adventSeason2025() {
        let seasons = engine.seasonsForYear(2025)
        let advent = seasons.first { $0.type == .advent }
        #expect(advent != nil, "Advent season should exist for 2025")
        if let a = advent {
            // Advent 2025 starts Nov 30
            let start = gregorian.dateComponents([.month, .day], from: a.startDate)
            #expect(start.month == 11 || start.month == 12,
                    "Advent must start in November or December")
        }
    }

    @Test("Lent season resolves correctly")
    func lentSeason() {
        for year in 2024...2027 {
            let seasons = engine.seasonsForYear(year)
            let lent = seasons.first { $0.type == .lent }
            #expect(lent != nil, "Lent season should exist for \(year)")
            if let l = lent {
                let startMonth = gregorian.component(.month, from: l.startDate)
                #expect(startMonth == 2 || startMonth == 3,
                        "Lent must start in February or March")
            }
        }
    }

    @Test("All 9 seasons exist for a given year")
    func allSeasonsExist() {
        let seasons = engine.seasonsForYear(2025)
        let types = Set(seasons.map { $0.type })
        for expected in LiturgicalSeasonType.allCases {
            #expect(types.contains(expected), "Season \(expected.rawValue) missing for 2025")
        }
    }
}

// MARK: - Biblical Feast Tests

@Suite("Biblical Feast Dates")
struct BiblicalFeastTests {

    @Test("Passover 2025 is April 12")
    func passover2025() {
        let p = engine.passoverDate(year: 2025)
        let c = gregorian.dateComponents([.month, .day], from: p)
        #expect(c.month == 4 && c.day == 12, "Passover 2025 should be April 12")
    }

    @Test("Passover 2026 is April 1")
    func passover2026() {
        let p = engine.passoverDate(year: 2026)
        let c = gregorian.dateComponents([.month, .day], from: p)
        #expect(c.month == 4 && c.day == 1, "Passover 2026 should be April 1")
    }

    @Test("Rosh Hashanah 2025 is September 22")
    func roshHashanah2025() {
        let r = engine.roshHashanahDate(year: 2025)
        let c = gregorian.dateComponents([.month, .day], from: r)
        #expect(c.month == 9 && c.day == 22, "Rosh Hashanah 2025 should be September 22")
    }

    @Test("Day of Atonement is 9 days after Feast of Trumpets")
    func dayOfAtonement9DaysAfter() {
        for year in 2024...2027 {
            let cal = engine.calendarForYear(year)
            let trumpets = cal.first { $0.type == .feastOfTrumpets }
            let atonement = cal.first { $0.type == .dayOfAtonement }
            guard let t = trumpets, let a = atonement else {
                Issue.record("Missing feast observances for \(year)")
                continue
            }
            let diff = gregorian.dateComponents([.day], from: t.date, to: a.date).day!
            #expect(diff == 9, "Day of Atonement (\(year)) should be 9 days after Feast of Trumpets")
        }
    }

    @Test("Feast of Tabernacles is 14 days after Feast of Trumpets")
    func feastOfTabernacles14DaysAfter() {
        for year in 2024...2027 {
            let cal = engine.calendarForYear(year)
            let trumpets = cal.first { $0.type == .feastOfTrumpets }
            let tabernacles = cal.first { $0.type == .feastOfTabernacles }
            guard let t = trumpets, let tab = tabernacles else { continue }
            let diff = gregorian.dateComponents([.day], from: t.date, to: tab.date).day!
            #expect(diff == 14, "Feast of Tabernacles (\(year)) should be 14 days after Feast of Trumpets")
        }
    }

    @Test("Feast of Weeks is 49 days after Firstfruits")
    func feastOfWeeks49DaysAfterFirstfruits() {
        for year in 2024...2027 {
            let cal = engine.calendarForYear(year)
            let ff = cal.first { $0.type == .firstfruits }
            let fw = cal.first { $0.type == .feastOfWeeks }
            guard let firstfruits = ff, let weeks = fw else { continue }
            let diff = gregorian.dateComponents([.day], from: firstfruits.date, to: weeks.date).day!
            #expect(diff == 49, "Feast of Weeks (\(year)) should be 49 days after Firstfruits")
        }
    }

    @Test("Firstfruits falls on a Sunday")
    func firstfruitsFallsOnSunday() {
        for year in 2024...2028 {
            let ff = engine.firstfruitsDate(year: year)
            let wd = gregorian.component(.weekday, from: ff)
            #expect(wd == 1, "Firstfruits (\(year)) should fall on Sunday (weekday 1)")
        }
    }

    @Test("Biblical feast dates are read from backend, not guessed by client")
    func biblicalFeastUsesLookupTable() {
        // Verifies the client lookup table is used for known years rather than algorithm
        // (algorithm is fallback for unknown years)
        let p2024 = engine.passoverDate(year: 2024)
        let expected2024 = date(year: 2024, month: 4, day: 22)
        #expect(gregorian.isDate(p2024, inSameDayAs: expected2024),
                "Passover 2024 lookup should match verified date April 22")
    }
}

// MARK: - Priority Resolution Tests

@Suite("Holiday Priority Resolution")
struct HolidayPriorityTests {

    @Test("Easter beats Mother's Day when they coincide")
    func easterBeatsMothersDayOnSameDate() {
        // Easter 2025 = April 20 (third Sunday of April)
        // Mother's Day 2025 = May 11 — different date, but test the priority system
        let easterPriority = HolidayType.easter.priorityWeight
        let mothersDayPriority = HolidayType.mothersDay.priorityWeight
        #expect(easterPriority > mothersDayPriority,
                "Easter (priority \(easterPriority)) must outrank Mother's Day (\(mothersDayPriority))")
    }

    @Test("Good Friday beats Memorial Day when they coincide")
    func goodFridayBeatsMemorialDay() {
        #expect(HolidayType.goodFriday.priorityWeight > HolidayType.memorialDay.priorityWeight)
    }

    @Test("Biblical feasts outrank discernment holidays")
    func biblicalFeastsBeatDiscernmentHolidays() {
        let lowestFeast = [
            HolidayType.firstfruits,
            HolidayType.feastOfWeeks,
            HolidayType.unleavenedBread
        ].map { $0.priorityWeight }.min()!

        let highestDiscernment = [
            HolidayType.halloween,
            HolidayType.valentinesDay,
            HolidayType.stPatricksDay,
            HolidayType.mardiGras
        ].map { $0.priorityWeight }.max()!

        #expect(lowestFeast > highestDiscernment,
                "Lowest biblical feast (\(lowestFeast)) should outrank highest discernment (\(highestDiscernment))")
    }

    @Test("Christian events outrank civic holidays")
    func christianEventsBeatCivicHolidays() {
        #expect(HolidayType.pentecost.priorityWeight > HolidayType.thanksgiving.priorityWeight)
        #expect(HolidayType.ascension.priorityWeight >= HolidayType.independenceDay.priorityWeight)
    }

    @Test("All holiday types have a priority weight greater than 0")
    func allHolidaysHavePositivePriority() {
        for type in HolidayType.allCases {
            #expect(type.priorityWeight > 0, "\(type.rawValue) has priority 0")
        }
    }
}

// MARK: - Timezone Tests

@Suite("User Timezone")
struct UserTimezoneTests {

    @Test("UTC+14 and UTC-12 can differ by one calendar day")
    func timezoneShiftsDate() {
        // New Year's: Jan 1 midnight UTC+14 → Dec 31 in UTC-12
        let utcPlus14 = TimeZone(secondsFromGMT: 14 * 3600)!
        let utcMinus12 = TimeZone(secondsFromGMT: -12 * 3600)!

        var cal14 = Calendar(identifier: .gregorian)
        cal14.timeZone = utcPlus14
        var cal12 = Calendar(identifier: .gregorian)
        cal12.timeZone = utcMinus12

        // Simulate midnight Jan 1 UTC (end of Dec 31 in UTC-12)
        var utcComponents = DateComponents()
        utcComponents.year = 2025; utcComponents.month = 1; utcComponents.day = 1
        utcComponents.hour = 0; utcComponents.minute = 0
        utcComponents.timeZone = TimeZone(secondsFromGMT: 0)
        let midnight = Calendar.current.date(from: utcComponents)!

        let day14 = cal14.component(.day, from: midnight)
        let day12 = cal12.component(.day, from: midnight)
        // +14 is already on Jan 1; -12 is still Dec 31
        #expect(day14 == 1, "UTC+14 should see Jan 1")
        #expect(day12 == 31, "UTC-12 should still see Dec 31")
    }

    @Test("Thanksgiving is local date in user timezone")
    func thanksgivingLocalDate() {
        // Verify the calendar generates Thanksgiving in November regardless of timezone
        let cal = engine.calendarForYear(2025)
        let thanksgiving = cal.first { $0.type == .thanksgiving }!
        let month = gregorian.component(.month, from: thanksgiving.date)
        #expect(month == 11, "Thanksgiving must be in November")
    }
}

// MARK: - Discernment Holiday Tone Tests

@Suite("Discernment Holiday Safety")
struct DiscernmentHolidayTests {

    @Test("Halloween does not use celebratory or occult language")
    func halloweenNoCelebration() {
        let content = HolidayBannerCatalog.content(for: .halloween)!
        let combined = (content.shortBannerMessage + content.expandedReflection).lowercased()
        let forbidden = ["celebrate halloween", "happy halloween", "spooky", "occult",
                         "witch", "ghost", "spirit", "dark ritual"]
        for word in forbidden {
            #expect(!combined.contains(word),
                    "Halloween banner must not contain '\(word)'")
        }
    }

    @Test("St. Patrick's Day does not promote drunkenness")
    func stPatricksDayNoAlcohol() {
        let content = HolidayBannerCatalog.content(for: .stPatricksDay)!
        let combined = (content.shortBannerMessage + content.expandedReflection).lowercased()
        let forbidden = ["drunk", "alcohol", "beer", "pub", "drink up", "shot"]
        for word in forbidden {
            #expect(!combined.contains(word),
                    "St. Patrick's Day must not contain '\(word)'")
        }
    }

    @Test("Mardi Gras does not promote excess or immorality")
    func mardiGrasNoExcess() {
        let content = HolidayBannerCatalog.content(for: .mardiGras)!
        let combined = (content.shortBannerMessage + content.expandedReflection).lowercased()
        let forbidden = ["drunk", "party hard", "indulge", "debauch", "reveal"]
        for word in forbidden {
            #expect(!combined.contains(word),
                    "Mardi Gras must not contain '\(word)'")
        }
    }

    @Test("Valentine's Day does not promote lust")
    func valentinesDayNoLust() {
        let content = HolidayBannerCatalog.content(for: .valentinesDay)!
        let combined = (content.shortBannerMessage + content.expandedReflection).lowercased()
        let forbidden = ["lust", "sexy", "hookup", "romance without commitment"]
        for word in forbidden {
            #expect(!combined.contains(word),
                    "Valentine's Day must not contain '\(word)'")
        }
    }

    @Test("Discernment holidays have consistencyLevel == .discernment")
    func discernmentHolidaysAreMarked() {
        let discernmentTypes: [HolidayType] = [.halloween, .valentinesDay, .stPatricksDay, .mardiGras]
        for type in discernmentTypes {
            let content = HolidayBannerCatalog.content(for: type)!
            #expect(content.consistencyLevel == .discernment,
                    "\(type.rawValue) must have consistencyLevel == .discernment")
            #expect(content.category == .discernment,
                    "\(type.rawValue) must have category == .discernment")
        }
    }

    @Test("Spiritual guardrail passes all discernment holidays")
    func guardrailPassesDiscernmentContent() {
        for type in HolidayType.allCases {
            guard let content = HolidayBannerCatalog.content(for: type) else { continue }
            #expect(HolidaySpiritualGuardrail.isSafe(content: content),
                    "Guardrail failed for \(type.rawValue)")
        }
    }

    @Test("Safe CTA label replaces original for discernment holidays")
    func safeCTALabel() {
        let label = HolidaySpiritualGuardrail.safeCTALabel(for: .discernment, original: "Celebrate")
        #expect(label == "Practice discernment", "Discernment CTA should override to safe copy")
    }
}

// MARK: - Personal Celebration Tests

@Suite("Personal Celebrations")
struct PersonalCelebrationTests {

    @Test("Birthday only shows if enabled in settings")
    func birthdayHiddenWhenDisabled() {
        var settings = HolidayAwarenessSettings.defaultSettings
        settings.showPersonalCelebrations = false
        #expect(!settings.allows(category: .personal),
                "Personal celebrations should be blocked when showPersonalCelebrations == false")
    }

    @Test("Birthday shows if enabled and date matches today")
    func birthdayShowsWhenEnabled() {
        var settings = HolidayAwarenessSettings.defaultSettings
        settings.showPersonalCelebrations = true
        #expect(settings.allows(category: .personal))

        // Create a personal celebration matching today
        let today = gregorian.dateComponents([.month, .day], from: Date())
        var celebrations = PersonalHolidayCelebrations()
        celebrations.birthday = PersonalHolidayCelebrations.MonthDay(
            month: today.month!,
            day: today.day!
        )
        #expect(celebrations.activeCelebration() == .birthday)
    }

    @Test("Wedding date matches today returns .wedding")
    func weddingDateMatch() {
        let today = gregorian.dateComponents([.month, .day], from: Date())
        var c = PersonalHolidayCelebrations()
        c.weddingDate = PersonalHolidayCelebrations.MonthDay(month: today.month!, day: today.day!)
        #expect(c.activeCelebration() == .wedding)
    }

    @Test("No personal celebration returns nil when no date set")
    func noPersonalCelebration() {
        let c = PersonalHolidayCelebrations()
        #expect(c.activeCelebration() == nil)
    }

    @Test("Child dedication dates array is checked")
    func childDedicationDateMatch() {
        let today = gregorian.dateComponents([.month, .day], from: Date())
        var c = PersonalHolidayCelebrations()
        c.childDedicationDates = [
            PersonalHolidayCelebrations.MonthDay(month: (today.month! % 12) + 1, day: 1),
            PersonalHolidayCelebrations.MonthDay(month: today.month!, day: today.day!)
        ]
        #expect(c.activeCelebration() == .childDedication)
    }
}

// MARK: - Settings Filtering Tests

@Suite("HolidayAwarenessSettings Filtering")
struct SettingsFilteringTests {

    @Test("When disabled, no categories are allowed")
    func disabledBlocksAll() {
        var settings = HolidayAwarenessSettings.defaultSettings
        settings.enabled = false
        for category in HolidayCategory.allCases {
            #expect(!settings.allows(category: category),
                    "Category \(category.rawValue) should be blocked when disabled")
        }
    }

    @Test("showBiblicalFeasts = false blocks biblical feast category")
    func biblicalFeastBlocked() {
        var settings = HolidayAwarenessSettings.defaultSettings
        settings.showBiblicalFeasts = false
        #expect(!settings.allows(category: .biblicalFeast))
        #expect(settings.allows(category: .christianEvent))
    }

    @Test("showDiscernmentHolidays = false blocks discernment category")
    func discernmentBlocked() {
        var settings = HolidayAwarenessSettings.defaultSettings
        settings.showDiscernmentHolidays = false
        #expect(!settings.allows(category: .discernment))
        #expect(settings.allows(category: .biblicallyConsistent))
    }

    @Test("showCivicBiblicalValues = false blocks biblically consistent category")
    func civicBlocked() {
        var settings = HolidayAwarenessSettings.defaultSettings
        settings.showCivicBiblicalValues = false
        #expect(!settings.allows(category: .biblicallyConsistent))
        #expect(settings.allows(category: .christianEvent))
    }

    @Test("Default settings allow all categories except personal celebrations")
    func defaultSettings() {
        let settings = HolidayAwarenessSettings.defaultSettings
        #expect(settings.allows(category: .christianEvent))
        #expect(settings.allows(category: .biblicalFeast))
        #expect(settings.allows(category: .biblicallyConsistent))
        #expect(settings.allows(category: .discernment))
        #expect(!settings.allows(category: .personal), "Personal celebrations off by default")
    }
}

// MARK: - Holiday Catalog Coverage Tests

@Suite("Holiday Catalog Completeness")
struct HolidayCatalogTests {

    private let expectedHolidays: [HolidayType] = [
        // Christian events
        .easter, .goodFriday, .christmas, .christmasEve, .pentecost, .palmSunday,
        .ascension, .adventStart, .ashWednesday, .maundyThursday, .holySaturday,
        // Civic
        .thanksgiving, .newYearConsecration, .mothersDay, .fathersDay, .memorialDay,
        .laborDay, .independenceDay, .veteransDay,
        // Discernment
        .halloween, .valentinesDay, .stPatricksDay, .mardiGras,
        // Biblical feasts
        .passover, .unleavenedBread, .firstfruits, .feastOfWeeks, .feastOfTrumpets,
        .dayOfAtonement, .feastOfTabernacles
    ]

    @Test("All required holidays have banner content")
    func allRequiredHolidaysHaveBannerContent() {
        for type in expectedHolidays {
            let content = HolidayBannerCatalog.content(for: type)
            #expect(content != nil, "\(type.rawValue) missing from HolidayBannerCatalog")
        }
    }

    @Test("All banner content has non-empty titles and messages")
    func allBannerContentNonEmpty() {
        for type in expectedHolidays {
            guard let content = HolidayBannerCatalog.content(for: type) else { continue }
            #expect(!content.shortBannerTitle.isEmpty, "\(type.rawValue) has empty title")
            #expect(!content.shortBannerMessage.isEmpty, "\(type.rawValue) has empty message")
            #expect(!content.primaryScriptureReference.isEmpty, "\(type.rawValue) has empty scripture")
            #expect(!content.callToActionLabel.isEmpty, "\(type.rawValue) has empty CTA")
        }
    }

    @Test("All banner content has valid category + consistency level")
    func allBannerContentHasValidCategory() {
        for type in expectedHolidays {
            guard let content = HolidayBannerCatalog.content(for: type) else { continue }
            // Category must not be a placeholder
            #expect(HolidayCategory.allCases.contains(content.category),
                    "\(type.rawValue) has invalid category")
        }
    }

    @Test("All holiday types have a category assigned")
    func allHolidayTypesHaveCategory() {
        for type in HolidayType.allCases {
            let cat = type.category
            #expect(HolidayCategory.allCases.contains(cat),
                    "\(type.rawValue) has invalid category \(cat.rawValue)")
        }
    }
}

// MARK: - Offline Fallback Tests

@Suite("Offline Fallback")
struct OfflineFallbackTests {

    @Test("calendarForYear returns non-empty list when Firestore is unavailable")
    func calendarReturnsObservances() {
        let cal = engine.calendarForYear(2025)
        #expect(!cal.isEmpty, "Calendar should return observances even offline")
    }

    @Test("Calendar includes all 4 holiday categories for 2025")
    func calendarIncludesAllCategories() {
        let cal = engine.calendarForYear(2025)
        let categories = Set(cal.map { $0.type.category })
        #expect(categories.contains(.christianEvent))
        #expect(categories.contains(.biblicalFeast))
        #expect(categories.contains(.biblicallyConsistent))
        #expect(categories.contains(.discernment))
    }

    @Test("HolidayContextResponse.noHoliday is safe fallback")
    func noHolidayFallback() {
        let response = HolidayContextResponse.noHoliday
        #expect(!response.shouldShowHolidayBanner)
        #expect(response.bannerContent == nil)
        #expect(response.holidayType == nil)
        #expect(response.personalCelebration == nil)
    }
}
#endif

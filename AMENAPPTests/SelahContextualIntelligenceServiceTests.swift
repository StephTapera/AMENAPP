import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

@Suite("SelahContextualIntelligenceService")
struct SelahContextualIntelligenceServiceTests {
    private let service = SelahContextualIntelligenceService()

    @Test("Advent creates a liturgical inline suggestion without extra permissions")
    func adventCreatesLiturgicalSuggestion() throws {
        let input = SelahContextualInput(
            now: try date(year: 2026, month: 12, day: 6, hour: 9),
            calendar: testCalendar()
        )
        let evaluation = service.evaluate(input: input)

        let suggestion = try #require(evaluation.suggestions.first { $0.feature == .liturgicalLayer })
        #expect(suggestion.surface == .inline)
        #expect(suggestion.title == "Advent")
        #expect(suggestion.scriptureRefs.contains("Isaiah 9:2-7"))
    }

    @Test("Sabbath mode suppresses non-rest contextual suggestions")
    func sabbathSuppressesNonRestSuggestions() throws {
        var settings = SelahContextualSettings()
        settings.chosenSabbathWeekday = 1
        let input = SelahContextualInput(
            now: try date(year: 2026, month: 12, day: 6, hour: 9),
            calendar: testCalendar(),
            signalConfidenceByFeature: [.sabbathRestMode: 0.9],
            recentReflectionText: "I need to slow down and pray through this.",
            recentScriptureRefs: ["Psalm 46:10"]
        )

        let evaluation = service.evaluate(input: input, settings: settings)

        #expect(evaluation.suggestions.contains { $0.feature == .sabbathRestMode })
        #expect(evaluation.suggestions.contains { $0.feature == .liturgicalLayer } == false)
        #expect(evaluation.suppressedFeatures[.liturgicalLayer] == .sabbathSilence)
        #expect(evaluation.suppressedFeatures[.reflectionActionLoop] == .sabbathSilence)
    }

    @Test("Missing permission suppresses sensitive and audio features")
    func missingPermissionSuppressesFeature() throws {
        let input = SelahContextualInput(
            now: try date(year: 2026, month: 7, day: 7, hour: 12),
            calendar: testCalendar(),
            signalConfidenceByFeature: [.stressAwareSurfacing: 0.99]
        )
        let evaluation = service.evaluate(input: input)

        #expect(evaluation.suppressedFeatures[.stressAwareSurfacing] == .permissionMissing)
    }

    @Test("Low confidence reflection stays silent")
    func lowConfidenceReflectionSuppresses() throws {
        let input = SelahContextualInput(
            now: try date(year: 2026, month: 7, day: 7, hour: 12),
            calendar: testCalendar(),
            signalConfidenceByFeature: [.reflectionActionLoop: 0.4],
            recentReflectionText: "This stood out to me.",
            recentScriptureRefs: ["James 1:22"]
        )
        let evaluation = service.evaluate(input: input)

        #expect(evaluation.suggestions.contains { $0.feature == .reflectionActionLoop } == false)
        #expect(evaluation.suppressedFeatures[.reflectionActionLoop] == .confidenceTooLow)
    }

    @Test("Cooldown suppresses repeated surfaces")
    func cooldownSuppressesRepeatedSurface() throws {
        let now = try date(year: 2026, month: 12, day: 6, hour: 9)
        var settings = SelahContextualSettings()
        settings.lastSurfaceAtByFeature[.liturgicalLayer] = now.addingTimeInterval(-30 * 60)
        settings.minimumMinutesBetweenSurfaces = 240
        let input = SelahContextualInput(now: now, calendar: testCalendar())

        let evaluation = service.evaluate(input: input, settings: settings)

        #expect(evaluation.suppressedFeatures[.liturgicalLayer] == .cooldownActive)
    }

    @Test("Phase one catalog contains the first mic-free Selah slice")
    func phaseOneCatalogContainsFirstSlice() {
        let phaseOne = Set(SelahContextualFeature.allCases.filter { $0.phase == .phaseOneMicFree })

        #expect(phaseOne.contains(.liturgicalLayer))
        #expect(phaseOne.contains(.sabbathRestMode))
        #expect(phaseOne.contains(.confidenceGatedSilence))
        #expect(phaseOne.contains(.reflectionActionLoop))
    }

    private func testCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int) throws -> Date {
        let calendar = testCalendar()
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        )
        return try #require(components.date)
    }
}

#endif

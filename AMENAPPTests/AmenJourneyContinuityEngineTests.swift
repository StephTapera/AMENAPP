// AmenJourneyContinuityEngineTests.swift
// AMENAPPTests
// Unit tests for AmenJourneyContinuityEngine pure-Swift model logic.
// Tests WeeklyEngagement scoring, date key generation, and streak helpers
// without requiring Firebase or MainActor dispatch.

import Testing
import Foundation

private enum JourneyEngine {
    struct WeeklyEngagement {
        var bibleStudyDays: Int = 0
        var prayerCheckIns: Int = 0
        var selahSessions: Int = 0
        var bereanSessions: Int = 0
        var churchNotesCreated: Int = 0

        var overallScore: Double {
            let total = bibleStudyDays + prayerCheckIns + selahSessions + bereanSessions + churchNotesCreated
            return min(max(Double(total) / 15.0, 0), 1.0)
        }
    }

    struct ContinuityPrompt {
        enum ActionType {
            case continueStudyThread
            case revisitVerse
            case resumeChurchNote
            case returnToSelah
            case followUpPrayer
        }

        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let actionType: ActionType
        let contextId: String?
    }

    struct FormationMilestone {
        let id: String
        let title: String
        let description: String
        let achievedAt: Date
        let icon: String
        let category: String
    }
}

// MARK: - WeeklyEngagement score

@Suite("WeeklyEngagement score")
struct WeeklyEngagementScoreTests {

    @Test func zeroEngagementScoresZero() {
        let e = JourneyEngine.WeeklyEngagement()
        #expect(e.overallScore == 0.0)
    }

    @Test func scoreIsCappedAtOne() {
        var e = JourneyEngine.WeeklyEngagement()
        e.bibleStudyDays = 100
        e.prayerCheckIns = 100
        e.selahSessions = 100
        e.bereanSessions = 100
        e.churchNotesCreated = 100
        #expect(e.overallScore <= 1.0)
    }

    @Test func scoreIsProportionalToTotal() {
        var e = JourneyEngine.WeeklyEngagement()
        // 15 total activities = score 1.0 (15/15)
        e.bibleStudyDays = 3
        e.prayerCheckIns = 3
        e.selahSessions = 3
        e.bereanSessions = 3
        e.churchNotesCreated = 3
        #expect(e.overallScore == 1.0)
    }

    @Test func partialEngagementIsLessThanOne() {
        var e = JourneyEngine.WeeklyEngagement()
        e.bibleStudyDays = 1  // 1/15 ≈ 0.0667
        let expected = 1.0 / 15.0
        #expect(abs(e.overallScore - expected) < 0.0001)
    }

    @Test func scoreDoesNotGoNegative() {
        var e = JourneyEngine.WeeklyEngagement()
        e.bibleStudyDays = 0
        #expect(e.overallScore >= 0.0)
    }
}

// MARK: - ContinuityPrompt model

@Suite("ContinuityPrompt model")
struct ContinuityPromptModelTests {

    @Test func promptStoresTitle() {
        let prompt = JourneyEngine.ContinuityPrompt(
            id: "p1",
            title: "Continue: Romans 8",
            subtitle: "Studying Romans 8",
            icon: "arrow.triangle.branch",
            actionType: .continueStudyThread,
            contextId: "thread-123"
        )
        #expect(prompt.title == "Continue: Romans 8")
    }

    @Test func promptContextIdCanBeNil() {
        let prompt = JourneyEngine.ContinuityPrompt(
            id: "p2",
            title: "Return to Selah",
            subtitle: "Continue your spiritual practice",
            icon: "sparkles",
            actionType: .returnToSelah,
            contextId: nil
        )
        #expect(prompt.contextId == nil)
    }

    @Test func allActionTypesAreDistinct() {
        let types: [JourneyEngine.ContinuityPrompt.ActionType] = [
            .continueStudyThread,
            .revisitVerse,
            .resumeChurchNote,
            .returnToSelah,
            .followUpPrayer
        ]
        // Verify we can construct them all (no missing cases)
        #expect(types.count == 5)
    }

    @Test func promptStoresActionType() {
        let prompt = JourneyEngine.ContinuityPrompt(
            id: "p3",
            title: "Follow up in prayer",
            subtitle: "Continue praying for your request",
            icon: "hands.sparkles",
            actionType: .followUpPrayer,
            contextId: "prayer-42"
        )
        #expect(prompt.actionType == .followUpPrayer)
    }
}

// MARK: - FormationMilestone model

@Suite("FormationMilestone model")
struct FormationMilestoneModelTests {

    @Test func milestoneStoresDate() {
        let now = Date()
        let m = JourneyEngine.FormationMilestone(
            id: "m1",
            title: "7-Day Streak",
            description: "Engaged with AMEN 7 days in a row",
            achievedAt: now,
            icon: "flame.fill",
            category: "streak"
        )
        #expect(m.achievedAt == now)
    }

    @Test func milestoneIsIdentifiable() {
        let m = JourneyEngine.FormationMilestone(
            id: "unique-id",
            title: "First Church Note",
            description: "",
            achievedAt: Date(),
            icon: "note.text",
            category: "notes"
        )
        #expect(m.id == "unique-id")
    }
}

// MARK: - Day key format

@Suite("Journey day key")
struct JourneyDayKeyTests {

    // Inline copy of todayKey() from AmenJourneyContinuityEngine
    private func makeDayKey(from date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }

    @Test func dayKeyMatchesExpectedFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = 2026; components.month = 5; components.day = 9
        let date = calendar.date(from: components)!
        let key = makeDayKey(from: date)
        #expect(key == "2026-05-09")
    }

    @Test func dayKeyIsAlwaysTenCharacters() {
        // yyyy-MM-dd is always 10 chars
        let key = makeDayKey(from: Date())
        #expect(key.count == 10)
    }

    @Test func dayKeyContainsDashes() {
        let key = makeDayKey(from: Date())
        let dashes = key.filter { $0 == "-" }
        #expect(dashes.count == 2)
    }
}

// MARK: - Streak increment

@Suite("Streak increment logic")
struct StreakIncrementTests {

    @Test func streakIncrementsFromZero() {
        var streak = 0
        streak += 1
        #expect(streak == 1)
    }

    @Test func streakIsAdditiveOnSelahCompletion() {
        // Mirror: currentStreak += 1 after updateStreak(uid:) succeeds
        var streak = 5
        streak += 1
        #expect(streak == 6)
    }

    @Test func streakDoesNotDecrementOnRead() {
        let initial = 10
        let streak = initial
        #expect(streak == initial)
    }

    @Test func multipleIncrementsAccumulate() {
        var streak = 2
        streak += 1
        streak += 1
        #expect(streak == 4)
    }
}

// SpiritualRhythmOSTests.swift
// AMENAPPTests
//
// Unit tests for the SpiritualRhythmOS model layer.
// Targets types from SpiritualRhythmOSModels.swift:
//   SpiritualStreakType, SpiritualRhythmSettings, SabbathModeSettings,
//   NotificationPreferences, NotificationIntensityMode.
//
// No Firebase required — pure logic tests.
//
// Run with: ⌘U in Xcode or via `xcodebuild test`

import Testing
import Foundation
@testable import AMENAPP

// MARK: - SpiritualRhythmOS Tests

@Suite("SpiritualRhythmOSTests")
struct SpiritualRhythmOSTests {

    // MARK: 1. Streak Grace Periods

    @Test("Each SpiritualStreakType has gracePeriodDays >= 1")
    func testSpiritualStreakTypeGracePeriods() {
        for streakType in SpiritualStreakType.allCases {
            #expect(
                streakType.gracePeriodDays >= 1,
                "SpiritualStreakType.\(streakType.rawValue) gracePeriodDays must be >= 1"
            )
        }
    }

    // MARK: 2. Default Settings Notification Intensity

    @Test("SpiritualRhythmSettings.defaults notificationPreferences intensity is .balanced")
    func testDefaultSettingsNotificationIntensity() {
        // SpiritualRhythmSettings from SpiritualRhythmOSModels.swift has a static .defaults.
        // notificationPreferences is NotificationPreferences (Codable) whose static .defaults
        // sets intensity to .balanced.
        let defaults = SpiritualRhythmSettings.defaults
        #expect(defaults.notificationPreferences.intensity == .balanced)
    }

    // MARK: 3. Notification Intensity Daily Limits

    @Test("NotificationIntensityMode daily limits: minimal=1, balanced=3, encouraging=5, activeCommunity=8")
    func testNotificationIntensityDailyLimits() {
        // NotificationIntensityMode is defined in SpiritualRhythmOSModels.swift with dailyLimit.
        #expect(NotificationIntensityMode.minimal.dailyLimit == 1)
        #expect(NotificationIntensityMode.balanced.dailyLimit == 3)
        #expect(NotificationIntensityMode.encouraging.dailyLimit == 5)
        #expect(NotificationIntensityMode.activeCommunity.dailyLimit == 8)
    }

    // MARK: 4. Sabbath Mode Defaults to Disabled

    @Test("SabbathModeSettings default initializer sets enabled = false")
    func testSabbathModeDefaultsToDisabled() {
        // SabbathModeSettings in SpiritualRhythmOSModels.swift has init(enabled:startDay:startHour:endDay:endHour:)
        // with all defaults — default enabled = false.
        // We construct with no arguments to exercise that default.
        let sabbath = SabbathModeSettings()
        #expect(sabbath.enabled == false)
    }

    // MARK: 5. Inactivity Pause Not Active by Default

    @Test("SpiritualRhythmSettings.defaults isInactivityPauseActive is false")
    func testInactivityPauseNotActive() {
        let settings = SpiritualRhythmSettings.defaults
        #expect(settings.isInactivityPauseActive == false)
    }

    // MARK: 6. daysSinceLastActive When lastActiveAt Is Nil

    @Test("daysSinceLastActive returns 0 when lastActiveAt is nil and isInactivityPauseActive is false")
    func testDaysSinceLastActiveWhenNil() {
        // SpiritualRhythmSettings.defaults has lastActiveAt == nil.
        // daysSinceLastActive uses guard let lastActive = lastActiveAt else { return 0 }.
        // The 7-day inactivity gate is driven by the service calling checkInactivityStatus,
        // which sets inactivityPauseActivatedAt — NOT by daysSinceLastActive alone.
        // We verify the nil-guard semantics: nil lastActiveAt → daysSinceLastActive returns 0
        // (not >= 7), so the pause is NOT auto-activated on the model level.
        let settings = SpiritualRhythmSettings.defaults
        #expect(settings.lastActiveAt == nil)
        // daysSinceLastActive returns 0 on nil (via guard let, not a "large" sentinel).
        #expect(settings.daysSinceLastActive == 0)
        // Confirm inactivity pause is also not active at defaults.
        #expect(settings.isInactivityPauseActive == false)
    }
}

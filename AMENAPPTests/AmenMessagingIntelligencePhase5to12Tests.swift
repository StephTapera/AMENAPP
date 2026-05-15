// AmenMessagingIntelligencePhase5to12Tests.swift
// AMENAPPTests
//
// Phase 5–12 coverage for the Messaging Intelligence system.
// Tests pure model contracts, pill eligibility logic, safety nudge behaviour,
// voice transcript state, and analytics event invariants.
// No Firebase emulator required — runs in app-hosted test process.

import Testing
import Foundation
@testable import AMENAPP

// MARK: — Phase 5: Smart Pill Type Model Contracts

@Suite("Phase 5 — Smart Pill Type Model Contracts")
struct SmartPillTypeModelTests {

    @Test("All pill types have non-empty labels")
    func allPillTypesHaveLabels() {
        for type in AmenSmartPillType.allCases {
            #expect(!type.label.isEmpty, "Pill \(type.rawValue) has empty label")
        }
    }

    @Test("All pill types have non-empty system images")
    func allPillTypesHaveSystemImages() {
        for type in AmenSmartPillType.allCases {
            #expect(!type.systemImage.isEmpty, "Pill \(type.rawValue) has empty systemImage")
        }
    }

    @Test("All pill types have non-empty accessibility hints")
    func allPillTypesHaveAccessibilityHints() {
        for type in AmenSmartPillType.allCases {
            #expect(!type.accessibilityHint.isEmpty, "Pill \(type.rawValue) has empty accessibilityHint")
        }
    }

    @Test("translate pill accessibility hint describes translation")
    func translatePillAccessibilityHint() {
        let hint = AmenSmartPillType.translate.accessibilityHint.lowercased()
        #expect(hint.contains("translat"), "translate pill hint should mention translation")
    }

    @Test("voiceTranscript pill accessibility hint describes transcript or voice")
    func voiceTranscriptPillAccessibilityHint() {
        let hint = AmenSmartPillType.voiceTranscript.accessibilityHint.lowercased()
        #expect(hint.contains("transcript") || hint.contains("voice"),
                "voiceTranscript hint should mention transcript or voice")
    }

    @Test("mediaActions pill accessibility hint describes media or actions")
    func mediaActionsPillAccessibilityHint() {
        let hint = AmenSmartPillType.mediaActions.accessibilityHint.lowercased()
        #expect(hint.contains("media") || hint.contains("action"),
                "mediaActions hint should mention media or actions")
    }
}

// MARK: — Phase 5: Smart Pill Descriptor Model Tests

@Suite("Phase 5 — Smart Pill Descriptor Model")
struct SmartPillDescriptorModelTests {

    @Test("Descriptor defaults to idle state when no state is provided")
    func descriptorDefaultsToIdleState() {
        let desc = AmenSmartPillDescriptor(type: .translate)
        #expect(desc.state == .idle)
    }

    @Test("Descriptor can be constructed with explicit non-idle state")
    func descriptorWithExplicitState() {
        let desc = AmenSmartPillDescriptor(type: .catchMeUp, state: .loading)
        #expect(desc.state == .loading)
        #expect(desc.type == .catchMeUp)
    }

    @Test("Two descriptors of the same type have different UUID identifiers")
    func descriptorsHaveUniqueIds() {
        let d1 = AmenSmartPillDescriptor(type: .translate)
        let d2 = AmenSmartPillDescriptor(type: .translate)
        #expect(d1.id != d2.id)
    }

    @Test("All pill states are equatable and distinct")
    func pillStatesAreDistinct() {
        let idle    = AmenSmartPillState.idle
        let loading = AmenSmartPillState.loading
        let active  = AmenSmartPillState.active
        let dis     = AmenSmartPillState.disabled
        #expect(idle    != loading)
        #expect(idle    != active)
        #expect(loading != dis)
    }
}

// MARK: — Phase 5: Eligibility Context — Translation Language Guard

@Suite("Phase 5 — Eligibility Context: Translation Language Guard")
struct TranslationLanguageGuardTests {

    private func makeContext(detectedLanguage: String?, userLanguageCode: String = "en") -> AmenSmartPillEligibilityContext {
        let msg = AppMessage(text: "hello", isFromCurrentUser: false, timestamp: Date(), senderId: "uid1")
        return AmenSmartPillEligibilityContext(
            conversationId: "conv-lang-test",
            messageCount: 5,
            unreadCount: 0,
            lastMessage: msg,
            selectedMessage: nil,
            userLanguageCode: userLanguageCode,
            isGroupConversation: false,
            detectedLanguage: detectedLanguage,
            hasVoiceMessage: false,
            hasMediaMessage: false,
            hasLongText: false,
            safetySignalPresent: false,
            transcriptAvailable: false,
            isNetworkAvailable: true
        )
    }

    @Test("detectedLanguage defaults to nil when not provided in context")
    func detectedLanguageDefaultsToNil() {
        let ctx = makeContext(detectedLanguage: nil)
        #expect(ctx.detectedLanguage == nil)
    }

    @Test("detectedLanguage is stored as provided")
    func detectedLanguageStoredCorrectly() {
        let ctx = makeContext(detectedLanguage: "es")
        #expect(ctx.detectedLanguage == "es")
    }
}

// MARK: — Phase 5: Priority Engine Structural Invariants

@Suite("Phase 5 — Priority Engine: Structural Invariants")
@MainActor
struct PriorityEngineInvariantTests {

    private func richContext() -> AmenSmartPillEligibilityContext {
        let msg = AppMessage(
            text: String(repeating: "x", count: 300),
            isFromCurrentUser: false,
            timestamp: Date(),
            senderId: "uid1"
        )
        return AmenSmartPillEligibilityContext(
            conversationId: "conv-rich",
            messageCount: 100,
            unreadCount: 50,
            lastMessage: msg,
            selectedMessage: msg,
            userLanguageCode: "en",
            isGroupConversation: true,
            detectedLanguage: "es",
            hasVoiceMessage: true,
            hasMediaMessage: true,
            hasLongText: true,
            safetySignalPresent: true,
            transcriptAvailable: true,
            isNetworkAvailable: true
        )
    }

    @Test("Priority engine returns at most 3 pills regardless of context richness")
    func engineCapsAtThreePills() {
        let pills = AmenSmartPillPriorityEngine.eligiblePills(
            for: richContext(),
            flags: AMENFeatureFlags.shared
        )
        #expect(pills.count <= 3, "Engine must never return more than 3 pills")
    }

    @Test("No translate pill when detectedLanguage matches userLanguageCode")
    func noTranslatePillWhenLanguageMatches() {
        let msg = AppMessage(text: "hello", isFromCurrentUser: false, timestamp: Date(), senderId: "uid1")
        let ctx = AmenSmartPillEligibilityContext(
            conversationId: "conv-match-lang",
            messageCount: 5,
            unreadCount: 0,
            lastMessage: msg,
            selectedMessage: nil,
            userLanguageCode: "en",
            isGroupConversation: false,
            detectedLanguage: "en",  // same → no translate needed
            hasVoiceMessage: false,
            hasMediaMessage: false,
            hasLongText: false,
            safetySignalPresent: false,
            transcriptAvailable: false,
            isNetworkAvailable: true
        )
        let pills = AmenSmartPillPriorityEngine.eligiblePills(for: ctx, flags: AMENFeatureFlags.shared)
        #expect(!pills.contains(where: { $0.type == .translate }),
                "No translate pill when detected language matches user language")
    }

    @Test("No translate pill when detectedLanguage is nil")
    func noTranslatePillWhenDetectedLanguageIsNil() {
        let msg = AppMessage(text: "hello", isFromCurrentUser: false, timestamp: Date(), senderId: "uid1")
        let ctx = AmenSmartPillEligibilityContext(
            conversationId: "conv-nil-lang",
            messageCount: 5,
            unreadCount: 0,
            lastMessage: msg,
            selectedMessage: nil,
            userLanguageCode: "en",
            isGroupConversation: false,
            detectedLanguage: nil,  // no detection → never translate
            hasVoiceMessage: false,
            hasMediaMessage: false,
            hasLongText: false,
            safetySignalPresent: false,
            transcriptAvailable: false,
            isNetworkAvailable: true
        )
        let pills = AmenSmartPillPriorityEngine.eligiblePills(for: ctx, flags: AMENFeatureFlags.shared)
        #expect(!pills.contains(where: { $0.type == .translate }),
                "No translate pill when detectedLanguage is nil")
    }

    @Test("CatchUp unread threshold constant is 15")
    func catchUpUnreadThresholdIs15() {
        #expect(AmenSmartPillPriorityEngine.catchUpUnreadThreshold == 15)
    }

    @Test("Long message char threshold constant is 200")
    func longMessageCharThresholdIs200() {
        #expect(AmenSmartPillPriorityEngine.longMessageCharThreshold == 200)
    }
}

// MARK: — Phase 7: Safety Nudge Context

@Suite("Phase 7 — Safety Nudge Context")
struct SafetyNudgeContextModelTests {

    @Test("softWarn nudge: canSendAnyway is true")
    func softWarnNudgeCanSendAnyway() {
        let ctx = AmenSafetyNudgeContext(
            warningMessage: "This message may come across as harsh.",
            messageText: "You are wrong.",
            canSendAnyway: true
        )
        #expect(ctx.canSendAnyway == true)
    }

    @Test("requireEdit nudge: canSendAnyway is false")
    func requireEditNudgeCannotSendAnyway() {
        let ctx = AmenSafetyNudgeContext(
            warningMessage: "This message contains prohibited content.",
            messageText: "...",
            canSendAnyway: false
        )
        #expect(ctx.canSendAnyway == false)
    }

    @Test("softWarn and requireEdit contexts are not equal when canSendAnyway differs")
    func nudgeContextsAreDistinctWhenCanSendAnywayDiffers() {
        let soft = AmenSafetyNudgeContext(warningMessage: "msg", messageText: "txt", canSendAnyway: true)
        let hard = AmenSafetyNudgeContext(warningMessage: "msg", messageText: "txt", canSendAnyway: false)
        #expect(soft != hard)
    }

    @Test("Safety nudge context preserves warningMessage and messageText")
    func nudgeContextPreservesFields() {
        let ctx = AmenSafetyNudgeContext(
            warningMessage: "Watch your tone.",
            messageText: "Original draft",
            canSendAnyway: true
        )
        #expect(ctx.warningMessage == "Watch your tone.")
        #expect(ctx.messageText == "Original draft")
    }
}

// MARK: — Phase 10: Voice Transcript Panel State

@Suite("Phase 10 — Voice Transcript Panel State")
struct VoiceTranscriptStateModelTests {

    @Test("AmenVoiceTranscriptState.unavailable is not .failed")
    func unavailableStateIsDistinctFromFailed() {
        let state = AmenVoiceTranscriptState.unavailable
        if case .failed = state {
            Issue.record("unavailable must not be .failed — honest 'not yet wired', not an error")
        }
    }

    @Test("AmenVoiceTranscriptState.succeeded carries its text payload")
    func succeededStateCarriesText() {
        let state = AmenVoiceTranscriptState.succeeded("He said: 'God is good'")
        if case .succeeded(let text) = state {
            #expect(text == "He said: 'God is good'")
        } else {
            Issue.record("Expected .succeeded state")
        }
    }

    @Test("Unavailable panel static message is non-empty and not error-framed")
    func unavailableMessageIsHonest() {
        let msg = AmenVoiceTranscriptPanel.unavailableMessage
        #expect(!msg.isEmpty)
        let lower = msg.lowercased()
        #expect(!lower.contains("error"), "Unavailable copy must not be framed as an error")
        #expect(!lower.contains("try again"), "Unavailable copy must not suggest retry — the feature isn't wired yet")
    }
}

// MARK: — Phase 12: Analytics Event Contracts

@Suite("Phase 12 — Messaging Analytics Event Contracts")
struct MessagingAnalyticsContractTests {

    @Test("All analytics events have non-empty raw values")
    func analyticsEventsHaveNonEmptyRawValues() {
        for event in AmenMessagingAnalyticsEvent.allCases {
            #expect(!event.rawValue.isEmpty, "Event \(event) has empty rawValue")
        }
    }

    @Test("All analytics event raw values are prefixed with msg_")
    func analyticsEventsPrefixedWithMsg() {
        for event in AmenMessagingAnalyticsEvent.allCases {
            #expect(event.rawValue.hasPrefix("msg_"),
                    "Event '\(event.rawValue)' must use msg_ prefix")
        }
    }

    @Test("No fake success events exist for stubbed save actions (NB-6 audit fix)")
    func noFakeSuccessEventsForStubs() {
        let rawValues = AmenMessagingAnalyticsEvent.allCases.map(\.rawValue)
        #expect(!rawValues.contains("msg_save_selah_succeeded"),
                "saveToSelahSucceeded must not exist — removed in NB-6 audit fix")
        #expect(!rawValues.contains("msg_add_church_notes_succeeded"),
                "addToChurchNotesSucceeded must not exist — removed in NB-6 audit fix")
        #expect(!rawValues.contains("msg_save_notes_succeeded"),
                "saveToNotesSucceeded must not exist — saveToNotes is always unavailable")
        #expect(!rawValues.contains("msg_remind_me_succeeded"),
                "remindMeSucceeded must not exist — remindMe is always unavailable")
    }
}

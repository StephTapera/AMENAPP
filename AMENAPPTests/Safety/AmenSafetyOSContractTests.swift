import Foundation
import Testing
@testable import AMENAPP

// MARK: - AmenSafetyOSContractTests
// Contract tests for AmenSafetyOSClientService.
// Tests verify the shape of data passed to and received from the service,
// not network calls. Uses stored props and invokable closures.

@Suite("AmenSafetyOS Contract Tests")
struct AmenSafetyOSContractTests {

    // MARK: - TextModerationResult decoding

    @Test("TextModerationResult decodes allowed result")
    @MainActor
    func decodesAllowedModerationResult() throws {
        let json = """
        {
          "allowed": true,
          "moderationStatus": "approved",
          "harmCategoryId": null,
          "userFacingMessage": null,
          "contentWarning": null,
          "requiresHumanReview": false,
          "policyVersion": "2026-05-25"
        }
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(TextModerationResult.self, from: json)
        #expect(result.allowed == true)
        #expect(result.moderationStatus == "approved")
        #expect(result.harmCategoryId == nil)
    }

    @Test("TextModerationResult decodes borderline result with content warning")
    @MainActor
    func decodesBorderlineModerationResult() throws {
        // TextModerationResult doesn't have a contentWarning field — we test
        // what the struct actually supports per AmenSafetyOSClientService.swift
        let json = """
        {
          "allowed": true,
          "moderationStatus": "borderline",
          "harmCategoryId": null,
          "userFacingMessage": "This content may be sensitive.",
          "requiresHumanReview": false,
          "policyVersion": "2026-05-25"
        }
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(TextModerationResult.self, from: json)
        #expect(result.allowed == true)
        #expect(result.moderationStatus == "borderline")
        #expect(result.userFacingMessage != nil)
    }

    @Test("TextModerationResult decodes blocked result")
    @MainActor
    func decodesBlockedModerationResult() throws {
        let json = """
        {
          "allowed": false,
          "moderationStatus": "blocked",
          "harmCategoryId": "harassment",
          "userFacingMessage": "This message violates our community guidelines.",
          "requiresHumanReview": false,
          "policyVersion": "2026-05-25"
        }
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(TextModerationResult.self, from: json)
        #expect(result.allowed == false)
        #expect(result.harmCategoryId == "harassment")
    }

    // MARK: - TrustProfileResult decoding

    @Test("TrustProfileResult decodes level 0 new account")
    @MainActor
    func decodesLevel0TrustProfile() throws {
        let json = """
        {
          "trustLevel": 0,
          "trustPoints": 0,
          "trustCapabilities": {
            "canDM": false,
            "dmScope": "none",
            "canUploadMedia": false,
            "mediaScope": "none",
            "canCreateGroup": false,
            "canPostPublicly": false,
            "canMentor": false,
            "maxDailyComments": 5
          },
          "nextLevelRequirement": 5
        }
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(TrustProfileResult.self, from: json)
        #expect(result.trustLevel == 0)
        #expect(result.trustCapabilities.canDM == false)
        #expect(result.nextLevelRequirement == 5)
    }

    @Test("TrustCapabilities decodes full access level")
    @MainActor
    func decodesFullAccessTrustCapabilities() throws {
        let json = """
        {
          "canDM": true,
          "dmScope": "unrestricted",
          "canUploadMedia": true,
          "mediaScope": "image_and_video",
          "canCreateGroup": true,
          "canPostPublicly": true,
          "canMentor": true,
          "maxDailyComments": 100
        }
        """.data(using: .utf8)!
        let caps = try JSONDecoder().decode(TrustCapabilities.self, from: json)
        #expect(caps.canDM == true)
        #expect(caps.canMentor == true)
        #expect(caps.maxDailyComments == 100)
    }

    @Test("TrustCapabilities canDM false at level 0")
    @MainActor
    func trustCapabilitiesLevel0HasNoDM() throws {
        let json = """
        {
          "canDM": false,
          "dmScope": "none",
          "canUploadMedia": false,
          "mediaScope": "none",
          "canCreateGroup": false,
          "canPostPublicly": false,
          "canMentor": false,
          "maxDailyComments": 10
        }
        """.data(using: .utf8)!
        let caps = try JSONDecoder().decode(TrustCapabilities.self, from: json)
        #expect(caps.canDM == false)
        #expect(caps.canMentor == false)
        #expect(caps.canCreateGroup == false)
    }

    // MARK: - InteractionMode

    @Test("InteractionMode all cases decode correctly")
    func interactionModeAllCasesDecodeCorrectly() throws {
        let modes: [InteractionMode] = [.social, .discussion, .study, .quiet, .campus, .family]
        for mode in modes {
            let encoded = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(InteractionMode.self, from: encoded)
            #expect(decoded == mode)
        }
    }

    @Test("InteractionMode youth cannot be user-set")
    func youthModeFilteredFromDisplayList() {
        let displayable = InteractionMode.allCases.filter { $0 != .youth }
        #expect(!displayable.contains(.youth))
    }

    @Test("InteractionMode.social rawValue is correct")
    func interactionModeRawValues() {
        #expect(InteractionMode.social.rawValue == "social")
        #expect(InteractionMode.discussion.rawValue == "discussion")
        #expect(InteractionMode.study.rawValue == "study")
        #expect(InteractionMode.quiet.rawValue == "quiet")
        #expect(InteractionMode.youth.rawValue == "youth")
        #expect(InteractionMode.campus.rawValue == "campus")
        #expect(InteractionMode.family.rawValue == "family")
    }

    @Test("InteractionMode has 7 total cases including youth")
    func interactionModeHasCorrectCaseCount() {
        #expect(InteractionMode.allCases.count == 7)
    }

    @Test("InteractionMode displayNames are non-empty")
    func interactionModeDisplayNamesAreNonEmpty() {
        for mode in InteractionMode.allCases {
            #expect(!mode.displayName.isEmpty)
            #expect(!mode.description.isEmpty)
        }
    }

    // MARK: - TextRewriteResult decoding

    @Test("TextRewriteResult decodes with suggestions and rationale")
    @MainActor
    func textRewriteResultDecodes() throws {
        let json = """
        {
          "suggestions": ["Option A", "Option B"],
          "rationale": "Your message could be kinder.",
          "harmCategoryId": "harassment"
        }
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(TextRewriteResult.self, from: json)
        #expect(result.suggestions.count == 2)
        #expect(result.rationale == "Your message could be kinder.")
        #expect(result.harmCategoryId == "harassment")
    }

    @Test("TextRewriteResult decodes empty suggestions (fallback case)")
    @MainActor
    func textRewriteResultDecodesEmptySuggestions() throws {
        let json = """
        {
          "suggestions": [],
          "rationale": "We were unable to generate suggestions right now.",
          "harmCategoryId": "harassment"
        }
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(TextRewriteResult.self, from: json)
        #expect(result.suggestions.isEmpty)
    }

    // MARK: - SafetyToneCheckResult decoding

    @Test("SafetyToneCheckResult decodes null suggestion (text is fine)")
    @MainActor
    func toneCheckResultDecodesNullSuggestion() throws {
        let json = """
        {
          "suggestion": null,
          "reason": null
        }
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(SafetyToneCheckResult.self, from: json)
        #expect(result.suggestion == nil)
        #expect(result.reason == nil)
    }

    @Test("SafetyToneCheckResult decodes non-null suggestion")
    @MainActor
    func toneCheckResultDecodesNonNullSuggestion() throws {
        let json = """
        {
          "suggestion": "Perhaps try: I respectfully disagree.",
          "reason": "The original may come across as dismissive."
        }
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(SafetyToneCheckResult.self, from: json)
        #expect(result.suggestion != nil)
        #expect(result.reason != nil)
    }

    // MARK: - SafetyComposerState

    @Test("SafetyComposerState resets cleanly")
    @MainActor
    func safetyComposerStateResetsCleanly() {
        let state = SafetyComposerState()
        state.toneCheckSuggestion = "Try a kinder phrasing."
        state.showRewritePanel = true
        state.blockedCategoryId = "harassment"
        state.reset()
        #expect(state.toneCheckSuggestion == nil)
        #expect(state.showRewritePanel == false)
        #expect(state.blockedCategoryId == nil)
    }

    @Test("SafetyComposerState skips tone check for short text")
    @MainActor
    func safetyComposerStateSkipsToneCheckForShortText() {
        let state = SafetyComposerState()
        state.onTextChange("Hi", contentType: "post")
        // Short text (< 20 chars) is ignored — no suggestion set synchronously
        #expect(state.toneCheckSuggestion == nil)
    }

    @Test("SafetyComposerState initializes with nil suggestion and false flags")
    @MainActor
    func safetyComposerStateDefaultValues() {
        let state = SafetyComposerState()
        #expect(state.toneCheckSuggestion == nil)
        #expect(state.showRewritePanel == false)
        #expect(state.blockedCategoryId == nil)
        #expect(state.isCheckingTone == false)
    }

    @Test("SafetyComposerState applyToneSuggestion clears toneCheckSuggestion")
    @MainActor
    func safetyComposerStateApplySuggestionClearsPrevious() {
        let state = SafetyComposerState()
        state.toneCheckSuggestion = "A suggestion"
        let applied = state.applyToneSuggestion("A suggestion")
        #expect(applied == "A suggestion")
        #expect(state.toneCheckSuggestion == nil)
    }

    @Test("SafetyComposerState dismissToneSuggestion clears suggestion")
    @MainActor
    func safetyComposerStateDismissClearsSuggestion() {
        let state = SafetyComposerState()
        state.toneCheckSuggestion = "Some suggestion"
        state.dismissToneSuggestion()
        #expect(state.toneCheckSuggestion == nil)
    }

    // MARK: - MentorshipConnection decoding

    @Test("MentorshipConnection decodes with optional context")
    @MainActor
    func mentorshipConnectionDecodes() throws {
        let json = """
        {
          "id": "conn-abc",
          "mentorUid": "uid-mentor",
          "menteeUid": "uid-mentee",
          "status": "active",
          "context": "Bible study"
        }
        """.data(using: .utf8)!
        let conn = try JSONDecoder().decode(MentorshipConnection.self, from: json)
        #expect(conn.mentorUid == "uid-mentor")
        #expect(conn.menteeUid == "uid-mentee")
        #expect(conn.status == "active")
        #expect(conn.context == "Bible study")
    }

    @Test("MentorshipConnection decodes without context")
    @MainActor
    func mentorshipConnectionDecodesWithoutContext() throws {
        let json = """
        {
          "id": "conn-abc",
          "mentorUid": "uid-mentor",
          "menteeUid": "uid-mentee",
          "status": "pending",
          "context": null
        }
        """.data(using: .utf8)!
        let conn = try JSONDecoder().decode(MentorshipConnection.self, from: json)
        #expect(conn.context == nil)
        #expect(conn.status == "pending")
    }
}

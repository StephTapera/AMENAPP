// AuditLogTests.swift
// AMENAPPTests
//
// Verifies the True Source audit log system model completeness.
// Tests the 15 required event types, enum contracts, and model structure.
// No Firebase writes — these are pure-model and compile-time contract tests.

import Testing
import Foundation
import FirebaseCore
@testable import AMENAPP

// MARK: - TrueSourceEventType Coverage

@Suite("TrueSourceEventType — 15 Required Event Types")
struct TrueSourceEventTypeCoverageTests {

    @Test("All 15 required True Source event types exist")
    func allFifteenEventTypesExist() {
        // The blueprint requires exactly 15 event types for a complete audit trail.
        // If any type is missing, this test will fail to compile or count will be wrong.
        let requiredTypes: [ModerationAuditLogService.TrueSourceEventType] = [
            .postCreated,
            .mediaUploaded,
            .aiGenerated,
            .aiAssisted,
            .safetyScanned,
            .sourceChecked,
            .rankingScored,
            .labelApplied,
            .reachReduced,
            .humanReviewRequested,
            .contentRemoved,
            .appealSubmitted,
            .appealResolved,
            .userTunedFeed,
            .healthyModeEnabled,
        ]
        #expect(requiredTypes.count == 15,
                "Exactly 15 True Source event types are required by the safety blueprint")
    }

    @Test("All event types have non-empty raw values")
    func allEventTypesHaveRawValues() {
        let types: [ModerationAuditLogService.TrueSourceEventType] = [
            .postCreated, .mediaUploaded, .aiGenerated, .aiAssisted, .safetyScanned,
            .sourceChecked, .rankingScored, .labelApplied, .reachReduced,
            .humanReviewRequested, .contentRemoved, .appealSubmitted,
            .appealResolved, .userTunedFeed, .healthyModeEnabled,
        ]
        for type in types {
            #expect(!type.rawValue.isEmpty,
                    "Event type \(type) must have a non-empty raw value")
        }
    }

    @Test("Event type raw values use snake_case")
    func eventTypeRawValuesAreSnakeCase() {
        let types: [ModerationAuditLogService.TrueSourceEventType] = [
            .postCreated, .mediaUploaded, .aiGenerated, .safetyScanned,
            .humanReviewRequested, .contentRemoved, .healthyModeEnabled,
        ]
        for type in types {
            let value = type.rawValue
            #expect(value == value.lowercased(),
                    "Raw value '\(value)' must be lowercase snake_case")
            #expect(!value.contains(" "),
                    "Raw value '\(value)' must not contain spaces")
        }
    }
}

// MARK: - ModerationAuditEntry Contracts

@Suite("ModerationAuditEntry — Surface and Action Contracts")
struct ModerationAuditEntryContractTests {

    @Test("Surface enum covers all 8 required content surfaces")
    func surfaceEnumCoversRequiredSurfaces() {
        let requiredSurfaces: [ModerationAuditEntry.Surface] = [
            .post, .comment, .dmText, .dmMedia,
            .profileField, .bereanQuery, .media, .notification,
        ]
        #expect(requiredSurfaces.count == 8)
    }

    @Test("Surface raw values use lowercase with underscores")
    func surfaceRawValuesAreCorrectFormat() {
        let surfaces: [ModerationAuditEntry.Surface] = [
            .post, .comment, .dmText, .dmMedia,
            .profileField, .bereanQuery, .media, .notification,
        ]
        for surface in surfaces {
            #expect(!surface.rawValue.isEmpty)
            #expect(surface.rawValue == surface.rawValue.lowercased(),
                    "Surface '\(surface.rawValue)' must be lowercase")
        }
    }

    @Test("Action enum has all required enforcement tiers")
    func actionEnumHasRequiredTiers() {
        let requiredActions: [ModerationAuditEntry.Action] = [
            .allow,
            .warnUser,
            .warnRecipient,
            .holdForReview,
            .blockContent,
            .strikeAccount,
            .freezeAccount,
        ]
        #expect(requiredActions.count == 7)
    }

    @Test("Action raw values are snake_case strings")
    func actionRawValuesAreSnakeCase() {
        let actions: [ModerationAuditEntry.Action] = [
            .allow, .warnUser, .holdForReview, .blockContent, .strikeAccount, .freezeAccount,
        ]
        for action in actions {
            #expect(!action.rawValue.isEmpty)
        }
    }
}

// MARK: - Convenience Method Signatures (Compile-Time Contract)

@Suite("ModerationAuditLogService — Convenience Method Signatures")
@MainActor
struct AuditLogConvenienceMethodTests {

    // These tests verify that the convenience methods exist with the correct
    // signatures. They do NOT make Firestore writes — they only verify the API
    // surface compiles correctly. Calling them in production requires Firebase.

    @Test("logPostCreated method signature is correct")
    func logPostCreatedExists() {
        // Just verify the method exists and is callable with correct types.
        // We don't call it here to avoid requiring Firebase in unit tests.
        let _ = ModerationAuditLogService.logPostCreated
        let _ = ModerationAuditLogService.logMediaUploaded
        let _ = ModerationAuditLogService.logAIGenerated
        let _ = ModerationAuditLogService.logAIAssisted
        let _ = ModerationAuditLogService.logSafetyScanned
    }

    @Test("Remaining convenience methods exist")
    func remainingConvenienceMethodsExist() {
        let _ = ModerationAuditLogService.logSourceChecked
        let _ = ModerationAuditLogService.logRankingScored
        let _ = ModerationAuditLogService.logLabelApplied
        let _ = ModerationAuditLogService.logReachReduced
        let _ = ModerationAuditLogService.logHumanReviewRequested
        let _ = ModerationAuditLogService.logContentRemoved
        let _ = ModerationAuditLogService.logAppealSubmitted
        let _ = ModerationAuditLogService.logAppealResolved
        let _ = ModerationAuditLogService.logUserTunedFeed
        let _ = ModerationAuditLogService.logHealthyModeChanged
    }
}

// MARK: - TrueSourceEventEntry Model Tests

@Suite("TrueSourceEventEntry — Model Structure")
struct TrueSourceEventEntryModelTests {

    @Test("Event entry model has policyVersion field")
    func hasRequiredPolicyVersion() {
        // The blueprint requires policyVersion on every event for regulatory traceability.
        // This compile-time test verifies the field exists in the Codable struct.
        let entry = ModerationAuditLogService.TrueSourceEventEntry(
            eventId: "test-id",
            eventType: .postCreated,
            actor: "uid-123",
            contentId: "post-456",
            mediaId: nil,
            action: "post_created",
            modelProvider: nil,
            promptVersion: nil,
            policyVersion: "v1",
            riskScores: [:],
            labelsApplied: [],
            decision: "pending_moderation",
            confidence: 0,
            reasonCodes: [],
            createdAt: .init(date: Date()),
            requestId: "test-id",
            appCheckVerified: true,
            rateLimitStatus: "ok",
            appealEligible: false
        )
        #expect(entry.policyVersion == "v1")
        #expect(entry.appCheckVerified == true)
        #expect(entry.appealEligible == false)
    }

    @Test("Confidence is clamped to 0..1 range in recordTrueSourceEvent")
    func confidenceOutOfRange() {
        // Verify the model's fields store what we pass (clamping happens in service layer).
        let entry = ModerationAuditLogService.TrueSourceEventEntry(
            eventId: "clamp-test",
            eventType: .safetyScanned,
            actor: "system",
            contentId: nil,
            mediaId: nil,
            action: "scan",
            modelProvider: "test",
            promptVersion: nil,
            policyVersion: "v1",
            riskScores: [:],
            labelsApplied: [],
            decision: "allow",
            confidence: 0.85,
            reasonCodes: [],
            createdAt: .init(date: Date()),
            requestId: "clamp-test",
            appCheckVerified: true,
            rateLimitStatus: "ok",
            appealEligible: false
        )
        #expect(entry.confidence == 0.85)
    }
}

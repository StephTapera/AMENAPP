// VerificationUITests.swift
// AMENAPPTests — Verification & Trust System
//
// Contract tests for the Verification & Trust models.
// Uses Swift Testing (not XCTest). Tests cover model contracts,
// not UIHostingController accessibility-tree walks.

import Testing
import Foundation
@testable import AMENAPP

// MARK: - Badge Component Tests

@Suite("Verification Badge Components")
struct BadgeTests {

    // Every badge type must have a non-empty displayName.
    @Test func allBadgeTypesHaveNonEmptyDisplayName() {
        for type in VerificationBadgeType.allCases {
            #expect(!type.displayName.isEmpty,
                    "displayName must not be empty for \(type.rawValue)")
        }
    }

    // Every badge type must have a non-empty systemImage.
    @Test func allBadgeTypesHaveNonEmptySystemImage() {
        for type in VerificationBadgeType.allCases {
            #expect(!type.systemImage.isEmpty,
                    "systemImage must not be empty for \(type.rawValue)")
        }
    }

    // Every badge type must have a non-empty accessibilityLabel.
    @Test func allBadgeTypesHaveNonEmptyAccessibilityLabel() {
        for type in VerificationBadgeType.allCases {
            #expect(!type.accessibilityLabel.isEmpty,
                    "accessibilityLabel must not be empty for \(type.rawValue)")
        }
    }

    // Every badge type must have a non-empty explanationCopy.
    @Test func allBadgeTypesHaveNonEmptyExplanationCopy() {
        for type in VerificationBadgeType.allCases {
            #expect(!type.explanationCopy.isEmpty,
                    "explanationCopy must not be empty for \(type.rawValue)")
        }
    }

    // All badge type systemImages must be distinct — no two types share the same icon.
    @Test func allBadgeTypesHaveDistinctSystemImages() {
        let images = VerificationBadgeType.allCases.map { $0.systemImage }
        let unique = Set(images)
        #expect(unique.count == images.count,
                "Every VerificationBadgeType must have a unique systemImage; found duplicates")
    }
}

// MARK: - AmenRoleVerification Contract Tests

@Suite("Verification Center View")
struct CenterTests {

    // isActive returns true when status=approved, not expired, not revoked.
    @Test func roleIsActiveWhenApprovedAndNotExpired() {
        let role = AmenRoleVerification(
            id: "test1",
            role: "Pastor",
            status: .approved,
            scope: "congregation",
            issuedBy: "org1",
            organizationId: "org1",
            organizationName: "Grace Church",
            issuedAt: Date(),
            expiresAt: Date().addingTimeInterval(60 * 60 * 24 * 365), // 1 year from now
            revokedAt: nil,
            revokeReason: nil
        )
        #expect(role.isActive == true)
    }

    // isActive returns false for a revoked role (revokedAt is set but isActive uses status).
    // Revoked roles would have status .revoked, not .approved.
    @Test func roleIsNotActiveWhenRevoked() {
        let role = AmenRoleVerification(
            id: "test2",
            role: "Pastor",
            status: .revoked,
            scope: "congregation",
            issuedBy: "org1",
            organizationId: "org1",
            organizationName: "Grace Church",
            issuedAt: Date(),
            expiresAt: nil,
            revokedAt: Date(),
            revokeReason: "Removed from role"
        )
        #expect(role.isActive == false)
    }

    // isActive returns false when the expiry date is in the past.
    @Test func roleIsNotActiveWhenExpired() {
        let pastDate = Date().addingTimeInterval(-60 * 60 * 24) // 1 day ago
        let role = AmenRoleVerification(
            id: "test3",
            role: "Youth Leader",
            status: .approved,
            scope: "youth",
            issuedBy: "org1",
            organizationId: "org1",
            organizationName: nil,
            issuedAt: Date().addingTimeInterval(-60 * 60 * 24 * 30),
            expiresAt: pastDate,
            revokedAt: nil,
            revokeReason: nil
        )
        #expect(role.isActive == false)
    }

    // isActive returns false when status is .pending (not yet approved).
    @Test func roleIsNotActiveWhenPending() {
        let role = AmenRoleVerification(
            id: "test4",
            role: "Deacon",
            status: .pending,
            scope: "main campus",
            issuedBy: "org1",
            organizationId: "org1",
            organizationName: "Grace Church",
            issuedAt: Date(),
            expiresAt: nil,
            revokedAt: nil,
            revokeReason: nil
        )
        #expect(role.isActive == false)
    }

    // AmenVerificationSectionState.displayStatus returns "Verified" when isVerified=true and no past expiry.
    @Test func sectionStateDisplayStatusIsVerifiedWhenVerifiedAndNoExpiry() {
        let state = AmenVerificationSectionState(
            id: .identityVerified,
            isVerified: true,
            isEligible: true,
            hasPending: false,
            pendingRequest: nil,
            expiresAt: nil,
            canStart: false,
            actionLabel: "Reverify"
        )
        #expect(state.displayStatus == "Verified")
    }

    // AmenVerificationSectionState.displayStatus returns "Verified" when isVerified=true and expiry is future.
    @Test func sectionStateDisplayStatusIsVerifiedWhenExpiryIsFuture() {
        let futureDate = Date().addingTimeInterval(60 * 60 * 24 * 180) // 6 months from now
        let state = AmenVerificationSectionState(
            id: .identityVerified,
            isVerified: true,
            isEligible: true,
            hasPending: false,
            pendingRequest: nil,
            expiresAt: futureDate,
            canStart: false,
            actionLabel: "Reverify"
        )
        #expect(state.displayStatus == "Verified")
    }

    // AmenVerificationSectionState.displayStatus returns "Expired" when isVerified=true and expiresAt is past.
    @Test func sectionStateDisplayStatusIsExpiredWhenExpiryIsPast() {
        let pastDate = Date().addingTimeInterval(-60 * 60 * 24) // 1 day ago
        let state = AmenVerificationSectionState(
            id: .identityVerified,
            isVerified: true,
            isEligible: true,
            hasPending: false,
            pendingRequest: nil,
            expiresAt: pastDate,
            canStart: true,
            actionLabel: "Reverify"
        )
        #expect(state.displayStatus == "Expired")
    }

    // AmenVerificationSectionState.displayStatus contains pending info when hasPending=true.
    // The actual return value uses pendingRequest?.status.displayLabel, which for .pending is "Pending Review".
    @Test func sectionStateDisplayStatusIsPendingWhenHasPending() {
        let pendingRequest = AmenVerificationRequest(
            id: "req1",
            type: .identity,
            status: .pending,
            safeUserReason: nil,
            createdAt: Date(),
            updatedAt: Date(),
            expiresAt: nil
        )
        let state = AmenVerificationSectionState(
            id: .identityVerified,
            isVerified: false,
            isEligible: true,
            hasPending: true,
            pendingRequest: pendingRequest,
            expiresAt: nil,
            canStart: false,
            actionLabel: "View Status"
        )
        // When hasPending=true and request status is .pending, displayStatus uses the request's displayLabel
        #expect(state.displayStatus == pendingRequest.status.displayLabel)
        // The displayLabel for .pending is "Pending Review"
        #expect(state.displayStatus == "Pending Review")
    }

    // AmenPublicVerificationSummary.empty has all verification flags set to false.
    @Test func publicSummaryEmptyHasAllVerifiedFalse() {
        let empty = AmenPublicVerificationSummary.empty
        #expect(empty.emailVerified == false)
        #expect(empty.phoneVerified == false)
        #expect(empty.identityVerified == false)
        #expect(empty.creatorVerified == false)
    }

    // AmenPublicVerificationSummary.empty has active safety standing.
    @Test func publicSummaryEmptyHasActiveSafetyStanding() {
        let empty = AmenPublicVerificationSummary.empty
        #expect(empty.safetyStanding == .active)
    }

    // AmenPublicVerificationSummary.empty has no visible badges.
    @Test func publicSummaryEmptyHasNoVisibleBadges() {
        let empty = AmenPublicVerificationSummary.empty
        #expect(empty.visibleBadges.isEmpty)
    }

    @Test func miniProfileMapperReadsPublicVerificationSummary() {
        let model = UserProfileMiniMapper.model(
            from: [
                "userId": "user-1",
                "username": "pastor_maya",
                "displayName": "Maya Brooks",
                "publicVerificationSummary": [
                    "identityVerified": true,
                    "creatorVerified": true,
                    "safetyStanding": "active",
                    "visibleBadges": ["identity_verified", "creator_verified"]
                ]
            ],
            source: .discovery
        )

        #expect(model?.publicVerificationSummary.identityVerified == true)
        #expect(model?.publicVerificationSummary.creatorVerified == true)
        #expect(model?.publicVerificationSummary.visibleBadges.contains("identity_verified") == true)
    }
}

// MARK: - Feature Flag Gating Tests

@Suite("Feature Flag Gating")
struct FeatureFlagTests {

    // Legacy Covenant trust badges must not regress into a generic blue check model.
    @Test func legacyCreatorTrustBadgeUsesScopedCreatorSymbol() {
        #expect(TrustBadgeType.verifiedCreator.icon == "star.bubble.fill")
        #expect(TrustBadgeType.verifiedCreator.color == "orange")
    }

    @Test func legacyOrganizationTrustBadgeUsesScopedOrganizationSymbol() {
        #expect(TrustBadgeType.churchVerified.icon == "building.2.crop.circle.fill")
        #expect(TrustBadgeType.ministryVerified.icon == "person.badge.shield.checkmark.fill")
    }

    // VerificationBadgeType.rawValue is stable and non-empty for all cases.
    @Test func badgeTypeRawValuesAreNonEmpty() {
        for type in VerificationBadgeType.allCases {
            #expect(!type.rawValue.isEmpty,
                    "rawValue must not be empty for badge type \(type)")
        }
    }

    // VerificationBadgeType conforms to CaseIterable and has at least six cases.
    @Test func badgeTypeHasAtLeastSixCases() {
        #expect(VerificationBadgeType.allCases.count >= 6)
    }

    // AmenVerificationRequestStatus.pending is not terminal.
    @Test func pendingStatusIsNotTerminal() {
        #expect(AmenVerificationRequestStatus.pending.isTerminal == false)
    }

    // AmenVerificationRequestStatus.approved is terminal.
    @Test func approvedStatusIsTerminal() {
        #expect(AmenVerificationRequestStatus.approved.isTerminal == true)
    }

    // AmenVerificationRequestStatus.rejected is actionable (user can reapply).
    @Test func rejectedStatusIsActionable() {
        #expect(AmenVerificationRequestStatus.rejected.isActionable == true)
    }

    // AmenVerificationRequestStatus.approved is not actionable (no further action needed).
    @Test func approvedStatusIsNotActionable() {
        #expect(AmenVerificationRequestStatus.approved.isActionable == false)
    }

    // AmenSafetyStanding.active displayLabel is non-empty.
    @Test func safetyStandingActiveHasNonEmptyDisplayLabel() {
        #expect(!AmenSafetyStanding.active.displayLabel.isEmpty)
    }

    // All AmenSafetyStanding cases have non-empty display labels.
    @Test func allSafetyStandingCasesHaveNonEmptyDisplayLabel() {
        let cases: [AmenSafetyStanding] = [.active, .limited, .suspended, .underReview]
        for standing in cases {
            #expect(!standing.displayLabel.isEmpty,
                    "displayLabel must not be empty for \(standing.rawValue)")
        }
    }
}

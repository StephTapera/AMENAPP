// AmenVerificationAnalytics.swift
// AMENAPP — Verification & Trust System
//
// Privacy contract (applies to every method in this file):
//   LOG:    verification type strings ("identity", "organization", "role", "creator"),
//           role category labels (e.g. "Pastor"), badge type identifiers, event names.
//   NEVER LOG: legal names, government ID data, phone numbers, email addresses,
//           raw server payloads, reviewer notes, organization domain strings,
//           session tokens, session URLs, or any user-supplied free text.

import Foundation
import FirebaseAnalytics

struct AmenVerificationAnalytics {

    private init() {}

    // MARK: - Verification Center

    // Log only surface open. No user state, no verification status.
    static func verificationCenterOpened() {
        Analytics.logEvent("verification_center_opened", parameters: nil)
    }

    // MARK: - Verification Start

    // type: "identity" | "organization" | "role" | "creator" — NOT user PII.
    static func verificationStarted(type: String) {
        Analytics.logEvent("verification_started", parameters: [
            "verification_type": type
        ])
    }

    // MARK: - Identity Verification Funnel

    // Log identity lifecycle events. No session token, no identity data.
    static func identitySessionCreated() {
        Analytics.logEvent("identity_session_created", parameters: nil)
    }

    static func identityVerificationPending() {
        Analytics.logEvent("identity_verification_pending", parameters: nil)
    }

    static func identityVerificationApproved() {
        Analytics.logEvent("identity_verification_approved", parameters: nil)
    }

    static func identityVerificationRejected() {
        Analytics.logEvent("identity_verification_rejected", parameters: nil)
    }

    // MARK: - Organization Verification

    // No domain email, no org name, no domain string.
    static func organizationVerificationRequested() {
        Analytics.logEvent("organization_verification_requested", parameters: nil)
    }

    // MARK: - Role Verification

    // role: category label acceptable (e.g. "Pastor", "Deacon"). NOT name/email/phone.
    static func roleVerificationRequested(role: String) {
        Analytics.logEvent("role_verification_requested", parameters: [
            "role": role
        ])
    }

    static func roleVerificationApproved(role: String) {
        Analytics.logEvent("role_verification_approved", parameters: [
            "role": role
        ])
    }

    // No role label on revoke — avoids logging sensitive state transitions tied to a role.
    static func roleVerificationRevoked() {
        Analytics.logEvent("role_verification_revoked", parameters: nil)
    }

    // MARK: - Creator Verification

    static func creatorVerificationRequested() {
        Analytics.logEvent("creator_verification_requested", parameters: nil)
    }

    static func creatorVerificationApproved() {
        Analytics.logEvent("creator_verification_approved", parameters: nil)
    }

    static func creatorVerificationRejected() {
        Analytics.logEvent("creator_verification_rejected", parameters: nil)
    }

    // MARK: - Safety & Trust

    // No target UID, no report reason text.
    static func impersonationReportSubmitted() {
        Analytics.logEvent("impersonation_report_submitted", parameters: nil)
    }

    // MARK: - Badge Explainer

    // badgeType: VerificationBadgeType.rawValue — a stable enum string, not user data.
    static func badgeExplainerOpened(badgeType: String) {
        Analytics.logEvent("badge_explainer_opened", parameters: [
            "badge_type": badgeType
        ])
    }
}

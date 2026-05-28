// AmenAccessPassAnalytics.swift
// AMENAPP — Privacy-safe Access Pass Analytics
//
// Never logs: prayer content, private messages, note body, token, tokenHash, request messages.
// Safe to log: targetType, mode, verifiedHostBadge, status, appVersion, platform, broad reason code.

import Foundation
import FirebaseAnalytics

final class AmenAccessPassAnalytics {
    static let shared = AmenAccessPassAnalytics()
    private init() {}

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

    func logCreated(passId: String, targetType: AmenAccessTargetType, mode: AmenAccessMode, verifiedHostBadge: Bool) {
        Analytics.logEvent("access_pass_created", parameters: [
            "target_type": targetType.rawValue,
            "mode": mode.rawValue,
            "verified_host_badge": verifiedHostBadge,
            "app_version": appVersion,
            "platform": "ios"
        ])
    }

    func logResolved(passId: String, targetType: AmenAccessTargetType, mode: AmenAccessMode) {
        Analytics.logEvent("access_pass_resolved", parameters: [
            "target_type": targetType.rawValue,
            "mode": mode.rawValue,
            "app_version": appVersion,
            "platform": "ios"
        ])
    }

    func logPreviewed(passId: String, targetType: AmenAccessTargetType) {
        Analytics.logEvent("access_pass_previewed", parameters: [
            "target_type": targetType.rawValue,
            "app_version": appVersion
        ])
    }

    func logJoined(passId: String, targetType: AmenAccessTargetType) {
        Analytics.logEvent("access_pass_joined", parameters: [
            "target_type": targetType.rawValue,
            "app_version": appVersion
        ])
    }

    func logRequested(passId: String, targetType: AmenAccessTargetType) {
        Analytics.logEvent("access_pass_requested", parameters: [
            "target_type": targetType.rawValue,
            "app_version": appVersion
        ])
    }

    func logCheckedIn(passId: String, targetType: AmenAccessTargetType) {
        Analytics.logEvent("access_pass_checked_in", parameters: [
            "target_type": targetType.rawValue,
            "app_version": appVersion
        ])
    }

    func logDenied(passId: String, reason: String) {
        Analytics.logEvent("access_pass_denied", parameters: [
            "reason_code": reason,
            "app_version": appVersion
        ])
    }

    func logRevoked(passId: String, targetType: AmenAccessTargetType) {
        Analytics.logEvent("access_pass_revoked", parameters: [
            "target_type": targetType.rawValue,
            "app_version": appVersion
        ])
    }

    func logPaused(passId: String) {
        Analytics.logEvent("access_pass_paused", parameters: ["app_version": appVersion])
    }

    func logResumed(passId: String) {
        Analytics.logEvent("access_pass_resumed", parameters: ["app_version": appVersion])
    }

    func logTokenRotated(passId: String) {
        Analytics.logEvent("access_pass_token_rotated", parameters: ["app_version": appVersion])
    }

    func logRateLimited(passId: String) {
        Analytics.logEvent("access_pass_rate_limited", parameters: ["app_version": appVersion])
    }

    func logInvalid(passId: String) {
        Analytics.logEvent("access_pass_invalid", parameters: ["app_version": appVersion])
    }

    func logExpired(passId: String) {
        Analytics.logEvent("access_pass_expired", parameters: ["app_version": appVersion])
    }
}

// SettingsAuditClient.swift
// AMEN — Settings/Safety system · Foundation
//
// Client-side audit breadcrumb. The AUTHORITATIVE, append-only audit log is written
// SERVER-SIDE inside each S2 Cloud Function via the internal writeAuditLog (auditLogs/
// {uid}/events/{eventId}) — clients cannot write that collection (S3). This helper is a
// best-effort, categorical, fire-and-forget breadcrumb for UI-initiated actions and a
// local diagnostic trail. It NEVER throws to the caller and NEVER carries sensitive text.

import Foundation

enum SettingsAuditClient {

    /// Record a categorical audit breadcrumb for a Settings/Safety action.
    /// metadata must be categorical only (no free text) — it is funneled through the same
    /// sanitization as analytics.
    static func record(_ type: SettingsAuditEventType, metadata: [String: String] = [:]) {
        // Local diagnostic trail (categorical).
        dlog("[SettingsAudit] \(type.rawValue) \(metadata.keys.sorted().joined(separator: ","))")

        // Mirror as a categorical analytics signal where a canonical name exists; the
        // server-side writeAuditLog inside the corresponding callable remains the source of truth.
        if let name = analyticsName(for: type) {
            SettingsAnalytics.log(name, params: metadata)
        }
    }

    private static func analyticsName(for type: SettingsAuditEventType) -> AnalyticsEventName? {
        switch type {
        case .mfaChanged: return .mfaChanged
        case .sessionRevoked: return .sessionRevoked
        case .trustedContactChanged: return .trustedContactChanged
        case .familyLinkChanged: return .familyLinkChanged
        case .issueReportSubmitted: return .issueReportSubmitted
        case .dataExportRequested: return .dataExportRequested
        case .accountDeletionRequested: return .accountDeletionRequested
        case .lockdownModeChanged, .parentalControlsChanged, .aiMemoryDeleted, .safetySettingChanged:
            return .settingToggled
        }
    }
}

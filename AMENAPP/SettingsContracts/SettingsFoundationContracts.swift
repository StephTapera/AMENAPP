import Foundation

enum SettingsFirestorePath {
    static func preferences(uid: String) -> String { "users/\(uid)/settings/preferences" }
    static func security(uid: String) -> String { "users/\(uid)/settings/security" }
    static func notifications(uid: String) -> String { "users/\(uid)/settings/notifications" }
    static func safety(uid: String) -> String { "users/\(uid)/settings/safety" }
    static func aiControls(uid: String) -> String { "users/\(uid)/settings/aiControls" }
    static func trustedContact(uid: String, id: String) -> String { "users/\(uid)/trustedContacts/\(id)" }
    static func familyLink(uid: String, id: String) -> String { "users/\(uid)/familyLinks/\(id)" }
    static func auditEvent(uid: String, eventId: String) -> String { "auditLogs/\(uid)/events/\(eventId)" }
    static func issueReport(id: String) -> String { "issueReports/\(id)" }
    static func moderationAction(id: String) -> String { "moderationActions/\(id)" }
    static func familyGroup(id: String) -> String { "familyGroups/\(id)" }
}

enum SettingsFeatureFlag: String, CaseIterable, Identifiable {
    case settingsV2 = "ff_settings_v2"
    case appearanceV2 = "ff_appearance_v2"
    case generalV2 = "ff_general_v2"
    case passkeys = "ff_passkeys"
    case mfaTotp = "ff_mfa_totp"
    case mfaSms = "ff_mfa_sms"
    case lockdownMode = "ff_lockdown_mode"
    case faceIDGate = "ff_face_id_gate"
    case sessions = "ff_sessions"
    case trustedContact = "ff_trusted_contact"
    case parentalControls = "ff_parental_controls"
    case familyLinking = "ff_family_linking"
    case notificationPrefsV2 = "ff_notification_prefs_v2"
    case storageManagement = "ff_storage_management"
    case dataExport = "ff_data_export"
    case accountDeletion = "ff_account_deletion"
    case aiMemoryDelete = "ff_ai_memory_delete"
    case bereanAIControls = "ff_berean_ai_controls"
    case amenSafetyControls = "ff_amen_safety_controls"
    case issueReporting = "ff_issue_reporting"

    var id: String { rawValue }
    var defaultValue: Bool { false }
}

enum SettingsFunctionContract {
    static let region = "us-east1"

    enum Callable: String, CaseIterable, Identifiable {
        case setMfaTotp
        case verifyMfaTotp
        case disableMfaTotp
        case setMfaSms
        case verifyMfaSms
        case disableMfaSms
        case listActiveSessions
        case revokeSession
        case revokeAllSessions
        case setLockdownMode
        case addTrustedContact
        case confirmTrustedContact
        case removeTrustedContact
        case requestFamilyLink
        case acceptFamilyLink
        case unlinkFamily
        case setParentalControls
        case submitIssueReport
        case requestDataExport
        case requestAccountDeletion
        case deleteAiMemory

        var id: String { rawValue }
    }

    enum Internal: String, CaseIterable, Identifiable {
        case writeAuditLog
        case stripSensitiveFields
        case notifyTrustedContact

        var id: String { rawValue }
    }
}

struct SettingAnalyticsEvent: Codable, Equatable {
    var name: AnalyticsEventName
    var params: [String: String]
}

enum AnalyticsEventName: String, Codable, CaseIterable, Identifiable {
    case settingsOpened = "settings_opened"
    case settingToggled = "setting_toggled"
    case pickerChanged = "picker_changed"
    case mfaChanged = "mfa_changed"
    case sessionRevoked = "session_revoked"
    case trustedContactChanged = "trusted_contact_changed"
    case familyLinkChanged = "family_link_changed"
    case issueReportSubmitted = "issue_report_submitted"
    case dataExportRequested = "data_export_requested"
    case accountDeletionRequested = "account_deletion_requested"

    var id: String { rawValue }
}

struct SettingsAuditEvent: Codable, Identifiable, Equatable {
    var eventId: String
    var uid: String
    var actorUid: String
    var type: SettingsAuditEventType
    var timestamp: Date
    var ip: String?
    var deviceId: String?
    var metadata: [String: String]
    var result: AuditEventResult

    var id: String { eventId }
}

enum SettingsAuditEventType: String, Codable, CaseIterable, Identifiable {
    case mfaChanged
    case sessionRevoked
    case lockdownModeChanged
    case trustedContactChanged
    case familyLinkChanged
    case parentalControlsChanged
    case issueReportSubmitted
    case dataExportRequested
    case accountDeletionRequested
    case aiMemoryDeleted
    case safetySettingChanged

    var id: String { rawValue }
}

enum AuditEventResult: String, Codable, CaseIterable, Identifiable {
    case succeeded
    case denied
    case failed
    case queued

    var id: String { rawValue }
}

struct SettingsSafetyInvariant: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var summary: String

    static let all: [SettingsSafetyInvariant] = [
        .init(id: "S1", title: "Safe defaults", summary: "New toggles default protective and rollout flags default off."),
        .init(id: "S2", title: "Server-authoritative sensitive ops", summary: "Sensitive account, family, and safety actions run through authenticated Cloud Functions and audit logs."),
        .init(id: "S3", title: "Ownership isolation", summary: "Users read and write only their own user subtree; server-owned queues deny client writes."),
        .init(id: "S4", title: "Guardian wall", summary: "Guardians see safety flags and controls, never private journals, prayers, DMs, or memory content."),
        .init(id: "S5", title: "No spiritual or clinical authority", summary: "Berean AI is never framed as clergy, therapist, counselor, or emergency responder."),
        .init(id: "S6", title: "No sensitive text in analytics", summary: "Analytics contains categorical metadata only."),
        .init(id: "S7", title: "Child-safety pipeline supremacy", summary: "NCMEC, CSAM hash matching, age gates, and COPPA VPC cannot be disabled by settings."),
        .init(id: "S8", title: "Destructive confirmation", summary: "Destructive actions confirm, and irreversible actions require secondary confirmation."),
        .init(id: "S9", title: "Theological humility", summary: "Sources, uncertainty labels, cross-checking, and alternatives are system-enforced."),
        .init(id: "S10", title: "E2EE respect", summary: "Encrypted exports decrypt client-side; the server never sees plaintext.")
    ]
}

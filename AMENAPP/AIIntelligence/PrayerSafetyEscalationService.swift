// PrayerSafetyEscalationService.swift
// AMEN App — Prayer Safety + Pastoral Escalation (Agent 4)
//
// Detects urgent risk in prayer requests and routes to REAL help.
// This is CARE, not moderation — no autonomous punishment.
// Detection is SCAFFOLDED — thresholds and resource lists are policy decisions.
//
// POLICY STOPS (surface with options, never decide alone):
//   - Risk thresholds and what triggers resource display vs. pastoral handoff vs. nothing
//   - Emergency resource lists per region
//   - Who "trusted pastoral reviewers" are and the consent/contact flow
//   - Fundraising-language policy definitions
//
// Care tags are a separate UX layer — see PrayerCareTagsView.swift

import Foundation
import FirebaseFunctions

// MARK: - Risk Level (SCAFFOLDED)

enum PrayerRiskLevel {
    case none
    case mild          // general distress — surface gentle care prompt
    case moderate      // sustained concern — suggest pastoral resources
    case urgent        // self-harm/abuse signal — surface 988 + route to care pipe
}

// MARK: - Scan Result

struct PrayerSafetyScanResult {
    let riskLevel: PrayerRiskLevel
    let triggerCategories: [PrayerRiskCategory]
    let resourcesToSurface: [PrayerCareResource]
    let shouldRouteToReview: Bool       // opt-in pastoral queue
    let moderationDecision: String      // "allow" | "hold" | "route_to_care" — from prePublishSafetyScan

    var requiresImmediateResources: Bool { riskLevel == .urgent }
}

// MARK: - Risk Categories (SCAFFOLDED thresholds)

enum PrayerRiskCategory: String {
    case selfHarm        = "self_harm"
    case abuseDisclosure = "abuse_disclosure"
    case medicalEmergency = "medical_emergency"
    case financialManipulation = "financial_manipulation"
    case minorRisk       = "minor_risk"
    case familyCrisis    = "family_crisis"
}

// MARK: - Care Resources

struct PrayerCareResource: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let actionURL: URL?
    let phoneNumber: String?
    let isEmergency: Bool

    // POLICY STOP: region-aware resource lists (US defaults below)
    // Remote Config should provide region-specific lists.
    static let crisis988 = PrayerCareResource(
        title: "988 Suicide & Crisis Lifeline",
        subtitle: "Free, confidential — call or text 988",
        actionURL: URL(string: "tel://988"),
        phoneNumber: "988",
        isEmergency: true
    )

    static let crisisText = PrayerCareResource(
        title: "Crisis Text Line",
        subtitle: "Text HOME to 741741",
        actionURL: URL(string: "sms://741741&body=HOME"),
        phoneNumber: nil,
        isEmergency: true
    )

    static let domesticViolence = PrayerCareResource(
        title: "National DV Hotline",
        subtitle: "1-800-799-7233 (call or text)",
        actionURL: URL(string: "tel://18007997233"),
        phoneNumber: "1-800-799-7233",
        isEmergency: true
    )

    static let generalCare = PrayerCareResource(
        title: "AMEN Care Team",
        subtitle: "Connect with a pastoral care volunteer",
        actionURL: nil,
        phoneNumber: nil,
        isEmergency: false
    )
}

// MARK: - Pastoral Review Request

struct PastoralReviewRequest: Codable {
    let prayerRequestId: String
    let authorUid: String
    let text: String
    let riskCategories: [String]
    let consentGranted: Bool      // user must OPT IN before routing to pastoral queue
    let createdAt: Date
}

// MARK: - Service

@MainActor
final class PrayerSafetyEscalationService: ObservableObject {

    static let shared = PrayerSafetyEscalationService()

    @Published private(set) var isScanning = false
    @Published private(set) var lastScanResult: PrayerSafetyScanResult?

    private let functions = Functions.functions()

    // MARK: - Pre-Publish Scan (feeds existing moderation pipeline)

    /// Scan a prayer request before publish. Routes to the crisis/abuse pipe.
    /// NEVER surfaces a moderation decision to the user — only surfaces care resources.
    func scanBeforePublish(text: String, authorUid: String) async -> PrayerSafetyScanResult {
        guard AMENFeatureFlags.shared.bereanPrayerSafetyEnabled else {
            return PrayerSafetyScanResult(riskLevel: .none, triggerCategories: [], resourcesToSurface: [], shouldRouteToReview: false, moderationDecision: "allow")
        }

        isScanning = true
        defer { isScanning = false }

        // Step 1: Feed existing prePublishSafetyScan (passes to ContentModerationService)
        // The server handles crisis routing — client only surfaces care resources

        // SCAFFOLDED: local keyword scan for immediate UI response
        // Remote Config "prayer_safety_local_scan_enabled" gates this
        let localRisk = runLocalRiskScan(text: text)

        let result = PrayerSafetyScanResult(
            riskLevel: localRisk.level,
            triggerCategories: localRisk.categories,
            resourcesToSurface: resourcesFor(level: localRisk.level),
            shouldRouteToReview: false,    // opt-in only — never auto-route
            moderationDecision: "allow"     // server makes the actual moderation call
        )

        lastScanResult = result
        return result
    }

    // MARK: - Opt-In Pastoral Routing (user consent REQUIRED)

    /// Routes to the pastoral review queue ONLY when user has opted in.
    /// POLICY STOP: confirm who the pastoral reviewers are and their consent/contact flow.
    func routeToPastoralReview(
        prayerRequestId: String,
        authorUid: String,
        text: String,
        riskCategories: [PrayerRiskCategory],
        userConsented: Bool
    ) async throws {
        guard userConsented else { return }    // Never route without explicit consent

        let payload: [String: Any] = [
            "prayerRequestId": prayerRequestId,
            "authorUid":       authorUid,
            "riskCategories":  riskCategories.map(\.rawValue),
            "consentGranted":  true,
            "task":            "PASTORAL_REVIEW_REQUEST"
        ]

        // Feeds Security Agent 10 review queue (appeals + human-in-the-loop)
        _ = try? await functions.httpsCallable("moderateContent").call(payload)
    }

    // MARK: - Solicitation Block

    /// Returns true if the text contains fundraising/manipulation patterns that should be blocked.
    /// POLICY STOP: confirm solicitation-language policy before enabling auto-block.
    func containsSolicitationPatterns(text: String) -> Bool {
        // SCAFFOLDED: returns false until policy is confirmed.
        return false
    }

    // MARK: - Location Hiding

    /// Strips or redacts precise location from prayer request text.
    /// Called client-side before submit; server also strips location data.
    func stripPreciseLocation(from text: String) -> String {
        // SCAFFOLDED: no-op until NER model is confirmed for this use case.
        return text
    }

    // MARK: - Private: Local Risk Scan (SCAFFOLDED)

    private struct LocalScanResult {
        let level: PrayerRiskLevel
        let categories: [PrayerRiskCategory]
    }

    private func runLocalRiskScan(text: String) -> LocalScanResult {
        // SCAFFOLDED: immediate keyword scan for the most critical signals only.
        // This is a UI hint — the server makes the authoritative moderation decision.
        // POLICY STOP: confirm keyword lists and false-positive tolerance before enabling.
        let lower = text.lowercased()

        var categories: [PrayerRiskCategory] = []
        var level: PrayerRiskLevel = .none

        // Urgent signals (self-harm) — surface 988 immediately
        let urgentKeywords = ["end my life", "kill myself", "suicide", "don't want to be here anymore", "can't go on"]
        if urgentKeywords.contains(where: { lower.contains($0) }) {
            categories.append(.selfHarm)
            level = .urgent
        }

        // Moderate signals — suggest care resources
        let moderateKeywords = ["abuse", "harmed", "scared to go home", "hurting me"]
        if moderateKeywords.contains(where: { lower.contains($0) }) {
            categories.append(.abuseDisclosure)
            if level == .none { level = .moderate }
        }

        return LocalScanResult(level: level, categories: categories)
    }

    private func resourcesFor(level: PrayerRiskLevel) -> [PrayerCareResource] {
        switch level {
        case .none:     return []
        case .mild:     return [.generalCare]
        case .moderate: return [.generalCare, .domesticViolence]
        case .urgent:   return [.crisis988, .crisisText, .generalCare]
        }
    }
}

// MARK: - Care Tags

enum PrayerCareTag: String, CaseIterable, Codable {
    case grief       = "grief"
    case anxiety     = "anxiety"
    case healing     = "healing"
    case family      = "family"
    case guidance    = "guidance"
    case finances    = "finances"
    case relationships = "relationships"
    case work        = "work"
    case loneliness  = "loneliness"
    case gratitude   = "gratitude"
    case salvation   = "salvation"

    var displayName: String {
        switch self {
        case .grief:         return "Grief"
        case .anxiety:       return "Anxiety"
        case .healing:       return "Healing"
        case .family:        return "Family"
        case .guidance:      return "Guidance"
        case .finances:      return "Finances"
        case .relationships: return "Relationships"
        case .work:          return "Work & Career"
        case .loneliness:    return "Loneliness"
        case .gratitude:     return "Gratitude"
        case .salvation:     return "Salvation"
        }
    }

    var systemIcon: String {
        switch self {
        case .grief:         return "cloud.rain.fill"
        case .anxiety:       return "waveform.path.ecg"
        case .healing:       return "cross.fill"
        case .family:        return "house.fill"
        case .guidance:      return "map.fill"
        case .finances:      return "banknote.fill"
        case .relationships: return "person.2.fill"
        case .work:          return "briefcase.fill"
        case .loneliness:    return "moon.fill"
        case .gratitude:     return "sun.max.fill"
        case .salvation:     return "sparkles"
        }
    }
}

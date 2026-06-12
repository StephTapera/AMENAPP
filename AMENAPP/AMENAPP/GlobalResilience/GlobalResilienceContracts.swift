// GlobalResilienceContracts.swift
// AMEN — Global Resilience System
// Contracts only. No business logic, no force unwraps. Import Foundation only.

import Foundation

// MARK: - Device & Network Enums

enum DeviceTier: String, Codable {
    case low
    case mid
    case high
}

enum NetworkClass: String, Codable {
    case offline
    case constrained
    case expensive
    case standard
    case fast
}

enum DataMode: String, Codable {
    case automatic
    case lowData
    case wifiOnlyMedia
    case standard
}

enum StorageTier: String, Codable {
    case critical
    case low
    case medium
    case ample
}

// MARK: - Outbox

enum OutboxStatus: String, Codable {
    case draft
    case pending
    case sent
    case delivered
    case synced
    case failed
}

// MARK: - Verification

enum VerificationTier: String, Codable {
    case none
    case person
    case leader
    case churchLinked
    case ministry
    case charityDonation
    case eventHost
}

// MARK: - Device Capability Profile

struct DeviceCapabilityProfile: Codable {
    /// Canonical platform string, e.g. "ios", "ipados", "visionos"
    let platform: String
    let deviceModel: String
    let deviceTier: DeviceTier
    let networkClass: NetworkClass
    let isConstrainedPath: Bool
    let isExpensivePath: Bool
    let lowPowerModeEnabled: Bool
    /// String representation of ProcessInfo.ThermalState, e.g. "nominal", "fair", "serious", "critical"
    let thermalState: String
    let storagePressure: StorageTier
    let dataMode: DataMode
    let preferredLanguages: [String]
    let sharedDeviceMode: Bool
    let updatedAt: Date
}

// MARK: - Trust Profile

struct TrustProfile: Codable {
    let userId: String
    let identityTier: VerificationTier
    /// 0.0–1.0
    let communityTrustScore: Double
    /// 0.0–1.0; higher = riskier
    let impersonationRiskScore: Double
    let donationPermission: Bool
    /// "low" | "medium" | "high" | "blocked"
    let dmRiskLevel: String
    let abuseReportsCount: Int
    let updatedAt: Date
}

// MARK: - Feed Ranking Signals

struct FeedRankingSignals: Codable {
    let postId: String
    /// 0.0–1.0
    let relationshipScore: Double
    let localRelevanceScore: Double
    let trustScore: Double
    let safetyScore: Double
    let contextCompletenessScore: Double
    let spiritualUsefulnessScore: Double
    let freshnessScore: Double
    let engagementScore: Double
    /// Higher = more viral risk; used to apply friction
    let viralityRiskScore: Double
    /// When true, client must show a friction sheet before full expansion
    let contextFrictionRequired: Bool
}

// MARK: - Language Metadata

struct ContentLanguageMetadata: Codable {
    let detectedLanguages: [String]
    let codeSwitch: Bool
    /// 0.0–1.0 detection confidence
    let confidence: Double
    let originalText: String
    /// keyed by BCP-47 locale tag, e.g. ["es": "Hola mundo"]
    let translatedVersions: [String: String]
}

struct LanguageProfile: Codable {
    /// BCP-47 primary locale
    let primary: String
    let secondaries: [String]
    let autoTranslate: Bool
    let showOriginal: Bool
}

// MARK: - Low Data Preview

struct LowDataPreview: Codable {
    let title: String
    let textPreview: String
    let thumbnailUrl: String?
    /// Estimated network cost to load the full item
    let estimatedDataKb: Int
}

// MARK: - Crisis Bulletin

struct CrisisBulletin: Codable, Identifiable {
    let id: String
    let title: String
    let bodyText: String
    /// "info" | "warning" | "critical" | "emergency"
    let severity: String
    /// ISO 3166-1 alpha-2 code or "global"
    let regionScope: String
    let expiresAt: Date
    /// When true only serve this bulletin to low-data-mode clients
    let lowDataOnly: Bool
    let publishedByOrgId: String
}

// MARK: - Locale Policy Pack

struct LocalePolicyPack: Codable {
    /// BCP-47 locale identifier
    let localeId: String
    let sensitiveTopics: [String]
    let escalationKeywords: [String]
    let humanReviewRequired: Bool
    /// 0.0–1.0; content scoring below this threshold triggers review
    let safetyThreshold: Double
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when DeviceCapabilityProfile is refreshed
    static let capabilityProfileChanged = Notification.Name("gr_capabilityProfileChanged")
    /// Posted when the user's DataMode changes
    static let dataModeChanged = Notification.Name("gr_dataModeChanged")
    /// Deep-link intent: open the device Data Access settings pane
    static let openDataAccessSettings = Notification.Name("gr_openDataAccessSettings")
    /// Intent: save the current content as a Church Note
    static let saveAsChurchNote = Notification.Name("gr_saveAsChurchNote")
    /// Intent: request server-side translation for a piece of content
    static let requestServerTranslation = Notification.Name("gr_requestServerTranslation")
    /// Posted when a queued outbox upload succeeds
    static let uploadCompleted = Notification.Name("gr_uploadCompleted")
    /// Posted when a queued outbox upload fails permanently
    static let uploadFailed = Notification.Name("gr_uploadFailed")
}

// MARK: - Feature Flag Keys

struct GRFlags {
    private init() {}

    static let globalResilienceEnabled = "gr_globalResilienceEnabled"
    static let lowDataModeEnabled = "gr_lowDataModeEnabled"
    static let offlineOutboxEnabled = "gr_offlineOutboxEnabled"
    static let adaptiveMediaEnabled = "gr_adaptiveMediaEnabled"
    static let voiceTranscriptEnabled = "gr_voiceTranscriptEnabled"
    static let autoTranslateEnabled = "gr_autoTranslateEnabled"
    static let sharedDevicePrivacyEnabled = "gr_sharedDevicePrivacyEnabled"
    static let localLanguagePolicyPacksEnabled = "gr_localLanguagePolicyPacksEnabled"
    static let antiScamTrustLayerEnabled = "gr_antiScamTrustLayerEnabled"
    static let verifiedDonationFlowEnabled = "gr_verifiedDonationFlowEnabled"
    static let crisisBulletinsEnabled = "gr_crisisBulletinsEnabled"
    static let constitutionalFeedRankingEnabled = "gr_constitutionalFeedRankingEnabled"
}

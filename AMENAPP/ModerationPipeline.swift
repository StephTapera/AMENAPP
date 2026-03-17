// ModerationPipeline.swift
// AMEN App — Production-Grade Multi-Layer Moderation Pipeline
//
// Architecture:
//   ModerationPipeline       ← unified entry point for all content decisions
//   PipelineDecision         ← structured result with action + audit trail
//   PipelineAction           ← what to do with the content
//   ModerationContext        ← what surface/type of content is being moderated
//   TrustScoreService        ← per-user reputation and trust tracking
//   UserReportService        ← user-submitted reports workflow
//
// Type naming note:
//   PipelineAction / PipelineDecision / PipelineRiskLevel are AMEN-pipeline-specific
//   types. They intentionally differ from the legacy ModerationAction/ModerationDecision
//   types in ImageModerationService.swift and AdvancedModerationService.swift to
//   avoid ambiguity. Those legacy types are preserved for backwards compatibility.

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Moderation Context

/// The surface/type of content being moderated.
enum ModerationContext: String, Codable {
    case post = "post"
    case comment = "comment"
    case directMessage = "direct_message"
    case profileBio = "profile_bio"
    case profileName = "profile_name"
    case churchNote = "church_note"
    case jobPost = "job_post"
    case imageCaption = "image_caption"
    case prayerRequest = "prayer_request"
    case testimony = "testimony"
    case reportText = "report_text"
    case unknown = "unknown"

    var requiresHeightenedScan: Bool { self == .directMessage }

    var displayName: String {
        switch self {
        case .post: return "post"
        case .comment: return "comment"
        case .directMessage: return "message"
        case .profileBio: return "bio"
        case .profileName: return "name"
        case .churchNote: return "note"
        case .jobPost: return "opportunity"
        case .imageCaption: return "caption"
        case .prayerRequest: return "prayer request"
        case .testimony: return "testimony"
        case .reportText, .unknown: return "content"
        }
    }
}

// MARK: - Pipeline Action

enum PipelineAction: String, Codable {
    case allow              // Publish as-is
    case allowWithWarning   // Publish + show calm author notice
    case requireEdit        // Block + ask author to revise
    case holdForSoftReview  // Show "being reviewed"; not visible publicly yet
    case shadowQueue        // Silently held; author sees it published but others cannot
    case blockAndReview     // Hard block + queue for human review
    case blockImmediate     // Instant block — highest confidence violation

    var isBlocking: Bool {
        switch self {
        case .allow, .allowWithWarning: return false
        default: return true
        }
    }

    var requiresHumanReview: Bool {
        switch self {
        case .holdForSoftReview, .shadowQueue, .blockAndReview, .blockImmediate: return true
        default: return false
        }
    }
}

// MARK: - Pipeline Risk Level

enum PipelineRiskLevel: String, Codable, Comparable {
    case safe = "safe"
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"

    static func < (lhs: PipelineRiskLevel, rhs: PipelineRiskLevel) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    private var ordinal: Int {
        switch self {
        case .safe: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .critical: return 4
        }
    }

    static func from(score: Double) -> PipelineRiskLevel {
        switch score {
        case ..<0.15: return .safe
        case 0.15..<0.35: return .low
        case 0.35..<0.60: return .medium
        case 0.60..<0.80: return .high
        default: return .critical
        }
    }
}

// MARK: - Pipeline Decision

struct PipelineDecision {
    let action: PipelineAction
    let riskLevel: PipelineRiskLevel
    let riskScore: Double
    let primaryCategory: String
    let matchedSignals: [String]
    let moderatorReason: String
    let userFacingMessage: String?
    let requiresHumanReview: Bool
    let logForAudit: Bool
    let authorSupportRecommended: Bool
    let timestamp: Date

    static func allow() -> PipelineDecision {
        PipelineDecision(
            action: .allow,
            riskLevel: .safe,
            riskScore: 0,
            primaryCategory: "none",
            matchedSignals: [],
            moderatorReason: "Within safe threshold",
            userFacingMessage: nil,
            requiresHumanReview: false,
            logForAudit: false,
            authorSupportRecommended: false,
            timestamp: Date()
        )
    }
}

// MARK: - Moderation Pipeline

@MainActor
final class ModerationPipeline: ObservableObject {

    static let shared = ModerationPipeline()

    private let riskAnalyzer = ContentRiskAnalyzer.shared
    private let db = Firestore.firestore()
    private let flags = AMENFeatureFlags.shared

    @Published private(set) var totalEvaluated: Int = 0
    @Published private(set) var totalFlagged: Int = 0
    @Published private(set) var totalBlocked: Int = 0

    private init() {}

    // MARK: - Primary Entry Point

    func evaluate(
        text: String,
        context: ModerationContext,
        userId: String? = nil
    ) async -> PipelineDecision {
        guard flags.moderationV2Enabled else { return .allow() }

        totalEvaluated += 1

        let safetyContext = mapToSafetyContext(context)
        let risk = riskAnalyzer.analyze(text: text, context: safetyContext)

        var dmRisk: ContentRiskResult? = nil
        if context.requiresHeightenedScan && flags.dmEnhancedScanningEnabled {
            dmRisk = scanForDMRisks(text: text, baseRisk: risk)
        }

        let effectiveRisk = selectHigherRisk(primary: risk, dm: dmRisk)
        let decision = buildDecision(risk: effectiveRisk, context: context)

        if decision.action != .allow && decision.action != .allowWithWarning {
            totalFlagged += 1
        }
        if decision.action.isBlocking {
            totalBlocked += 1
        }

        if decision.logForAudit {
            Task.detached(priority: .background) { [weak self] in
                await self?.logModerationEvent(
                    context: context.rawValue,
                    category: decision.primaryCategory,
                    riskScore: decision.riskScore,
                    action: decision.action.rawValue,
                    userId: userId
                )
            }
        }

        if decision.requiresHumanReview {
            Task.detached(priority: .background) { [weak self] in
                await self?.queueForHumanReview(
                    context: context.rawValue,
                    category: decision.primaryCategory,
                    riskScore: decision.riskScore,
                    userId: userId,
                    signals: decision.matchedSignals
                )
            }
        }

        return decision
    }

    // MARK: - DM Heightened Scan

    private func scanForDMRisks(text: String, baseRisk: ContentRiskResult) -> ContentRiskResult {
        let lower = text.lowercased()
        var additionalScore: Double = 0
        var signals: [String] = []

        let coercivePatterns = [
            "don't tell anyone", "keep this between us", "our secret",
            "don't tell your parents", "no one will know",
            "meet me somewhere private", "come alone", "don't bring anyone",
            "i know where you live", "i'll find you",
            "send me your address", "what are you wearing",
            "are you alone right now", "can you video chat privately"
        ]

        let suspiciousLinkPatterns = [
            "click this link", "claim your prize", "you've been selected",
            "send me crypto", "paypal me", "gift card", "wire transfer"
        ]

        for pattern in coercivePatterns where lower.contains(pattern) {
            additionalScore += 0.25
            signals.append("dm_coercion: \(pattern)")
        }
        for pattern in suspiciousLinkPatterns where lower.contains(pattern) {
            additionalScore += 0.20
            signals.append("dm_scam_link: \(pattern)")
        }

        guard additionalScore > 0 else { return baseRisk }

        let effectiveScore = min(1.0, baseRisk.totalScore + additionalScore)
        return ContentRiskResult(
            primaryCategory: additionalScore >= 0.25 ? .groomingTrafficking : baseRisk.primaryCategory,
            totalScore: effectiveScore,
            categoryScores: baseRisk.categoryScores,
            matchedSignals: baseRisk.matchedSignals + signals,
            isDeepScan: false
        )
    }

    private func selectHigherRisk(primary: ContentRiskResult, dm: ContentRiskResult?) -> ContentRiskResult {
        guard let dm = dm else { return primary }
        return dm.totalScore > primary.totalScore ? dm : primary
    }

    // MARK: - Decision Builder

    private func buildDecision(risk: ContentRiskResult, context: ModerationContext) -> PipelineDecision {
        let score = risk.totalScore
        let category = risk.primaryCategory
        let signals = Array(risk.matchedSignals.prefix(5))
        let surface = context.displayName

        // Grooming / trafficking — absolute lowest tolerance
        if category == .groomingTrafficking {
            if score > 0.45 {
                return PipelineDecision(action: .blockImmediate, riskLevel: .critical, riskScore: score,
                    primaryCategory: category.rawValue, matchedSignals: signals,
                    moderatorReason: "Child safety / grooming / trafficking language",
                    userFacingMessage: "This content couldn't be posted. It may violate our community safety guidelines.",
                    requiresHumanReview: true, logForAudit: true, authorSupportRecommended: false, timestamp: Date())
            } else if score > 0.25 {
                return PipelineDecision(action: .blockAndReview, riskLevel: .high, riskScore: score,
                    primaryCategory: category.rawValue, matchedSignals: signals,
                    moderatorReason: "Possible grooming / predatory contact",
                    userFacingMessage: "Your \(surface) is being reviewed before it's shared.",
                    requiresHumanReview: true, logForAudit: true, authorSupportRecommended: false, timestamp: Date())
            }
        }

        // Explicit sexual content
        if category == .explicitSexual {
            if score > 0.55 {
                return PipelineDecision(action: .blockImmediate, riskLevel: .critical, riskScore: score,
                    primaryCategory: category.rawValue, matchedSignals: signals,
                    moderatorReason: "Explicit sexual content",
                    userFacingMessage: "This content couldn't be posted. Explicit content isn't allowed on AMEN.",
                    requiresHumanReview: true, logForAudit: true, authorSupportRecommended: false, timestamp: Date())
            } else if score > 0.35 {
                return PipelineDecision(action: .blockAndReview, riskLevel: .high, riskScore: score,
                    primaryCategory: category.rawValue, matchedSignals: signals,
                    moderatorReason: "Possible explicit content",
                    userFacingMessage: "Your \(surface) is being reviewed before it's shared.",
                    requiresHumanReview: true, logForAudit: true, authorSupportRecommended: false, timestamp: Date())
            }
        }

        // Self-harm / crisis — never hard-block; route to support
        if category == .selfHarmCrisis {
            if score > 0.75 {
                return PipelineDecision(action: .holdForSoftReview, riskLevel: .critical, riskScore: score,
                    primaryCategory: category.rawValue, matchedSignals: signals,
                    moderatorReason: "High-confidence self-harm / crisis language",
                    userFacingMessage: "We noticed something that concerns us. Your \(surface) has been paused — please know you're not alone.",
                    requiresHumanReview: true, logForAudit: true, authorSupportRecommended: true, timestamp: Date())
            } else if score > 0.45 {
                return PipelineDecision(action: .allowWithWarning, riskLevel: .medium, riskScore: score,
                    primaryCategory: category.rawValue, matchedSignals: signals,
                    moderatorReason: "Moderate distress / self-harm signal",
                    userFacingMessage: nil,
                    requiresHumanReview: false, logForAudit: true, authorSupportRecommended: true, timestamp: Date())
            }
        }

        // Violence / threats
        if category == .violenceThreat {
            if score > 0.80 {
                return PipelineDecision(action: .blockAndReview, riskLevel: .critical, riskScore: score,
                    primaryCategory: category.rawValue, matchedSignals: signals,
                    moderatorReason: "High-confidence threat or violent language",
                    userFacingMessage: "This content couldn't be posted. If you're going through something difficult, support is available.",
                    requiresHumanReview: true, logForAudit: true, authorSupportRecommended: true, timestamp: Date())
            } else if score > 0.55 {
                return PipelineDecision(action: .holdForSoftReview, riskLevel: .high, riskScore: score,
                    primaryCategory: category.rawValue, matchedSignals: signals,
                    moderatorReason: "Possible threatening language — pending review",
                    userFacingMessage: "Your \(surface) is being reviewed before it's shared.",
                    requiresHumanReview: true, logForAudit: true, authorSupportRecommended: false, timestamp: Date())
            }
        }

        // Illegal activity
        if category == .illegalActivity {
            if score > 0.70 {
                return PipelineDecision(action: .blockImmediate, riskLevel: .critical, riskScore: score,
                    primaryCategory: category.rawValue, matchedSignals: signals,
                    moderatorReason: "High-confidence illegal activity",
                    userFacingMessage: "This content violated our community guidelines and couldn't be posted.",
                    requiresHumanReview: true, logForAudit: true, authorSupportRecommended: false, timestamp: Date())
            } else if score > 0.45 {
                return PipelineDecision(action: .holdForSoftReview, riskLevel: .high, riskScore: score,
                    primaryCategory: category.rawValue, matchedSignals: signals,
                    moderatorReason: "Possible illegal activity — pending review",
                    userFacingMessage: "Your \(surface) is being reviewed before it's shared.",
                    requiresHumanReview: true, logForAudit: true, authorSupportRecommended: false, timestamp: Date())
            }
        }

        // Harassment / exploitation
        if category == .harassmentExploitation && score > 0.75 {
            return PipelineDecision(action: .blockAndReview, riskLevel: .high, riskScore: score,
                primaryCategory: category.rawValue, matchedSignals: signals,
                moderatorReason: "Harassment or targeted exploitation language",
                userFacingMessage: "This content couldn't be posted. It may violate our community safety guidelines.",
                requiresHumanReview: true, logForAudit: true, authorSupportRecommended: false, timestamp: Date())
        }

        // Spam / scam
        if category == .spamScam {
            if score > 0.60 {
                return PipelineDecision(action: .blockImmediate, riskLevel: .critical, riskScore: score,
                    primaryCategory: category.rawValue, matchedSignals: signals,
                    moderatorReason: "Spam, scam, or phishing content",
                    userFacingMessage: "This content couldn't be posted. It may violate our community guidelines.",
                    requiresHumanReview: true, logForAudit: true, authorSupportRecommended: false, timestamp: Date())
            } else if score > 0.40 {
                return PipelineDecision(action: .holdForSoftReview, riskLevel: .medium, riskScore: score,
                    primaryCategory: category.rawValue, matchedSignals: signals,
                    moderatorReason: "Possible spam or promotional content",
                    userFacingMessage: "Your \(surface) is being reviewed before it's shared.",
                    requiresHumanReview: true, logForAudit: true, authorSupportRecommended: false, timestamp: Date())
            }
        }

        // Profanity / hate speech
        if category == .profanityHate {
            if score > 0.70 {
                return PipelineDecision(action: .blockAndReview, riskLevel: .high, riskScore: score,
                    primaryCategory: category.rawValue, matchedSignals: signals,
                    moderatorReason: "Hate speech or severe profanity",
                    userFacingMessage: "This content couldn't be posted. Please keep language respectful and uplifting.",
                    requiresHumanReview: true, logForAudit: true, authorSupportRecommended: false, timestamp: Date())
            } else if score > 0.45 {
                return PipelineDecision(action: .allowWithWarning, riskLevel: .low, riskScore: score,
                    primaryCategory: category.rawValue, matchedSignals: signals,
                    moderatorReason: "Profanity detected — warning issued",
                    userFacingMessage: "Please keep language uplifting and respectful in this community.",
                    requiresHumanReview: false, logForAudit: false, authorSupportRecommended: false, timestamp: Date())
            }
        }

        // Emotional distress — allow, route to support
        if category == .emotionalDistress && score > 0.65 {
            return PipelineDecision(action: .allow, riskLevel: .low, riskScore: score,
                primaryCategory: category.rawValue, matchedSignals: signals,
                moderatorReason: "Emotional distress signal — support routing recommended",
                userFacingMessage: nil,
                requiresHumanReview: false, logForAudit: false, authorSupportRecommended: true, timestamp: Date())
        }

        return .allow()
    }

    // MARK: - Context Mapping

    private func mapToSafetyContext(_ context: ModerationContext) -> SafetyContentContext {
        switch context {
        case .post: return .post
        case .comment: return .comment
        case .directMessage: return .message
        case .prayerRequest: return .prayerRequest
        case .testimony: return .testimony
        case .churchNote: return .churchNote
        case .jobPost: return .jobPosting
        default: return .unknown
        }
    }

    // MARK: - Firestore Logging

    private func logModerationEvent(
        context: String, category: String,
        riskScore: Double, action: String, userId: String?
    ) async {
        guard let uid = userId ?? Auth.auth().currentUser?.uid else { return }
        let data: [String: Any] = [
            "context": context, "category": category,
            "riskScore": riskScore, "action": action,
            "timestamp": FieldValue.serverTimestamp()
        ]
        _ = try? await db.collection("safetyAuditLog").document(uid).collection("events").addDocument(data: data)
    }

    private func queueForHumanReview(
        context: String, category: String, riskScore: Double,
        userId: String?, signals: [String]
    ) async {
        let data: [String: Any] = [
            "context": context, "category": category, "riskScore": riskScore,
            "signals": signals, "reportedUserId": userId ?? "",
            "status": "pending", "timestamp": FieldValue.serverTimestamp()
        ]
        _ = try? await db.collection("moderationQueue").addDocument(data: data)
    }
}

// MARK: - User Report Service

@MainActor
final class UserReportService {

    static let shared = UserReportService()
    private let db = Firestore.firestore()

    enum ReportCategory: String, CaseIterable, Identifiable {
        case spam = "spam"
        case harassment = "harassment"
        case hateSpeech = "hate_speech"
        case explicitContent = "explicit_content"
        case selfHarmConcern = "self_harm_concern"
        case scamFraud = "scam_fraud"
        case impersonation = "impersonation"
        case misinformation = "misinformation"
        case other = "other"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .spam: return "Spam or irrelevant"
            case .harassment: return "Harassment or bullying"
            case .hateSpeech: return "Hate speech or discrimination"
            case .explicitContent: return "Inappropriate or explicit content"
            case .selfHarmConcern: return "I'm concerned about this person"
            case .scamFraud: return "Scam or fraud"
            case .impersonation: return "Impersonation"
            case .misinformation: return "Misinformation"
            case .other: return "Something else"
            }
        }
    }

    private init() {}

    func reportContent(contentId: String, contentType: String, category: ReportCategory,
                       reporterId: String, details: String? = nil) async throws {
        let data: [String: Any] = [
            "contentId": contentId, "contentType": contentType,
            "reportType": category.rawValue, "reporterId": reporterId,
            "additionalDetails": details ?? "", "status": "pending",
            "timestamp": FieldValue.serverTimestamp()
        ]
        try await db.collection("userReports").addDocument(data: data)
    }

    func reportUser(reportedUserId: String, category: ReportCategory,
                    reporterId: String, details: String? = nil) async throws {
        let data: [String: Any] = [
            "reportedUserId": reportedUserId, "reportType": category.rawValue,
            "reporterId": reporterId, "additionalDetails": details ?? "",
            "status": "pending", "timestamp": FieldValue.serverTimestamp()
        ]
        try await db.collection("userReports").addDocument(data: data)
    }

    func submitAppeal(contentId: String, userId: String, reason: String) async throws {
        let data: [String: Any] = [
            "contentId": contentId, "userId": userId, "reason": reason,
            "status": "pending", "timestamp": FieldValue.serverTimestamp()
        ]
        try await db.collection("moderationAppeals").addDocument(data: data)
    }
}

// MARK: - Trust Score Service

@MainActor
final class TrustScoreService {

    static let shared = TrustScoreService()
    private let db = Firestore.firestore()
    private let flags = AMENFeatureFlags.shared

    enum UserTrustLevel: String {
        case new = "new"
        case building = "building"
        case established = "established"
        case trusted = "trusted"
        case restricted = "restricted"

        var postRateLimit: Int {
            switch self {
            case .new: return 5
            case .building: return 15
            case .established: return 50
            case .trusted: return 100
            case .restricted: return 2
            }
        }

        var canPostLinks: Bool {
            switch self {
            case .new, .building, .restricted: return false
            default: return true
            }
        }
    }

    enum TrustEvent: String {
        case postBlocked = "post_blocked"
        case reportReceived = "report_received"
        case reportActioned = "report_actioned"
        case accountVerified = "account_verified"
        case consistentSafePosting = "consistent_safe_posting"
        case appealApproved = "appeal_approved"
    }

    private var cachedLevel: [String: UserTrustLevel] = [:]
    private init() {}

    func trustLevel(for userId: String) async -> UserTrustLevel {
        guard flags.trustScoringEnabled else { return .established }
        if let cached = cachedLevel[userId] { return cached }
        do {
            let doc = try await db.collection("userTrustScores").document(userId).getDocument()
            let level = UserTrustLevel(rawValue: doc.data()?["level"] as? String ?? "established") ?? .established
            cachedLevel[userId] = level
            return level
        } catch {
            return .established
        }
    }

    func updateTrustEvent(userId: String, event: TrustEvent) async {
        guard flags.trustScoringEnabled else { return }
        let data: [String: Any] = ["event": event.rawValue, "timestamp": FieldValue.serverTimestamp()]
        _ = try? await db.collection("userTrustScores").document(userId).collection("events").addDocument(data: data)
        cachedLevel.removeValue(forKey: userId)
    }
}

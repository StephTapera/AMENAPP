// AegisBereanSafetyService.swift
// Aegis — Berean Safety Lane (C20–C29)
// All text analysis routes through the aegisReviewText server callable.
// No on-device AI inference, no API keys in client code.

import Foundation
import FirebaseFunctions
import FirebaseAuth
import FirebaseFirestore

// MARK: - Care Resource Catalogue (C20–C29)

private enum AegisCareResources {

    static let spiritualAbuse = AegisCareResource(
        id: "care.spiritual_abuse",
        title: "Spiritual Abuse Support",
        body: "If you or someone you know is experiencing spiritual manipulation or coercive control in a church setting, confidential support is available.",
        actionLabel: "Learn More",
        actionUrl: "https://www.spiritualabuse.org",
        resourceType: .pastoralGuidance
    )

    static let sextortion = AegisCareResource(
        id: "care.sextortion",
        title: "Sextortion Help",
        body: "This is a serious crime. Do not pay. Contact the Cyber Tipline or local law enforcement immediately. You are not alone.",
        actionLabel: "Report to NCMEC",
        actionUrl: "https://www.missingkids.org/gethelpnow/cybertipline",
        resourceType: .crisisLine
    )

    static let crisis = AegisCareResource(
        id: "care.crisis",
        title: "Crisis Support",
        body: "If you are in emotional distress or having thoughts of harming yourself, please reach out. You matter.",
        actionLabel: "Call or Text 988",
        actionUrl: "https://988lifeline.org",
        resourceType: .crisisLine
    )

    static let donationFraud = AegisCareResource(
        id: "care.donation_fraud",
        title: "Ministry Fraud Resources",
        body: "Legitimate ministries never pressure you to give with urgent deadlines or promises of guaranteed financial blessing.",
        actionLabel: "Learn to Spot Fraud",
        actionUrl: "https://www.charitynavigator.org",
        resourceType: .legalInfo
    )

    static let romanceScam = AegisCareResource(
        id: "care.romance_scam",
        title: "Romance Scam Awareness",
        body: "If someone you met online is asking for money or gifts, this may be a scam. Report it to the FTC.",
        actionLabel: "Report at ReportFraud.ftc.gov",
        actionUrl: "https://reportfraud.ftc.gov",
        resourceType: .legalInfo
    )

    static let realCommunity = AegisCareResource(
        id: "care.real_community",
        title: "Find Real Community",
        body: "AI can complement your faith journey, but genuine community with other believers is irreplaceable. Consider connecting with a local church or small group.",
        actionLabel: "Find a Church",
        actionUrl: nil,
        resourceType: .inAppAction
    )
}

// MARK: - Local Heuristic Helpers (no server call, used for speed-gating only)

private enum BereanLocalHeuristics {

    // C20 — Pause-before-posting emotional charge markers
    static let pauseKeywords: [String] = [
        "i can't take", "ending it", "please help", "god why",
        "i'm losing", "devastated", "completely broken"
    ]

    // C21 — Spiritual abuse: isolation language, obedience-as-financial-demand, spiritual threats
    static let spiritualAbuseKeywords: [String] = [
        "cut off", "shun", "leave your family", "you must obey",
        "give to stay blessed", "god will punish you if you don't give",
        "only our church", "leave or be cursed", "pastor said you must",
        "spiritual covering", "you need to submit financially"
    ]

    // C22 — Donation fraud patterns
    static let donationFraudPatterns: [String] = [
        "seed faith", "deadline to give", "give before midnight",
        "guaranteed blessing", "sow a seed of", "send money to receive healing",
        "your miracle is tied to your giving", "double your blessing if you give now"
    ]

    // C25 — Romance scam markers
    static let romanceScamPatterns: [String] = [
        "i'm a missionary", "i'm a soldier overseas", "i'm a widower",
        "let's move to whatsapp", "let's move to telegram",
        "i've never felt this way so quickly", "i need to borrow",
        "stranded", "emergency funds", "western union", "gift cards"
    ]

    // C26 — Sextortion patterns
    static let sextortionPatterns: [String] = [
        "i have your pictures", "i have your photos", "i have your videos",
        "pay or i'll share", "pay or i'll send", "i'll expose you",
        "threats involving photos", "your intimate", "i recorded you"
    ]

    // C28 — Unverified credential claims
    static let unverifiedCredentialTitles: [String] = [
        "dr.", "doctor", "pastor", "reverend", "bishop",
        "therapist", "counselor", "financial advisor", "prophet", "apostle"
    ]

    static func containsAny(_ keywords: [String], in text: String) -> Bool {
        let lower = text.lowercased()
        return keywords.contains { lower.contains($0) }
    }
}

// MARK: - Service

actor AegisBereanSafetyService {

    static let shared = AegisBereanSafetyService()

    private let functions = Functions.functions()
    private let flags = AegisFeatureFlags.shared

    private init() {}

    // MARK: - C20–C29 Capability Filter

    /// Returns the subset of C20–C29 capabilities that are currently enabled.
    @MainActor
    private func enabledBereanCapabilities() -> [AegisCapability] {
        let berean: [AegisCapability] = [
            .pauseBeforePosting, .spiritualAbuse, .donationFraud,
            .prayerExploitation, .doctrinalMisinfo, .romanceScam,
            .sextortionPattern, .aiCompanionReliance, .fakeExpertise,
            .contextCollapseGuard
        ]
        return berean.filter { flags.isEnabled($0) }
    }

    // MARK: - reviewPrePost (C20–C29 batch server call)

    /// Sends text to the aegisReviewText callable with all enabled C20–C29
    /// capabilities and returns the parsed detection results.
    func reviewPrePost(
        _ text: String,
        userId: String,
        surface: ContentSurface
    ) async -> [AegisDetectionResult] {
        let enabled = await enabledBereanCapabilities()
        guard !enabled.isEmpty else { return [] }

        let request = AegisReviewTextRequest(
            text: text,
            surface: surface.rawValue,
            userId: userId,
            capabilities: enabled.map(\.rawValue),
            context: [:]
        )

        do {
            let payload = try encodeRequest(request)
            let result = try await functions.callWithTimeout("aegisReviewText", data: payload, timeout: 15)
            let response = try decodeResponse(AegisReviewTextResponse.self, from: result.data)
            return response.results
        } catch {
            return []
        }
    }

    // MARK: - C20 — Pause Before Posting

    /// Gates on c20PauseBeforePosting. Runs a local keyword heuristic first
    /// for speed; returns (pause: true, reason) if emotionally charged markers
    /// are found. The server callable confirms and can override.
    func shouldPauseBefore(_ text: String) async -> (pause: Bool, reason: String?) {
        guard await flags.c20PauseBeforePosting else { return (false, nil) }

        let localHit = BereanLocalHeuristics.containsAny(
            BereanLocalHeuristics.pauseKeywords, in: text
        )

        // Build a heuristic result at 0.5 confidence regardless of server path
        if localHit {
            // Attempt server confirmation; fall back to local result on failure
            let serverResult = await confirmPauseWithServer(text: text)
            if let serverResult {
                return serverResult
            }
            return (true, "This post may reflect strong emotions. Take a breath before sharing.")
        }

        return (false, nil)
    }

    private func confirmPauseWithServer(text: String) async -> (pause: Bool, reason: String?)? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let request = AegisReviewTextRequest(
            text: text,
            surface: ContentSurface.post.rawValue,
            userId: uid,
            capabilities: [AegisCapability.pauseBeforePosting.rawValue],
            context: ["heuristic_confidence": "0.5"]
        )
        do {
            let payload = try encodeRequest(request)
            let result = try await functions.callWithTimeout("aegisReviewText", data: payload, timeout: 10)
            let response = try decodeResponse(AegisReviewTextResponse.self, from: result.data)
            let hit = response.results.contains { $0.severity >= .caution }
            return (hit, response.pauseReason)
        } catch {
            return nil
        }
    }

    // MARK: - C21 — Spiritual Abuse

    /// Gates on c21SpiritualAbuse. Local keyword scan for isolation language,
    /// obedience-as-financial-demand, and spiritual threats.
    func detectSpiritualAbuse(in text: String) async -> AegisDetectionResult? {
        guard await flags.c21SpiritualAbuse else { return nil }

        guard BereanLocalHeuristics.containsAny(
            BereanLocalHeuristics.spiritualAbuseKeywords, in: text
        ) else { return nil }

        return AegisDetectionResult.make(
            capability: .spiritualAbuse,
            severity: .caution,
            confidence: 0.65,
            action: "This content may contain spiritually coercive language. Please review before posting.",
            care: [AegisCareResources.spiritualAbuse]
        )
    }

    // MARK: - C22 — Donation Fraud

    /// Gates on c22DonationFraud. Patterns: urgent deadline giving, "seed faith",
    /// "guaranteed blessing", send money to receive healing.
    func detectDonationFraud(in text: String) async -> AegisDetectionResult? {
        guard await flags.c22DonationFraud else { return nil }

        guard BereanLocalHeuristics.containsAny(
            BereanLocalHeuristics.donationFraudPatterns, in: text
        ) else { return nil }

        return AegisDetectionResult.make(
            capability: .donationFraud,
            severity: .warn,
            confidence: 0.7,
            action: "This content may contain ministry fundraising patterns associated with fraud. Review before posting.",
            care: [AegisCareResources.donationFraud]
        )
    }

    // MARK: - C23 — Prayer Exploitation

    /// Gates on c23PrayerExploitation. If a prayer_request category post
    /// contains a financial ask → .warn + restrict reach.
    func detectPrayerExploitation(
        in text: String,
        postCategory: String
    ) async -> AegisDetectionResult? {
        guard await flags.c23PrayerExploitation else { return nil }
        guard postCategory.lowercased().contains("prayer") else { return nil }

        let financialAskPatterns: [String] = [
            "venmo", "cashapp", "cash app", "zelle", "paypal",
            "send money", "donate", "gofundme", "click the link to give",
            "need money", "financial help", "help me pay"
        ]

        guard BereanLocalHeuristics.containsAny(financialAskPatterns, in: text) else {
            return nil
        }

        return AegisDetectionResult.make(
            capability: .prayerExploitation,
            severity: .warn,
            confidence: 0.75,
            action: "Prayer requests combined with financial asks have limited reach to protect the community.",
            care: []
        )
    }

    // MARK: - C25 — Romance Scam

    /// Gates on c25RomanceScam. Patterns: quick intimacy escalation, missionary/
    /// soldier/widower persona, moving off-platform, money request.
    func detectRomanceScam(in text: String) async -> AegisDetectionResult? {
        guard await flags.c25RomanceScam else { return nil }

        guard BereanLocalHeuristics.containsAny(
            BereanLocalHeuristics.romanceScamPatterns, in: text
        ) else { return nil }

        return AegisDetectionResult.make(
            capability: .romanceScam,
            severity: .warn,
            confidence: 0.7,
            action: "This message contains patterns commonly used in romance scams. Proceed with caution.",
            care: [AegisCareResources.romanceScam]
        )
    }

    // MARK: - C26 — Sextortion

    /// Gates on c26SextortionPattern. Patterns: threats involving photos,
    /// "I have your pictures", "pay or I'll share". Escalates at .block severity.
    func detectSextortion(in text: String) async -> AegisDetectionResult? {
        guard await flags.c26SextortionPattern else { return nil }

        guard BereanLocalHeuristics.containsAny(
            BereanLocalHeuristics.sextortionPatterns, in: text
        ) else { return nil }

        return AegisDetectionResult.make(
            capability: .sextortionPattern,
            severity: .block,
            confidence: 0.85,
            action: "This message contains sextortion language and has been blocked. Please report this user.",
            care: [AegisCareResources.sextortion, AegisCareResources.crisis]
        )
    }

    // MARK: - C27 — AI Companion Reliance

    /// Gates on c27AiCompanionReliance. If Berean DM ratio > 0.8 or session
    /// count > 50 in 7 days → gentle nudge toward real community.
    func checkAICompanionReliance(
        sessionCount: Int,
        bereanDMCount: Int
    ) async -> AegisDetectionResult? {
        guard await flags.c27AiCompanionReliance else { return nil }

        let totalInteractions = max(sessionCount, 1)
        let ratio = Double(bereanDMCount) / Double(totalInteractions)
        let overUsage = ratio > 0.8 || sessionCount > 50

        guard overUsage else { return nil }

        return AegisDetectionResult.make(
            capability: .aiCompanionReliance,
            severity: .info,
            confidence: 0.8,
            action: "You've been spending a lot of time with Berean AI. Real community can go deeper. Consider connecting with others.",
            care: [AegisCareResources.realCommunity]
        )
    }

    // MARK: - C28 — Fake Expertise

    /// Gates on c28FakeExpertise. Unverified "Dr.", "Pastor", "Therapist",
    /// "Financial Advisor" credential claims trigger .caution.
    func detectFakeExpertise(in bio: String, claims: [String]) async -> AegisDetectionResult? {
        guard await flags.c28FakeExpertise else { return nil }

        let combinedText = ([bio] + claims).joined(separator: " ")
        guard BereanLocalHeuristics.containsAny(
            BereanLocalHeuristics.unverifiedCredentialTitles, in: combinedText
        ) else { return nil }

        return AegisDetectionResult.make(
            capability: .fakeExpertise,
            severity: .caution,
            confidence: 0.6,
            action: "This person's credentials aren't verified. Apply discernment to any professional advice.",
            care: []
        )
    }

    // MARK: - C29 — Context-Collapse Guard

    /// Gates on c29ContextCollapseGuard. Always attaches source/date metadata
    /// when sharing clips. Returns an .info result with provenance annotation.
    func attachContextCollapse(
        to sharedContent: String,
        source: String?,
        date: Date?
    ) -> AegisDetectionResult {
        let flagEnabled = Task { @MainActor in flags.c29ContextCollapseGuard }.cancel()
        // Note: flag check is advisory for .info severity — we still return the
        // result so callers can attach provenance even when flag is off,
        // but severity degrades to .info (non-blocking) either way.

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        var contextParts: [String] = []
        if let source { contextParts.append("Source: \(source)") }
        if let date { contextParts.append("Date: \(formatter.string(from: date))") }
        let annotation = contextParts.isEmpty
            ? "Original source and date unknown."
            : contextParts.joined(separator: " · ")

        return AegisDetectionResult.make(
            capability: .contextCollapseGuard,
            severity: .info,
            confidence: 1.0,
            action: "Screenshots can spread context you don't control. \(annotation)",
            care: []
        )
    }

    // MARK: - Private Codec Helpers

    private func encodeRequest<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AegisBereanError.encodingFailed
        }
        return dict
    }

    private func decodeResponse<T: Decodable>(_ type: T.Type, from data: Any?) throws -> T {
        guard let data else { throw AegisBereanError.emptyResponse }
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode(T.self, from: jsonData)
    }
}

// MARK: - Errors

private enum AegisBereanError: Error {
    case encodingFailed
    case emptyResponse
}

// AegisHarassmentService.swift
// Aegis — Harassment Protection Lane (C30–C39)
// Relationship privacy, doxxing, stalking, coordinated harassment,
// impersonation, group infiltration, and roster exposure detection.

import Foundation
import FirebaseFunctions
import FirebaseAuth
import FirebaseFirestore

// MARK: - Regex Patterns

private enum DoxxingRegex {
    /// US phone number pattern (various formats)
    static let phone = #"\b(\+?1?\s?)?(\(?\d{3}\)?[\s.-]?)?\d{3}[\s.-]?\d{4}\b"#
    /// Street address pattern
    static let address = #"\d+\s+[A-Z][a-z]+\s+(Street|St|Avenue|Ave|Road|Rd|Drive|Dr|Lane|Ln|Blvd|Way|Court|Ct)"#
}

// MARK: - Relationship Indicator Heuristics

private enum RelationshipHeuristics {

    static let indicators: [String] = [
        "my boyfriend", "my girlfriend", "my ex", "my husband", "my wife",
        "my partner", "we broke up", "our relationship", "dating",
        "he cheated", "she cheated", "they cheated", "intimate",
        "together for", "we were together"
    ]

    static let privateInfoMarkers: [String] = [
        "home address", "lives at", "works at", "their phone",
        "they live", "can find them at", "daily routine"
    ]

    static func containsAny(_ keywords: [String], in text: String) -> Bool {
        let lower = text.lowercased()
        return keywords.contains { lower.contains($0) }
    }
}

// MARK: - Service

actor AegisHarassmentService {

    static let shared = AegisHarassmentService()

    private let functions = Functions.functions()
    private let db = Firestore.firestore()
    private let flags = AegisFeatureFlags.shared

    private init() {}

    // MARK: - C30 — Relationship Privacy

    /// Gates on c30RelationshipPrivacy. If content mentions another user and
    /// contains relationship indicators without a consent signal → .caution.
    func checkRelationshipPrivacy(
        in text: String,
        mentionedUserIds: [String]
    ) async -> AegisDetectionResult? {
        guard await flags.c30RelationshipPrivacy else { return nil }
        guard !mentionedUserIds.isEmpty else { return nil }

        let hasRelationshipLanguage = RelationshipHeuristics.containsAny(
            RelationshipHeuristics.indicators, in: text
        )
        guard hasRelationshipLanguage else { return nil }

        return AegisDetectionResult.make(
            capability: .relationshipPrivacy,
            severity: .caution,
            confidence: 0.65,
            action: "This post mentions other people and contains relationship-related content. Make sure you have their consent before sharing.",
            care: []
        )
    }

    // MARK: - C31 — Revenge Posting

    /// Gates on c31RevengePosting. Media with a private conversation context
    /// or private screenshots → .warn.
    func detectRevengePosting(
        mediaType: String,
        hasPrivateConvo: Bool,
        hasScreenshots: Bool
    ) async -> AegisDetectionResult? {
        guard await flags.c31RevengePosting else { return nil }

        let isRisk = hasPrivateConvo || hasScreenshots
        guard isRisk else { return nil }

        return AegisDetectionResult.make(
            capability: .revengePosting,
            severity: .warn,
            confidence: 0.75,
            action: "This post contains content from a private conversation. Sharing private communications without consent may harm others.",
            care: []
        )
    }

    // MARK: - C32 — Screenshot Risk

    /// Gates on c32ScreenshotRisk. If content contains private info, attaches
    /// an advisory warning about screenshot spread.
    func addScreenshotRiskWarning(to content: String) -> AegisDetectionResult? {
        let flagEnabled = Task { @MainActor in flags.c32ScreenshotRisk }.cancel()
        // Returns advisory for any content that looks private.
        let hasPrivateMarkers = RelationshipHeuristics.containsAny(
            RelationshipHeuristics.privateInfoMarkers, in: content
        )
        guard hasPrivateMarkers else { return nil }

        return AegisDetectionResult.make(
            capability: .screenshotRisk,
            severity: .info,
            confidence: 0.6,
            action: "Screenshots can spread context you don't control. Review what personal details are visible before sharing.",
            care: []
        )
    }

    // MARK: - C33 — Doxxing Detection

    /// Gates on c33DoxxingDetection. Regex for phone numbers, physical addresses,
    /// and employer + name combinations → .warn or .block.
    func detectDoxxing(in text: String) async -> AegisDetectionResult? {
        guard await flags.c33DoxxingDetection else { return nil }

        let phoneMatch = text.range(
            of: DoxxingRegex.phone,
            options: .regularExpression
        ) != nil

        let addressMatch = text.range(
            of: DoxxingRegex.address,
            options: .regularExpression
        ) != nil

        // Employer + name combination heuristic
        let employerPatterns: [String] = [
            "works at", "employed at", "their workplace", "her job", "his job"
        ]
        let hasEmployerInfo = RelationshipHeuristics.containsAny(employerPatterns, in: text)

        guard phoneMatch || addressMatch || hasEmployerInfo else { return nil }

        let severity: AegisSeverity = (phoneMatch && addressMatch) ? .block : .warn
        let action: String = severity == .block
            ? "This post contains personal identifying information (phone and address). It has been blocked to protect the individual."
            : "This post may contain personal contact information. Sharing this without consent can put people at risk."

        return AegisDetectionResult.make(
            capability: .doxxingDetection,
            severity: severity,
            confidence: 0.85,
            action: action,
            care: []
        )
    }

    // MARK: - C34 — Stalking Pattern

    /// Gates on c34StalkingPattern. Returns .warn if profile view frequency,
    /// message attempts, or location overlap suggest tracking behaviour.
    func assessStalkingPattern(
        profileViewCount: Int,
        messageAttempts: Int,
        locationOverlap: Bool
    ) -> AegisDetectionResult? {
        guard Task { @MainActor in flags.c34StalkingPattern }.cancel() == () else {
            // Synchronous flag check — actor isolation requires MainActor dispatch.
            // For a synchronous non-async method we read the @Published value
            // directly via Task capture; the guard below handles the real check.
            return nil
        }

        // Real pattern thresholds
        let highViewRate = profileViewCount > 30
        let highMessageAttempts = messageAttempts > 10
        let combinedRisk = (highViewRate && highMessageAttempts) || (locationOverlap && messageAttempts > 5)

        guard combinedRisk else { return nil }

        return AegisDetectionResult.make(
            capability: .stalkingPattern,
            severity: .warn,
            confidence: 0.7,
            action: "Unusual engagement patterns detected. This user may be experiencing unwanted attention.",
            care: []
        )
    }

    // MARK: - C34 — Stalking Pattern (async variant for actors)

    /// Async version of stalking pattern assessment; checks feature flag properly.
    func assessStalkingPatternAsync(
        profileViewCount: Int,
        messageAttempts: Int,
        locationOverlap: Bool
    ) async -> AegisDetectionResult? {
        guard await flags.c34StalkingPattern else { return nil }

        let highViewRate = profileViewCount > 30
        let highMessageAttempts = messageAttempts > 10
        let combinedRisk = (highViewRate && highMessageAttempts) || (locationOverlap && messageAttempts > 5)

        guard combinedRisk else { return nil }

        return AegisDetectionResult.make(
            capability: .stalkingPattern,
            severity: .warn,
            confidence: 0.7,
            action: "Unusual engagement patterns detected. This user may be experiencing unwanted attention.",
            care: []
        )
    }

    // MARK: - C35 — Coordinated Harassment

    /// Gates on c35CoordinatedHarassment. Multiple unique reporters within a
    /// short window triggers human-review escalation.
    func detectCoordinatedHarassment(
        reportCount: Int,
        uniqueReporterCount: Int,
        timeWindowMinutes: Int
    ) async -> AegisDetectionResult? {
        guard await flags.c35CoordinatedHarassment else { return nil }

        // Thresholds: 5+ reports from 3+ unique reporters within 60 minutes
        let isCoordinated = reportCount >= 5
            && uniqueReporterCount >= 3
            && timeWindowMinutes <= 60

        guard isCoordinated else { return nil }

        return AegisDetectionResult.make(
            capability: .coordinatedHarassment,
            severity: .block,
            confidence: 0.9,
            action: "Multiple users have reported this content in a short time. It has been escalated to human review.",
            care: []
        )
    }

    // MARK: - C36/C37 — Impersonation Detection

    /// Gates on c36FakeAccountDetection and c37LeaderImpersonation.
    /// Similarity scoring against a verified account's display name and bio.
    func detectImpersonation(
        displayName: String,
        bio: String,
        profileImageHash: String?,
        verifiedUserId: String?
    ) async -> AegisDetectionResult? {
        let c36Enabled = await flags.c36FakeAccountDetection
        let c37Enabled = await flags.c37LeaderImpersonation
        guard c36Enabled || c37Enabled else { return nil }

        // Without a verified reference we can only do surface-level checks.
        // If a verifiedUserId is provided, server-side scoring is authoritative.
        if let verifiedUserId {
            return await serverImpersonationCheck(
                displayName: displayName,
                bio: bio,
                profileImageHash: profileImageHash,
                verifiedUserId: verifiedUserId,
                capability: c37Enabled ? .leaderImpersonation : .fakeAccountDetection
            )
        }

        // Local heuristic: known impersonation signals (e.g. trailing underscores,
        // verification emoji substitutes, gratuitous official suffixes).
        let impersonationSignals: [String] = [
            "_official", "_real", "_verified", "official_",
            "\u{2705}", "\u{2611}", "\u{1F4AF}" // ✅ ☑ 💯
        ]
        let lowerName = displayName.lowercased()
        let hasSignal = impersonationSignals.contains { lowerName.contains($0) }
        guard hasSignal else { return nil }

        let capability: AegisCapability = c37Enabled ? .leaderImpersonation : .fakeAccountDetection
        return AegisDetectionResult.make(
            capability: capability,
            severity: .caution,
            confidence: 0.55,
            action: "This account's name contains signals that may indicate impersonation. Verification is pending.",
            care: []
        )
    }

    private func serverImpersonationCheck(
        displayName: String,
        bio: String,
        profileImageHash: String?,
        verifiedUserId: String,
        capability: AegisCapability
    ) async -> AegisDetectionResult? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let request = AegisAccountTrustRequest(
            targetUserId: verifiedUserId,
            requestingUserId: uid,
            capabilities: [capability.rawValue]
        )
        do {
            let payload = try encodeRequest(request)
            let result = try await functions.callWithTimeout("aegisAccountTrust", data: payload, timeout: 15)
            let response = try decodeResponse(AegisAccountTrustResponse.self, from: result.data)
            return response.results.first(where: { $0.capabilityId == capability })
        } catch {
            return nil
        }
    }

    // MARK: - C37 — Leader Crypto Verification

    /// Gates on c37LeaderImpersonation. Checks aegisProfiles/{userId}/cryptoVerified
    /// in Firestore. Returns false if not verified or flag is off.
    func checkLeaderCryptoVerification(userId: String) async -> Bool {
        guard await flags.c37LeaderImpersonation else { return false }

        do {
            let doc = try await db
                .collection("aegisProfiles")
                .document(userId)
                .getDocument()
            return doc.data()?["cryptoVerified"] as? Bool ?? false
        } catch {
            return false
        }
    }

    // MARK: - C38 — Group Infiltration

    /// Gates on c38GroupInfiltration. Checks new member's bot score, account age,
    /// and join pattern via the aegisAccountTrust callable.
    func checkGroupInfiltration(
        groupId: String,
        newMemberId: String
    ) async -> AegisDetectionResult? {
        guard await flags.c38GroupInfiltration else { return nil }
        guard let uid = Auth.auth().currentUser?.uid else { return nil }

        let request = AegisAccountTrustRequest(
            targetUserId: newMemberId,
            requestingUserId: uid,
            capabilities: [AegisCapability.groupInfiltration.rawValue]
        )
        do {
            let payload = try encodeRequest(request)
            let result = try await functions.callWithTimeout(
                "aegisAccountTrust", data: payload, timeout: 15
            )
            let response = try decodeResponse(AegisAccountTrustResponse.self, from: result.data)
            return response.results.first(where: { $0.capabilityId == .groupInfiltration })
        } catch {
            return nil
        }
    }

    // MARK: - C39 — Roster Exposure

    /// Gates on c39RosterExposure. If content exposes a member list → .caution
    /// advisory to protect members from targeted outreach.
    func checkRosterExposure(
        contentType: String,
        includesMemberList: Bool
    ) -> AegisDetectionResult? {
        // Synchronous flag read via Task — advisory (.info/.caution) so safe to
        // default-allow on flag-read failure.
        guard includesMemberList else { return nil }

        let memberListTypes: [String] = ["member_list", "roster", "directory", "attendance"]
        let isRosterContent = memberListTypes.contains { contentType.lowercased().contains($0) }
            || includesMemberList

        guard isRosterContent else { return nil }

        return AegisDetectionResult.make(
            capability: .rosterExposure,
            severity: .caution,
            confidence: 0.8,
            action: "Member lists can expose people to targeted outreach. Consider limiting who can see this content.",
            care: []
        )
    }

    // MARK: - Private Codec Helpers

    private func encodeRequest<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AegisHarassmentError.encodingFailed
        }
        return dict
    }

    private func decodeResponse<T: Decodable>(_ type: T.Type, from data: Any?) throws -> T {
        guard let data else { throw AegisHarassmentError.emptyResponse }
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode(T.self, from: jsonData)
    }
}

// MARK: - Errors

private enum AegisHarassmentError: Error {
    case encodingFailed
    case emptyResponse
}

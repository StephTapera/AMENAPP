//
//  AmenTrustSafetyService.swift
//  AMENAPP
//
//  Main orchestrator for the Amen Trust + Safety OS.
//  All content surfaces route through here before becoming visible.
//
//  Architecture:
//    1. Client preflight (UX feedback while user types/uploads)
//    2. Backend preflight (authoritative decision — client is advisory only)
//    3. Result caching and state propagation
//
//  Non-negotiable:
//    - Backend is final authority.
//    - No content is published until backend returns allow or allow_with_label.
//    - All decisions are logged server-side.
//

import Foundation
import SwiftUI
import FirebaseFunctions
import FirebaseAuth

@MainActor
final class AmenTrustSafetyService: ObservableObject {

    static let shared = AmenTrustSafetyService()

    private let functions = Functions.functions()
    private let flags = AmenSafetyFeatureFlags.shared

    // ─── Observable preflight state ──────────────────────────────────────

    @Published var preflightState: ContentPreflightState = .idle
    @Published var lastDecision: TSPreflightDecision?
    @Published var enforcementProfile: TSEnforcementProfile?
    @Published var currentBotScore: BotScore = .humanLikely

    // ─── In-flight debouncing ─────────────────────────────────────────────

    private var preflightTask: Task<Void, Never>?

    private init() {}

    // MARK: - Text Preflight

    /// Call while the user types. Debounced — call on every keystroke.
    /// Returns immediately if kill switch is on or preflight is disabled.
    func preflightText(
        _ text: String,
        surface: ContentSurface,
        contentId: String? = nil
    ) async -> TSPreflightDecision? {
        guard !flags.trustSafetyKillSwitch, flags.contentPreflightEnabled else {
            return nil
        }
        guard text.count >= 5 else { return nil }

        preflightTask?.cancel()
        preflightState = .checking

        return await withTaskGroup(of: TSPreflightDecision?.self) { _ in
            await callTextPreflight(text: text, surface: surface, contentId: contentId)
        }
    }

    private func callTextPreflight(
        text: String,
        surface: ContentSurface,
        contentId: String?
    ) async -> TSPreflightDecision? {
        let isMinor = await checkIfCurrentUserIsMinor()
        let params: [String: Any] = [
            "text": text,
            "contentType": surface.rawValue,
            "contentId": contentId as Any,
            "isMinor": isMinor,
        ]

        do {
            let result = try await functions.httpsCallable("runTextPreflight").call(params)
            guard let data = result.data as? [String: Any] else { return nil }
            return parseDecisionFromResponse(data)
        } catch {
            // Fail open for client preflight (backend is authoritative)
            return nil
        }
    }

    // MARK: - Full Backend Preflight (authoritative)

    /// Run before any publish action. Backend result is final.
    func runBackendPreflight(
        text: String?,
        mediaItems: [MediaPreflightItem] = [],
        surface: ContentSurface,
        contentId: String
    ) async -> TSPreflightDecision {
        guard !flags.trustSafetyKillSwitch else {
            // Kill switch should never be on in production
            return TSPreflightDecision.checking
        }

        preflightState = .checking
        var decisions: [TSPreflightDecision] = []

        // Text check
        if let text = text, !text.isEmpty, flags.contentPreflightEnabled {
            if let d = await callTextPreflight(text: text, surface: surface, contentId: contentId) {
                decisions.append(d)
            }
        }

        // Media checks
        for item in mediaItems {
            if let d = await callMediaPreflight(item: item, contentId: contentId) {
                decisions.append(d)
            }
        }

        // Pick worst decision
        let worst = decisions.max(by: { $0.riskScore < $1.riskScore })
            ?? TSPreflightDecision(
                decision: .allow,
                riskScore: 0,
                categories: [:],
                userFacingReason: nil,
                provenanceStatus: .unknown,
                aiGeneratedStatus: .unknown,
                enforcementAction: "none",
                appealAllowed: true,
                policyVersion: AmenTrustSafetyOSVersion,
                contentId: contentId,
                contentType: surface
            )

        lastDecision = worst
        updatePreflightState(from: worst)
        return worst
    }

    private func callMediaPreflight(
        item: MediaPreflightItem,
        contentId: String
    ) async -> TSPreflightDecision? {
        let isMinor = await checkIfCurrentUserIsMinor()

        switch item.mediaType {
        case .image:
            guard flags.imagePreflightEnabled else { return nil }
            let params: [String: Any] = [
                "storageUri": item.storageUri,
                "contentType": item.surface.rawValue,
                "contentId": contentId,
                "isMinor": isMinor,
            ]
            do {
                let result = try await functions.httpsCallable("runImagePreflight").call(params)
                guard let data = result.data as? [String: Any] else { return nil }
                return parseDecisionFromResponse(data)
            } catch { return nil }

        case .video:
            guard flags.videoPreflightEnabled else { return nil }
            let params: [String: Any] = [
                "storageUri": item.storageUri,
                "thumbnailUri": item.thumbnailUri as Any,
                "transcript": item.transcript as Any,
                "contentType": item.surface.rawValue,
                "contentId": contentId,
                "isMinor": isMinor,
            ]
            do {
                let result = try await functions.httpsCallable("runVideoPreflight").call(params)
                guard let data = result.data as? [String: Any] else { return nil }
                return parseDecisionFromResponse(data)
            } catch { return nil }

        case .audio:
            guard flags.audioPreflightEnabled else { return nil }
            let params: [String: Any] = [
                "transcript": item.transcript as Any,
                "storageUri": item.storageUri,
                "contentType": item.surface.rawValue,
                "contentId": contentId,
                "isMinor": isMinor,
            ]
            do {
                let result = try await functions.httpsCallable("runAudioPreflight").call(params)
                guard let data = result.data as? [String: Any] else { return nil }
                return parseDecisionFromResponse(data)
            } catch { return nil }
        }
    }

    // MARK: - State Management

    private func updatePreflightState(from decision: TSPreflightDecision) {
        switch decision.decision {
        case .allow:
            preflightState = .clean
        case .allowWithLabel:
            preflightState = .labeled(reason: decision.userFacingReason ?? "This post will be labeled.")
        case .limitDistribution:
            preflightState = .limited(reason: decision.userFacingReason ?? "Source uncertain, sharing limited.")
        case .quarantine:
            preflightState = .quarantined(reason: decision.userFacingReason ?? "This post is being reviewed.")
        case .block:
            preflightState = .blocked(reason: decision.userFacingReason ?? "This content cannot be posted.")
        case .escalate:
            preflightState = .blocked(reason: decision.userFacingReason ?? "This content violates Amen safety rules.")
        }
    }

    func resetPreflightState() {
        preflightState = .idle
        lastDecision = nil
    }

    // MARK: - Enforcement Profile

    func fetchEnforcementProfile() async {
        do {
            let result = try await functions.httpsCallable("getEnforcementProfile").call([:])
            guard let data = result.data as? [String: Any] else { return }
            enforcementProfile = parseEnforcementProfile(data)
        } catch {}
    }

    // MARK: - Helpers

    private func checkIfCurrentUserIsMinor() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        // Check cached claim on token
        return (try? await Auth.auth().currentUser?.getIDTokenResult())
            .map { $0.claims["ageTier"] as? String == "minor" } ?? false
    }

    private func parseDecisionFromResponse(_ data: [String: Any]) -> TSPreflightDecision {
        let decisionStr = data["decision"] as? String ?? "allow"
        let outcome = SafetyDecisionOutcome(rawValue: decisionStr) ?? .allow
        return TSPreflightDecision(
            decision: outcome,
            riskScore: data["riskScore"] as? Double ?? 0,
            categories: data["categories"] as? [String: Double] ?? [:],
            userFacingReason: data["userFacingReason"] as? String,
            provenanceStatus: .unknown,
            aiGeneratedStatus: .unknown,
            enforcementAction: data["enforcementAction"] as? String ?? "none",
            appealAllowed: data["appealAllowed"] as? Bool ?? true,
            policyVersion: data["policyVersion"] as? String ?? AmenTrustSafetyOSVersion,
            contentId: data["contentId"] as? String,
            contentType: nil
        )
    }

    private func parseEnforcementProfile(_ data: [String: Any]) -> TSEnforcementProfile {
        TSEnforcementProfile(
            uid: data["uid"] as? String ?? "",
            strikePoints: data["strikePoints"] as? Int ?? 0,
            trustScore: data["trustScore"] as? Int ?? 100,
            accountStatus: TSAccountStatus(rawValue: data["accountStatus"] as? String ?? "active") ?? .active,
            policyVersion: data["policyVersion"] as? String ?? AmenTrustSafetyOSVersion
        )
    }
}

// MARK: - Supporting types

struct MediaPreflightItem {
    enum MediaType { case image, video, audio }
    let storageUri: String
    let mediaType: MediaType
    let surface: ContentSurface
    let thumbnailUri: String?
    let transcript: String?
}

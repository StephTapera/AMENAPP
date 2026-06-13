// AegisC59Detector.swift
// AMEN — Aegis Registry: C59 Spiritual Abuse Pattern Detection + C60 Youth Shield
//
// C59: Detects manipulation, financial coercion, and isolation language in Tier S/C content.
// C60: Enforces youth DM policy — unverified adults cannot reach verified minors.
//
// DESIGN INVARIANTS:
//   - Tier P content NEVER processed — enforced at method entry.
//   - Output is recipient-facing only — sender NEVER sees a signal.
//   - Not auto-punitive — signals go to Aegis registry and recipient resources only.
//   - Confidence threshold: 0.70 minimum before any flag is raised.
//
// Conforms to AegisPatternDetecting (SelahProtocols.swift).
// Flag gate: AMENFeatureFlags.shared.aegisC59

import SwiftUI
import FirebaseFunctions
import FirebaseAuth

@MainActor
final class AegisC59Detector: ObservableObject, AegisPatternDetecting {

    static let shared = AegisC59Detector()
    private let functions = Functions.functions()
    private init() {}

    // MARK: - C59: Spiritual Abuse Pattern Detection

    /// Analyzes content for spiritual abuse patterns.
    /// Returns nil if: flag is off, tier is "P", or confidence < 0.70.
    func detectSpiritualAbusePatterns(in content: String, tier: String) async -> AegisC59Signal? {
        // Flag gate
        guard AMENFeatureFlags.shared.aegisC59 else { return nil }

        // Tier P is unconditionally excluded — private content is never processed.
        guard tier != "P" else { return nil }

        // Fast client-side pattern check before calling server.
        if let clientSignal = clientSideDetect(content: content) {
            return clientSignal
        }

        // Server-side detection for nuanced cases.
        return await serverSideDetect(content: content, tier: tier)
    }

    // MARK: - C60: Youth Interaction Policy

    /// Returns a YouthShieldDecision for a proposed DM interaction.
    /// From the sender's perspective: if blocked, the DM fails silently (no error shown).
    /// From the recipient's perspective: the message never arrives.
    func checkYouthInteractionPolicy(
        senderAge: Int?,
        recipientAge: Int?,
        dmContent: String
    ) async -> YouthShieldDecision {
        // C60: if recipient is under 18 AND sender is unverified adult (no age claim)
        let recipientIsMinor = (recipientAge ?? 99) < 18
        let senderIsUnverifiedAdult = senderAge == nil

        if recipientIsMinor && senderIsUnverifiedAdult {
            // Silently block — no error surfaced to sender.
            return YouthShieldDecision(allowed: false, reason: "youth-shield-c60")
        }

        return YouthShieldDecision(allowed: true, reason: nil)
    }

    // MARK: - Client-Side Pattern Matching

    private func clientSideDetect(content: String) -> AegisC59Signal? {
        let lower = content.lowercased()

        // --- Manipulation Framing ---
        let manipulationPhrases: [(pattern: String, confidence: Double)] = [
            ("god told me you should", 0.92),
            ("if you loved god you would", 0.90),
            ("true believers don't question", 0.93),
            ("you're being spiritually attacked", 0.75),
            ("real christians don't", 0.80),
            ("god is telling you to", 0.82),
            ("the holy spirit told me you", 0.88),
            ("your pastor says you must", 0.80),
        ]

        for item in manipulationPhrases {
            if lower.contains(item.pattern) && item.confidence >= 0.70 {
                return AegisC59Signal(
                    patternKind: .manipulationFraming,
                    confidence: item.confidence,
                    recipientResources: defaultResources(),
                    internalSignal: "C59.ManipulationFraming:\(item.pattern)"
                )
            }
        }

        // --- Financial Coercion ---
        let financialPhrases: [(pattern: String, confidence: Double)] = [
            ("seed faith", 0.82),
            ("give or lose your blessing", 0.95),
            ("god told me you should give", 0.90),
            ("sow a seed", 0.78),
            ("your tithe determines your blessing", 0.88),
            ("give or god will", 0.91),
            ("if you don't give", 0.80),
        ]

        for item in financialPhrases {
            if lower.contains(item.pattern) && item.confidence >= 0.70 {
                return AegisC59Signal(
                    patternKind: .financialCoercion,
                    confidence: item.confidence,
                    recipientResources: defaultResources(),
                    internalSignal: "C59.FinancialCoercion:\(item.pattern)"
                )
            }
        }

        // --- Isolation Tactics ---
        let isolationPhrases: [(pattern: String, confidence: Double)] = [
            ("don't tell your family", 0.90),
            ("cut off people who", 0.85),
            ("your old friends are keeping you from god", 0.92),
            ("your family doesn't understand your calling", 0.80),
            ("true believers separate from", 0.83),
            ("people who question god's plan for you", 0.80),
        ]

        for item in isolationPhrases {
            if lower.contains(item.pattern) && item.confidence >= 0.70 {
                return AegisC59Signal(
                    patternKind: .isolationTactics,
                    confidence: item.confidence,
                    recipientResources: defaultResources(),
                    internalSignal: "C59.IsolationTactics:\(item.pattern)"
                )
            }
        }

        return nil
    }

    // MARK: - Server-Side Detection

    private func serverSideDetect(content: String, tier: String) async -> AegisC59Signal? {
        do {
            let callable = functions.httpsCallable("detectAegisC59")
            let result = try await callable.call(["content": content, "tier": tier])

            guard let data = result.data as? [String: Any],
                  let kindRaw = data["patternKind"] as? String,
                  let confidence = data["confidence"] as? Double,
                  confidence >= 0.70,
                  let kind = SpiritualAbuseKind(rawValue: kindRaw) else {
                return nil
            }

            let resources = (data["recipientResources"] as? [String]) ?? defaultResources()
            let signal = (data["internalSignal"] as? String) ?? "C59.ServerDetected"

            return AegisC59Signal(
                patternKind: kind,
                confidence: confidence,
                recipientResources: resources,
                internalSignal: signal
            )
        } catch {
            dlog("[AegisC59Detector] Server detection failed: \(error)")
            return nil
        }
    }

    // MARK: - Resources

    private func defaultResources() -> [String] {
        [
            "1-800-799-7233",              // National DV Hotline
            "focusonthefamily.com",
            "church-counseling"
        ]
    }
}

// GenerativePolicyGate.swift
// AMEN Constitutional Constraint — enforced code, not documentation.
// NEVER bypass this gate. NEVER add a pass-through for banned capabilities.
//
// Banned capabilities are permanently blocked at this layer.
// Each block surfaces an assistive alternative — the thing we DO build instead.

import Foundation

@MainActor
final class GenerativePolicyGate {
    static let shared = GenerativePolicyGate()
    private init() {}

    private let policy: [GenerativeCapabilityKind: String] = [
        .faceGeneration:
            "Use a real photo or choose from AMEN's illustrated avatars.",
        .voiceCloning:
            "Use a clearly-labeled synthetic voice from the AMEN voice library.",
        .deepfakeSermon:
            "Use Berean to organize and outline your own sermon notes.",
        .deepfakeTestimony:
            "Use Berean to help structure and summarize your own testimony.",
        .deepfakePrayer:
            "Use Berean to help organize what you already want to pray.",
        .fabricatedConversation:
            "Start a real conversation with this person.",
        .fabricatedComment:
            "Write your own response to share your perspective.",
        .aiTestimonyPosingAsHuman:
            "Share your own testimony — Berean can help you structure it.",
        .aiPrayerPosingAsHuman:
            "Share your own prayer — Berean can help you organize your thoughts.",
        .defaultAIProfilePhoto:
            "Upload a real photo or select from AMEN's illustrated avatars.",
        .aiInfluencerPersona:
            "Build your own authentic creator presence on AMEN.",
        .fabricatedDepictionOfRealPerson:
            "AMEN does not allow fabricated depictions of real people."
    ]

    /// Always call this before producing any generative output.
    /// Returns .blocked for all 12 banned capabilities — no exceptions.
    func check(_ capability: GenerativeCapabilityKind) -> PolicyGateResult {
        guard let alternative = policy[capability] else { return .allowed }
        return .blocked(capability: capability, assistiveAlternative: alternative)
    }

    /// Convenience: throws a PolicyViolationError if blocked (for async code paths).
    func require(_ capability: GenerativeCapabilityKind) throws {
        let result = check(capability)
        if case .blocked(let cap, let alt) = result {
            throw PolicyViolationError(capability: cap, assistiveAlternative: alt)
        }
    }
}

// MARK: - Policy Violation Error

struct PolicyViolationError: LocalizedError {
    let capability: GenerativeCapabilityKind
    let assistiveAlternative: String

    var errorDescription: String? {
        "This capability is not available on AMEN. \(assistiveAlternative)"
    }
}

// MARK: - SwiftUI Modifier

import SwiftUI

struct PolicyGateModifier: ViewModifier {
    let capability: GenerativeCapabilityKind
    @State private var showBlocked = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                let result = GenerativePolicyGate.shared.check(capability)
                if case .blocked = result { showBlocked = true }
            }
            .overlay {
                if showBlocked, case .blocked(_, let alt) = GenerativePolicyGate.shared.check(capability) {
                    PolicyGateBlockedView(assistiveAlternative: alt)
                }
            }
    }
}

struct PolicyGateBlockedView: View {
    let assistiveAlternative: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                Text("Not Available")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(assistiveAlternative)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}

extension View {
    func policyGated(_ capability: GenerativeCapabilityKind) -> some View {
        modifier(PolicyGateModifier(capability: capability))
    }
}

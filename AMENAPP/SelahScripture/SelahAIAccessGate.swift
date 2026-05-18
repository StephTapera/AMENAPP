//
//  SelahAIAccessGate.swift
//  AMENAPP
//
//  Single source of truth for whether the Selah AI surfaces (Berean Context,
//  Reflection Rewriting, Scripture Companion) are available to a given user
//  right now.
//
//  Gate composition:
//   1. The remote feature flag `selahScriptureActionsEnabled` (already
//      consulted by individual services for kill-switch behavior).
//   2. The user's age-assurance tier: AI generation surfaces are reserved
//      for the `.adult` tier. Minors see the calm reader, scripture,
//      reactions, and prayed-through markers — but never AI generation.
//   3. A user-facing opt-out persisted in UserDefaults.
//
//  The three AI services read this gate as their first guard. The reader
//  UI hides the Companion / Deeper Study / Rewrite chips when the gate
//  says `.disabled`, so the user never taps a button that can't function.
//

import Foundation
import SwiftUI

@MainActor
final class SelahAIAccessGate: ObservableObject {
    static let shared = SelahAIAccessGate()

    /// Why an AI surface is unavailable, when it is.
    enum Block: Equatable {
        case featureDisabledRemotely
        case minorUserAgeRestricted
        case userOptedOut
    }

    enum State: Equatable {
        case available
        case disabled(Block)

        var isAvailable: Bool {
            if case .available = self { return true }
            return false
        }

        var humanExplanation: String? {
            switch self {
            case .available: return nil
            case .disabled(.featureDisabledRemotely):
                return "AI features are not enabled in this build."
            case .disabled(.minorUserAgeRestricted):
                return "AI generation is available to adult accounts only."
            case .disabled(.userOptedOut):
                return "You turned off AI features in Selah. Re-enable in Settings."
            }
        }
    }

    @Published private(set) var state: State = .available

    private let defaults: UserDefaults
    private let optOutKey = "selah.ai.userOptedOut.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recompute()
    }

    /// User-facing opt-out (read-only externally; toggle via `setUserOptOut`).
    var userHasOptedOut: Bool {
        defaults.bool(forKey: optOutKey)
    }

    /// Persist the user's AI opt-out preference.
    func setUserOptOut(_ optedOut: Bool) {
        defaults.set(optedOut, forKey: optOutKey)
        recompute()
    }

    /// Call when the remote flag or age tier changes.
    func recompute() {
        if !AMENFeatureFlags.shared.selahScriptureActionsEnabled {
            state = .disabled(.featureDisabledRemotely)
            return
        }
        if AgeAssuranceService.shared.currentUserTier.isMinor {
            state = .disabled(.minorUserAgeRestricted)
            return
        }
        if userHasOptedOut {
            state = .disabled(.userOptedOut)
            return
        }
        state = .available
    }

    /// Lightweight pure check used by the AI services on every call (also
    /// recomputes; tier / flag / preference can change between calls).
    func currentState() -> State {
        recompute()
        return state
    }
}

// MARK: - Inline AI Settings Card

/// A compact opt-in / opt-out control for AI features. Suitable for a
/// Selah settings page or for embedding into the About Selah AI sheet.
struct SelahAISettingsCard: View {
    @ObservedObject var gate: SelahAIAccessGate = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use AI features in Selah")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Berean Context, Reflection Rewriting, Scripture Companion.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { !gate.userHasOptedOut },
                    set: { gate.setUserOptOut(!$0) }
                ))
                .labelsHidden()
                .disabled(disabledForReasonOtherThanOptOut)
            }
            if let explanation = gate.state.humanExplanation {
                Text(explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                SelahAIGeneratedBadge(compact: true)
                Text("Every AI response is labeled and grounded.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }

    /// When the AI features are disabled for reasons the user can't change
    /// (age, remote kill-switch), the toggle is locked so it doesn't lie
    /// about being on.
    private var disabledForReasonOtherThanOptOut: Bool {
        switch gate.state {
        case .available, .disabled(.userOptedOut): return false
        case .disabled(.minorUserAgeRestricted), .disabled(.featureDisabledRemotely): return true
        }
    }
}

#if DEBUG
#Preview("AI Settings Card") {
    SelahAISettingsCard()
        .padding(20)
        .background(Color(.systemGroupedBackground))
}
#endif

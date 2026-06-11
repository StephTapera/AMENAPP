// FaithConsentView.swift
// AMEN Universal Migration & Context System — Wave 1 (faith-builder)
//
// The dedicated faith CONSENT gate. By contract (CONTRACTS.md §3, ContextStoreModels
// `ContextTierTable.consentGatedCategories`) a plain-language consent screen MUST appear
// before the FIRST server-readable (Tier C) faith write.
//
//   • ACCEPT  → Tier-C faith writes are allowed (faith matching enabled).
//   • DECLINE → faith facets remain Tier P (client-only); NO server-readable faith write
//               ever occurs; faith matching — and ONLY faith matching — is disabled.
//
// This file owns:
//   • FaithConsentState   — the persisted decision (reusable, observable)
//   • FaithConsentView    — the plain-language gate screen (GlassKit)
//   • .faithConsentGate() — a reusable modifier the Faith Journey builder uses.
//
// NO scores / levels / rankings anywhere — by contract.

import SwiftUI

// MARK: - Consent decision

enum FaithConsentDecision: String, Codable {
    case undecided   // never asked, or asked and dismissed without choosing
    case accepted    // server-readable (Tier C) faith writes allowed → matching ON
    case declined    // faith facets stay Tier P, no server-readable write → matching OFF
}

/// Reusable, observable holder for the faith consent decision.
///
/// `effectiveTierCAllowed` is the single source of truth the builder consults before
/// emitting any Tier-C faith facet. Even when allowed, the per-facet tier is STILL
/// derived from `ContextTierTable` — `*.areas_needing_support` always returns `.p`.
@MainActor
final class FaithConsentState: ObservableObject {
    static let shared = FaithConsentState()

    @Published private(set) var decision: FaithConsentDecision

    // TODO(gate: HUMAN-MACHINE) — store: persist via ContextStoreService once it exists. For now this is a
    // process-lifetime decision mirrored into UserDefaults so the gate isn't re-shown
    // every launch. No faith CONTENT is stored here — only the yes/no decision.
    private let defaultsKey = "amen.faith.consent.decision.v1"

    private init() {
        let raw = UserDefaults.standard.string(forKey: defaultsKey)
        self.decision = raw.flatMap(FaithConsentDecision.init(rawValue:)) ?? .undecided
    }

    /// True only when the user has explicitly accepted. Declining or being undecided
    /// keeps this false, which forces every faith facet down the Tier-P, client-only path.
    var effectiveTierCAllowed: Bool { decision == .accepted }

    func accept() { persist(.accepted) }
    func decline() { persist(.declined) }

    /// Allows the user to "turn this off anytime" (per the required copy).
    func revoke() { persist(.declined) }

    private func persist(_ d: FaithConsentDecision) {
        decision = d
        UserDefaults.standard.set(d.rawValue, forKey: defaultsKey)
    }
}

// MARK: - Consent screen

/// Plain-language faith consent gate. Presented before the first Tier-C faith write.
struct FaithConsentView: View {
    @ObservedObject var state: FaithConsentState
    /// Called after the user makes (or changes) a choice so the host can dismiss.
    var onResolved: (FaithConsentDecision) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var allowMatching: Bool

    init(state: FaithConsentState, onResolved: @escaping (FaithConsentDecision) -> Void = { _ in }) {
        self.state = state
        self.onResolved = onResolved
        _allowMatching = State(initialValue: state.decision == .accepted)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                // Plain-language explanation — required copy.
                VStack(alignment: .leading, spacing: 8) {
                    Text("In plain language")
                        .font(.subheadline.weight(.semibold))
                    Text("AMEN's servers will use this to match you with churches and communities. You can turn this off anytime.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(consentPanel)

                // Distinct opt-in toggle.
                Toggle(isOn: $allowMatching.animation(Motion.adaptive(Motion.popToggle))) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Allow faith matching")
                            .font(.body.weight(.semibold))
                        Text("Lets AMEN's servers read your faith details to suggest churches and communities.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.green)
                .accessibilityHint("When off, your faith details stay private on this device and faith matching is disabled.")

                // What declining means — explicit degradation.
                Text("If you decline, everything you enter stays private on this device (Tier P). Nothing faith-related is sent to AMEN's servers, and faith matching stays off. Declining disables faith matching only — nothing else.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                buttons
            }
            .padding(20)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "cross.fill")
                .font(.title)
                .foregroundStyle(.secondary)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("Use your Faith Journey to connect you")
                .font(.title2.weight(.bold))
            Text("You're about to add details about your faith. These can help AMEN connect you — but only if you say yes here first.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var consentPanel: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                resolve(allowMatching ? .accepted : .declined)
            } label: {
                Text(allowMatching ? "Turn on faith matching" : "Keep my faith details private")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                resolve(.declined)
            } label: {
                Text("Not now")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func resolve(_ decision: FaithConsentDecision) {
        switch decision {
        case .accepted: state.accept()
        case .declined: state.decline()
        case .undecided: break
        }
        onResolved(decision)
        dismiss()
    }
}

// MARK: - Reusable gate modifier

/// Presents the faith consent screen the first time the host needs a Tier-C faith write,
/// or whenever `present` is set true. The host reads `state.effectiveTierCAllowed` to
/// decide whether faith facets may be written server-readable (Tier C) or must stay Tier P.
private struct FaithConsentGateModifier: ViewModifier {
    @ObservedObject var state: FaithConsentState
    @Binding var present: Bool
    var onResolved: (FaithConsentDecision) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $present) {
                FaithConsentView(state: state) { decision in
                    onResolved(decision)
                }
                .presentationDetents([.large])
            }
    }
}

extension View {
    /// Attaches the reusable faith consent gate. Set `present` true to show it.
    /// On resolve, `onResolved` fires with the user's decision; the host then keys
    /// its Tier-C-vs-Tier-P write path off `state.effectiveTierCAllowed`.
    func faithConsentGate(
        state: FaithConsentState,
        present: Binding<Bool>,
        onResolved: @escaping (FaithConsentDecision) -> Void = { _ in }
    ) -> some View {
        modifier(FaithConsentGateModifier(state: state, present: present, onResolved: onResolved))
    }
}

#if DEBUG
#Preview("Faith Consent Gate") {
    FaithConsentView(state: FaithConsentState.shared)
}
#endif

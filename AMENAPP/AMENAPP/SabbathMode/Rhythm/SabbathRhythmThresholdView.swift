// SabbathRhythmThresholdView.swift
// AMENAPP — SabbathMode / Rhythm (Sabbath Mode v2, Wave 0)
//
// The threshold surfaces: a deliberate begin (entry ritual), the calm in-rest
// surface (with the always-available exit — I1), and the private gentle return
// ("what can wait" reframe, optional reflection — no notification dump, no streak).
//
// Rest with edges feels like rest. All copy is guilt-free.

import SwiftUI

// MARK: - Calm palette

private enum SabbathRhythmTokens {
    /// Ivory, restful background — "calm palette" (SabbathSubtractionPolicy.calmPalette).
    static let canvas = Color(red: 0.98, green: 0.97, blue: 0.95)
    static let ink = Color(red: 0.16, green: 0.15, blue: 0.13)
    static let secondaryInk = Color(red: 0.42, green: 0.40, blue: 0.37)
    static let hairline = Color(red: 0.16, green: 0.15, blue: 0.13).opacity(0.10)
}

// MARK: - In-rest surface (shown over Home while resting)

/// The single calm surface presented during the takeover states (`.rest` and the deeper
/// `.holyGround`). Its only required job is to hold the one-tap, guilt-free exit (I1); it
/// also offers a gentle path to deepen into prayer and back. Copy adapts to the active state.
struct SabbathRestSurfaceView: View {
    @ObservedObject private var controller = SabbathRhythmController.shared
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var reduceMotion: Bool {
        systemReduceMotion || controller.activePolicy.reduceMotion
    }

    private var isHolyGround: Bool { controller.state == .holyGround }

    private var glyph: String { isHolyGround ? "sparkles" : "leaf" }
    private var title: String { isHolyGround ? "Holy ground" : "Resting" }
    private var subtitle: String {
        isHolyGround
            ? "Just stillness. Stay as long as you like."
            : "Selah is quiet for now. Nothing here needs you."
    }

    var body: some View {
        ZStack {
            SabbathRhythmTokens.canvas.ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer(minLength: 0)

                Image(systemName: glyph)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(SabbathRhythmTokens.secondaryInk)
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text(title)
                        .font(.custom("Georgia", size: 30))
                        .foregroundStyle(SabbathRhythmTokens.ink)

                    Text(subtitle)
                        .font(.system(size: 16))
                        .foregroundStyle(SabbathRhythmTokens.secondaryInk)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 36)
                }

                // `.holyGround` is single-surface by design — the named burden is hidden there.
                if let intention = controller.currentIntention, !isHolyGround {
                    VStack(spacing: 5) {
                        Text("You set down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SabbathRhythmTokens.secondaryInk)
                        Text(intention)
                            .font(.system(size: 16))
                            .foregroundStyle(SabbathRhythmTokens.ink)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(SabbathRhythmTokens.hairline, lineWidth: 1)
                    )
                    .padding(.horizontal, 32)
                }

                Spacer(minLength: 0)

                // Gentle deepen / return path between `.rest` and `.holyGround`. Optional,
                // never required — the only *necessary* control is the exit below (I1).
                if isHolyGround {
                    Button { controller.returnToRest() } label: {
                        Text("Return to rest")
                            .font(.system(size: 15))
                            .foregroundStyle(SabbathRhythmTokens.secondaryInk)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Eases back from prayer to ordinary rest")
                } else {
                    Button { controller.deepenToHolyGround() } label: {
                        Label("Go deeper — prayer", systemImage: "sparkles")
                            .font(.system(size: 15))
                            .foregroundStyle(SabbathRhythmTokens.secondaryInk)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Enters a single, silent prayer surface")
                }

                // Invariant I1 — always-available, one-tap, guilt-free exit.
                Button {
                    controller.leaveRest()
                } label: {
                    Text("Leave rest")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SabbathRhythmTokens.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(SabbathRhythmTokens.ink.opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .padding(.bottom, 28)
                .accessibilityLabel("Leave rest")
                .accessibilityHint("Returns you to the full app")
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

// MARK: - Begin threshold (entry ritual)

/// The deliberate entry to rest. Optionally names the burden being laid down
/// (Sabbath Intention). Confirming commits `.rest`.
struct SabbathThresholdBeginView: View {
    @ObservedObject private var controller = SabbathRhythmController.shared
    @Environment(\.dismiss) private var dismiss
    @State private var intention: String = ""

    var body: some View {
        ZStack {
            SabbathRhythmTokens.canvas.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 0)

                Image(systemName: "flame")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(SabbathRhythmTokens.secondaryInk)
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("Begin rest")
                        .font(.custom("Georgia", size: 28))
                        .foregroundStyle(SabbathRhythmTokens.ink)
                    Text("Is there something you'd like to lay down?")
                        .font(.system(size: 15))
                        .foregroundStyle(SabbathRhythmTokens.secondaryInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                TextField("Optional — a worry, a task, a name", text: $intention, axis: .vertical)
                    .font(.system(size: 16))
                    .foregroundStyle(SabbathRhythmTokens.ink)
                    .lineLimit(1...3)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(SabbathRhythmTokens.hairline, lineWidth: 1)
                    )
                    .padding(.horizontal, 28)

                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    Button {
                        controller.confirmBeginRest(intention: intention)
                    } label: {
                        Text("Enter rest")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SabbathRhythmTokens.canvas)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(SabbathRhythmTokens.ink)
                            )
                    }
                    .buttonStyle(.plain)

                    Button("Not now") { dismiss() }
                        .font(.system(size: 15))
                        .foregroundStyle(SabbathRhythmTokens.secondaryInk)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
    }
}

// MARK: - Gentle return

/// Shown privately *after* leaving rest. Reframes from "what you missed" to
/// "what can wait", offers an optional reflection, and never dumps notifications.
struct SabbathGentleReturnView: View {
    let signal: SabbathRestSignal

    @ObservedObject private var controller = SabbathRhythmController.shared
    @Environment(\.dismiss) private var dismiss
    @State private var reflection: String = ""

    var body: some View {
        ZStack {
            SabbathRhythmTokens.canvas.ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Text("Welcome back")
                        .font(.custom("Georgia", size: 28))
                        .foregroundStyle(SabbathRhythmTokens.ink)
                    // "What can wait" reframe — rest cost nothing.
                    Text("Everything here stayed the same. What was waiting can keep waiting a little longer.")
                        .font(.system(size: 15))
                        .foregroundStyle(SabbathRhythmTokens.secondaryInk)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 32)
                }

                // Private, qualitative — never a chase-able number (I2).
                Text(Self.restPhrase(for: signal.timeInState))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SabbathRhythmTokens.secondaryInk)

                VStack(alignment: .leading, spacing: 8) {
                    Text("A quiet thought, if you have one")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SabbathRhythmTokens.secondaryInk)
                    TextField("Only you will ever see this", text: $reflection, axis: .vertical)
                        .font(.system(size: 16))
                        .foregroundStyle(SabbathRhythmTokens.ink)
                        .lineLimit(1...4)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(SabbathRhythmTokens.hairline, lineWidth: 1)
                        )
                }
                .padding(.horizontal, 28)

                Spacer(minLength: 0)

                Button {
                    controller.recordReturnReflection(reflection, for: signal)
                    controller.dismissReturn()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SabbathRhythmTokens.canvas)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(SabbathRhythmTokens.ink)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
    }

    /// Map a duration to a gentle, non-comparative phrase. No precise count to chase.
    private static func restPhrase(for seconds: TimeInterval) -> String {
        switch seconds {
        case ..<(60 * 20):     return "A short pause."
        case ..<(60 * 90):     return "A real rest."
        default:               return "A long, unhurried rest."
        }
    }
}

// MARK: - Gated manual entry affordance

/// A discreet way to begin rest manually. Shown only when both `sabbath_mode_enabled`
/// and `sabbath_trigger_manual_enabled` are ON and the state is `.normal`.
struct SabbathEnterRestPill: View {
    @ObservedObject private var controller = SabbathRhythmController.shared
    @ObservedObject private var flags = AMENFeatureFlags.shared

    var body: some View {
        if flags.sabbathModeEnabled,
           flags.sabbathTriggerManualEnabled,
           controller.state == .normal {
            Button {
                controller.requestBeginRest()
            } label: {
                Label("Enter rest", systemImage: "leaf")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().stroke(SabbathRhythmTokens.ink.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(SabbathRhythmTokens.ink)
            .accessibilityLabel("Enter Sabbath rest")
        }
    }
}

// MARK: - Presence banner (non-blocking)

/// The `.presence` indicator. Unlike the takeover states, presence keeps navigation, so this
/// is a slim, dismissable banner — quiet acknowledgement, not a wall. Tapping "Leave" exits.
struct SabbathPresenceBanner: View {
    @ObservedObject private var controller = SabbathRhythmController.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hands.and.sparkles")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(SabbathRhythmTokens.secondaryInk)
                .accessibilityHidden(true)

            Text("In worship — Selah is quiet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SabbathRhythmTokens.ink)

            Spacer(minLength: 8)

            Button("Leave") { controller.leaveRest() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SabbathRhythmTokens.ink)
                .buttonStyle(.plain)
                .accessibilityHint("Returns you to the full app")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(SabbathRhythmTokens.canvas)
                .overlay(Capsule(style: .continuous).stroke(SabbathRhythmTokens.hairline, lineWidth: 1))
        )
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You are in worship. Selah is quiet.")
    }
}

// MARK: - Host modifier

/// Attach to the primary surface to (a) cover the app with the calm takeover surface during
/// `.rest` / `.holyGround`, (b) show the non-blocking presence banner during `.presence`, and
/// (c) present the begin / gentle-return thresholds. Inert unless Sabbath Mode is ON.
private struct SabbathRhythmHost: ViewModifier {
    @ObservedObject private var controller = SabbathRhythmController.shared
    @ObservedObject private var flags = AMENFeatureFlags.shared

    /// Full-screen takeover states — the calm surface covers everything (single-surface).
    private var isTakeover: Bool {
        flags.sabbathModeEnabled && (controller.state == .rest || controller.state == .holyGround)
    }

    /// Presence keeps navigation; only a slim banner is shown.
    private var isPresence: Bool {
        flags.sabbathModeEnabled && controller.state == .presence
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTakeover {
                    SabbathRestSurfaceView()
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .top) {
                if isPresence {
                    SabbathPresenceBanner()
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isTakeover)
            .animation(.easeInOut(duration: 0.25), value: isPresence)
            .sheet(item: $controller.presentation) { presentation in
                switch presentation {
                case .beginThreshold:
                    SabbathThresholdBeginView()
                case .gentleReturn(let signal):
                    SabbathGentleReturnView(signal: signal)
                }
            }
    }
}

extension View {
    /// Host the Sabbath rhythm rest surface + threshold sheets on a primary surface.
    func sabbathRhythmHost() -> some View {
        modifier(SabbathRhythmHost())
    }
}

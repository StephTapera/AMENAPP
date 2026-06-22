// AILCalmModeModifier.swift
// AMENAPP — Accessibility Intelligence Layer (AIL) · Interaction Surface (A5)
//
// C13 Calm Mode — ONE unified low-cognitive-load mode that EXTENDS the existing
// AmenSimpleModeService (it never reimplements it). When the user turns Calm Mode
// on (AILProfileService.shared.profile.calmMode), this modifier:
//   • Suppresses badge/count chrome — exposes `\.ailCalmModeActive` so any view can
//     read it and HIDE counters (likes/replies/unread tallies). No counts surfaced.
//   • Enforces a focus-card, one-thing-at-a-time feel via generous spacing/padding.
//   • Composes with Simple Mode: applies AmenSimpleModeService.shared.fontScale's
//     dynamicTypeSize so the two modes stack rather than fight.
//   • ALWAYS honors Apple's Reduce Motion + Reduce Transparency — we never override
//     or reimplement Apple accessibility; we defer to it.
//
// No tier checks. No force-unwraps. 4-space indent.

import SwiftUI

// MARK: - Environment key (counter suppression)

private struct AILCalmModeActiveKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// True when Calm Mode is active. Views that show counts/badges should read
    /// this and suppress that chrome (iron rule: NO counts surfaced in Calm Mode).
    var ailCalmModeActive: Bool {
        get { self[AILCalmModeActiveKey.self] }
        set { self[AILCalmModeActiveKey.self] = newValue }
    }
}

// MARK: - Modifier

struct AILCalmMode: ViewModifier {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // Read the live services so Calm Mode + Simple Mode compose.
    private var profileService = AILProfileService.shared
    private var simpleMode = AmenSimpleModeService.shared

    func body(content: Content) -> some View {
        let calmActive = profileService.profile.calmMode

        return Group {
            if calmActive {
                calmContent(content)
            } else {
                content
                    .environment(\.ailCalmModeActive, false)
            }
        }
    }

    @ViewBuilder
    private func calmContent(_ content: Content) -> some View {
        if let dynamicTypeSize = effectiveDynamicTypeSize {
            decoratedCalmContent(content)
                .dynamicTypeSize(dynamicTypeSize)
        } else {
            decoratedCalmContent(content)
        }
    }

    private func decoratedCalmContent(_ content: Content) -> some View {
        content
            .environment(\.ailCalmModeActive, true)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .transaction { txn in
                if reduceMotion { txn.animation = nil }
            }
    }

    /// When Simple Mode is also on, stack its font scale; otherwise pass through.
    private var effectiveDynamicTypeSize: DynamicTypeSize? {
        simpleMode.isSimpleModeActive ? simpleMode.fontScale.dynamicTypeSize : nil
    }
}

// MARK: - View extension

extension View {
    /// Apply Calm Mode (C13). Active only while the user's profile opts in. Honors
    /// Reduce Motion / Reduce Transparency and composes with Simple Mode.
    func ailCalmMode() -> some View {
        modifier(AILCalmMode())
    }
}

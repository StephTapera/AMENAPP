// AILCaptionRenderer.swift
// AMENAPP — Accessibility Intelligence Layer (AIL) · Perception Surface (A4)
//
// Renders a caption overlay from a [CaptionCue] (recorded) or a live cue stream,
// applying the user's CaptionStyle: font size, background (none/dim/solid),
// high-contrast colors, and top/bottom placement. Shows the last ~2–3 cues like a
// caption track.
//
// ACCESSIBILITY (iron rules):
//  • @Environment(\.accessibilityReduceTransparency): the `.solid` (and `.dim`)
//    backgrounds collapse to a FULLY OPAQUE fill — no translucency.
//  • @Environment(\.accessibilityReduceMotion): the animated reveal of new cues
//    is disabled (cues appear instantly, no transition).
//  • Captions are an OVERLAY aid — they never block the media beneath them.
//
// NO tier checks. No force-unwraps. 4-space indent.

import SwiftUI

/// A caption overlay. Drive it with a fixed `cues` array (recorded media) or push
/// live cues in via `liveCue`. Only the most recent few lines are shown.
struct AILCaptionRenderer: View {

    /// Recorded cues (optional). When a `liveCue` is supplied it takes precedence
    /// and is appended to a rolling on-screen buffer.
    var cues: [CaptionCue] = []

    /// The newest live cue, if rendering a live stream. Updating this animates a
    /// reveal (unless Reduce Motion is on).
    var liveCue: CaptionCue? = nil

    /// The style to apply. Defaults to the user's saved preference.
    var style: CaptionStyle = AILProfileService.shared.profile.captionStyle

    /// How many recent cues to keep visible (caption-track feel).
    var visibleCount: Int = 3

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Rolling buffer of the cues currently shown (most recent last).
    @State private var liveBuffer: [CaptionCue] = []

    var body: some View {
        VStack(spacing: 0) {
            if style.placement == .top {
                captionStack
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                captionStack
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)            // overlay aid — never intercepts media taps
        .onChange(of: liveCue) { _, newValue in
            guard let newValue else { return }
            appendLive(newValue)
        }
    }

    // MARK: - States

    @ViewBuilder
    private var captionStack: some View {
        let lines = displayedCues
        if lines.isEmpty {
            // Quiet empty state — nothing to show, render nothing visible.
            EmptyView()
        } else {
            VStack(alignment: .center, spacing: 4) {
                ForEach(lines) { cue in
                    captionLine(cue.text)
                        .transition(revealTransition)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: lines.map(\.id))
        }
    }

    private func captionLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: fontSize, weight: style.highContrast ? .bold : .semibold))
            .foregroundStyle(textColor)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(lineBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel(Text("Caption: \(text)"))
    }

    // MARK: - Cue selection

    /// The cues to render: live buffer when streaming, else the tail of `cues`.
    private var displayedCues: [CaptionCue] {
        let source = liveBuffer.isEmpty ? cues : liveBuffer
        return Array(source.suffix(visibleCount))
    }

    private func appendLive(_ cue: CaptionCue) {
        // Live recognizers re-emit a growing partial; replace the trailing partial
        // when it shares the same start, otherwise append a fresh line.
        if let last = liveBuffer.last, last.startMs == cue.startMs {
            liveBuffer[liveBuffer.count - 1] = cue
        } else {
            liveBuffer.append(cue)
        }
        if liveBuffer.count > visibleCount {
            liveBuffer.removeFirst(liveBuffer.count - visibleCount)
        }
    }

    // MARK: - Style mapping

    private var fontSize: CGFloat {
        switch style.size {
        case .small:  return 15
        case .medium: return 19
        case .large:  return 24
        case .xl:     return 30
        }
    }

    private var textColor: Color {
        if style.highContrast {
            return .white
        }
        return .primary
    }

    /// Per-line background. Reduce Transparency forces every shaded variant to a
    /// fully opaque fill (iron rule).
    @ViewBuilder
    private var lineBackground: some View {
        switch style.background {
        case .none:
            // No background — but high contrast still needs a readable backing.
            if style.highContrast {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(opaqueBacking)
            } else {
                Color.clear
            }
        case .dim:
            if reduceTransparency || style.highContrast {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(opaqueBacking)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.45))
            }
        case .solid:
            // `.solid` is the Reduce-Transparency fallback — always fully opaque.
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(opaqueBacking)
        }
    }

    private var opaqueBacking: Color {
        style.highContrast ? Color.black : Color(.systemBackground)
    }

    private var revealTransition: AnyTransition {
        reduceMotion ? .identity : .opacity
    }
}

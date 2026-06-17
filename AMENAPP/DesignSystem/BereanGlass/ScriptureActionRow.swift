// ScriptureActionRow.swift
// AMEN — Berean Reading Surface component (W0 shell → W1 implementation)
//
// W0: Public signature frozen.
// W1: Implement inside a single GlassEffectContainer.
//     Scroll-aware: collapses when reader scrolls down (actionRowCollapse spring),
//     restores on scroll stop. Blurs reader text behind the row.
//     Actions: Save · Share · Pray · Explain · More.
//     All actions require 44pt targets + VoiceOver labels.
//     Share routes through Guard before any share sheet is shown.

import SwiftUI

/// Scripture passage context + primary actions, clustered in one GlassEffectContainer.
struct ScriptureActionRow: View {

    let passageTitle: String
    let isCollapsed: Bool
    let onSave: () -> Void
    let onShare: () -> Void   // caller confirms + routes through Guard before invoking
    let onPray: () -> Void
    let onExplain: () -> Void
    let onMore: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // W1: Replace with GlassEffectContainer + collapse animation.
        // Collapse/expand is gated on reduceMotion: spring when motion is allowed,
        // instant opacity-only when reduce motion is enabled (actionRowCollapse spring).
        if !isCollapsed {
            VStack(spacing: 4) {
                Text(passageTitle)
                    .font(BereanType.subheadline())
                    .foregroundStyle(Color.bereanInk)

                HStack(spacing: 0) {
                    actionButton("bookmark",             label: "Save",    action: onSave)
                    actionButton("square.and.arrow.up",  label: "Share",   action: onShare)
                    actionButton("hands.and.sparkles.fill", label: "Pray", action: onPray)
                    actionButton("text.magnifyingglass", label: "Explain", action: onExplain)
                    actionButton("ellipsis",             label: "More",    action: onMore)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            // W1: collapse transition respects reduce motion.
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func actionButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .frame(width: BereanMetrics.minTapTarget, height: BereanMetrics.minTapTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

#Preview {
    ScriptureActionRow(
        passageTitle: "John 1:1",
        isCollapsed: false,
        onSave: {}, onShare: {}, onPray: {}, onExplain: {}, onMore: {}
    )
    .padding()
}

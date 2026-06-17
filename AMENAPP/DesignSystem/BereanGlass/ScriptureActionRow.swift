// ScriptureActionRow.swift
// AMEN — Berean Reading Surface: ScriptureActionRow component (W1)
//
// Scripture passage title + 5 actions in one glass container.
// Scroll-aware collapse: caller drives isCollapsed via scroll offset.
// Share: caller confirms + routes through Guard before invoking onShare.
// ReduceTransparency: solid bereanIvory bar.

import SwiftUI

/// Scripture passage context + primary actions.
/// Wrap in a GlassEffectContainer at the call site for batched blur.
struct ScriptureActionRow: View {

    let passageTitle: String
    let isCollapsed: Bool
    let onSave: () -> Void
    let onShare: () -> Void
    let onPray: () -> Void
    let onExplain: () -> Void
    let onMore: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if !isCollapsed {
                rowContent
                    .transition(
                        reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                    )
            }
        }
        .animation(
            .berean(BereanSpring.actionRowCollapse, reduceMotion: reduceMotion),
            value: isCollapsed
        )
        .clipped()
    }

    private var rowContent: some View {
        VStack(spacing: 6) {
            // Passage title
            Text(passageTitle)
                .font(BereanType.subheadline())
                .foregroundStyle(Color.bereanInk.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 10)

            // Divider
            Rectangle()
                .fill(Color.bereanTan.opacity(0.5))
                .frame(height: BereanMetrics.strokeWidth)
                .padding(.horizontal, 20)

            // Action strip
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                actionButton("bookmark",                label: "Save",    action: onSave)
                actionButton("square.and.arrow.up",     label: "Share",   action: onShare)
                actionButton("hands.and.sparkles.fill", label: "Pray",    action: onPray)
                actionButton("text.magnifyingglass",    label: "Explain", action: onExplain)
                actionButton("ellipsis",                label: "More",    action: onMore)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 10)
        }
        .background(reduceTransparency ? Color.bereanIvory : Color.bereanIvory.opacity(0.92))
    }

    @ViewBuilder
    private func actionButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.body.weight(.regular))
                Text(label)
                    .font(BereanType.caption())
            }
            .foregroundStyle(Color.bereanInk)
            .frame(minWidth: BereanMetrics.minTapTarget, minHeight: BereanMetrics.minTapTarget)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
    }
}

#Preview("Visible") {
    VStack {
        Spacer()
        ScriptureActionRow(
            passageTitle: "John 1:1-5 (NIV)",
            isCollapsed: false,
            onSave: {}, onShare: {}, onPray: {}, onExplain: {}, onMore: {}
        )
    }
    .background(Color.bereanWhite)
}

#Preview("Collapsed") {
    VStack {
        Spacer()
        ScriptureActionRow(
            passageTitle: "John 1:1-5 (NIV)",
            isCollapsed: true,
            onSave: {}, onShare: {}, onPray: {}, onExplain: {}, onMore: {}
        )
    }
    .background(Color.bereanWhite)
}

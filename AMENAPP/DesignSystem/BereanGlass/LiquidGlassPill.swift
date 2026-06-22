// LiquidGlassPill.swift
// AMEN — Berean Reading Surface: BereanActionPill component (W1)
//
// Selected state: filled bereanInk bg, ivory text.
// Unselected: glass/ivory chip, ink text.
// ReduceTransparency: solid bereanTan (unselected) / bereanInk (selected).
// Press feedback: scale ~0.96, gated on ReduceMotion.

import SwiftUI

/// Tappable chip/filter pill for the Berean reading surface.
struct BereanActionPill: View {

    let label: String
    let icon: String?
    let isSelected: Bool
    let accessibilityHint: String?
    let onTap: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPressed = false

    init(
        label: String,
        icon: String? = nil,
        isSelected: Bool = false,
        accessibilityHint: String? = nil,
        onTap: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.isSelected = isSelected
        self.accessibilityHint = accessibilityHint
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(label)
                    .font(BereanType.subheadline())
            }
            .foregroundStyle(isSelected ? Color.bereanIvory : Color.bereanInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: BereanMetrics.minTapTarget)
            .background(pillBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.clear : Color.bereanTan,
                        lineWidth: BereanMetrics.strokeWidth
                    )
            )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .scaleEffect(isPressed && !reduceMotion ? 0.96 : 1.0)
        .animation(
            .berean(BereanSpring.pillPress, reduceMotion: reduceMotion),
            value: isPressed
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
        )
        .accessibilityLabel(label)
        .accessibilityHint(accessibilityHint ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var pillBackground: some View {
        if isSelected {
            Color.bereanInk.opacity(reduceTransparency ? 1.0 : 0.88)
        } else if reduceTransparency {
            Color.bereanTan
        } else {
            Color.bereanIvory.opacity(0.75)
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        HStack(spacing: 8) {
            BereanActionPill(label: "Scripture", icon: "book.fill", isSelected: true, onTap: {})
            BereanActionPill(label: "Prayer", icon: "hands.and.sparkles.fill", onTap: {})
            BereanActionPill(label: "Notes", onTap: {})
        }
        HStack(spacing: 8) {
            BereanActionPill(label: "Discern", icon: "sparkle", isSelected: false, onTap: {})
            BereanActionPill(label: "Build", onTap: {})
        }
    }
    .padding()
    .background(Color.bereanIvory)
}

// SmartActionPills.swift
// AMENAPP — Berean Assistant smart-action pill row.
//
// Horizontally scrollable glass capsule pills driven by BereanIntelligenceEngine.
// Renders EmptyView when the actions array is empty.
// Full reduced-motion + reduced-transparency support.

import SwiftUI

// MARK: - SmartActionPills

struct SmartActionPills: View {
    let actions: [SmartAction]
    let onSelect: (SmartAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var appeared = false

    var body: some View {
        if actions.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(actions) { action in
                        pillButton(for: action)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
            .onAppear {
                let animation: Animation? = reduceMotion
                    ? nil
                    : .spring(response: 0.35, dampingFraction: 0.78).delay(0.05)
                if let animation {
                    withAnimation(animation) { appeared = true }
                } else {
                    appeared = true
                }
            }
            .onDisappear {
                appeared = false
            }
        }
    }

    // MARK: - Individual Pill

    @ViewBuilder
    private func pillButton(for action: SmartAction) -> some View {
        Button {
            HapticManager.impact(style: .light)
            onSelect(action)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(action.title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
            .background {
                if reduceTransparency {
                    Capsule()
                        .fill(Color(.secondarySystemBackground))
                }
            }
            .glassEffect(
                reduceTransparency ? GlassEffectStyle.identity : GlassEffectStyle.regular,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BereanAccessibility.selectableLabel(action))
        .accessibilityHint("Double tap to use this Berean suggestion")
    }
}

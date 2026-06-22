// BereanIntentSwitchChip.swift
// AMENAPP — Berean Spiritual Intelligence Layer (Wave 2)
//
// Small capsule pill that surfaces the auto-selected (mode × depth) proposal.
// Visible only when confidence >= 0.7 and bereanIntentSwitchEnabled is ON.
// Tapping opens a popover with the 5-stop BereanDepthDialView.

import SwiftUI

struct BereanIntentSwitchChip: View {

    let proposal: IntentProposal
    let onOverride: (BereanDepth) -> Void

    @State private var showDepthPicker = false
    @State private var appeared = false

    // Reduce-motion preference
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Guard: hide chip when flag is OFF or confidence too low
        if !AMENFeatureFlags.shared.bereanIntentSwitchEnabled
            || proposal.confidence < 0.7 {
            EmptyView()
        } else {
            chipContent
                .scaleEffect(appeared ? 1.0 : 0.85)
                .opacity(appeared ? 1.0 : 0.0)
                .onAppear {
                    if reduceMotion {
                        appeared = true
                    } else {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            appeared = true
                        }
                    }
                }
        }
    }

    // MARK: - Chip

    private var chipContent: some View {
        Button {
            showDepthPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: modeIcon)
                    .font(.caption.weight(.semibold))
                Text(proposal.depth.displayLabel)
                    .font(.caption.weight(.semibold))
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(proposal.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .foregroundStyle(.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text("Berean is \(proposal.rationale). Tap to change depth.")
        )
        .popover(isPresented: $showDepthPicker) {
            depthPickerPopover
        }
    }

    // MARK: - Popover

    private var depthPickerPopover: some View {
        BereanDepthDialView(
            currentDepth: proposal.depth,
            autoDepth: proposal.depth,
            onSelect: { depth in
                showDepthPicker = false
                onOverride(depth)
            }
        )
        .padding()
        .frame(minWidth: 260)
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - Mode Icon

    private var modeIcon: String {
        switch proposal.mode {
        case .ask:     return "sparkles"
        case .discern: return "scale.3d"
        case .build:   return "hammer"
        case .reflect: return "heart"
        case .guard:   return "shield"
        }
    }
}

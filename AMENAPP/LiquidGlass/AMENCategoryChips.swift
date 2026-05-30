// AMENCategoryChips.swift
// AMEN App — Horizontal scrollable glass pill filter strip.
//
// Idle: light frosted glass (white tint over bright content, iOS-Photos style).
// Selected: amenGold tint overlay over the same glass surface.
// iOS 26+: native glassEffect.  iOS 17-25: ultraThinMaterial fallback.

import SwiftUI

// MARK: - Model

struct AMENCategoryChip: Identifiable, Equatable {
    let id: String
    let label: String

    init(id: String = UUID().uuidString, label: String) {
        self.id  = id
        self.label = label
    }
}

// MARK: - Strip View

struct AMENCategoryChips: View {
    let chips: [AMENCategoryChip]
    @Binding var selectedID: String?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AMENGlassMediaTokens.chipSpacing) {
                ForEach(chips) { chip in
                    chipButton(chip)
                }
            }
            .padding(.horizontal, AMENGlassMediaTokens.chipStripHPad)
            .padding(.vertical, 2)        // prevent clipping of shadow
        }
        .frame(height: AMENGlassMediaTokens.chipHeight + 4)
    }

    // MARK: - Chip Button

    @ViewBuilder
    private func chipButton(_ chip: AMENCategoryChip) -> some View {
        let isSelected = selectedID == chip.id

        Button {
            withAnimation(reduceMotion ? .none : .amenSpringStandard) {
                selectedID = isSelected ? nil : chip.id
            }
            HapticManager.impact(style: .light)
        } label: {
            Text(chip.label)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(Color.primary.opacity(isSelected ? 1.0 : 0.65))
                .lineLimit(1)
                .padding(.horizontal, AMENGlassMediaTokens.chipHPad)
                .padding(.vertical, AMENGlassMediaTokens.chipVPad)
                .background { chipBackground(isSelected: isSelected) }
                .overlay { chipBorder(isSelected: isSelected) }
                .clipShape(Capsule(style: .continuous))
                .frame(height: AMENGlassMediaTokens.chipHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chip.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isSelected ? "Tap to deselect" : "Tap to filter by \(chip.label)")
    }

    // MARK: - Background

    @ViewBuilder
    private func chipBackground(isSelected: Bool) -> some View {
        if reduceTransparency {
            Capsule(style: .continuous)
                .fill(isSelected
                    ? Color.amenGold
                    : Color(.systemBackground).opacity(0.92))
        } else if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(Color.clear)
                .glassEffect(Glass.regular.interactive(), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .fill(isSelected
                            ? Color.amenGold.opacity(AMENGlassMediaTokens.selectedGoldOpacity)
                            : Color.white.opacity(AMENGlassMediaTokens.idleFrostOpacity))
                }
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(isSelected
                            ? Color.amenGold.opacity(AMENGlassMediaTokens.selectedGoldOpacity)
                            : Color.white.opacity(AMENGlassMediaTokens.idleFrostOpacity))
                }
        }
    }

    // MARK: - Border

    private func chipBorder(isSelected: Bool) -> some View {
        Capsule(style: .continuous)
            .strokeBorder(
                isSelected
                    ? Color.amenGold.opacity(AMENGlassMediaTokens.selectedStrokeOpacity)
                    : Color.white.opacity(AMENGlassMediaTokens.strokeOpacity),
                lineWidth: 0.8
            )
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var selected: String? = nil
    let chips = ["All", "Faith", "Prayer", "Worship", "Testimony"].map {
        AMENCategoryChip(label: $0)
    }

    ZStack {
        Color(red: 0.96, green: 0.94, blue: 0.90).ignoresSafeArea()
        VStack(spacing: 24) {
            Text("Light canvas").font(.headline)
            AMENCategoryChips(chips: chips, selectedID: $selected)
        }
    }
}

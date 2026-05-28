import SwiftUI

struct AmenObjectHubTopicChips: View {
    let chips: [AmenHubTopicChip]
    @Binding var selectedChip: AmenHubTopicChip?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var accessibilityContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var glass: AmenObjectHubLiquidGlassStyle {
        AmenObjectHubLiquidGlassStyle(reduceTransparency: reduceTransparency, increasedContrast: accessibilityContrast == .increased)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(label: "All", selected: selectedChip == nil) { selectedChip = nil }
                ForEach(chips) { chip in
                    chipButton(label: chip.label, selected: selectedChip?.id == chip.id) {
                        selectedChip = selectedChip?.id == chip.id ? nil : chip
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .animation(reduceMotion ? .none : .spring(response: 0.34, dampingFraction: 0.84), value: selectedChip?.id)
    }

    private func chipButton(label: String, selected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(glass.primaryText)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(minHeight: 44)
                .background(selected ? AnyShapeStyle(Color.white.opacity(0.95)) : glass.materialSurface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(glass.glassBorder.opacity(selected ? 1 : 0.86), lineWidth: 1))
                .shadow(color: glass.shadow.opacity(selected ? 1 : 0.55), radius: selected ? 8 : 4, x: 0, y: selected ? 4 : 2)
        }
        .buttonStyle(AmenHubGlassButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(label)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }
}

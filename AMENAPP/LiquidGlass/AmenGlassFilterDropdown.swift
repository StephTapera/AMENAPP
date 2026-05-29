import SwiftUI

// MARK: - Data Models

struct AmenFilterOption: Identifiable, Equatable {
    let id: String
    let label: String
    let icon: String? // optional SF symbol

    init(id: String, label: String, icon: String? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
    }
}

struct AmenFilterSection {
    let header: String? // nil = no section header
    let options: [AmenFilterOption]
}

// MARK: - AmenGlassFilterDropdown
// Floating glass dropdown card anchored to the top-trailing edge of its parent.
// Renders as an inline ZStack overlay — not a sheet or popover.
// Entrance: scale(0.92, anchor: .topTrailing) + opacity, driven by .amenSpring equivalent.
// Dismiss: tap a clear full-screen overlay beneath the card.

struct AmenGlassFilterDropdown: View {
    let sections: [AmenFilterSection]
    @Binding var selectedId: String
    @Binding var isShowing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // Spec: spring(response: 0.32, dampingFraction: 0.82)
    private var entranceAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.15)
            : .spring(response: 0.32, dampingFraction: 0.82)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Full-screen clear tap-to-dismiss layer beneath the card
            if isShowing {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(entranceAnimation) { isShowing = false }
                    }
            }

            // The card itself
            if isShowing {
                dropdownCard
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.92, anchor: .topTrailing)
                                .combined(with: .opacity),
                            removal: .scale(scale: 0.92, anchor: .topTrailing)
                                .combined(with: .opacity)
                        )
                    )
            }
        }
        .animation(entranceAnimation, value: isShowing)
    }

    // MARK: - Card

    private var dropdownCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.offset) { sectionIdx, section in
                // Section divider (between sections only, not before the first)
                if sectionIdx > 0 {
                    Rectangle()
                        .fill(Color.separator.opacity(0.4))
                        .frame(height: 0.5)
                        .padding(.horizontal, 12)
                }

                // Section header
                if let header = section.header {
                    Text(header.uppercased())
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(Color.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, sectionIdx == 0 ? 12 : 10)
                        .padding(.bottom, 2)
                }

                // Options
                ForEach(section.options) { option in
                    optionRow(option, isFirstInSection: section.header == nil && option.id == section.options.first?.id && sectionIdx == 0)
                }

                // Bottom padding on last section
                if sectionIdx == sections.count - 1 {
                    Spacer().frame(height: 6)
                }
            }
        }
        .frame(width: 260)
        .background { cardBackground }
        .shadow(color: Color.primary.opacity(0.10), radius: 20, x: 0, y: 8)
        // Accessibility: treat the card as a group so VoiceOver announces it correctly
        .accessibilityElement(children: .contain)
    }

    // MARK: - Option Row

    private func optionRow(_ option: AmenFilterOption, isFirstInSection: Bool) -> some View {
        let isSelected = option.id == selectedId

        return Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                selectedId = option.id
            }
            // Short delay so the selection flash is visible before dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(entranceAnimation) { isShowing = false }
            }
        } label: {
            HStack(spacing: 10) {
                // Leading icon (optional)
                if let icon = option.icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSelected ? AmenTheme.Colors.amenGold : Color.secondary)
                        .frame(width: 20)
                }

                // Label
                Text(option.label)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                Spacer()

                // Trailing checkmark for selected state
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .contentShape(Rectangle())
            .background(
                isSelected
                    ? AmenTheme.Colors.amenGold.opacity(0.12)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Background

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                }
        } else {
            // Light glass surface per spec: systemBackground tint, not dark.
            // iOS 26+: hardware glass via amenGlassEffect; iOS <26: ultraThinMaterial fallback.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LiquidGlassTokens.blurRegular)
                .amenGlassEffect(Color(.systemBackground).opacity(0.3), cornerRadius: 18)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
                }
        }
    }
}

// MARK: - Filter Button

/// Drop-in filter button that toggles AmenGlassFilterDropdown.
/// Place this inside an `.overlay(alignment: .topTrailing)` on the parent container.
struct AmenFilterButton: View {
    @Binding var isShowing: Bool

    @GestureState private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                isShowing.toggle()
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed && !reduceMotion ? 0.92 : 1.0)
        .gesture(DragGesture(minimumDistance: 0).updating($isPressed) { _, s, _ in s = true })
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isPressed)
        .accessibilityLabel("Filter feed")
        .accessibilityAddTraits(.isButton)
    }
}

// AmenSearchDisambiguationPopup.swift
// AMEN App — Liquid Glass search-mode disambiguation card.
//
// Appears below a search bar when the user taps the dormant capsule.
// The user picks a mode; the popup dismisses and the caller routes
// to the correct destination.  Normal text-search focusing is also
// handled by the caller after dismissal.
//
// Design tokens: amenGold / amenBlue / amenPurple from AmenTheme.Colors.
// Motion: .amenSpring (show/hide), .amenSnappy (row press feedback).
// Glass: .amenGlassEffect(tint:cornerRadius:) from AmenGlassKit.swift.

import SwiftUI

// MARK: - AmenSearchMode

struct AmenSearchMode: Identifiable {
    let id: String
    let icon: String        // SF Symbol name
    let iconColor: Color    // AMEN brand token
    let label: String
    let subtitle: String
}

// MARK: - AmenSearchDisambiguationPopup

struct AmenSearchDisambiguationPopup: View {

    let modes: [AmenSearchMode]
    var onSelect: (AmenSearchMode) -> Void
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
                ModeRow(mode: mode) {
                    onSelect(mode)
                }
                if index < modes.count - 1 {
                    Divider()
                        .frame(height: 0.5)
                        .background(Color.separator.opacity(0.4))
                        .padding(.leading, 52)
                }
            }
        }
        .padding(.vertical, 4)
        .background(cardBackground)
        .shadow(color: Color.primary.opacity(0.12), radius: 24, x: 0, y: 10)
        .transition(
            reduceMotion
                ? .opacity
                : .scale(scale: 0.94, anchor: .top).combined(with: .opacity)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search mode options")
    }

    // MARK: - Card background

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
            // iOS 26+: amenGlassEffect provides the glass surface with the systemBackground tint.
            // iOS < 26: the modifier is a no-op so the regularMaterial fill is the visual fallback.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .amenGlassEffect(Color(.systemBackground).opacity(0.35), cornerRadius: 18)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
                }
        }
    }
}

// MARK: - ModeRow

private struct ModeRow: View {
    let mode: AmenSearchMode
    let action: () -> Void

    @GestureState private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: mode.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(mode.iconColor)
                    .frame(width: 28, height: 28)

                // Labels
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.label)
                        .font(AMENFont.semiBold(16))
                        .foregroundStyle(Color.primary)
                    Text(mode.subtitle)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(Color.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(rowPressBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect((!reduceMotion && isPressed) ? 0.98 : 1.0)
        .animation(reduceMotion ? .none : .amenSnappy, value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
        )
        .accessibilityLabel(mode.label)
        .accessibilityHint(mode.subtitle)
    }

    @ViewBuilder
    private var rowPressBackground: some View {
        if isPressed {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AmenTheme.Colors.amenGold.opacity(0.08))
        } else {
            Color.clear
        }
    }
}

// MARK: - Preview

#if DEBUG
struct AmenSearchDisambiguationPopup_Previews: PreviewProvider {
    static let discoverModes: [AmenSearchMode] = [
        AmenSearchMode(
            id: "people",
            icon: "magnifyingglass",
            iconColor: Color.primary,
            label: "Search People & Posts",
            subtitle: "Find testimonies, prayers & communities"
        ),
        AmenSearchMode(
            id: "berean",
            icon: "sparkles",
            iconColor: AmenTheme.Colors.amenGold,
            label: "Ask Berean AI",
            subtitle: "Get scripture-grounded answers"
        ),
        AmenSearchMode(
            id: "scripture",
            icon: "book.fill",
            iconColor: AmenTheme.Colors.amenBlue,
            label: "Find Scripture",
            subtitle: "Search Bible verses & passages"
        )
    ]

    static var previews: some View {
        VStack(spacing: 0) {
            // Simulated search bar placeholder
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text("Search...").foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule(style: .continuous))

            AmenSearchDisambiguationPopup(
                modes: discoverModes,
                onSelect: { _ in },
                onDismiss: {}
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
    }
}
#endif

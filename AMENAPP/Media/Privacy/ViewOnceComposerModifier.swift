import SwiftUI

// MARK: - ViewOnceComposerModifier

/// Adds a "view once" clock toggle button to the modified view.
/// When active: button tinted `amenGold`, a `1x` GlassBadge appears on the photo thumbnail.
@MainActor
struct ViewOnceComposerModifier: ViewModifier {
    @Binding var isViewOnce: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .glassBadge(
                icon: "1.circle.fill",
                label: "1x",
                tint: AmenTheme.Colors.amenGold,
                alignment: .topTrailing,
                isVisible: isViewOnce
            )
            .overlay(alignment: .bottomTrailing) {
                clockButton
                    .padding(8)
            }
    }

    // MARK: - Clock button

    private var clockButton: some View {
        Button {
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: LiquidGlassTokens.motionFast)
                    : .spring(response: 0.28, dampingFraction: 0.72)
            ) {
                isViewOnce.toggle()
            }
        } label: {
            Image(systemName: "timer")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(
                    isViewOnce
                        ? AmenTheme.Colors.amenGold
                        : AmenTheme.Colors.textSecondary
                )
                .frame(width: 36, height: 36)
                .background { buttonBackground }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isViewOnce ? "View once on" : "View once off")
        .accessibilityHint("Double-tap to toggle view-once mode")
        .accessibilityAddTraits(.isToggle)
    }

    @ViewBuilder private var buttonBackground: some View {
        Circle()
            .fill(LiquidGlassTokens.blurRegular)
            .overlay {
                Circle()
                    .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.6)
            }
    }
}

// MARK: - View extension

extension View {
    /// Adds a view-once composer toggle button and badge to the modified view.
    func viewOnceComposer(isViewOnce: Binding<Bool>) -> some View {
        modifier(ViewOnceComposerModifier(isViewOnce: isViewOnce))
    }
}

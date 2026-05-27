import SwiftUI

// MARK: - CaptionStrip
// Glass strip caption bar shown at the bottom of a media player.
// Fades in/out with `isVisible`. Hides entirely when `text` is empty.
// Respects reduceTransparency: uses opaque black instead of glass.

@MainActor
struct CaptionStrip: View {
    var text: String
    var isVisible: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 16, design: .default))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background { stripBackground }
                .opacity(isVisible ? 1 : 0)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: LiquidGlassTokens.motionFast)
                        : .easeInOut(duration: LiquidGlassTokens.motionNormal),
                    value: isVisible
                )
                .accessibilityLabel(text)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityHidden(!isVisible)
        }
    }

    @ViewBuilder
    private var stripBackground: some View {
        if reduceTransparency {
            Rectangle()
                .fill(Color.black)
        } else {
            Rectangle()
                .fill(Material.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color.black.opacity(0.35))
                )
        }
    }
}

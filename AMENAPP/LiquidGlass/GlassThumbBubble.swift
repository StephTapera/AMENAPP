import SwiftUI

/// Scrubber thumbnail preview bubble — floats above the scrubber thumb and tracks horizontal position.
/// Agent 3 (Media Player) drives `xOffset` and supplies the thumbnail `image`.
struct GlassThumbBubble: View {
    /// Horizontal offset from center in the parent coordinate space (matches scrubber thumb x).
    var xOffset: CGFloat
    /// Thumbnail frame extracted from the video asset at the scrub position.
    var image: UIImage?
    var isVisible: Bool

    @Environment(\.accessibilityReduceMotion)       private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let bubbleWidth:  CGFloat = 96
    private let bubbleHeight: CGFloat = 64
    private let stemHeight:   CGFloat = 8

    var body: some View {
        VStack(spacing: 0) {
            thumbnailView
                .frame(width: bubbleWidth, height: bubbleHeight)
                .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                        .strokeBorder(Color.white.opacity(reduceTransparency ? 0.20 : 0.44), lineWidth: 0.75)
                }
                .shadow(
                    color: LiquidGlassTokens.shadowFloating.color,
                    radius: LiquidGlassTokens.shadowFloating.radius,
                    y: LiquidGlassTokens.shadowFloating.y
                )
            // Stem triangle pointing downward toward the scrubber
            Triangle()
                .fill(Color.white.opacity(reduceTransparency ? 0.24 : 0.38))
                .frame(width: 14, height: stemHeight)
        }
        .offset(x: xOffset)
        .scaleEffect(isVisible ? 1 : 0.8, anchor: .bottom)
        .opacity(isVisible ? 1 : 0)
        .animation(
            reduceMotion ? .easeOut(duration: LiquidGlassTokens.motionFast)
                         : .spring(response: 0.22, dampingFraction: 0.78),
            value: isVisible
        )
        .animation(
            reduceMotion ? nil : .interactiveSpring(response: 0.12, dampingFraction: 0.90),
            value: xOffset
        )
        .allowsHitTesting(false)
    }

    @ViewBuilder private var thumbnailView: some View {
        if let img = image {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
        } else {
            // Placeholder shimmer until thumbnail loads
            if reduceTransparency {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                    .fill(Color(.systemFill))
            } else {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                    .fill(LiquidGlassTokens.blurThin)
            }
        }
    }
}

// MARK: - Stem Shape

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
        }
    }
}

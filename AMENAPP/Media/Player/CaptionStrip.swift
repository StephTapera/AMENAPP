import SwiftUI

struct CaptionStrip: View {
    var text: String
    var isVisible: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 16, weight: .regular, design: .default))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if reduceTransparency {
                        Capsule(style: .continuous).fill(Color.black.opacity(0.85))
                    } else {
                        Capsule(style: .continuous).fill(LiquidGlassTokens.blurElevated)
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6)
                            }
                    }
                }
                .padding(.horizontal, 16)
                .opacity(isVisible ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: LiquidGlassTokens.motionNormal), value: isVisible)
                .accessibilityLabel(text)
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

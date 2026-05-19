import SwiftUI

struct SelahGlassPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.018 : 0)
            .animation(
                reduceMotion ? nil : .interactiveSpring(response: 0.16, dampingFraction: 0.9, blendDuration: 0.04),
                value: configuration.isPressed
            )
    }
}

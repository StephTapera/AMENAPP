import SwiftUI

// MARK: - Configuration

struct LiquidGlassAlertConfig {
    let title: String
    let message: String?
    let icon: String?
    let primaryButton: LiquidGlassAlertButton
    let secondaryButton: LiquidGlassAlertButton?

    init(
        title: String,
        message: String? = nil,
        icon: String? = nil,
        primaryButton: LiquidGlassAlertButton,
        secondaryButton: LiquidGlassAlertButton? = nil
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.primaryButton = primaryButton
        self.secondaryButton = secondaryButton
    }
}

struct LiquidGlassAlertButton {
    enum Tone {
        case primary     // amenGold capsule fill
        case spiritual   // amenPurple capsule fill
        case destructive // red capsule fill
        case dismiss     // glass capsule, no solid fill
    }

    let title: String
    let tone: Tone
    let action: () -> Void

    init(_ title: String, tone: Tone = .primary, action: @escaping () -> Void) {
        self.title = title
        self.tone = tone
        self.action = action
    }

    static func cancel(_ title: String = "Cancel", action: @escaping () -> Void = {}) -> LiquidGlassAlertButton {
        .init(title, tone: .dismiss, action: action)
    }
}

// MARK: - Card View

private struct LiquidGlassAlertCard: View {
    let config: LiquidGlassAlertConfig
    @Binding var isPresented: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if let icon = config.icon {
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 10)
                }

                Text(config.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                if let message = config.message {
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }

                VStack(spacing: 10) {
                    alertButton(config.primaryButton)
                    if let secondary = config.secondaryButton {
                        alertButton(secondary)
                    }
                }
                .padding(.top, 22)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge, style: .continuous))
            .shadow(
                color: LiquidGlassTokens.shadowFloating.color,
                radius: LiquidGlassTokens.shadowFloating.radius,
                y: LiquidGlassTokens.shadowFloating.y
            )
            .padding(.horizontal, 20)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.96))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge, style: .continuous)
                    .fill(LiquidGlassTokens.blurElevated)
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.13 : 0.58),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .blendMode(.screen)
            }
        }
    }

    @ViewBuilder
    private func alertButton(_ button: LiquidGlassAlertButton) -> some View {
        Button {
            dismissCard()
            button.action()
        } label: {
            Text(button.title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
        }
        .buttonStyle(
            AlertCapsuleStyle(
                tone: button.tone,
                reduceTransparency: reduceTransparency,
                colorScheme: colorScheme
            )
        )
    }

    private func dismissCard() {
        withAnimation(
            Motion.adaptive(.spring(response: 0.24, dampingFraction: 0.88))
        ) {
            isPresented = false
        }
    }
}

// MARK: - Capsule Button Style

private struct AlertCapsuleStyle: ButtonStyle {
    let tone: LiquidGlassAlertButton.Tone
    let reduceTransparency: Bool
    let colorScheme: ColorScheme

    private static let amenGold   = Color(hex: "F59E0B")
    private static let amenPurple = Color(hex: "6B48FF")

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .background { capsuleBackground(pressed: configuration.isPressed) }
            .clipShape(Capsule(style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.88), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        tone == .dismiss ? .primary : .white
    }

    @ViewBuilder
    private func capsuleBackground(pressed: Bool) -> some View {
        let alpha = pressed ? 0.80 : 1.0
        switch tone {
        case .primary:
            Capsule().fill(Self.amenGold.opacity(alpha))
        case .spiritual:
            Capsule().fill(Self.amenPurple.opacity(alpha))
        case .destructive:
            Capsule().fill(Color.red.opacity(pressed ? 0.72 : 0.88))
        case .dismiss:
            if reduceTransparency {
                Capsule().fill(colorScheme == .dark ? Color(white: 0.28) : Color(white: 0.82))
            } else {
                Capsule().fill(Material.ultraThinMaterial)
            }
        }
    }
}

// MARK: - View Modifier

private struct LiquidGlassAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    let config: LiquidGlassAlertConfig

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    LiquidGlassAlertCard(config: config, isPresented: $isPresented)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.88).combined(with: .opacity),
                                removal:   .scale(scale: 0.96).combined(with: .opacity)
                            )
                        )
                }
            }
            .animation(
                reduceMotion
                    ? .easeOut(duration: LiquidGlassTokens.motionFast)
                    : .spring(response: 0.34, dampingFraction: 0.84),
                value: isPresented
            )
    }
}

// MARK: - Public API

extension View {
    /// Overlays a Liquid Glass alert card matching the AMEN design standard.
    /// Apply at the NavigationStack or scene level so the dim layer fills the screen.
    func amenAlert(isPresented: Binding<Bool>, config: LiquidGlassAlertConfig) -> some View {
        modifier(LiquidGlassAlertModifier(isPresented: isPresented, config: config))
    }
}

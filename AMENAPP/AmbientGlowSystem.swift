import SwiftUI
import Foundation

enum AmbientGlowSurface {
    case authentication
    case berean
    case selah
    case prayer
    case media
    case feed
}

enum AmbientGlowStyle {
    case edgeLitCapsule
    case aurora
    case breathing
    case spiritualCalm
    case reactive
}

enum AmbientGlowIntensity: CGFloat {
    case whisper = 0.35
    case subtle = 0.55
    case focused = 0.75
    case moment = 1.0
}

struct AmbientLightTokens {
    let primary: Color
    let secondary: Color
    let highlight: Color

    static func tokens(for surface: AmbientGlowSurface, colorScheme: ColorScheme) -> AmbientLightTokens {
        let dark = colorScheme == .dark

        switch surface {
        case .authentication:
            return AmbientLightTokens(
                primary: Color(red: 1.00, green: 0.93, blue: 0.78),
                secondary: Color(red: 0.70, green: 0.82, blue: 1.00),
                highlight: dark ? .white : Color(red: 0.72, green: 0.56, blue: 0.30)
            )
        case .berean:
            return AmbientLightTokens(
                primary: Color(red: 0.68, green: 0.78, blue: 1.00),
                secondary: Color(red: 0.78, green: 0.70, blue: 0.98),
                highlight: dark ? Color(red: 0.88, green: 0.92, blue: 1.00) : Color(red: 0.22, green: 0.32, blue: 0.55)
            )
        case .selah, .prayer:
            return AmbientLightTokens(
                primary: Color(red: 1.00, green: 0.88, blue: 0.58),
                secondary: Color(red: 0.92, green: 0.97, blue: 1.00),
                highlight: dark ? Color(red: 1.00, green: 0.95, blue: 0.82) : Color(red: 0.58, green: 0.42, blue: 0.14)
            )
        case .media:
            return AmbientLightTokens(
                primary: Color(red: 0.82, green: 0.90, blue: 1.00),
                secondary: Color(red: 1.00, green: 0.92, blue: 0.80),
                highlight: dark ? .white : Color(red: 0.22, green: 0.26, blue: 0.32)
            )
        case .feed:
            return AmbientLightTokens(
                primary: Color(red: 0.85, green: 0.92, blue: 1.00),
                secondary: Color(red: 1.00, green: 0.92, blue: 0.72),
                highlight: dark ? Color(red: 0.94, green: 0.96, blue: 1.00) : Color(red: 0.30, green: 0.35, blue: 0.42)
            )
        }
    }
}

private struct AmbientGlowModifier: ViewModifier {
    let style: AmbientGlowStyle
    let surface: AmbientGlowSurface
    let intensity: AmbientGlowIntensity
    let isActive: Bool
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var breathes = false

    private var isLowPower: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    @MainActor
    private var isEnabled: Bool {
        AMENFeatureFlags.shared.isAmbientGlowEnabled(for: surface)
    }

    private var canAnimate: Bool {
        !reduceMotion && !isLowPower && style == .breathing && isActive
    }

    private var accessibilityMultiplier: CGFloat {
        var value: CGFloat = 1
        if reduceTransparency { value *= 0.35 }
        if isLowPower { value *= 0.55 }
        return value
    }

    private var baseOpacity: CGFloat {
        let lightModeScale: CGFloat = colorScheme == .dark ? 1.0 : 0.62
        let styleScale: CGFloat
        switch style {
        case .edgeLitCapsule: styleScale = 0.34
        case .aurora: styleScale = 0.20
        case .breathing: styleScale = 0.30
        case .spiritualCalm: styleScale = 0.18
        case .reactive: styleScale = 0.24
        }

        let breathingScale: CGFloat = canAnimate ? (breathes ? 1.0 : 0.62) : 1.0
        return styleScale * intensity.rawValue * lightModeScale * accessibilityMultiplier
    }

    func body(content: Content) -> some View {
        if isEnabled && isActive {
            content
                .background(glowBloom)
                .overlay(edgeStroke)
                .onAppear {
                    guard canAnimate else { return }
                    withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                        breathes = true
                    }
                }
                .onChange(of: isActive) { _, active in
                    if active && canAnimate {
                        withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                            breathes = true
                        }
                    } else {
                        breathes = false
                    }
                }
        } else {
            content
        }
    }

    @ViewBuilder
    private var glowBloom: some View {
        let tokens = AmbientLightTokens.tokens(for: surface, colorScheme: colorScheme)
        let radius = cornerRadius + 6

        if style == .aurora || style == .breathing || style == .spiritualCalm || style == .reactive {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            tokens.primary.opacity(baseOpacity),
                            tokens.secondary.opacity(baseOpacity * 0.62),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 180
                    )
                )
                .blur(radius: reduceTransparency ? 8 : 22)
                .scaleEffect(canAnimate ? (breathes ? 1.035 : 0.985) : 1)
                .padding(-18)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var edgeStroke: some View {
        let tokens = AmbientLightTokens.tokens(for: surface, colorScheme: colorScheme)
        let shouldDrawEdge = style == .edgeLitCapsule || style == .breathing || style == .reactive

        if shouldDrawEdge {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            tokens.highlight.opacity(baseOpacity * 2.2),
                            tokens.primary.opacity(baseOpacity * 1.25),
                            Color.white.opacity(baseOpacity * 0.35)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(0.6, min(1.4, intensity.rawValue * 1.3))
                )
                .shadow(color: tokens.primary.opacity(baseOpacity), radius: reduceTransparency ? 2 : 8, x: 0, y: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    func ambientGlow(
        _ style: AmbientGlowStyle,
        surface: AmbientGlowSurface,
        intensity: AmbientGlowIntensity = .subtle,
        isActive: Bool = true,
        cornerRadius: CGFloat = 24
    ) -> some View {
        modifier(AmbientGlowModifier(
            style: style,
            surface: surface,
            intensity: intensity,
            isActive: isActive,
            cornerRadius: cornerRadius
        ))
    }
}

extension AMENFeatureFlags {
    @MainActor
    func isAmbientGlowEnabled(for surface: AmbientGlowSurface) -> Bool {
        guard ambientGlowEnabled else { return false }

        switch surface {
        case .authentication:
            return ambientGlowAuthenticationEnabled
        case .berean:
            return ambientGlowBereanEnabled
        case .selah:
            return ambientGlowSelahEnabled
        case .prayer:
            return ambientGlowPrayerEnabled
        case .media:
            return ambientGlowMediaEnabled
        case .feed:
            return ambientGlowFeedEnabled
        }
    }
}

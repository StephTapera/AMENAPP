import SwiftUI

/// Behavioral design tokens that let Liquid Glass become quieter or richer without changing feature architecture.
enum AmenAdaptiveDensity {
    case comfortable
    case balanced
    case compact

    var verticalSpacing: CGFloat {
        switch self {
        case .comfortable: 18
        case .balanced: 14
        case .compact: 10
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .comfortable: 18
        case .balanced: 14
        case .compact: 10
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .comfortable: 24
        case .balanced: 20
        case .compact: 16
        }
    }
}

enum AmenSemanticAtmosphere {
    case neutral
    case study
    case selah
    case creator
    case media

    var colors: [Color] {
        switch self {
        case .neutral:
            [Color.white, Color(red: 0.965, green: 0.972, blue: 0.965)]
        case .study:
            [Color(red: 0.992, green: 0.99, blue: 0.975), Color(red: 0.94, green: 0.965, blue: 0.952)]
        case .selah:
            [Color(red: 0.985, green: 0.982, blue: 0.965), Color(red: 0.94, green: 0.952, blue: 0.965)]
        case .creator:
            [Color.white, Color(red: 0.955, green: 0.965, blue: 0.975)]
        case .media:
            [Color(red: 0.975, green: 0.975, blue: 0.968), Color(red: 0.93, green: 0.94, blue: 0.94)]
        }
    }
}

enum AmenAdaptiveMotion {
    static let quickFade = Animation.easeOut(duration: 0.16)
    static let calmSpring = Animation.spring(response: 0.28, dampingFraction: 0.88)
    static let subtleSpring = Animation.spring(response: 0.22, dampingFraction: 0.9)
}

struct AmenSemanticAtmosphereBackground: View {
    let atmosphere: AmenSemanticAtmosphere
    var intensity: CGFloat = 1

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: reduceTransparency ? [Color(.systemBackground), Color(.systemBackground)] : atmosphere.colors,
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .top) {
            if !reduceTransparency && colorScheme == .light {
                LinearGradient(
                    colors: [Color.white.opacity(0.38 * intensity), Color.white.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
            }
        }
        .ignoresSafeArea()
    }
}

struct AmenIntentiveActionTray<Content: View>: View {
    let label: String?
    let density: AmenAdaptiveDensity
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    init(label: String? = nil, density: AmenAdaptiveDensity = .balanced, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.density = density
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8, content: content)
                    .padding(.horizontal, density.horizontalPadding)
                    .padding(.vertical, 8)
            }
            .background(trayBackground, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.black.opacity(contrast == .increased ? 0.18 : 0.08), lineWidth: contrast == .increased ? 1 : 0.75)
            )
        }
        .accessibilityElement(children: .contain)
    }

    private var trayBackground: AnyShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.ultraThinMaterial)
    }
}

private struct AmenAdaptiveChromeModifier: ViewModifier {
    let collapseProgress: CGFloat
    let minimumOpacity: Double
    let verticalOffset: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let clamped = min(max(collapseProgress, 0), 1)
        let largeTextFloor = dynamicTypeSize.isAccessibilitySize ? 0.92 : minimumOpacity
        let opacity = max(largeTextFloor, 1 - Double(clamped) * (1 - minimumOpacity))
        let offset = reduceMotion ? 0 : -(verticalOffset * clamped)

        content
            .opacity(reduceTransparency ? 1 : opacity)
            .offset(y: offset)
            .animation(reduceMotion ? AmenAdaptiveMotion.quickFade : AmenAdaptiveMotion.calmSpring, value: clamped)
    }
}

private struct AmenSpatialMicrodepthModifier: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(contrast == .increased ? 0.16 : 0.06), lineWidth: contrast == .increased ? 1 : 0.75)
            )
            .shadow(
                color: .black.opacity(reduceTransparency ? 0.04 : (isFocused ? 0.10 : 0.06)),
                radius: isFocused ? 20 : 12,
                x: 0,
                y: isFocused ? 10 : 5
            )
            .scaleEffect(isFocused && !reduceMotion ? 1.006 : 1)
            .animation(reduceMotion ? .none : AmenAdaptiveMotion.subtleSpring, value: isFocused)
    }
}

enum AmenBackdropLuminance {
    case light
    case balanced
    case dark

    var foregroundStyle: Color {
        switch self {
        case .light: Color.primary
        case .balanced: Color.primary
        case .dark: Color.white
        }
    }

    var secondaryForegroundStyle: Color {
        switch self {
        case .light: Color.secondary
        case .balanced: Color.secondary
        case .dark: Color.white.opacity(0.78)
        }
    }
}

private struct AmenProgressiveMaterialSurfaceModifier: ViewModifier {
    let scrollActivity: CGFloat
    let cornerRadius: CGFloat
    let ambientTint: Color?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let activity = min(max(scrollActivity, 0), 1)
        let borderOpacity = contrast == .increased ? 0.22 : 0.08 + (0.05 * activity)
        let shadowOpacity = reduceTransparency ? 0.04 : 0.06 + (0.05 * activity)

        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(materialStyle(activity: activity))
                    .overlay {
                        if let ambientTint, !reduceTransparency {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(ambientTint.opacity(0.035))
                        }
                    }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(borderOpacity), lineWidth: contrast == .increased ? 1 : 0.75)
            )
            .shadow(color: .black.opacity(shadowOpacity), radius: 12 + (8 * activity), x: 0, y: 5 + (5 * activity))
    }

    private func materialStyle(activity: CGFloat) -> AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(.systemBackground))
        }

        if activity > 0.58 {
            return AnyShapeStyle(.regularMaterial)
        }

        if activity > 0.22 {
            return AnyShapeStyle(.thinMaterial)
        }

        return AnyShapeStyle(.ultraThinMaterial)
    }
}

private struct AmenVelocityAwareChromeModifier: ViewModifier {
    let collapseProgress: CGFloat
    let scrollActivity: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let collapse = min(max(collapseProgress, 0), 1)
        let activity = min(max(scrollActivity, 0), 1)
        let compression = max(collapse, activity * 0.72)
        let largeTextScale: CGFloat = dynamicTypeSize.isAccessibilitySize ? 1 : 1 - (compression * 0.035)

        content
            .scaleEffect(largeTextScale, anchor: .top)
            .opacity(Double(1 - (compression * 0.10)))
            .animation(reduceMotion ? AmenAdaptiveMotion.quickFade : AmenAdaptiveMotion.calmSpring, value: compression)
    }
}

private struct AmenDynamicVibrancyModifier: ViewModifier {
    let luminance: AmenBackdropLuminance

    func body(content: Content) -> some View {
        content
            .foregroundStyle(luminance.foregroundStyle)
    }
}

extension View {
    func amenAdaptiveChrome(collapseProgress: CGFloat, minimumOpacity: Double = 0.72, verticalOffset: CGFloat = 8) -> some View {
        modifier(AmenAdaptiveChromeModifier(collapseProgress: collapseProgress, minimumOpacity: minimumOpacity, verticalOffset: verticalOffset))
    }

    func amenSpatialMicrodepth(isFocused: Bool, cornerRadius: CGFloat = 22) -> some View {
        modifier(AmenSpatialMicrodepthModifier(isFocused: isFocused, cornerRadius: cornerRadius))
    }

    func amenProgressiveMaterialSurface(scrollActivity: CGFloat, cornerRadius: CGFloat = 22, ambientTint: Color? = nil) -> some View {
        modifier(AmenProgressiveMaterialSurfaceModifier(scrollActivity: scrollActivity, cornerRadius: cornerRadius, ambientTint: ambientTint))
    }

    func amenVelocityAwareChrome(collapseProgress: CGFloat, scrollActivity: CGFloat) -> some View {
        modifier(AmenVelocityAwareChromeModifier(collapseProgress: collapseProgress, scrollActivity: scrollActivity))
    }

    func amenDynamicVibrancy(luminance: AmenBackdropLuminance) -> some View {
        modifier(AmenDynamicVibrancyModifier(luminance: luminance))
    }
}

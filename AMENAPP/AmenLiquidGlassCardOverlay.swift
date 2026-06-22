import SwiftUI

/// A gradient-to-glass overlay for media cards, video players, and image surfaces.
///
/// Applies a gradient ramp that fades from transparent at the far edge to a glass
/// panel at the control layer — avoiding a harsh boundary over dark media backgrounds.
///
/// Usage:
/// ```swift
/// ZStack(alignment: .bottom) {
///     videoPlayer
///     AmenLiquidGlassCardOverlay(position: .bottom, intensity: .light, cornerRadius: 20) {
///         mediaControls
///     }
/// }
/// ```
struct AmenLiquidGlassCardOverlay<Content: View>: View {
    enum OverlayPosition {
        case top
        case bottom
        case full
    }

    var position: OverlayPosition = .bottom
    var intensity: AmenGlassMaterialIntensity = .light
    var cornerRadius: CGFloat = 0
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(overlayBackground)
    }

    @ViewBuilder
    private var overlayBackground: some View {
        ZStack {
            if !reduceTransparency {
                gradientRamp
            }
            glassSurface
        }
    }

    @ViewBuilder
    private var gradientRamp: some View {
        let gradient = LinearGradient(
            colors: gradientColors,
            startPoint: gradientStart,
            endPoint: gradientEnd
        )
        if cornerRadius > 0 {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(gradient)
        } else {
            Rectangle().fill(gradient)
        }
    }

    @ViewBuilder
    private var glassSurface: some View {
        let fill: AnyShapeStyle = reduceTransparency ? intensity.solidFallback : intensity.material
        let borderOpacity: Double = contrast == .increased ? 0.55 : 0.30

        if cornerRadius > 0 {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(borderOpacity),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: contrast == .increased ? 1.0 : 0.6
                        )
                }
        } else {
            Rectangle().fill(fill)
        }
    }

    private var gradientColors: [Color] {
        switch position {
        case .top, .bottom: return [.black.opacity(0), .black.opacity(0.32)]
        case .full:         return [.black.opacity(0.18), .black.opacity(0.18)]
        }
    }

    private var gradientStart: UnitPoint {
        switch position {
        case .bottom: return .top
        case .top:    return .bottom
        case .full:   return .top
        }
    }

    private var gradientEnd: UnitPoint {
        switch position {
        case .bottom: return .bottom
        case .top:    return .top
        case .full:   return .bottom
        }
    }
}

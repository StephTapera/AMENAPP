// AmenTheme.swift
// AMENAPP
//
// Canonical semantic design token system for AMEN.
// Single source of truth for all theme-dependent values.
//
// Usage:
//   .background(AmenTheme.Colors.surfaceCard)
//   .foregroundStyle(AmenTheme.Colors.textPrimary)
//   .shadow(color: AmenTheme.Colors.shadowCard, ...)
//
// All raw Color.white / Color.black usages in view code should be migrated here.
// iOS system semantic colors (Color(.systemBackground), Color(.label), etc.)
// are used as the foundation where possible — they auto-adapt for free.

import SwiftUI

// MARK: - AmenTheme namespace

enum AmenTheme {

    // MARK: - Colors

    enum Colors {

        // ---- Backgrounds ----

        /// Root app background. Equivalent to .systemBackground — pure white in light, ~#1C1C1E in dark.
        static let backgroundPrimary   = Color(uiColor: .systemBackground)
        static let backgroundBase      = backgroundPrimary

        /// Secondary container background. .secondarySystemBackground — #F2F2F7 / #2C2C2E.
        static let backgroundSecondary = Color(uiColor: .secondarySystemBackground)
        static let backgroundElevated  = backgroundSecondary

        /// Tertiary container background. .tertiarySystemBackground — #FFFFFF / #3A3A3C.
        static let backgroundTertiary  = Color(uiColor: .tertiarySystemBackground)

        /// Grouped list root background. .systemGroupedBackground — #F2F2F7 / #1C1C1E.
        static let backgroundGrouped   = Color(uiColor: .systemGroupedBackground)

        /// Grouped list row background. .secondarySystemGroupedBackground — #FFFFFF / #2C2C2E.
        static let backgroundGroupedRow = Color(uiColor: .secondarySystemGroupedBackground)

        // ---- Surfaces / cards ----

        /// Post card, note card, chat bubble container — slightly elevated above background.
        static let surfaceCard = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0.14, alpha: 1)   // #242424 — warm dark charcoal
                : .white
        })

        /// Elevated surface (e.g. modal header, toolbar, input area).
        static let surfaceElevated = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0.17, alpha: 1)   // #2B2B2B
                : UIColor(white: 0.97, alpha: 1)   // #F7F7F7
        })

        /// Input field background (text fields, search bars, composer).
        static let surfaceInput = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0.13, alpha: 1)   // deep input well
                : UIColor(white: 0.94, alpha: 1)
        })
        static let surfaceGrouped = backgroundGroupedRow

        /// Chip / pill fill (non-selected).
        static let surfaceChip = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.10)
                : UIColor(white: 0, alpha: 0.05)
        })
        static let surfaceGlassDark = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0.08, alpha: 0.55)
                : UIColor(white: 1, alpha: 0.18)
        })

        // ---- Text ----

        /// Primary content text — highest contrast.
        static let textPrimary     = Color(uiColor: .label)

        /// Secondary content text — medium emphasis.
        static let textSecondary   = Color(uiColor: .secondaryLabel)

        /// Tertiary metadata — timestamps, captions.
        static let textTertiary    = Color(uiColor: .tertiaryLabel)

        /// Quaternary — very subtle hints.
        static let textQuaternary  = Color(uiColor: .quaternaryLabel)

        /// Placeholder text in inputs.
        static let textPlaceholder = Color(uiColor: .placeholderText)
        static let iconPrimary = textPrimary
        static let iconSecondary = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.58)
                : UIColor(white: 0, alpha: 0.42)
        })

        /// Inverse text — for use on primary action buttons (white on dark button / dark on light button).
        static let textInverse = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor.black : UIColor.white
        })

        // ---- Separators / dividers ----

        /// Standard iOS separator — adapts automatically.
        static let separator       = Color(uiColor: .separator)

        /// Opaque separator — never translucent.
        static let separatorOpaque = Color(uiColor: .opaqueSeparator)

        /// Subtle hairline divider for inside cards.
        static let separatorSubtle = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.09)
                : UIColor(white: 0, alpha: 0.07)
        })
        static let borderSoft = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.12)
                : UIColor(white: 0, alpha: 0.08)
        })

        // ---- Glass / Liquid Glass ----

        /// Glass surface highlight fill (the white-ish coat on glass).
        /// In light mode: bright translucent white.
        /// In dark mode: very subtle smoked highlight — NOT milky.
        static let glassFill = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.06)   // barely-there smoked highlight
                : UIColor(white: 1, alpha: 0.70)   // bright liquid glass
        })

        /// Glass gradient top highlight.
        static let glassHighlightTop = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.10)
                : UIColor(white: 1, alpha: 0.55)
        })

        /// Glass gradient bottom highlight.
        static let glassHighlightBottom = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.03)
                : UIColor(white: 1, alpha: 0.18)
        })

        /// Glass border stroke.
        static let glassStroke = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.16)   // subtle contour line in dark
                : UIColor(white: 1, alpha: 0.55)
        })

        /// Glass depth overlay (darkening pool at bottom/edges).
        static let glassDepth = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0, alpha: 0.25)
                : UIColor(white: 0, alpha: 0.06)
        })

        // ---- Interactive states ----

        /// Overlay applied to buttons/rows on press.
        static let pressedOverlay = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.10)
                : UIColor(white: 0, alpha: 0.06)
        })

        /// Fill for selected chips, active tabs, selected rows.
        static let selectedFill = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.14)
                : UIColor(white: 0, alpha: 0.08)
        })

        // ---- Action buttons ----

        /// Primary CTA background — uses .label so it's black in light, white in dark.
        static let buttonPrimary     = Color(uiColor: .label)
        static let accentPrimary     = buttonPrimary

        /// Text on primary CTA — inverse of label.
        static let buttonPrimaryText = Color(uiColor: .systemBackground)

        /// Secondary button fill (outlined).
        static let buttonSecondary = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0.24, alpha: 1)
                : UIColor.white
        })

        /// Destructive action.
        static let buttonDestructive = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.96, green: 0.44, blue: 0.44, alpha: 1)
                : UIColor(red: 0.88, green: 0.22, blue: 0.22, alpha: 1)
        })

        // ---- Overlay / scrim ----

        /// Modal/sheet scrim.
        static let scrim             = Color.black.opacity(0.40)
        static let overlayScrim      = scrim

        /// Media overlay (keeps text legible over photos/video).
        static let mediaOverlay      = Color.black.opacity(0.30)
        static let mediaOverlayGradient = LinearGradient(
            colors: [
                Color.black.opacity(0.00),
                Color.black.opacity(0.16),
                Color.black.opacity(0.42),
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        // ---- Status / semantic ----

        static let statusSuccess = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.36, green: 0.80, blue: 0.52, alpha: 1)
                : UIColor(red: 0.18, green: 0.70, blue: 0.38, alpha: 1)
        })

        static let statusWarning = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.97, green: 0.78, blue: 0.30, alpha: 1)
                : UIColor(red: 0.88, green: 0.60, blue: 0.08, alpha: 1)
        })
        static let warning = statusWarning

        static let statusError = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.97, green: 0.46, blue: 0.46, alpha: 1)
                : UIColor(red: 0.88, green: 0.22, blue: 0.22, alpha: 1)
        })
        static let destructive = statusError

        static let statusInfo = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.50, green: 0.78, blue: 0.98, alpha: 1)
                : UIColor(red: 0.14, green: 0.54, blue: 0.90, alpha: 1)
        })
        static let success = statusSuccess

        // ---- Skeleton shimmer ----

        static let shimmerBase = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0.18, alpha: 1)
                : UIColor(white: 0.88, alpha: 1)
        })

        static let shimmerHighlight = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0.25, alpha: 1)
                : UIColor(white: 0.96, alpha: 1)
        })

        // ---- Brand colors (invariant across themes) ----

        static let amenGold   = Color(red: 0.83, green: 0.69, blue: 0.22)
        static let amenBronze = Color(red: 0.80, green: 0.50, blue: 0.20)
        static let amenSilver = Color(red: 0.75, green: 0.75, blue: 0.75)

        /// Tab-bar / interactive accent blue. Used for the active tab selection tint.
        /// Fixed value (not adaptive) so it reads as the same vivid blue on both themes.
        static let amenBlue   = Color(red: 0.04, green: 0.52, blue: 1.0)

        /// LinkedGlyph tint — interlocking-rings community signal (Agent C).
        static let amenPurple = Color(red: 0.44, green: 0.26, blue: 0.80)

        /// Deep background for immersive Spaces surfaces.
        static let amenBlack  = Color(red: 0.06, green: 0.06, blue: 0.07)

        // ---- Shadow ----

        static let shadowCard = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0, alpha: 0.40)
                : UIColor(white: 0, alpha: 0.07)
        })

        static let shadowFloating = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0, alpha: 0.50)
                : UIColor(white: 0, alpha: 0.10)
        })
    }

    // MARK: - Glass Parameters

    /// Returns the correct glass highlight fill opacity for the current color scheme.
    static func glassFillOpacity(_ scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.06 : 0.70
    }

    /// Returns the correct glass gradient start opacity.
    static func glassGradientStartOpacity(_ scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.09 : 0.50
    }

    /// Returns the correct glass gradient end opacity.
    static func glassGradientEndOpacity(_ scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.03 : 0.15
    }

    /// Returns the correct glass stroke opacity.
    static func glassStrokeOpacity(_ scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.16 : 0.55
    }

    /// Returns the depth darkening opacity (bottom/edge pooling).
    static func glassDepthOpacity(_ scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.22 : 0.06
    }
}

// MARK: - Convenience Color extensions (backward-compatible shortcuts)

extension Color {
    // Backgrounds
    static var amenBackground: Color          { AmenTheme.Colors.backgroundPrimary }
    static var amenBackgroundSecondary: Color { AmenTheme.Colors.backgroundSecondary }
    static var amenSurfaceCard: Color         { AmenTheme.Colors.surfaceCard }
    static var amenSurfaceElevated: Color     { AmenTheme.Colors.surfaceElevated }
    static var amenSurfaceInput: Color        { AmenTheme.Colors.surfaceInput }
    static var amenSurfaceChip: Color         { AmenTheme.Colors.surfaceChip }

    // Text
    static var amenTextLabel: Color           { AmenTheme.Colors.textPrimary }
    static var amenTextLabelSecondary: Color  { AmenTheme.Colors.textSecondary }
    static var amenTextLabelTertiary: Color   { AmenTheme.Colors.textTertiary }
    static var amenTextInverse: Color         { AmenTheme.Colors.textInverse }

    // Separators
    static var amenSeparator: Color           { AmenTheme.Colors.separator }
    static var amenSeparatorSubtle: Color     { AmenTheme.Colors.separatorSubtle }

    // Glass
    static var amenGlassFill: Color           { AmenTheme.Colors.glassFill }
    static var amenGlassStroke: Color         { AmenTheme.Colors.glassStroke }

    // Status
    static var amenStatusSuccess: Color       { AmenTheme.Colors.statusSuccess }
    static var amenStatusWarning: Color       { AmenTheme.Colors.statusWarning }
    static var amenStatusError: Color         { AmenTheme.Colors.statusError }

    // Brand accent
    static var amenBlue: Color                { AmenTheme.Colors.amenBlue }

    // Shimmer
    static var amenShimmerBase: Color         { AmenTheme.Colors.shimmerBase }
    static var amenShimmerHighlight: Color    { AmenTheme.Colors.shimmerHighlight }
}

// MARK: - Reusable view modifiers

/// Adaptive card surface: correct background + subtle shadow for both themes.
struct AmenCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var cornerRadius: CGFloat = 16
    var includeShadow: Bool = true

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceCard)
            )
            .applyShadowIf(includeShadow,
                color: AmenTheme.Colors.shadowCard,
                radius: 12, x: 0, y: 3
            )
    }
}

/// Adaptive glass card: .ultraThinMaterial + adaptive highlight + glass stroke.
/// Replaces `LiquidGlassCard` with a theme-correct dark-mode version.
struct AmenGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var cornerRadius: CGFloat = 18
    var includeShadow: Bool = true

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(AmenTheme.Colors.glassFill)   // adaptive: bright in light, smoke in dark
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(AmenTheme.glassStrokeOpacity(scheme)),
                                Color.white.opacity(AmenTheme.glassStrokeOpacity(scheme) * 0.4),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            )
            .applyShadowIf(includeShadow,
                color: AmenTheme.Colors.shadowCard,
                radius: 16, x: 0, y: 5
            )
    }
}

/// Adaptive glass input bar (composer bars, search inputs).
struct AmenGlassInputBarModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(AmenTheme.Colors.glassFill)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        AmenTheme.Colors.glassStroke,
                        lineWidth: 0.5
                    )
            )
            .shadow(color: AmenTheme.Colors.shadowCard, radius: 12, x: 0, y: 4)
    }
}

/// Adaptive flat card (no glass): used for settings rows, notification cells.
struct AmenFlatCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AmenTheme.Colors.backgroundGroupedRow)
            )
    }
}

/// Adaptive separator line.
struct AmenSeparatorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AmenTheme.Colors.separatorSubtle)
                    .frame(height: 0.5)
            }
    }
}

// MARK: - View extension shortcuts

extension View {
    func amenCard(cornerRadius: CGFloat = 16, shadow: Bool = true) -> some View {
        modifier(AmenCardModifier(cornerRadius: cornerRadius, includeShadow: shadow))
    }

    func amenGlassCard(cornerRadius: CGFloat = 18, shadow: Bool = true) -> some View {
        modifier(AmenGlassCardModifier(cornerRadius: cornerRadius, includeShadow: shadow))
    }

    func amenGlassInputBar(cornerRadius: CGFloat = 24) -> some View {
        modifier(AmenGlassInputBarModifier(cornerRadius: cornerRadius))
    }

    func amenFlatCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(AmenFlatCardModifier(cornerRadius: cornerRadius))
    }

    func amenSeparatorBottom() -> some View {
        modifier(AmenSeparatorModifier())
    }

    /// Applies an adaptive shadow matching the current theme.
    func amenShadow(radius: CGFloat = 12, y: CGFloat = 3) -> some View {
        self.modifier(AmenAdaptiveShadowModifier(radius: radius, y: y))
    }
}

private struct AmenAdaptiveShadowModifier: ViewModifier {
    @Environment(\.colorScheme) var scheme
    let radius: CGFloat
    let y: CGFloat

    func body(content: Content) -> some View {
        content.shadow(
            color: scheme == .dark
                ? Color.black.opacity(0.40)
                : Color.black.opacity(0.07),
            radius: radius, x: 0, y: y
        )
    }
}

// MARK: - Skeleton shimmer modifier

struct AmenSkeletonModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: AmenTheme.Colors.shimmerBase, location: 0),
                            .init(color: AmenTheme.Colors.shimmerHighlight, location: 0.4),
                            .init(color: AmenTheme.Colors.shimmerBase, location: 0.8),
                        ],
                        startPoint: UnitPoint(x: phase - 0.5, y: 0),
                        endPoint: UnitPoint(x: phase + 0.5, y: 0)
                    )
                }
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 1.5
                    }
                }
            )
    }
}

extension View {
    func amenSkeleton() -> some View {
        modifier(AmenSkeletonModifier())
    }
}

// MARK: - Private helpers

private extension View {
    @ViewBuilder
    func applyShadowIf(
        _ condition: Bool,
        color: Color,
        radius: CGFloat,
        x: CGFloat,
        y: CGFloat
    ) -> some View {
        if condition {
            self.shadow(color: color, radius: radius, x: x, y: y)
        } else {
            self
        }
    }
}

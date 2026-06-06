// AmenDesignSystem.swift
// AMENAPP — CommunityOS/Design
//
// AMEN Design System — White Liquid Glass (C3 locked, 2026-06-05)
// Reference: Apple Photos / Mail aesthetic
// Tokens are frozen — extend via AmenDesignSystem extensions, never modify these values
//
// Cross-reference: contracts/C3-design-tokens.md
//
// FROZEN 2026-06-05. Amendments require a RUNLOG entry.
//
// Rules:
//   • All surface and text tokens derive from iOS semantic system colors — no custom hex.
//   • Single restrained accent: Color.accentColor (iOS system blue) for interactive affordances only.
//   • No dark backgrounds, no gold, no purple, no serif fonts.
//   • Every PURGE comment is a mandatory migration — do not ship the legacy token.

import SwiftUI

// MARK: — Surfaces

/// Page and card surface tokens.
/// PURGE reference: amenDarkPrimary, amenDarkSecondary, amenDarkTertiary, amenBlack, amenMainGradient,
///   amenCream (#F8F4EC), NotifGlassTokens.cosmicDark (#0D0D1A) → all replaced by tokens below.
enum AmenSurface {
    /// Root page background. Maps to iOS .systemGroupedBackground (~#F2F2F7 light).
    // PURGED: Color.amenDarkPrimary → Color(uiColor: .systemGroupedBackground)
    // PURGED: Color.amenMainGradient → Color(uiColor: .systemGroupedBackground)
    // PURGED: Color.amenCream (#F8F4EC) → Color(uiColor: .systemGroupedBackground)
    // PURGED: NotifGlassTokens.cosmicDark (#0D0D1A) → Color(uiColor: .systemGroupedBackground)
    static let pageBg = Color(uiColor: .systemGroupedBackground)

    /// Card / sheet surface. Pure white in light mode; uses secondarySystemGroupedBackground in dark.
    static let card = Color.white

    /// Grouped list row background — iOS standard.
    static let groupedRow = Color(uiColor: .secondarySystemGroupedBackground)

    /// Input field background.
    static let input = Color(uiColor: .tertiarySystemFill)

    /// Chip / pill fill for non-selected state.
    static let chip = Color(uiColor: .secondarySystemFill)
}

// MARK: — Typography scale

/// Dynamic Type only. No fixed sizes. No custom fonts.
/// PURGE reference: Font.custom("CormorantGaramond-SemiBold", size: 22) → .title2.weight(.semibold)
///   in AMENAPP/AMENAPP/Notifications/Views/AmenNotificationCard.swift (fixed in D1 sweep)
enum AmenType {
    static let display:     Font = .largeTitle
    static let title:       Font = .title
    static let title2:      Font = .title2
    static let title3:      Font = .title3
    static let headline:    Font = .headline
    static let subheadline: Font = .subheadline
    static let body:        Font = .body
    static let callout:     Font = .callout
    static let footnote:    Font = .footnote
    static let caption:     Font = .caption
    static let caption2:    Font = .caption2
}

// MARK: — Corner radius (extends AnimationTokens.AmenRadius)

/// Additional radii not in AnimationTokens.swift. All radii use `.continuous` squircle style.
extension AmenRadius {
    /// Photo hero image nested within a card — 22pt.
    static let photoHero: CGFloat = 22
    /// Input field — 16pt.
    static let input: CGFloat = 16
    /// Pill / capsule — use Capsule() shape directly.
    static let pill: CGFloat = 999
    /// Circular single-glyph button — use Circle() shape directly.
    static let circularButton: CGFloat = 999
}

// MARK: — Elevation

/// One ambient shadow token. No hard, colored, or brand-colored shadows.
/// PURGE reference: Any shadow using amenGold, accentPurple, or cosmicDark as shadow color.
struct AmenShadow {

    let color: Color
    let opacity: Double
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    /// Standard card ambient shadow — black 7% opacity.
    // PURGED: shadow(color: amenGold.opacity(x)) → AmenShadow.card
    static let card = AmenShadow(
        color: .black,
        opacity: 0.07,
        radius: 24,
        x: 0,
        y: 5
    )

    /// Floating pill / toolbar ambient shadow — black 10% opacity.
    static let floating = AmenShadow(
        color: .black,
        opacity: 0.10,
        radius: 32,
        x: 0,
        y: 10
    )

    enum Level {
        case card
        case floating
    }
}

// MARK: — Materials / Glass

/// Material tokens for glass surfaces.
/// PURGE reference: ONE.Colors.glassWarm (amber tint) — replaced with neutral glass.
/// Glass must be white/clear — no gold-tinted or cosmically-dark glass.
enum AmenMaterial {
    /// Standard glass panel — .regularMaterial.
    case regular

    /// Subtle glass — toolbars overlaid on scrolling content — .thinMaterial.
    case thin

    /// Ultra-subtle glass — sheet peek edges — .ultraThinMaterial.
    case ultraThin

    /// iOS 26 adaptive glass with per-background lensing.
    /// Requires GlassEffectContainer for grouped elements.
    @available(iOS 26.0, *)
    case glassEffect

    /// Over-photo dark translucent pill (Directions button pattern).
    /// Applies .ultraThinMaterial + forced dark color scheme for white text legibility.
    case darkOverlayPill

    /// Resolves to the corresponding SwiftUI Material.
    var material: Material {
        switch self {
        case .regular:         return .regularMaterial
        case .thin:            return .thinMaterial
        case .ultraThin:       return .ultraThinMaterial
        case .darkOverlayPill: return .ultraThinMaterial
        case .glassEffect:     return .regularMaterial  // fallback for < iOS 26
        }
    }
}

// MARK: — Accent color constraint

/// The ONLY permitted brand accent.
/// Use exclusively for interactive affordances: links, toggles, selection rings, progress.
/// PURGE reference:
///   Color.amenGold used as interactive accent → Color.accentColor
///   Color(hex: "#7B68EE") / NotifGlassTokens.accentPurple → Color.accentColor
///   ONE.Colors.witnessGold, subscriberGold, privateIndigo → Color.accentColor
enum AmenAccent {
    /// iOS system accent — adapts to user accessibility settings and system theme.
    static var interactive: Color { Color.accentColor }
}

// MARK: — ViewModifiers

// AmenCardModifier is defined in AmenTheme.swift (canonical implementation)

/// Applies the ambient elevation shadow without a background fill.
/// PURGE reference: shadow(color: amenGold.opacity(x), ...) → AmenElevationModifier(.card)
struct AmenElevationModifier: ViewModifier {
    var level: AmenShadow.Level = .card

    func body(content: Content) -> some View {
        let token: AmenShadow = level == .card ? .card : .floating
        content
            .shadow(
                color: token.color.opacity(token.opacity),
                radius: token.radius,
                x: token.x,
                y: token.y
            )
    }
}

// MARK: — View extensions

extension View {
    /// Applies the ambient elevation shadow without a fill.
    func amenElevation(_ level: AmenShadow.Level = .card) -> some View {
        modifier(AmenElevationModifier(level: level))
    }

    /// Clips content to a fully-rounded capsule shape.
    func amenPillShape() -> some View {
        clipShape(Capsule())
    }
}

// AmenPillAction is defined in CommunityOS/UI/AmenActionPill.swift (canonical implementation)

// MARK: — Stub components (Phase 0 — no production implementations yet)

/// Over-photo dark translucent pill — the "Directions" button pattern.
/// Legible white-on-image text via forced dark color scheme.
/// PURGE reference: Any over-photo label using amenGold foreground color on glass background.
struct AmenGlassOverlayPillStub: View {
    var label: String
    var icon: String  // SF Symbol name

    var body: some View {
        EmptyView()  // Phase 1 implementation pending
    }
}

// MARK: — Purge manifest (what was removed and why)

// PURGED: amenGold (#C9A84C) → Color.accentColor or Color(uiColor: .label)
//   Definition files: AmenAdaptiveColors.swift:133, AmenColorScheme.swift:100
//   Consumer files: 101 Swift files (see C3 §3 purge manifest) — Phase 5 D1 follow-up

// PURGED: amenGoldText (#8C6320 dark gold) → Color(uiColor: .label)
//   Definition file: AmenAdaptiveColors.swift:139

// PURGED: UIColor.amenGold → UIColor.systemBlue (system tintColor)
//   Definition file: AmenColorScheme.swift:143

// PURGED: amenGoldGradient → Color.accentColor gradient
//   Definition file: AmenColorScheme.swift:100

// PURGED: NotifGlassTokens.goldPrimary (#C9A84C) → Color.accentColor
//   Definition file: GlassMaterial.swift:101

// PURGED: NotifGlassTokens.goldLight (#FFD97D) → Color.accentColor
//   Definition file: GlassMaterial.swift:102

// PURGED: NotifGlassTokens.goldGradient → system accent gradient
//   Definition file: GlassMaterial.swift:106

// PURGED: NotifGlassTokens.primaryButtonGradient → system accent gradient
//   Definition file: GlassMaterial.swift:112

// PURGED: NotifGlassTokens.accentPurple (#7B68EE) → Color.accentColor
//   Definition file: GlassMaterial.swift:103

// PURGED: NotifGlassTokens.cosmicDark (#0D0D1A) → Color(uiColor: .systemBackground)
//   Definition file: GlassMaterial.swift:104

// PURGED: glassSurface reduceTransparency fallback #1A1A2E → Color(uiColor: .systemBackground)
//   Definition file: GlassMaterial.swift:49

// PURGED: ONE.Colors.witnessGold → Color.accentColor
//   Definition file: ONETokens.swift:31

// PURGED: ONE.Colors.subscriberGold → Color.accentColor
//   Definition file: ONETokens.swift:39

// PURGED: ONE.Colors.decayAmber (uses amenGold) → Color.orange.opacity(0.60)
//   Definition file: ONETokens.swift:27

// PURGED: ONE.Colors.privateIndigo (#4B5EC6 custom purple) → Color.accentColor
//   Definition file: ONETokens.swift:33

// PURGED: ONE.Colors.glassWarm (amber tint) → neutral secondarySystemBackground tint
//   Definition file: ONETokens.swift:21

// PURGED: amenDarkPrimary, amenDarkSecondary, amenDarkTertiary → Color(uiColor: .systemGroupedBackground)
//   Definition file: AmenColorScheme.swift:17–24

// PURGED: amenMainGradient (dark charcoal gradient) → Color(uiColor: .systemGroupedBackground)
//   Definition file: AmenColorScheme.swift:87

// PURGED: UIColor.amenDarkPrimary, UIColor.amenDarkSecondary → UIColor.systemGroupedBackground
//   Definition file: AmenColorScheme.swift:137–140

// PURGED: Font.custom("CormorantGaramond-SemiBold", size: 22) → .system(.title2).weight(.semibold)
//   Definition file: AmenNotificationCard.swift:93

// Reference: contracts/C3-design-tokens.md

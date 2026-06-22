// AmenDesignSystem.swift
// AMENAPP — Phase 0 Contract C3 Stubs
//
// FROZEN 2026-06-05. Design direction: white Liquid Glass (Apple Photos / Mail aesthetic).
//
// Rules:
//   • Phase 0 only — stubs, no implementations.
//   • All values must derive from iOS semantic system colors.
//   • No custom hex colors for UI surfaces, text, or brand identity.
//   • Single restrained accent: Color.accentColor (iOS system blue) for interactive affordances only.
//   • No dark backgrounds, no gold, no purple, no serif fonts.
//   • Every PURGE comment is a mandatory migration — do not ship the legacy token.
//   • Amendments require a RUNLOG entry.
//
// Cross-reference: Contracts/C3-design-tokens.md

import SwiftUI

// MARK: - AmenSurface

/// Page and card surface tokens.
/// These replace all custom dark/tinted background definitions.
// PURGE: Color.amenDarkPrimary → Color(uiColor: .systemGroupedBackground)
// PURGE: Color.amenDarkSecondary → Color(uiColor: .secondarySystemBackground)
// PURGE: Color.amenDarkTertiary → Color(uiColor: .tertiarySystemBackground)
// PURGE: Color.amenBlack → Color(uiColor: .systemBackground) or Color.black only when semantically correct
// PURGE: Color.amenMainGradient → plain Color(uiColor: .systemGroupedBackground)
// PURGE: Color.amenCream (#F8F4EC) → Color(uiColor: .systemGroupedBackground)
// PURGE: Color.amenSlate (#4A4A55) → Color(uiColor: .secondaryLabel)
// PURGE: NotifGlassTokens.cosmicDark (#0D0D1A) → Color(uiColor: .systemBackground)
// PURGE: glassSurface reduceTransparency fallback #1A1A2E → Color(uiColor: .systemBackground)

enum AmenSurface {
    /// Root page background. Maps to iOS .systemGroupedBackground (~#F2F2F7 light).
    static var pageBg: Color { Color(uiColor: .systemGroupedBackground) }

    /// Card / sheet surface. Pure white in light mode.
    static var cardSurface: Color { Color(uiColor: .secondarySystemGroupedBackground) }

    /// Input field background.
    static var input: Color { Color(uiColor: .tertiarySystemFill) }

    /// Chip / pill fill for non-selected state.
    static var chip: Color { Color(uiColor: .secondarySystemFill) }
}

// MARK: - AmenShadow

/// One ambient shadow token. No hard, colored, or brand-colored shadows.
// PURGE: Any shadow using amenGold, accentPurple, or cosmicDark as shadow color.
// PURGE: GlassMaterial.swift shadow(color: .black.opacity(0.25)) — replace with AmenShadow.card

struct AmenShadow {

    let color: Color
    let opacity: Double
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    /// Standard card ambient shadow — black 6–8% opacity.
    static let card = AmenShadow(
        color: .black,
        opacity: 0.07,
        radius: 24,
        x: 0,
        y: 5
    )

    /// Floating pill / toolbar ambient shadow — black 10–12% opacity.
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

// MARK: - AmenRadius

/// Corner radius tokens. All use continuous (squircle) style.
// PURGE: AmenGlassMetrics.cornerRadiusSmall (10) → AmenRadius.chip (fully rounded Capsule preferred)
// PURGE: AmenGlassMetrics.cornerRadiusMedium (16) → AmenRadius.photoHero
// PURGE: AmenGlassMetrics.cornerRadiusLarge (24) → AmenRadius.card (update to 28–32 range)
// PURGE: LiquidGlassTokens.cornerRadiusSmall (14) → keep as AmenRadius.input only
// NOTE: LiquidGlassTokens.cornerRadiusLarge (32) is compatible — keep

struct AmenRadius {
    /// Card / bottom sheet — squircle 28–32pt.
    static let card: CGFloat = 28

    /// Photo hero nested within a card — 20–24pt.
    static let photoHero: CGFloat = 22

    /// Input field corner radius — 14–16pt.
    static let input: CGFloat = 16

    /// Pill / capsule — use Capsule() shape directly.
    /// This constant is provided for manual path drawing only.
    static let pill: CGFloat = 999

    /// Circular single-glyph button — use Circle() shape directly.
    /// Width must equal height. This constant documents the intent.
    static let circularButton: CGFloat = 999
}

// MARK: - AmenMaterial

/// Material tokens for glass surfaces.
/// All cases map to SwiftUI system materials or iOS 26 glassEffect.
// PURGE: Any custom-tinted glass using amenGold / amber tint (ONE.Colors.glassWarm)
// PURGE: ONE.Colors.glassCool (blue tint) if used decoratively — only use for zone indicators

enum AmenMaterial {
    /// Standard glass panel. Equivalent to .regularMaterial.
    case regular

    /// Subtle glass — toolbars overlaid on scrolling content.
    case thin

    /// Ultra-subtle glass — sheet peek edges.
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
        case .regular:       return .regularMaterial
        case .thin:          return .thinMaterial
        case .ultraThin:     return .ultraThinMaterial
        case .darkOverlayPill: return .ultraThinMaterial
        case .glassEffect:   return .regularMaterial  // fallback for < iOS 26
        }
    }
}

// MARK: - ViewModifier stubs

/// Applies the canonical card surface: white background + ambient shadow + continuous corner radius.
// PURGE: Any caller using .background(Color.amenDarkPrimary).cornerRadius(x) — migrate to AmenCardModifier
struct AmenCardModifier: ViewModifier {
    var cornerRadius: CGFloat = AmenRadius.card
    var elevation: AmenShadow.Level = .card

    func body(content: Content) -> some View {
        // STUB — implementation pending Phase 1
        content
    }
}

/// Applies the ambient elevation shadow without a background fill.
// PURGE: shadow(color: amenGold.opacity(x), ...) — colored shadows not allowed
// PURGE: shadow(color: .black.opacity(0.25), ...) in GlassMaterial → AmenElevationModifier(.card)
struct AmenElevationModifier: ViewModifier {
    var level: AmenShadow.Level = .card

    func body(content: Content) -> some View {
        // STUB — implementation pending Phase 1
        content
    }
}

// MARK: - View stub protocols

/// A card view that wraps content in the canonical AmenCard surface.
protocol AmenHeroCardView: View {
    associatedtype HeroImage: View
    var image: HeroImage { get }
    var title: String { get }
    var subtitle: String? { get }
    // actionPill overlay is optional — AmenGlassOverlayPill pattern
}

/// A segmented selector following the "For You / Library" pattern.
/// Track: secondarySystemFill. Selected pill: white + AmenShadow.card. Black label.
// PURGE: Any segmented selector using amenGold as selected-state color
protocol AmenSegmentedSelectorView: View {
    var segments: [String] { get }
    var selectionIndex: Int { get nonmutating set }
}

/// The universal Action Pill — toolbar of line icons + circular primary action.
/// This is the same component as A18 from the Spatial Social OS directives.
// PURGE: Any floating action button using amenGold as background
protocol AmenActionPillView: View {
    associatedtype Actions
    var actions: [AmenPillAction] { get }
    var isExpanded: Bool { get nonmutating set }
    var onExpand: (() -> Void)? { get }
}

/// Toolbar binding of the Action Pill — leading icons, primary circular action, trailing icons.
protocol AmenToolbarView: View {
    var leadingActions: [AmenPillAction] { get }
    var primaryAction: AmenPillAction { get }
    var trailingActions: [AmenPillAction] { get }
}

// MARK: - AmenPillAction (supporting type for protocol stubs)

/// An action item in an AmenActionPill or AmenToolbar.
struct AmenPillAction: Identifiable {
    let id: String
    let icon: String        // SF Symbol name — monochrome line glyph
    let label: String       // Accessibility label
    let action: () -> Void

    init(id: String = UUID().uuidString,
         icon: String,
         label: String,
         action: @escaping () -> Void) {
        self.id = id
        self.icon = icon
        self.label = label
        self.action = action
    }
}

// MARK: - AmenGlassOverlayPill stub

/// Over-photo dark translucent pill — the "Directions" button pattern.
/// Legible white-on-image text via forced dark color scheme.
// PURGE: Any over-photo label using amenGold foreground color on a glass background
struct AmenGlassOverlayPillStub: View {
    var label: String
    var icon: String        // SF Symbol name

    var body: some View {
        // STUB — implementation pending Phase 1
        EmptyView()
    }
}

// MARK: - Typography stub

/// Typography scale — Dynamic Type only. No fixed sizes. No custom fonts.
// PURGE: Font.custom("CormorantGaramond-SemiBold", size: 22) → Font.title2.weight(.semibold)
//        in AMENAPP/AMENAPP/Notifications/Views/AmenNotificationCard.swift:93
// PURGE: Any Font.custom(...) call in production UI (not previews) — audit all Swift files

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

// MARK: - Accent color constraint

/// The ONLY permitted brand accent.
/// Use exclusively for interactive affordances: links, toggles, selection rings, progress.
// PURGE: Color.amenGold used as interactive accent → Color.accentColor
// PURGE: Color(hex: "#7B68EE") used as interactive accent → Color.accentColor
// PURGE: NotifGlassTokens.accentPurple → Color.accentColor

enum AmenAccent {
    /// iOS system accent — adapts to user accessibility settings and system theme.
    static var interactive: Color { Color.accentColor }
}

// MARK: - Convenience View extensions (stubs)

extension View {
    /// Applies the canonical AMEN card style.
    func amenCard(
        cornerRadius: CGFloat = AmenRadius.card,
        elevation: AmenShadow.Level = .card
    ) -> some View {
        // STUB
        modifier(AmenCardModifier(cornerRadius: cornerRadius, elevation: elevation))
    }

    /// Applies the ambient elevation shadow.
    func amenElevation(_ level: AmenShadow.Level = .card) -> some View {
        // STUB
        modifier(AmenElevationModifier(level: level))
    }
}

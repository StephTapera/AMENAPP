//
//  LiquidGlassNative.swift
//  AMENAPP
//
//  Wave 0 — Liquid Glass redesign core.
//
//  This is the SINGLE bridge to Apple's native iOS 26 Liquid Glass lens
//  (`glassEffect`, `GlassEffectContainer`, `glassEffectID`). It exists because
//  the app already declares its OWN types/modifiers with the EXACT SAME NAMES
//  in `GlassEffectModifiers.swift`:
//
//      • struct GlassEffectContainer            (a no-op padding container)
//      • View.glassEffect(_:in:) / glassEffect(_:)   (a custom .ultraThinMaterial blur)
//      • View.glassEffectID(_:in:)              (a matchedGeometryEffect shim)
//
//  Inside this module those local declarations SHADOW SwiftUI's. A naive
//  `GlassEffectContainer { }` or `.glassEffect(.regular, in: .capsule)` therefore
//  resolves to the FAKE blur, and the all-defaults form is ambiguous. To reach the
//  real lens we must:
//    1. Fully qualify the type:        `SwiftUI.GlassEffectContainer`
//    2. Pass an explicitly-typed Glass value so overload resolution picks Apple's
//       `glassEffect(_ glass: Glass, in:)` over the app's `glassEffect(_ style: GlassEffectStyle, in:)`.
//    3. For morphing, pass a NON-String id (the app's `glassEffectID` takes `String`,
//       Apple's takes `some Hashable & Sendable`).
//
//  All native usage is wrapped in `if #available(iOS 26, *)` and is fail-closed:
//  Reduce Transparency or an unavailable OS renders an opaque solid surface.
//  Nothing here renders until a caller is reached behind `liquid_glass_redesign_enabled`.
//

import SwiftUI

// MARK: - Public vocabulary

/// Where a glass surface sits in the chrome hierarchy. Reserved for future
/// shape/spacing defaults; native glass renders uniformly today.
enum LiquidGlassTier {
    case heavy   // bottom nav, search, composer, media controls, floating actions, context menus
    case medium  // filter rows
    case light   // hero / action chrome
}

/// Emphasis is the ONLY thing that introduces color. The glass is otherwise neutral —
/// its tint is derived from whatever sits beneath it (clean on a white app).
enum LiquidGlassEmphasis {
    case none         // neutral, derived tint
    case interactive  // blue  — tappable affordances, selected controls, links
    case positive     // green — success, confirmed, live / active status
}

/// The two — and only two — accent tokens the glass system introduces.
/// Mapped onto AMEN's existing semantic palette so they stay theme-adaptive.
enum LGAccent {
    /// Blue — interactive / links.
    static var interactive: Color { AmenTheme.Colors.statusInfo }
    /// Green — positive / active / confirmation.
    static var positive: Color { AmenTheme.Colors.success }
}

// MARK: - Solid fallback (the fail-closed contract)

/// Opaque surface with a hairline border and NO transparency. This is what
/// "fail-closed" renders whenever the real lens can't or shouldn't be used.
struct LiquidGlassSolidFallback: View {
    let shape: AnyShape
    var body: some View {
        shape
            .fill(AmenTheme.Colors.surfaceElevated)
            .overlay(shape.stroke(AmenTheme.Colors.borderSoft, lineWidth: 0.75))
    }
}

// MARK: - Native surface modifier

private struct LiquidGlassSurfaceModifier: ViewModifier {
    let tier: LiquidGlassTier
    let emphasis: LiquidGlassEmphasis
    let shape: AnyShape
    let interactive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(LiquidGlassSolidFallback(shape: shape))
        } else if #available(iOS 26.0, *) {
            // `resolvedGlass` is explicitly typed `Glass`, so this binds to
            // SwiftUI.glassEffect(_:in:), never the app's GlassEffectStyle overload.
            content.glassEffect(resolvedGlass, in: shape)
        } else {
            content.background(LiquidGlassSolidFallback(shape: shape))
        }
    }

    @available(iOS 26.0, *)
    private var resolvedGlass: Glass {
        var g: Glass = .regular
        switch emphasis {
        case .none:        break
        case .interactive: g = g.tint(LGAccent.interactive)
        case .positive:    g = g.tint(LGAccent.positive)
        }
        if interactive { g = g.interactive() }
        return g
    }
}

extension View {
    /// The single entry point for authentic Liquid Glass on a functional surface.
    /// Internally selects Apple's native lens or the opaque fallback based on
    /// Reduce Transparency and OS availability.
    ///
    /// Distinct name (`liquidGlassSurface`) deliberately avoids the legacy
    /// `glassEffect` shim in `GlassEffectModifiers.swift`.
    func liquidGlassSurface<S: Shape>(
        _ tier: LiquidGlassTier = .heavy,
        emphasis: LiquidGlassEmphasis = .none,
        in shape: S = Capsule(),
        interactive: Bool = false
    ) -> some View {
        modifier(LiquidGlassSurfaceModifier(
            tier: tier,
            emphasis: emphasis,
            shape: AnyShape(shape),
            interactive: interactive
        ))
    }
}

// MARK: - Native container wrapper

/// Wraps `SwiftUI.GlassEffectContainer` (the real one) so sibling glass shapes
/// blend/morph as one surface. Falls back to a plain passthrough when the lens
/// is unavailable or Reduce Transparency is on — there is nothing to blend then.
///
/// Always reach for THIS instead of the bare `GlassEffectContainer`, which in
/// this module resolves to the legacy no-op padding container.
struct NativeLiquidGlassContainer<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(spacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if !reduceTransparency, #available(iOS 26.0, *) {
            SwiftUI.GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

// MARK: - Native morphing id
//
// To morph the active plate between tab positions, attach the native
// `glassEffectID` using a NON-String id (e.g. an Int or enum). Example, at the
// call site inside a NativeLiquidGlassContainer:
//
//     if #available(iOS 26.0, *) {
//         plate.glassEffectID(selectedTab, in: namespace)   // Int id → native
//     }
//
// Passing an Int (not a String) ensures overload resolution picks SwiftUI's
// glassEffectID(_:in:) rather than the app's String-typed shim.

//
//  GlassEffectModifiers.swift
//  AMENAPP
//
//  Created by Steph on 1/15/26.
//
//  Production-ready Liquid Glass implementation for iOS
//  Matches Threads-style dark, sophisticated aesthetic
//

import SwiftUI

// MARK: - Glass Effect Container
/// A container that applies glass effect styling to its content and enables morphing between glass effects
struct GlassEffectContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content
    
    init(spacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }
    
    var body: some View {
        content()
            .padding(spacing)
    }
}

// MARK: - Glass Effect Modifiers

extension View {
    /// Applies a glassmorphic effect to the view with a specific shape
    /// - Parameters:
    ///   - style: The glass effect style
    ///   - shape: The shape to clip the effect to
    /// - Returns: A view with glass effect applied
    func glassEffect<S: Shape>(_ style: GlassEffectStyle, in shape: S) -> some View {
        self.modifier(GlassEffectModifier(style: style, shape: AnyShape(shape)))
    }
    
    /// Applies a glassmorphic effect to the view
    /// - Parameter style: The glass effect style
    /// - Returns: A view with glass effect applied
    func glassEffect(_ style: GlassEffectStyle = .regular) -> some View {
        self.modifier(GlassEffectModifier(style: style, shape: nil))
    }
    
    /// Assigns an identifier for glass effect animations and morphing
    /// - Parameters:
    ///   - id: The identifier for this view
    ///   - namespace: The namespace for matched geometry
    /// - Returns: A view with the glass effect ID applied
    func glassEffectID(_ id: String, in namespace: Namespace.ID) -> some View {
        self.matchedGeometryEffect(id: "glass_\(id)", in: namespace)
    }
    
    /// Unites multiple glass effects into a single unified effect
    /// - Parameters:
    ///   - id: The group identifier
    ///   - namespace: The namespace for matched geometry
    /// - Returns: A view with glass effect union applied
    func glassEffectUnion(id: String, namespace: Namespace.ID) -> some View {
        self.matchedGeometryEffect(id: "union_\(id)", in: namespace)
    }

    /// Overlays a scroll-reactive bottom-up frosted glass fog on a ScrollView.
    ///
    /// Reads the scroll offset via `DynamicGlassScrollOffsetKey` and feeds it into
    /// `DynamicGlassOverlay`. The overlay is non-interactive (`allowsHitTesting(false)`)
    /// and ignores the bottom safe area so it flows under the home indicator.
    ///
    /// **Usage — wrap your ScrollView:**
    /// ```swift
    /// ScrollView {
    ///     VStack {
    ///         ScrollOffsetReader()   // must be first child
    ///         // ... content ...
    ///     }
    /// }
    /// .coordinateSpace(name: "dynamicGlassScroll")
    /// .scrollReactiveGlass()
    /// ```
    ///
    /// - Parameters:
    ///   - coverageFraction: Fraction of the view height the glass panel covers at full intensity (default 0.65).
    ///   - rampDistance: Scroll distance in points over which glass ramps from base to full intensity (default 180).
    /// - Returns: The view with a `DynamicGlassOverlay` anchored to its bottom edge.
    func scrollReactiveGlass(
        coverageFraction: CGFloat = 0.65,
        rampDistance: CGFloat = 180
    ) -> some View {
        self.modifier(ScrollReactiveGlassModifier(
            coverageFraction: coverageFraction,
            rampDistance: rampDistance
        ))
    }
}

// MARK: - Glass Effect Style

struct GlassEffectStyle {
    let intensity: CGFloat
    let isInteractive: Bool
    let tintColor: Color?
    let blurRadius: CGFloat
    let strokeWidth: CGFloat
    let strokeOpacity: Double
    
    /// Regular glass effect - standard intensity
    static let regular = GlassEffectStyle(
        intensity: 0.15,
        isInteractive: false,
        tintColor: nil,
        blurRadius: 12,
        strokeWidth: 1,
        strokeOpacity: 0.15
    )
    
    /// Prominent glass effect - higher intensity
    static let prominent = GlassEffectStyle(
        intensity: 0.25,
        isInteractive: false,
        tintColor: nil,
        blurRadius: 16,
        strokeWidth: 1.5,
        strokeOpacity: 0.2
    )
    
    /// Subtle glass effect - lower intensity
    static let subtle = GlassEffectStyle(
        intensity: 0.08,
        isInteractive: false,
        tintColor: nil,
        blurRadius: 8,
        strokeWidth: 0.5,
        strokeOpacity: 0.1
    )

    /// No-op glass effect — zero intensity/blur/stroke. Use when reduceTransparency
    /// is on so the solid .background block shows through without changing view structure.
    static let identity = GlassEffectStyle(
        intensity: 0,
        isInteractive: false,
        tintColor: nil,
        blurRadius: 0,
        strokeWidth: 0,
        strokeOpacity: 0
    )
    
    /// Makes the glass effect interactive (responds to touch)
    func interactive() -> GlassEffectStyle {
        GlassEffectStyle(
            intensity: intensity,
            isInteractive: true,
            tintColor: tintColor,
            blurRadius: blurRadius,
            strokeWidth: strokeWidth,
            strokeOpacity: strokeOpacity
        )
    }
    
    /// Adds a color tint to the glass effect
    func tint(_ color: Color) -> GlassEffectStyle {
        GlassEffectStyle(
            intensity: intensity,
            isInteractive: isInteractive,
            tintColor: color,
            blurRadius: blurRadius,
            strokeWidth: strokeWidth,
            strokeOpacity: strokeOpacity
        )
    }
    
    /// Adjusts the intensity of the glass effect
    func intensity(_ value: CGFloat) -> GlassEffectStyle {
        GlassEffectStyle(
            intensity: value,
            isInteractive: isInteractive,
            tintColor: tintColor,
            blurRadius: blurRadius,
            strokeWidth: strokeWidth,
            strokeOpacity: strokeOpacity
        )
    }
}

// MARK: - Glass Effect Modifier

struct GlassEffectModifier: ViewModifier {
    let style: GlassEffectStyle
    let shape: AnyShape?

    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if let shape = shape {
            content
                .background(
                    glassBackground()
                        .clipShape(shape)
                )
        } else {
            content
                .background(glassBackground())
        }
    }

    @ViewBuilder
    private func glassBackground() -> some View {
        // PERF: Collapsed to 2 layers. See original comment for rationale.
        // Dark-mode calibration: white overlays are dramatically reduced so the
        // glass feels like smoked/refined dark glass rather than milky frosted white.
        // Light-mode behavior is unchanged.
        let isDark = colorScheme == .dark

        // Gradient highlight: bright in light, barely-there in dark
        let gradStartOpacity = isDark ? style.intensity * 0.45 : style.intensity * 0.80
        let gradEndOpacity   = isDark ? style.intensity * 0.15 : style.intensity * 0.30

        // Stroke: visible contour in both modes; slightly brighter in dark for definition
        let strokeStart = isDark ? style.strokeOpacity * 1.1 : style.strokeOpacity
        let strokeEnd   = isDark ? style.strokeOpacity * 0.6 : style.strokeOpacity * 0.5

        // Depth pooling: more visible in dark mode
        let depthOpacity = isDark ? style.intensity * 1.8 : style.intensity

        ZStack {
            // Layer 1 — GPU-composited backdrop blur (cannot be merged)
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(isDark ? 0.92 : 0.80)

            // Layer 2 — All decorative fills in one Canvas pass
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)

                // Depth overlay (darker in dark mode for depth, lighter in light)
                context.fill(Path(rect), with: .color(.black.opacity(depthOpacity)))

                // Optional color tint
                if let tint = style.tintColor {
                    context.fill(Path(rect), with: .color(tint.opacity(isDark ? 0.08 : 0.15)))
                }

                // Highlight gradient — the core "glass" look
                // In dark mode this is very subtle; in light mode it's the bright gloss
                context.fill(
                    Path(rect),
                    with: .linearGradient(
                        Gradient(colors: [
                            .white.opacity(gradStartOpacity),
                            .white.opacity(gradEndOpacity)
                        ]),
                        startPoint: CGPoint(x: rect.minX, y: rect.minY),
                        endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
                    )
                )

                // Border stroke — provides contour definition on both backgrounds
                let inset = style.strokeWidth / 2
                context.stroke(
                    Path(rect.insetBy(dx: inset, dy: inset)),
                    with: .linearGradient(
                        Gradient(colors: [
                            .white.opacity(strokeStart),
                            .white.opacity(strokeEnd)
                        ]),
                        startPoint: CGPoint(x: rect.minX, y: rect.minY),
                        endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
                    ),
                    lineWidth: style.strokeWidth
                )
            }
        }
        .drawingGroup()
        .scaleEffect(style.isInteractive && isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onTapGesture {
            if style.isInteractive {
                withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.5))) {
                    isPressed = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.5))) {
                        isPressed = false
                    }
                }
            }
        }
    }
}
// MARK: - AnyShape (Type-erased Shape)

struct AnyShape: Shape {
    private let _path: @Sendable (CGRect) -> Path
    
    init<S: Shape>(_ shape: S) {
        _path = { rect in
            shape.path(in: rect)
        }
    }
    
    func path(in rect: CGRect) -> Path {
        _path(rect)
    }
}

// MARK: - Scroll-Reactive Glass Modifier

/// ViewModifier backing `.scrollReactiveGlass()`. Tracks `DynamicGlassScrollOffsetKey`
/// changes and passes the value to `DynamicGlassOverlay`.
private struct ScrollReactiveGlassModifier: ViewModifier {
    let coverageFraction: CGFloat
    let rampDistance: CGFloat

    @State private var scrollOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(DynamicGlassScrollOffsetKey.self) { value in
                // Throttle sub-pixel noise — only update when change ≥ 1pt
                if abs(value - scrollOffset) >= 1 {
                    scrollOffset = value
                }
            }
            .overlay(alignment: .bottom) {
                DynamicGlassOverlay(
                    scrollOffset: scrollOffset,
                    coverageFraction: coverageFraction,
                    rampDistance: rampDistance
                )
                .ignoresSafeArea(edges: .bottom)
            }
    }
}

// MARK: - Scroll-Edge Top Blur

/// UIKit bridge for the top-edge blur — wraps UIVisualEffectView for GPU-composited
/// CABackdropLayer rendering. Separate from ScrollReactiveGlass's private copy so
/// both top and bottom overlays can use the same technique independently.
private struct TopEdgeBlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

/// A LinearGradient that goes opaque (top) → transparent (bottom).
/// Mirror of FadeUpMask — applied so the material fades OUT toward content.
private struct FadeDownMask: View {
    /// 0 = fully transparent everywhere, 1 = full gradient from opaque→clear
    let intensity: CGFloat

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(intensity),        location: 0.0),
                .init(color: .black.opacity(0.82 * intensity), location: 0.25),
                .init(color: .black.opacity(0.45 * intensity), location: 0.55),
                .init(color: .black.opacity(0.0),              location: 0.85),
                .init(color: .clear,                           location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Top-anchored frosted glass overlay that fades in as the user scrolls down.
/// Designed for screens with hidden navigation bars where content scrolls
/// into the status bar area (Messages, Notifications, Resources).
///
/// Architecture matches `DynamicGlassOverlay` — GPU-composited UIVisualEffectView
/// behind a gradient mask, driven by a single CGFloat scroll offset.
struct ScrollEdgeTopBlurOverlay: View {
    /// Raw scroll offset — positive = bouncing above top, negative = scrolled down.
    let scrollOffset: CGFloat

    /// Height of the blur panel in points. Default covers status bar + ~20pt breathing room.
    var panelHeight: CGFloat = 72

    /// Scroll distance (pts) over which effect ramps from 0→1.
    var rampDistance: CGFloat = 100

    /// Minimum intensity at rest (0 = invisible until scroll).
    var baseIntensity: CGFloat = 0.0

    @Environment(\.colorScheme) private var colorScheme

    private var intensity: CGFloat {
        let scrolledDown = max(0, -scrollOffset)
        let progress = min(scrolledDown / rampDistance, 1.0)
        return baseIntensity + (1.0 - baseIntensity) * progress
    }

    private var tintOpacity: Double {
        colorScheme == .dark
            ? Double(intensity) * 0.04
            : Double(intensity) * 0.18
    }

    var body: some View {
        if intensity > 0.01 {
            ZStack {
                // Layer 1: GPU-composited blur
                TopEdgeBlurView(style: colorScheme == .dark ? .systemUltraThinMaterialDark
                                                            : .systemUltraThinMaterialLight)

                // Layer 2: Subtle tint wash
                Color(colorScheme == .dark ? .systemBackground : .white)
                    .opacity(tintOpacity)

                // Layer 3: Very subtle bottom-edge separator
                VStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.primary.opacity(0.05 * intensity)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 12)
                }
            }
            .frame(height: panelHeight)
            .mask(FadeDownMask(intensity: intensity))
            .allowsHitTesting(false)
            .animation(.linear(duration: 0.016), value: intensity)
        }
    }
}

/// Convenience ViewModifier: attaches a `ScrollEdgeTopBlurOverlay` to the top
/// of any view. The caller must supply the current scroll offset.
///
/// Usage:
/// ```swift
/// ZStack(alignment: .top) {
///     ScrollView { ... }
///     // modifier reads scrollOffset binding
/// }
/// .scrollEdgeTopBlur(scrollOffset: scrollOffset)
/// ```
struct ScrollEdgeTopBlurModifier: ViewModifier {
    let scrollOffset: CGFloat
    var panelHeight: CGFloat = 72
    var rampDistance: CGFloat = 100

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                ScrollEdgeTopBlurOverlay(
                    scrollOffset: scrollOffset,
                    panelHeight: panelHeight,
                    rampDistance: rampDistance
                )
                .ignoresSafeArea(edges: .top)
            }
    }
}

extension View {
    /// Adds a scroll-edge frosted glass blur at the top of the view.
    /// - Parameters:
    ///   - scrollOffset: Current scroll offset (positive = above origin, negative = scrolled down)
    ///   - panelHeight: Height of the blur panel (default 72pt)
    ///   - rampDistance: Scroll distance for full intensity (default 100pt)
    func scrollEdgeTopBlur(
        scrollOffset: CGFloat,
        panelHeight: CGFloat = 72,
        rampDistance: CGFloat = 100
    ) -> some View {
        self.modifier(ScrollEdgeTopBlurModifier(
            scrollOffset: scrollOffset,
            panelHeight: panelHeight,
            rampDistance: rampDistance
        ))
    }
}

// MARK: - Shake Effect

/// A `GeometryEffect` that produces a rapid horizontal shake to signal an error or rejection.
/// Usage: `.modifier(ShakeEffect(shakes: triggerBool ? 3 : 0))`
struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let angle = sin(shakes * .pi * 3) * 6.0
        let translation = CGAffineTransform(translationX: angle, y: 0)
        return ProjectionTransform(translation)
    }
}


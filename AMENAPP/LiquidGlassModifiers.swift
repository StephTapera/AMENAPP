//
//  LiquidGlassModifiers.swift
//  AMENAPP
//
//  Premium Liquid Glass visual system for white background apps
//

import SwiftUI

// MARK: - Liquid Glass Style

struct LiquidGlassStyle: ViewModifier {
    let opacity: Double
    let blur: CGFloat
    let shadowOpacity: Double
    let cornerRadius: CGFloat
    
    init(
        opacity: Double = 0.08,
        blur: CGFloat = 12,
        shadowOpacity: Double = 0.08,
        cornerRadius: CGFloat = 20
    ) {
        self.opacity = opacity
        self.blur = blur
        self.shadowOpacity = shadowOpacity
        self.cornerRadius = cornerRadius
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Base white glass layer
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(opacity))
                        .background(
                            .ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius)
                        )
                    
                    // Top edge highlight
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.5),
                                    Color.white.opacity(0.2),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                    
                    // Inner light reflection
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .padding(1)
                }
            )
            .shadow(
                color: Color.black.opacity(shadowOpacity),
                radius: blur,
                y: 4
            )
            .shadow(
                color: Color.black.opacity(shadowOpacity * 0.5),
                radius: blur / 2,
                y: 2
            )
    }
}

// MARK: - Input Glass Style

struct InputGlassStyle: ViewModifier {
    let opacity: Double
    let isFocused: Bool
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Input field glass
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(opacity))
                    
                    // Focus ring
                    if isFocused {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                    } else {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Color.gray.opacity(0.15), lineWidth: 0.5)
                    }
                }
            )
    }
}

// MARK: - Action Pill Style

struct ActionPillStyle: ViewModifier {
    let color: Color
    
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    // Pill base
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .background(
                            .ultraThinMaterial,
                            in: Capsule()
                        )
                    
                    // Edge highlight
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                    
                    // Subtle color tint
                    Capsule()
                        .fill(color.opacity(0.05))
                }
            )
            .shadow(color: Color.black.opacity(0.08), radius: 8, y: 2)
    }
}

// MARK: - Floating Pill Style

struct FloatingPillStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .background(
                            .ultraThinMaterial,
                            in: Capsule()
                        )
                    
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.4),
                                    Color.white.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
            )
            .shadow(color: Color.black.opacity(0.1), radius: 10, y: 3)
    }
}

// MARK: - Suggestion Chip Style

struct SuggestionChipStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                        .background(
                            .ultraThinMaterial,
                            in: Capsule()
                        )
                    
                    Capsule()
                        .strokeBorder(Color.gray.opacity(0.15), lineWidth: 0.5)
                }
            )
    }
}

// MARK: - View Extensions

extension View {
    func liquidGlass(
        opacity: Double = 0.08,
        blur: CGFloat = 12,
        shadowOpacity: Double = 0.08,
        cornerRadius: CGFloat = 20
    ) -> some View {
        modifier(LiquidGlassStyle(
            opacity: opacity,
            blur: blur,
            shadowOpacity: shadowOpacity,
            cornerRadius: cornerRadius
        ))
    }
    
    func inputGlass(opacity: Double = 0.15, isFocused: Bool = false) -> some View {
        modifier(InputGlassStyle(opacity: opacity, isFocused: isFocused))
    }
    
    func actionPill(color: Color = .blue) -> some View {
        modifier(ActionPillStyle(color: color))
    }
    
    func floatingPill() -> some View {
        modifier(FloatingPillStyle())
    }
    
    func suggestionChip() -> some View {
        modifier(SuggestionChipStyle())
    }
}

// MARK: - iOS 18 symbolEffect compatibility shims

extension View {
    @ViewBuilder
    func amenBreatheSymbolEffect(isActive: Bool = true) -> some View {
        if #available(iOS 18, *) {
            self.symbolEffect(.breathe, isActive: isActive)
        } else {
            self
        }
    }

    @ViewBuilder
    func amenSymbolReplaceTransition() -> some View {
        if #available(iOS 18, *) {
            self.contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
        } else {
            self.contentTransition(.symbolEffect(.replace))
        }
    }
}

// MARK: - iOS 18 scrollTargetBehavior(.viewAligned(limitBehavior:)) shim

extension View {
    @ViewBuilder
    func amenViewAlignedScrollTarget() -> some View {
        if #available(iOS 18, *) {
            self.scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByFew))
        } else {
            self.scrollTargetBehavior(.viewAligned)
        }
    }
}

// MARK: - iOS 26 glassEffect compatibility shim

extension View {
    /// Wraps `.glassEffect(in:)` behind `#available(iOS 26, *)` so the call site
    /// compiles on any deployment target. On older OS versions the modifier is a no-op.
    @ViewBuilder
    func amenGlassEffect<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(in: shape)
        } else {
            self
        }
    }

    @ViewBuilder
    func amenGlassEffect() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect()
        } else {
            self
        }
    }

    // SECURITY FIX (MEDIUM 2026-06-11): Added shims for .glassEffect(.regular, in:) and
    // .glassEffect(.regular.interactive(), in:) variants used across SignInView, HomeView,
    // EmptyFeedView, AppUsageTracker, and SelahView. Without these guards the views crash
    // at launch on iOS 17/18 (deployment target). Falls back to .background(.thinMaterial).
    @ViewBuilder
    func amenRegularGlassEffect<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(Glass.regular, in: shape)
        } else {
            self.background(.thinMaterial, in: shape)
        }
    }

    @ViewBuilder
    func amenInteractiveGlassEffect<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(Glass.regular.interactive(), in: shape)
        } else {
            self.background(.thinMaterial, in: shape)
        }
    }

    @ViewBuilder
    func amenProminentGlassEffect<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.prominent, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}

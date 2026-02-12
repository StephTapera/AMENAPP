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
        ZStack {
            // Base frosted glass layer
            RoundedRectangle(cornerRadius: 0)
                .fill(.ultraThinMaterial)
                .opacity(0.8)
            
            // Dark tinted overlay for depth
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.black.opacity(style.intensity))
            
            // Optional color tint
            if let tint = style.tintColor {
                RoundedRectangle(cornerRadius: 0)
                    .fill(tint.opacity(0.15))
            }
            
            // Gradient overlay for liquid effect
            RoundedRectangle(cornerRadius: 0)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(style.intensity * 0.8),
                            Color.white.opacity(style.intensity * 0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Subtle border for definition
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(style.strokeOpacity),
                            Color.white.opacity(style.strokeOpacity * 0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: style.strokeWidth
                )
        }
        .scaleEffect(style.isInteractive && isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onTapGesture {
            if style.isInteractive {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                    isPressed = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                        isPressed = false
                    }
                }
            }
        }
    }
}
// MARK: - AnyShape (Type-erased Shape)

struct AnyShape: Shape {
    private let _path: (CGRect) -> Path
    
    init<S: Shape>(_ shape: S) {
        _path = { rect in
            shape.path(in: rect)
        }
    }
    
    func path(in rect: CGRect) -> Path {
        _path(rect)
    }
}


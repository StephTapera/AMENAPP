// BereanDesignSystem.swift
// AMEN App — Design tokens and animation system for Berean AI
// Ensures visual consistency across all Berean components

import SwiftUI

// ─── MARK: AmenColor ────────────────────────────────────────────────────────

enum AmenColor {
    // ── Background ──────────────────────────────────────────────────────────
    static let background = Color(hex: "FAFBFC")
    
    // ── Typography ──────────────────────────────────────────────────────────
    static let titleText = Color(hex: "0D0D0D")
    static let bodyText = Color(hex: "1C1C1E")
    static let mutedText = Color(hex: "8E8E93")
    
    // ── Accent ──────────────────────────────────────────────────────────────
    static let accent = Color(hex: "D4A05A")  // AMEN gold
    static let accentMuted = Color(hex: "D4A05A").opacity(0.12)
    
    // ── Dividers & Borders ──────────────────────────────────────────────────
    static let divider = Color(hex: "E5E5EA")
    
    // ── Message Bubbles ─────────────────────────────────────────────────────
    static let userBubble = Color(hex: "0D0D0D")
    static let userBubbleText = Color.white
    static let bereanBubbleText = Color(hex: "1C1C1E")
    
    // ── Action Chips ────────────────────────────────────────────────────────
    static let chipActive = Color(hex: "D4A05A").opacity(0.18)
    static let chipActiveText = Color(hex: "0D0D0D")
}

// ─── MARK: AmenRadius ───────────────────────────────────────────────────────

enum AmenRadius {
    static let card: CGFloat = 18
    static let composer: CGFloat = 22
    static let bubble: CGFloat = 20
    static let chip: CGFloat = 20
    static let button: CGFloat = 14
}

// ─── MARK: AmenSpacing ──────────────────────────────────────────────────────

enum AmenSpacing {
    // ── Composer ────────────────────────────────────────────────────────────
    static let composerH: CGFloat = 18
    static let composerV: CGFloat = 16
    
    // ── Chips ───────────────────────────────────────────────────────────────
    static let chipH: CGFloat = 16
    static let chipV: CGFloat = 10
    
    // ── Quick Actions ───────────────────────────────────────────────────────
    static let quickActionSize: CGFloat = 36
}

// ─── MARK: AmenOpacity ──────────────────────────────────────────────────────

enum AmenOpacity {
    // ── Glass Fill ──────────────────────────────────────────────────────────
    static let glassFill: Double = 0.84
    static let glassFillFocused: Double = 0.92
    
    // ── Shadows ─────────────────────────────────────────────────────────────
    static let shadowIdle: Double = 0.08
    static let shadowFocused: Double = 0.14
    
    // ── Text ────────────────────────────────────────────────────────────────
    static let placeholderText: Double = 0.40
}

// ─── MARK: Animation Extensions ─────────────────────────────────────────────

extension Animation {
    // ── AMEN Standard Animations ────────────────────────────────────────────
    
    /// Primary spring for entries, transitions, and expansions
    static let amenSpringEntry = Animation.spring(
        response: 0.55,
        dampingFraction: 0.68,
        blendDuration: 0
    )
    
    /// Bouncy spring for interactive elements
    static let amenSpringBouncy = Animation.spring(
        response: 0.35,
        dampingFraction: 0.64,
        blendDuration: 0
    )
    
    /// Quick ease for state changes
    static let amenEaseQuick = Animation.easeOut(duration: 0.22)
    
    /// Smooth ease for polished transitions
    static let amenEaseSmooth = Animation.easeInOut(duration: 0.35)
    
    /// Focus lift animation
    static let amenFocusLift = Animation.spring(
        response: 0.30,
        dampingFraction: 0.72,
        blendDuration: 0
    )
    
    /// Material formation (glass appearing)
    static let amenMaterialize = Animation.spring(
        response: 0.45,
        dampingFraction: 0.70,
        blendDuration: 0
    )
    
    /// Dematerialize (glass disappearing)
    static let amenDematerialize = Animation.easeIn(duration: 0.18)
}

// ─── MARK: Liquid Glass Modifiers ──────────────────────────────────────────

extension View {
    /// Apply standard AMEN Liquid Glass surface styling
    func amenGlassSurface(
        cornerRadius: CGFloat = AmenRadius.card,
        fillOpacity: CGFloat = AmenOpacity.glassFill,
        shadowRadius: CGFloat = 20,
        shadowY: CGFloat = 6
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(fillOpacity))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.80),
                                        Color.white.opacity(0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.75
                            )
                    )
                    .shadow(
                        color: Color.black.opacity(AmenOpacity.shadowIdle),
                        radius: shadowRadius,
                        x: 0,
                        y: shadowY
                    )
            )
    }
    
    /// Apply premium press animation
    func amenPressAnimation() -> some View {
        self.modifier(AmenPressModifier())
    }
    
    /// Apply material formation animation
    func amenMaterialize(delay: Double = 0) -> some View {
        self.modifier(AmenMaterializeModifier(delay: delay))
    }
}

// ─── MARK: Press Modifier ───────────────────────────────────────────────────

private struct AmenPressModifier: ViewModifier {
    @GestureState private var isPressed = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.93 : 1.0)
            .animation(.amenSpringBouncy, value: isPressed)
            .gesture(
                LongPressGesture(minimumDuration: 2.0)
                    .updating($isPressed) { value, state, _ in
                        state = value
                    }
            )
    }
}

// ─── MARK: Materialize Modifier ─────────────────────────────────────────────

private struct AmenMaterializeModifier: ViewModifier {
    let delay: Double
    @State private var appeared = false
    
    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.92)
            .offset(y: appeared ? 0 : 12)
            .onAppear {
                withAnimation(.amenMaterialize.delay(delay)) {
                    appeared = true
                }
            }
    }
}

// ─── MARK: Color Extension ──────────────────────────────────────────────────

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (r, g, b) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: 1
        )
    }
}

// ─── MARK: Smart Animation Helpers ──────────────────────────────────────────

/// Animation coordinator for complex multi-element transitions
struct AmenAnimationCoordinator {
    
    /// Stagger animation across multiple elements
    static func stagger(
        count: Int,
        baseDelay: Double = 0,
        interval: Double = 0.08,
        animation: Animation = .amenMaterialize
    ) -> [(delay: Double, animation: Animation)] {
        (0..<count).map { index in
            (
                delay: baseDelay + Double(index) * interval,
                animation: animation
            )
        }
    }
    
    /// Cascade animation (later elements have longer duration)
    static func cascade(
        count: Int,
        baseResponse: Double = 0.4,
        responseIncrease: Double = 0.05
    ) -> [Animation] {
        (0..<count).map { index in
            Animation.spring(
                response: baseResponse + Double(index) * responseIncrease,
                dampingFraction: 0.68
            )
        }
    }
}

// ─── MARK: Haptic Feedback ──────────────────────────────────────────────────

enum AmenHaptics {
    /// Light tap for chip selection
    static func lightTap() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
    
    /// Medium tap for button presses
    static func mediumTap() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
    
    /// Success feedback
    static func success() {
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)
    }
    
    /// Warning feedback
    static func warning() {
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.warning)
    }
    
    /// Error feedback
    static func error() {
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.error)
    }
}

// ─── MARK: Performance Optimization Helpers ─────────────────────────────────

extension View {
    /// Draw priority for performance-critical views
    func amenDrawPriority(_ priority: Double = 1) -> some View {
        self.drawingGroup()
            .compositingGroup()
    }
    
    /// Optimize for scrolling performance
    func amenScrollOptimized() -> some View {
        self
            .drawingGroup()
            .id(UUID()) // Force view identity for better recycling
    }
}

// ─── MARK: Typography Scale ────────────────────────────────────────────────

enum AmenTypography {
    // ── Display ─────────────────────────────────────────────────────────────
    static let displayLarge = Font.system(size: 34, weight: .bold)
    static let displayMedium = Font.system(size: 28, weight: .bold)
    static let displaySmall = Font.system(size: 22, weight: .semibold)
    
    // ── Heading ─────────────────────────────────────────────────────────────
    static let headingLarge = Font.system(size: 20, weight: .semibold)
    static let headingMedium = Font.system(size: 17, weight: .semibold)
    static let headingSmall = Font.system(size: 15, weight: .semibold)
    
    // ── Body ────────────────────────────────────────────────────────────────
    static let bodyLarge = Font.system(size: 17, weight: .regular)
    static let bodyMedium = Font.system(size: 15, weight: .regular)
    static let bodySmall = Font.system(size: 13, weight: .regular)
    
    // ── Label ───────────────────────────────────────────────────────────────
    static let labelLarge = Font.system(size: 14, weight: .medium)
    static let labelMedium = Font.system(size: 12, weight: .medium)
    static let labelSmall = Font.system(size: 10, weight: .medium)
    
    // ── Caption ─────────────────────────────────────────────────────────────
    static let caption = Font.system(size: 11, weight: .regular)
    static let captionEmphasized = Font.system(size: 11, weight: .semibold)
}

//
//  AmenAdaptiveColors.swift
//  AMENAPP
//
//  Adaptive color system for seamless light/dark mode support
//  Preserves the same design language and layout - only colors adapt
//

import SwiftUI
import Combine

// MARK: - Adaptive Color Extensions

extension Color {
    // MARK: - Adaptive Backgrounds
    
    /// Primary background - Main app background
    /// Light: white (#FFFFFF), Dark: deep charcoal (#1A1A1A)
    static let adaptiveBackground = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)  // #1A1A1A
            : UIColor.white
    })
    
    /// Secondary background - Elevated surfaces, cards
    /// Light: very light gray (#F5F5F5), Dark: lighter charcoal (#252525)
    static let adaptiveSecondaryBackground = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0)  // #252525
            : UIColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1.0)  // #F5F5F5
    })
    
    /// Surface - Cards, cells, post cards
    /// Light: white, Dark: medium gray (#2E2E2E)
    static let adaptiveSurface = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1.0)  // #2E2E2E
            : UIColor.white
    })
    
    /// Grouped background - For grouped lists
    /// Light: iOS default systemGroupedBackground, Dark: very dark (#121212)
    static let adaptiveGroupedBackground = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1.0)  // #121212
            : UIColor.systemGroupedBackground
    })
    
    // MARK: - Adaptive Text
    
    /// Primary text - Highest emphasis, main content
    /// Light: black, Dark: white
    static let adaptiveTextPrimary = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white
            : UIColor.black
    })
    
    /// Secondary text - Medium emphasis, supporting content
    /// Light: black 70% opacity, Dark: white 70% opacity
    static let adaptiveTextSecondary = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.7)
            : UIColor.black.withAlphaComponent(0.7)
    })
    
    /// Tertiary text - Low emphasis, captions, timestamps
    /// Light: black 50% opacity, Dark: white 50% opacity
    static let adaptiveTextTertiary = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.5)
            : UIColor.black.withAlphaComponent(0.5)
    })
    
    /// Placeholder text - Text field placeholders
    /// Light: black 30% opacity, Dark: white 30% opacity
    static let adaptivePlaceholder = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.3)
            : UIColor.black.withAlphaComponent(0.3)
    })
    
    // MARK: - Adaptive UI Elements
    
    /// Divider - Separator lines between content
    /// Light: black 10% opacity, Dark: white 15% opacity
    static let adaptiveDivider = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.15)
            : UIColor.black.withAlphaComponent(0.1)
    })
    
    /// Border - Stroke borders around elements
    /// Light: black 10% opacity, Dark: white 20% opacity
    static let adaptiveBorder = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.2)
            : UIColor.black.withAlphaComponent(0.1)
    })
    
    /// Shadow - Color for shadow overlays (used with opacity)
    /// Light: black, Dark: black (but with higher opacity in dark mode)
    static let adaptiveShadow = Color(uiColor: UIColor { traitCollection in
        // Shadow is always black, but we'll use different opacities when applying
        UIColor.black
    })
    
    /// Glass overlay - For glassmorphic effects
    /// Light: white 30% opacity, Dark: white 10% opacity
    static let adaptiveGlassOverlay = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.1)
            : UIColor.white.withAlphaComponent(0.3)
    })
    
    /// Glass secondary overlay - Subtle highlight
    /// Light: white 12% opacity, Dark: white 5% opacity
    static let adaptiveGlassSecondary = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.05)
            : UIColor.white.withAlphaComponent(0.12)
    })
    
    /// Glass border - For glassmorphic borders
    /// Light: white 50% opacity, Dark: white 30% opacity
    static let adaptiveGlassBorder = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.3)
            : UIColor.white.withAlphaComponent(0.5)
    })
    
    // MARK: - Adaptive Button Colors
    
    /// Primary button background - High emphasis actions (Follow, Post, Send)
    /// Light: black, Dark: white
    static let adaptiveButtonPrimaryBackground = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white
            : UIColor.black
    })
    
    /// Primary button text - Text on primary buttons
    /// Light: white, Dark: black
    static let adaptiveButtonPrimaryText = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.black
            : UIColor.white
    })
    
    /// Secondary button background - Medium emphasis actions
    /// Light: white with border, Dark: gray with border
    static let adaptiveButtonSecondaryBackground = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1.0)  // Medium gray
            : UIColor.white
    })
    
    /// Secondary button text - Text on secondary buttons
    /// Light: black, Dark: white
    static let adaptiveButtonSecondaryText = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white
            : UIColor.black
    })
    
    /// Tertiary button background - Low emphasis, transparent
    /// Light: black 5% opacity, Dark: white 10% opacity
    static let adaptiveButtonTertiaryBackground = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.1)
            : UIColor.black.withAlphaComponent(0.05)
    })
    
    /// Tertiary button text - Text on tertiary/ghost buttons
    /// Light: black, Dark: white
    static let adaptiveButtonTertiaryText = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white
            : UIColor.black
    })
    
    /// Destructive button background - Delete, Remove actions
    /// Light: red, Dark: lighter red
    static let adaptiveButtonDestructiveBackground = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.4, blue: 0.4, alpha: 1.0)
            : UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1.0)
    })
    
    /// Destructive button text - Text on destructive buttons
    /// Always white for contrast
    static let adaptiveButtonDestructiveText = Color.white
    
    /// Disabled button background - Non-interactive state
    /// Light: black 10% opacity, Dark: white 10% opacity
    static let adaptiveButtonDisabledBackground = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.1)
            : UIColor.black.withAlphaComponent(0.1)
    })
    
    /// Disabled button text - Text on disabled buttons
    /// Light: black 30% opacity, Dark: white 30% opacity
    static let adaptiveButtonDisabledText = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.3)
            : UIColor.black.withAlphaComponent(0.3)
    })
    
    /// Icon button background - Small icon-only buttons
    /// Light: black 5% opacity, Dark: white 8% opacity
    static let adaptiveIconButtonBackground = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor.black.withAlphaComponent(0.05)
    })
    
    /// Icon button foreground - Icon color in icon buttons
    /// Light: black 70%, Dark: white 70%
    static let adaptiveIconButtonForeground = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.7)
            : UIColor.black.withAlphaComponent(0.7)
    })
    
    // MARK: - Accent Colors (Remain Constant Across Modes)
    
    /// Gold accent - Premium, elegant (stays the same in both modes)
    static let amenGold = Color(red: 0.83, green: 0.69, blue: 0.22)
    
    /// Bronze accent - Warm, sophisticated (stays the same)
    static let amenBronze = Color(red: 0.80, green: 0.50, blue: 0.20)
    
    /// Silver accent - Cool, modern (stays the same)
    static let amenSilver = Color(red: 0.75, green: 0.75, blue: 0.75)
    
    // MARK: - Status Colors (Adaptive for Better Contrast)
    
    /// Success state - Green
    /// Light: standard green, Dark: lighter green for contrast
    static let amenSuccess = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.4, green: 0.8, blue: 0.5, alpha: 1.0)  // Lighter in dark
            : UIColor(red: 0.3, green: 0.8, blue: 0.5, alpha: 1.0)
    })
    
    /// Warning state - Orange
    /// Light: standard orange, Dark: lighter orange for contrast
    static let amenWarning = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.7, blue: 0.3, alpha: 1.0)  // Lighter in dark
            : UIColor(red: 0.95, green: 0.65, blue: 0.2, alpha: 1.0)
    })
    
    /// Error state - Red
    /// Light: standard red, Dark: lighter red for contrast
    static let amenError = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.4, blue: 0.4, alpha: 1.0)  // Lighter in dark
            : UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1.0)
    })
    
    /// Info state - Blue
    /// Light: standard blue, Dark: lighter blue for contrast
    static let amenInfo = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.5, green: 0.75, blue: 0.95, alpha: 1.0)  // Lighter in dark
            : UIColor(red: 0.4, green: 0.7, blue: 0.95, alpha: 1.0)
    })
    
    // MARK: - Category Colors (Adaptive)
    
    /// Prayer category - Purple
    static let amenPrayer = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.7, green: 0.6, blue: 0.95, alpha: 1.0)  // Lighter in dark
            : UIColor(red: 0.6, green: 0.5, blue: 0.9, alpha: 1.0)
    })
    
    /// Testimony category - Yellow
    static let amenTestimony = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.85, blue: 0.4, alpha: 1.0)  // Lighter in dark
            : UIColor(red: 0.95, green: 0.8, blue: 0.3, alpha: 1.0)
    })
    
    /// OpenTable category - Teal
    static let amenOpenTable = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.5, green: 0.85, blue: 0.85, alpha: 1.0)  // Lighter in dark
            : UIColor(red: 0.4, green: 0.8, blue: 0.8, alpha: 1.0)
    })
    
    /// Scripture category - Indigo
    static let amenScripture = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.6, green: 0.7, blue: 0.95, alpha: 1.0)  // Lighter in dark
            : UIColor(red: 0.5, green: 0.6, blue: 0.9, alpha: 1.0)
    })
}

// MARK: - Adaptive Gradient Extensions

extension LinearGradient {
    /// Main app gradient - Adapts to dark mode
    /// Light: subtle gray gradient, Dark: deep charcoal to black
    static func adaptiveMainGradient(colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.15, blue: 0.15),
                    Color(red: 0.08, green: 0.08, blue: 0.08),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.98, blue: 0.98),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    /// Glass gradient - For glassmorphic overlays
    static func adaptiveGlassGradient(colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.1),
                    Color.white.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.3),
                    Color.white.opacity(0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Helper Extensions for Shadows

extension View {
    /// Adaptive shadow that adjusts opacity based on color scheme
    func adaptiveShadow(radius: CGFloat = 8, x: CGFloat = 0, y: CGFloat = 2) -> some View {
        self.modifier(AdaptiveShadowModifier(radius: radius, x: x, y: y))
    }
}

private struct AdaptiveShadowModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
    
    func body(content: Content) -> some View {
        content
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.08),
                radius: radius,
                x: x,
                y: y
            )
    }
}

// MARK: - Usage Examples

/*
 
 // BEFORE (Hardcoded):
 .background(Color.white)
 .foregroundColor(.black)
 .shadow(color: .black.opacity(0.1), radius: 8)
 
 // AFTER (Adaptive):
 .background(Color.adaptiveBackground)
 .foregroundColor(Color.adaptiveTextPrimary)
 .adaptiveShadow(radius: 8)
 
 // Glassmorphic effects:
 .background(.ultraThinMaterial)  // Auto-adapts
 .overlay(Color.adaptiveGlassOverlay)
 
 // Gradients:
 @Environment(\.colorScheme) var colorScheme
 .background(LinearGradient.adaptiveMainGradient(colorScheme: colorScheme))
 
 */

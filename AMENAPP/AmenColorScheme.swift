//
//  AmenColorScheme.swift
//  AMENAPP
//
//  Created by Steph on 1/15/26.
//

import SwiftUI

// MARK: - AMEN App Color Scheme
/// Consistent color palette inspired by the welcome screen's elegant dark aesthetic

// PURGED: cosmic-dark gradients replaced with systemGroupedBackground per C3 design contract
// amenDarkPrimary (#1A1A1A) → Color(uiColor: .systemGroupedBackground)
// amenDarkSecondary (#262626) → Color(uiColor: .systemGroupedBackground)
// amenDarkTertiary (#2E2E2E) → Color(uiColor: .systemGroupedBackground)
// amenBlack → Color(uiColor: .systemBackground) or Color.black only when semantically correct (e.g. true-black overlays)
// amenMainGradient (dark charcoal gradient) → Color(uiColor: .systemGroupedBackground)
// UIColor.amenDarkPrimary, UIColor.amenDarkSecondary → UIColor.systemGroupedBackground
// UIColor.amenGold → UIColor.systemBlue (system accent)
extension Color {
    // MARK: - Background Colors

    /// Primary background — migrated to systemGroupedBackground per C3 design contract.
    // PURGED: was Color(red: 0.1, green: 0.1, blue: 0.1) dark charcoal brand surface
    static let amenDarkPrimary = Color(uiColor: .systemGroupedBackground)

    /// Secondary background — migrated to systemGroupedBackground per C3 design contract.
    // PURGED: was Color(red: 0.15, green: 0.15, blue: 0.15) dark charcoal
    static let amenDarkSecondary = Color(uiColor: .systemGroupedBackground)

    /// Tertiary background — migrated to systemGroupedBackground per C3 design contract.
    // PURGED: was Color(red: 0.18, green: 0.18, blue: 0.18) dark subtle gray
    static let amenDarkTertiary = Color(uiColor: .systemGroupedBackground)

    /// Black — retained as-is; use only for true-black semantic contexts.
    static let amenBlack = Color.black

    /// Elevated surface color — adaptive
    static var amenSurface: Color { AmenTheme.Colors.surfaceElevated }
    
    // MARK: - Accent Colors
    // NOTE: These are now defined in AmenAdaptiveColors.swift with dark/light mode support
    // Keeping here for reference only (commented out to avoid conflicts)

    // amenGold, amenBronze, amenSilver defined in AmenAdaptiveColors.swift
    
    // MARK: - Text Colors
    // Redirected to AmenTheme adaptive tokens — auto-adapt for light/dark mode.

    /// Primary text — adaptive (was .white, broke light mode)
    static var amenTextPrimary: Color    { AmenTheme.Colors.textPrimary }

    /// Secondary text — adaptive
    static var amenTextSecondary: Color  { AmenTheme.Colors.textSecondary }

    /// Tertiary text — adaptive
    static var amenTextTertiary: Color   { AmenTheme.Colors.textTertiary }

    /// Quaternary text — adaptive
    static var amenTextQuaternary: Color { AmenTheme.Colors.textQuaternary }
    
    // MARK: - Semantic Colors
    // NOTE: These are now defined in AmenAdaptiveColors.swift with dark/light mode support
    // Keeping here for reference only (commented out to avoid conflicts)

    /// Success state - Soft green
    // static let amenSuccess = Color(red: 0.3, green: 0.8, blue: 0.5)

    /// Warning state - Soft orange
    // static let amenWarning = Color(red: 0.95, green: 0.65, blue: 0.2)

    /// Error state - Soft red
    // static let amenError = Color(red: 0.9, green: 0.3, blue: 0.3)

    /// Info state - Soft blue
    // static let amenInfo = Color(red: 0.4, green: 0.7, blue: 0.95)

    // MARK: - Category Colors (for tags/pills)
    // NOTE: These are now defined in AmenAdaptiveColors.swift with dark/light mode support
    // Keeping here for reference only (commented out to avoid conflicts)

    /// Prayer category - Soft purple
    // static let amenPrayer = Color(red: 0.6, green: 0.5, blue: 0.9)

    /// Testimony category - Soft yellow
    // static let amenTestimony = Color(red: 0.95, green: 0.8, blue: 0.3)

    /// OpenTable category - Soft teal
    // static let amenOpenTable = Color(red: 0.4, green: 0.8, blue: 0.8)

    /// Scripture category - Soft indigo
    // static let amenScripture = Color(red: 0.5, green: 0.6, blue: 0.9)
    
    // MARK: - Gradient Presets

    /// Main background — migrated to systemGroupedBackground per C3 design contract.
    // PURGED: was dark charcoal LinearGradient brand surface; replaced with plain system background
    static var amenMainGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(uiColor: .systemGroupedBackground),
                Color(uiColor: .systemGroupedBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Gold gradient — purged per C3 design contract; replaced with system accent.
    // PURGED: was gold/bronze LinearGradient; interactive contexts use Color.accentColor
    static var amenGoldGradient: LinearGradient {
        LinearGradient(
            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// Profile avatar gradient
    static var amenAvatarGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.8),
                Color.purple.opacity(0.8)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// Glass morphism gradient
    static var amenGlassGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.1),
                Color.white.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - UIColor Extensions (for UIKit integration)

extension UIColor {
    /// Primary background — migrated per C3 design contract.
    // PURGED: was UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0) dark charcoal brand surface
    static let amenDarkPrimary = UIColor.systemGroupedBackground

    /// Secondary background — migrated per C3 design contract.
    // PURGED: was UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0) dark charcoal
    static let amenDarkSecondary = UIColor.systemGroupedBackground

    /// Interactive accent — migrated per C3 design contract.
    // PURGED: was UIColor(red: 0.83, green: 0.69, blue: 0.22, alpha: 1.0) gold #C9A84C
    static let amenGold = UIColor.systemBlue   // system accent (tintColor)

    /// Bronze accent — retained as warm secondary for non-interactive use only.
    static let amenBronze = UIColor(red: 0.80, green: 0.50, blue: 0.20, alpha: 1.0)
}

// MARK: - Usage Examples

/*
 
 // BACKGROUND USAGE:
 .background(.amenDarkPrimary)
 .background(.amenSurface)
 .background(Color.amenMainGradient)
 
 // TEXT USAGE:
 .foregroundColor(.amenTextPrimary)
 .foregroundColor(.amenTextSecondary)
 .foregroundColor(.amenGold)
 
 // COMPLETE EXAMPLE:
 struct MyView: View {
     var body: some View {
         VStack {
             Text("AMEN")
                 .font(.largeTitle)
                 .foregroundColor(.amenTextPrimary)
             
             Text("Welcome back")
                 .foregroundColor(.amenTextSecondary)
         }
         .frame(maxWidth: .infinity, maxHeight: .infinity)
         .background(.amenDarkPrimary)
     }
 }
 
 // ACCENT USAGE:
 Button("Create Post") {
     // Action
 }
 .foregroundColor(.amenBlack)
 .background(.amenGold)
 .cornerRadius(12)
 
 // CATEGORY TAG:
 Text("#OPENTABLE")
     .foregroundColor(.amenOpenTable)
     .padding(.horizontal, 12)
     .padding(.vertical, 6)
     .background(
         Capsule()
             .fill(Color.amenOpenTable.opacity(0.15))
     )
 
 // SEMANTIC USAGE:
 Text("Success!")
     .foregroundColor(.amenSuccess)
 
 Text("Warning!")
     .foregroundColor(.amenWarning)
 
 Text("Error occurred")
     .foregroundColor(.amenError)
 
 */

// MARK: - Color Scheme Helper

struct AmenColorScheme {
    /// Returns appropriate text color for given background
    static func textColor(for background: Color) -> Color {
        // This is a simple implementation
        // For production, consider using contrast ratio calculations
        return .amenTextPrimary
    }
    
    /// Returns category color for category name
    static func categoryColor(for category: String) -> Color {
        switch category.lowercased() {
        case let c where c.contains("prayer"):
            return .amenPrayer
        case let c where c.contains("testimony"), let c where c.contains("testimonies"):
            return .amenTestimony
        case let c where c.contains("opentable"):
            return .amenOpenTable
        case let c where c.contains("scripture"), let c where c.contains("bible"):
            return .amenScripture
        default:
            return .amenGold
        }
    }
}

// MARK: - Preview

#Preview("Color Palette") {
    ScrollView(.vertical) {
        VStack(spacing: 24) {
            // Backgrounds
            VStack(alignment: .leading, spacing: 8) {
                Text("BACKGROUNDS")
                    .font(.caption)
                    .tracking(2)
                    .foregroundColor(.amenTextSecondary)
                
                HStack(spacing: 12) {
                    ColorSwatch(color: .amenBlack, name: "Black")
                    ColorSwatch(color: .amenDarkPrimary, name: "Primary")
                    ColorSwatch(color: .amenDarkSecondary, name: "Secondary")
                    ColorSwatch(color: .amenDarkTertiary, name: "Tertiary")
                }
            }
            
            // Accents
            VStack(alignment: .leading, spacing: 8) {
                Text("ACCENTS")
                    .font(.caption)
                    .tracking(2)
                    .foregroundColor(.amenTextSecondary)
                
                HStack(spacing: 12) {
                    ColorSwatch(color: Color(red: 0.83, green: 0.69, blue: 0.22), name: "Gold")
                    ColorSwatch(color: Color(red: 0.80, green: 0.50, blue: 0.20), name: "Bronze")
                    ColorSwatch(color: Color(red: 0.75, green: 0.75, blue: 0.75), name: "Silver")
                }
            }
            
            // Text
            VStack(alignment: .leading, spacing: 8) {
                Text("TEXT COLORS")
                    .font(.caption)
                    .tracking(2)
                    .foregroundColor(.amenTextSecondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Primary Text").foregroundColor(.amenTextPrimary)
                    Text("Secondary Text").foregroundColor(.amenTextSecondary)
                    Text("Tertiary Text").foregroundColor(.amenTextTertiary)
                    Text("Quaternary Text").foregroundColor(.amenTextQuaternary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.amenDarkSecondary)
                .cornerRadius(12)
            }
            
            // Semantic
            VStack(alignment: .leading, spacing: 8) {
                Text("SEMANTIC COLORS")
                    .font(.caption)
                    .tracking(2)
                    .foregroundColor(.amenTextSecondary)
                
                HStack(spacing: 12) {
                    ColorSwatch(color: .green, name: "Success")
                    ColorSwatch(color: .orange, name: "Warning")
                    ColorSwatch(color: .red, name: "Error")
                    ColorSwatch(color: .blue, name: "Info")
                }
            }
            
            // Categories
            VStack(alignment: .leading, spacing: 8) {
                Text("CATEGORY COLORS")
                    .font(.caption)
                    .tracking(2)
                    .foregroundColor(.amenTextSecondary)
                
                HStack(spacing: 12) {
                    ColorSwatch(color: .purple, name: "Prayer")
                    ColorSwatch(color: .orange, name: "Testimony")
                    ColorSwatch(color: .blue, name: "OpenTable")
                    ColorSwatch(color: .teal, name: "Scripture")
                }
            }
            
            // Gradients
            VStack(alignment: .leading, spacing: 8) {
                Text("GRADIENTS")
                    .font(.caption)
                    .tracking(2)
                    .foregroundColor(.amenTextSecondary)
                
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.amenMainGradient)
                        .frame(height: 80)
                        .overlay(
                            Text("Main Gradient")
                                .foregroundColor(.white)
                        )
                    
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.amenGoldGradient)
                        .frame(height: 80)
                        .overlay(
                            Text("Gold Gradient")
                                .foregroundColor(.white)
                        )
                    
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.amenAvatarGradient)
                        .frame(height: 80)
                        .overlay(
                            Text("Avatar Gradient")
                                .foregroundColor(.white)
                        )
                }
            }
        }
        .padding()
    }
    .background(Color.amenBlack)
}

// Helper view for color swatches
private struct ColorSwatch: View {
    let color: Color
    let name: String
    
    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 60, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
            
            Text(name)
                .font(.caption2)
                .foregroundColor(.amenTextSecondary)
        }
    }
}

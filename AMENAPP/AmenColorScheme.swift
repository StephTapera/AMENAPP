//
//  AmenColorScheme.swift
//  AMENAPP
//
//  Created by Steph on 1/15/26.
//

import SwiftUI

// MARK: - AMEN App Color Scheme
/// Consistent color palette inspired by the welcome screen's elegant dark aesthetic

extension Color {
    // MARK: - Background Colors
    
    /// Primary dark background - Deep charcoal
    static let amenDarkPrimary = Color(red: 0.1, green: 0.1, blue: 0.1)
    
    /// Secondary dark background - Slightly lighter charcoal
    static let amenDarkSecondary = Color(red: 0.15, green: 0.15, blue: 0.15)
    
    /// Tertiary dark background - Subtle gray
    static let amenDarkTertiary = Color(red: 0.18, green: 0.18, blue: 0.18)
    
    /// Pure black for maximum contrast
    static let amenBlack = Color.black
    
    /// Elevated surface color
    static let amenSurface = Color.white.opacity(0.05)
    
    // MARK: - Accent Colors
    
    /// Gold accent - Premium, elegant
    static let amenGold = Color(red: 0.83, green: 0.69, blue: 0.22)
    
    /// Bronze accent - Warm, sophisticated
    static let amenBronze = Color(red: 0.80, green: 0.50, blue: 0.20)
    
    /// Silver accent - Cool, modern
    static let amenSilver = Color(red: 0.75, green: 0.75, blue: 0.75)
    
    // MARK: - Text Colors
    
    /// Primary text - Pure white
    static let amenTextPrimary = Color.white
    
    /// Secondary text - 70% white
    static let amenTextSecondary = Color.white.opacity(0.7)
    
    /// Tertiary text - 50% white
    static let amenTextTertiary = Color.white.opacity(0.5)
    
    /// Quaternary text - 30% white (subtle)
    static let amenTextQuaternary = Color.white.opacity(0.3)
    
    // MARK: - Semantic Colors
    
    /// Success state - Soft green
    static let amenSuccess = Color(red: 0.3, green: 0.8, blue: 0.5)
    
    /// Warning state - Soft orange
    static let amenWarning = Color(red: 0.95, green: 0.65, blue: 0.2)
    
    /// Error state - Soft red
    static let amenError = Color(red: 0.9, green: 0.3, blue: 0.3)
    
    /// Info state - Soft blue
    static let amenInfo = Color(red: 0.4, green: 0.7, blue: 0.95)
    
    // MARK: - Category Colors (for tags/pills)
    
    /// Prayer category - Soft purple
    static let amenPrayer = Color(red: 0.6, green: 0.5, blue: 0.9)
    
    /// Testimony category - Soft yellow
    static let amenTestimony = Color(red: 0.95, green: 0.8, blue: 0.3)
    
    /// OpenTable category - Soft teal
    static let amenOpenTable = Color(red: 0.4, green: 0.8, blue: 0.8)
    
    /// Scripture category - Soft indigo
    static let amenScripture = Color(red: 0.5, green: 0.6, blue: 0.9)
    
    // MARK: - Gradient Presets
    
    /// Main gradient (top to bottom) - Used in welcome screen
    static var amenMainGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.15, green: 0.15, blue: 0.15),
                Color(red: 0.08, green: 0.08, blue: 0.08),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// Gold gradient - Premium accent
    static var amenGoldGradient: LinearGradient {
        LinearGradient(
            colors: [amenGold, amenBronze],
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
    /// Primary dark background
    static let amenDarkPrimary = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
    
    /// Secondary dark background
    static let amenDarkSecondary = UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0)
    
    /// Gold accent
    static let amenGold = UIColor(red: 0.83, green: 0.69, blue: 0.22, alpha: 1.0)
    
    /// Bronze accent
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
    ScrollView {
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
                    ColorSwatch(color: .amenGold, name: "Gold")
                    ColorSwatch(color: .amenBronze, name: "Bronze")
                    ColorSwatch(color: .amenSilver, name: "Silver")
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
                    ColorSwatch(color: .amenSuccess, name: "Success")
                    ColorSwatch(color: .amenWarning, name: "Warning")
                    ColorSwatch(color: .amenError, name: "Error")
                    ColorSwatch(color: .amenInfo, name: "Info")
                }
            }
            
            // Categories
            VStack(alignment: .leading, spacing: 8) {
                Text("CATEGORY COLORS")
                    .font(.caption)
                    .tracking(2)
                    .foregroundColor(.amenTextSecondary)
                
                HStack(spacing: 12) {
                    ColorSwatch(color: .amenPrayer, name: "Prayer")
                    ColorSwatch(color: .amenTestimony, name: "Testimony")
                    ColorSwatch(color: .amenOpenTable, name: "OpenTable")
                    ColorSwatch(color: .amenScripture, name: "Scripture")
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

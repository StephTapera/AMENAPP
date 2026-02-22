//
//  AnimationSystem.swift
//  AMENAPP
//
//  Premium iOS Motion System
//  Standard animation timings for consistent, polished feel
//

import SwiftUI

/// Standard animation system for app-wide consistency
/// All animations follow iOS guidelines for premium feel
enum AppAnimation {
    
    // MARK: - Fast Interactions (Buttons, Toggles)
    
    /// Ultra-fast tap feedback (80-100ms feel)
    /// Use for: Button press, toggle switches, checkbox
    static let tap = Animation.spring(response: 0.18, dampingFraction: 0.8)
    
    /// Quick press feedback with slight bounce
    /// Use for: Icon buttons, action buttons
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.75)
    
    // MARK: - UI State Changes (Pills, Segmented Controls)
    
    /// Standard state transition
    /// Use for: Segmented controls, filter pills, tab selection
    static let stateChange = Animation.spring(response: 0.25, dampingFraction: 0.75)
    
    /// Smooth state transition with minimal bounce
    /// Use for: Badge updates, count changes
    static let smoothState = Animation.spring(response: 0.25, dampingFraction: 0.8)
    
    // MARK: - Panels & Navigation
    
    /// Panel/sheet presentation
    /// Use for: Sheet open/close, modal presentation
    static let panel = Animation.spring(response: 0.28, dampingFraction: 0.78)
    
    /// Navigation transitions
    /// Use for: Push/pop, tab switching
    static let navigation = Animation.spring(response: 0.3, dampingFraction: 0.75)
    
    // MARK: - Smooth Fades
    
    /// Standard fade in/out
    /// Use for: Opacity changes, element appearance
    static let fade = Animation.easeInOut(duration: 0.2)
    
    /// Quick fade for fast transitions
    /// Use for: Tooltip dismiss, error message fade
    static let quickFade = Animation.easeOut(duration: 0.15)
    
    /// Slow elegant fade
    /// Use for: Success states, confirmation messages
    static let slowFade = Animation.easeInOut(duration: 0.3)
    
    // MARK: - Special Cases
    
    /// Elastic bounce for success states
    /// Use for: Success animations, celebration moments
    static let successBounce = Animation.spring(response: 0.35, dampingFraction: 0.6)
    
    /// Gentle slide for scroll-driven UI
    /// Use for: Header collapse, toolbar hide/show
    static let slide = Animation.easeInOut(duration: 0.25)
    
    /// No animation (instant)
    /// Use for: Initial state setup, immediate updates
    static var none: Animation? { nil }
}

// MARK: - Animation Modifiers

extension View {
    /// Apply tap feedback animation to any view
    func tapAnimation() -> some View {
        animation(AppAnimation.tap, value: UUID())
    }
    
    /// Apply state change animation
    func stateAnimation<V: Equatable>(value: V) -> some View {
        animation(AppAnimation.stateChange, value: value)
    }
}

// MARK: - Timing Constants for Manual Use

enum AnimationTiming {
    /// Debounce thresholds
    static let quickDebounce: UInt64 = 50_000_000    // 50ms
    static let standardDebounce: UInt64 = 150_000_000 // 150ms
    static let longDebounce: UInt64 = 300_000_000     // 300ms
    
    /// Delay timings
    static let shortDelay: UInt64 = 100_000_000      // 100ms
    static let standardDelay: UInt64 = 200_000_000   // 200ms
    static let longDelay: UInt64 = 400_000_000       // 400ms
}

// MARK: - Performance Guidelines

/*
 PERFORMANCE RULES:
 
 1. Use AppAnimation.tap for all button feedback
 2. Use AppAnimation.stateChange for toggles/pills
 3. Use AppAnimation.navigation for tab switching
 4. Avoid stacking multiple .animation() modifiers
 5. Always debounce rapid state changes
 6. Never animate during scroll unless necessary
 7. Use .transaction(animation: nil) to suppress unwanted animations
 
 TIMING GUIDELINES:
 - Tap feedback: 80-100ms (AppAnimation.tap)
 - State changes: 200-250ms (AppAnimation.stateChange)
 - Navigation: 250-300ms (AppAnimation.navigation)
 - Panels: 280-320ms (AppAnimation.panel)
 
 WHEN TO AVOID ANIMATION:
 - Initial view setup
 - Scrolling list items
 - Real-time data updates
 - Background state changes
 */

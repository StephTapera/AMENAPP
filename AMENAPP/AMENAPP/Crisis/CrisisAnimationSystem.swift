// CrisisAnimationSystem.swift
// AMENAPP
//
// Centralized animation tokens and haptic feedback for the Crisis Support system.
// All motion is highly damped, emotionally safe, and Apple-native.
// No bouncy, playful, or flashy animations. Motion reduces stress, not increases it.
//

import SwiftUI

// MARK: - Animation Tokens

enum CrisisAnimationTokens {
    /// Sheet settle — premium, stable, barely perceptible spring.
    static let sheetSettle     = Animation.spring(response: 0.55, dampingFraction: 0.88)
    /// Triage pill morph — smooth fill change on selection.
    static let triagePill      = Animation.spring(response: 0.32, dampingFraction: 0.82)
    /// Emergency reprioritization — card expand/compress when danger mode activates.
    static let emergencyReorder = Animation.spring(response: 0.44, dampingFraction: 0.84)
    /// Section collapse/expand — clean height reveal + chevron rotation.
    static let sectionExpand   = Animation.spring(response: 0.36, dampingFraction: 0.86)
    /// Grounding tool content swap — one prompt at a time, soft.
    static let groundingSwap   = Animation.easeInOut(duration: 0.26)
    /// Berean response gentle reveal — no hard pop-in.
    static let bereanReveal    = Animation.easeOut(duration: 0.32)
    /// Card reordering when crisis state changes.
    static let cardReorder     = Animation.spring(response: 0.50, dampingFraction: 0.86)
    /// Privacy card settle — subtle, not attention-seeking.
    static let privacySettle   = Animation.easeOut(duration: 0.40).delay(0.14)
    /// Hero text transition — cross-fade on state change.
    static let heroTransition  = Animation.easeInOut(duration: 0.38)
}

// MARK: - Haptics Manager

struct CrisisHapticsManager {

    /// Soft haptic on triage pill selection.
    static func triageSelected() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        g.impactOccurred()
    }

    /// Subtle haptic on section expand/collapse.
    static func sectionToggled() {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare()
        g.impactOccurred(intensity: 0.55)
    }

    /// Stronger but still tasteful haptic on emergency action (911, 988 call).
    static func emergencyAction() {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.warning)
    }

    /// Soft haptic on grounding step advance.
    static func groundingStep() {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare()
        g.impactOccurred(intensity: 0.40)
    }

    /// Success haptic on safety plan save / follow-up opt-in / contact sent.
    static func confirmation() {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.success)
    }

    /// Gentle haptic for Berean quick action tap.
    static func bereanTap() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        g.impactOccurred(intensity: 0.45)
    }
}

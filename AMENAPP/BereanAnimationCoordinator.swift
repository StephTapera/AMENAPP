//
//  BereanAnimationCoordinator.swift
//  AMENAPP
//
//  Centralized animation tuning for Berean chat surfaces.
//  All animations respect the user's Reduce Motion preference
//  by substituting cross-fades for spring/positional motion.
//

import SwiftUI

enum BereanAnimationCoordinator {

    // MARK: - Spring Animations

    /// Standard soft spring — used for most transitions.
    static var softSpring: Animation {
        .spring(response: 0.34, dampingFraction: 0.86)
    }

    /// More compact spring for small UI changes (chips, pills, icons).
    static var compactSpring: Animation {
        .spring(response: 0.28, dampingFraction: 0.82)
    }

    /// Snappy spring for toolbar/input-bar compress/expand.
    static var inputBarSpring: Animation {
        .spring(response: 0.32, dampingFraction: 0.90)
    }

    /// Gentle spring for study surface expand/collapse.
    static var studySurfaceSpring: Animation {
        .spring(response: 0.42, dampingFraction: 0.84)
    }

    // MARK: - Fade Animations

    static var fade: Animation {
        .easeOut(duration: 0.18)
    }

    static var slowFade: Animation {
        .easeOut(duration: 0.30)
    }

    static var microFade: Animation {
        .easeOut(duration: 0.12)
    }

    // MARK: - Reduce Motion Adaptive

    /// Returns a motion-reduced alternative when the user prefers reduced motion.
    /// Substitutes cross-fade for springs and positional animations.
    static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.18) : animation
    }

    /// Soft spring that automatically degrades to a fade when reduce motion is on.
    static func adaptiveSoftSpring(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.22) : softSpring
    }

    /// Study surface spring that degrades to a fade when reduce motion is on.
    static func adaptiveStudySpring(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.25) : studySurfaceSpring
    }

    // MARK: - Pulse

    /// Repeating pulse used for reasoning node activity indicators.
    /// Returns nil when reduce motion is enabled so the caller can skip it.
    static func pulseAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
    }
}

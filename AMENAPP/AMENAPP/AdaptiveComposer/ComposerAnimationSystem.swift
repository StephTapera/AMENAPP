import SwiftUI
import UIKit

// MARK: - ComposerMotion (animation namespace)

enum ComposerMotion {
    /// Returns the animation if not in reduce-motion mode, else instant.
    static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0) : animation
    }

    static func railMorph(reduceMotion: Bool) -> Animation {
        adaptive(.spring(response: 0.35, dampingFraction: 0.8), reduceMotion: reduceMotion)
    }

    static func cardInsert(reduceMotion: Bool) -> Animation {
        adaptive(.spring(response: 0.28, dampingFraction: 0.86), reduceMotion: reduceMotion)
    }

    static func orbBloom(index: Int, reduceMotion: Bool) -> Animation {
        let base = Animation.spring(response: 0.35, dampingFraction: 0.82)
        if reduceMotion { return .linear(duration: 0) }
        return base.delay(Double(index) * 0.03)
    }

    static func pillExpand(reduceMotion: Bool) -> Animation {
        adaptive(.spring(response: 0.3, dampingFraction: 0.82), reduceMotion: reduceMotion)
    }

    static func predictiveSlide(reduceMotion: Bool) -> Animation {
        adaptive(.easeOut(duration: 0.18), reduceMotion: reduceMotion)
    }

    static func iconSwap(reduceMotion: Bool) -> Animation {
        adaptive(.easeInOut(duration: 0.15), reduceMotion: reduceMotion)
    }
}

// MARK: - ComposerHaptics

struct ComposerHaptics {
    static func railSnap() {
        // Haptics are appropriate even with Reduce Motion enabled (vestibular preference, not haptic preference)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func cardInsert() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func postSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Glass Card Transition

extension AnyTransition {
    static var glassCardInsert: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.92).combined(with: .opacity),
            removal: .scale(scale: 0.96).combined(with: .opacity)
        )
    }

    static var glassCardInsertFast: AnyTransition {
        .asymmetric(
            insertion: .opacity,
            removal: .opacity
        )
    }
}

// MARK: - Rail Namespace Key

private struct RailNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var composerRailNamespace: Namespace.ID? {
        get { self[RailNamespaceKey.self] }
        set { self[RailNamespaceKey.self] = newValue }
    }
}

// MARK: - Composer Animation View Modifier

extension View {
    /// Applies animation gated by reduce-motion preference.
    func composerAnimation<V: Equatable>(_ animation: Animation, value: V, reduceMotion: Bool) -> some View {
        self.animation(reduceMotion ? .linear(duration: 0) : animation, value: value)
    }
}

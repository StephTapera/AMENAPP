import SwiftUI
import UIKit

// MARK: - Breath

enum Breath {
    static let enter: Double = 0.45
    static let settle: Double = 0.70
    static let ambient: Double = 4.0

    // Inhale approximates ease-in, exhale approximates ease-out;
    // UnitCurve gives us a Bezier without requiring a spring which avoids
    // oscillation artifacts in ambient looping contexts.
    static let inhale: Animation = .timingCurve(0.4, 0.0, 1.0, 1.0, duration: enter)
    static let exhale: Animation = .timingCurve(0.0, 0.0, 0.6, 1.0, duration: settle)
}

// MARK: - SelahMomentConfig

struct SelahMomentConfig {
    static let duration: Double = 1.2
    static let dimOpacity: Double = 0.85
    static let haptic: UIImpactFeedbackGenerator.FeedbackStyle = .soft
}

// MARK: - Motion

enum Motion {
    /// Returns the full animation in normal mode; collapses to near-instant for reduce-motion.
    /// Pass ambient=true only for looping/ambient animations — those collapse to zero duration
    /// so they simply do not animate for reduce-motion users.
    static func adaptive(animation: Animation, reduceMotion: Bool, isAmbient: Bool = false) -> Animation {
        guard reduceMotion else { return animation }
        return isAmbient ? .linear(duration: 0) : .linear(duration: 0.15)
    }
}

// MARK: - SelahMoment ViewModifier

private struct SelahMomentModifier: ViewModifier {
    let trigger: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Single-fire haptic dispatch; avoids repeated triggers on re-render.
    @State private var lastTrigger: Bool = false
    @State private var dimmed: Bool = false
    @State private var scaled: Bool = false

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? SelahMomentConfig.dimOpacity : 1.0)
            .scaleEffect(scaled ? 0.98 : 1.0)
            .animation(
                Motion.adaptive(
                    animation: .easeIn(duration: 0.15),
                    reduceMotion: reduceMotion
                ),
                value: dimmed
            )
            .animation(
                Motion.adaptive(
                    animation: .easeOut(duration: SelahMomentConfig.duration - 0.15),
                    reduceMotion: reduceMotion
                ),
                value: scaled
            )
            .onChange(of: trigger) { _, newValue in
                guard newValue != lastTrigger else { return }
                lastTrigger = newValue

                // Haptic fires once per trigger regardless of motion preference —
                // haptics are a separate accessibility axis from visual motion.
                let generator = UIImpactFeedbackGenerator(style: SelahMomentConfig.haptic)
                generator.impactOccurred()

                guard !reduceMotion else { return }

                dimmed = true
                scaled = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    dimmed = false
                    scaled = false
                }
            }
    }
}

// MARK: - View extension

extension View {
    func selahMoment(trigger: Bool) -> some View {
        modifier(SelahMomentModifier(trigger: trigger))
    }
}

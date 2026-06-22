import SwiftUI

struct AdaptiveGlassMaterial {
    var opacity: Double
    var blurRadius: Double
    var highlightOpacity: Double
}

struct ContextAwareGlass {
    var quietMode: Bool
    var prayerMode: Bool
    var timeOfDayProgress: Double
}

struct MotionResponsiveGlass {
    var motionIntensity: Double
    var reduceMotion: Bool
}

struct WorshipReactiveGlass {
    var worshipState: ChurchLiveStateKind
    var emotionalTone: Double
}

enum AtmosphericBlurEngine {
    static func resolveState(
        context: ContextAwareGlass,
        motion: MotionResponsiveGlass,
        worship: WorshipReactiveGlass
    ) -> AmbientGlassState {
        let quietMultiplier = context.quietMode ? 0.72 : 1.0
        let prayerMultiplier = context.prayerMode ? 0.8 : 1.0
        let motionFactor = motion.reduceMotion ? 0.25 : max(0.35, 1.0 - motion.motionIntensity)
        let worshipBoost: Double

        switch worship.worshipState {
        case .live:
            worshipBoost = 1.05
        case .upcoming:
            worshipBoost = 0.98
        case .closed, .quiet, .unknown:
            worshipBoost = 0.9
        }

        let blur = 18 * quietMultiplier * prayerMultiplier * worshipBoost
        let highlights = 0.18 * (1.0 - context.timeOfDayProgress * 0.3) * prayerMultiplier

        return AmbientGlassState(
            glassIntensity: min(1, 0.64 * quietMultiplier * worshipBoost),
            blurRadius: blur,
            highlightOpacity: min(0.22, highlights),
            calmMotionFactor: motionFactor,
            quietMode: context.quietMode,
            prayerMode: context.prayerMode
        )
    }
}

struct AmenAdaptiveGlassViewModifier: ViewModifier {
    let state: AmbientGlassState

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.white.opacity(0.72 + state.glassIntensity * 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.black.opacity(0.05 + state.highlightOpacity), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: state.blurRadius * 0.6, y: 10)
            )
    }
}

extension View {
    func amenAdaptiveGlass(state: AmbientGlassState) -> some View {
        modifier(AmenAdaptiveGlassViewModifier(state: state))
    }
}

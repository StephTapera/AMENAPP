import SwiftUI

enum SocialV2MotionBudget: Equatable {
    case rich
    case lite

    static func derived(
        reduceMotion: Bool,
        isLowPowerModeEnabled: Bool,
        scrollVelocity: CGFloat,
        fastThreshold: CGFloat = 1800
    ) -> SocialV2MotionBudget {
        if reduceMotion || isLowPowerModeEnabled || abs(scrollVelocity) > fastThreshold {
            return .lite
        }

        return .rich
    }
}

private struct SocialV2MotionBudgetKey: EnvironmentKey {
    static let defaultValue: SocialV2MotionBudget = .lite
}

extension EnvironmentValues {
    var socialV2MotionBudget: SocialV2MotionBudget {
        get { self[SocialV2MotionBudgetKey.self] }
        set { self[SocialV2MotionBudgetKey.self] = newValue }
    }
}

extension View {
    func socialV2MotionBudget(_ budget: SocialV2MotionBudget) -> some View {
        environment(\.socialV2MotionBudget, budget)
    }
}

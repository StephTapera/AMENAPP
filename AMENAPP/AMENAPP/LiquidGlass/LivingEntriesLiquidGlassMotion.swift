import SwiftUI

enum LivingLiquidGlassMotion {
    static func fast(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: LiquidGlassTokens.motionFast, dampingFraction: 0.82)
    }

    static func normal(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.84)
    }

    static func slow(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.24) : .spring(response: LiquidGlassTokens.motionSlow, dampingFraction: 0.88)
    }
}

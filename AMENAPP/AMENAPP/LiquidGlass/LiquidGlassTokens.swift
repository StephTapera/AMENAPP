import SwiftUI

enum LiquidGlassTokens {
    static let cornerRadiusSmall: CGFloat = 14
    static let cornerRadiusMedium: CGFloat = 22
    static let cornerRadiusLarge: CGFloat = 32
    static let capsuleRadius: CGFloat = 999

    static let blurThin: Material = .ultraThinMaterial
    static let blurRegular: Material = .thinMaterial
    static let blurElevated: Material = .regularMaterial

    static let shadowSoft = Shadow(color: .black.opacity(0.08), radius: 14, y: 6)
    static let shadowFloating = Shadow(color: .black.opacity(0.12), radius: 24, y: 10)

    static let motionFast: Double = 0.18
    static let motionNormal: Double = 0.32
    static let motionSlow: Double = 0.55
}

struct Shadow {
    let color: Color
    let radius: CGFloat
    let y: CGFloat
}

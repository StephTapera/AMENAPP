import SwiftUI

struct AmenReactionMorphIcon: View {
    let baseSystemImage: String
    let morphedSystemImage: String
    let isAnimating: Bool
    let baseColor: Color
    let morphedColor: Color

    var body: some View {
        ZStack {
            Image(systemName: baseSystemImage)
                .opacity(isAnimating ? 0 : 1)
                .scaleEffect(isAnimating ? 0.82 : 1)
                .foregroundStyle(baseColor)

            Image(systemName: morphedSystemImage)
                .opacity(isAnimating ? 1 : 0)
                .scaleEffect(isAnimating ? 1 : 0.7)
                .foregroundStyle(morphedColor)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isAnimating)
    }
}

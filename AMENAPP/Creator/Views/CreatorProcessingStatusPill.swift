import SwiftUI

struct CreatorProcessingStatusPill: View {
    let title: String
    let progress: Double

    var body: some View {
        HStack(spacing: 10) {
            CreatorProgressRing(progress: progress)
            Text(title)
                .font(AMENFont.medium(12))
                .foregroundStyle(Color.black)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .amenGlassSurface(shape: .capsule, background: .balanced, placement: .floating)
    }
}

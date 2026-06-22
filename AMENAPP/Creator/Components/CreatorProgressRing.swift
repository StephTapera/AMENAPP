import SwiftUI

struct CreatorProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.1), lineWidth: 4)

            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(Color.black, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 32, height: 32)
    }
}

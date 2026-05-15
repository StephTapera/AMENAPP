import SwiftUI
import FirebaseAnalytics

struct GuideMyFeedComposerChip: View {
    let detection: FeedDirectionDetectionResult
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var pulse = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
                Text("Feed Direction")
                    .font(.system(size: 13, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(reduceTransparency
                          ? AnyShapeStyle(Color(.secondarySystemBackground))
                          : AnyShapeStyle(.thinMaterial))
                    .overlay(Capsule().stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.6), Color.black.opacity(0.07)],
                            startPoint: .top, endPoint: .bottom
                        ), lineWidth: 0.8
                    ))
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            }
            .scaleEffect(pulse ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Feed Direction detected. Double tap to guide your feed.")
        .onAppear {
            FeedDirectionAnalytics.chipShown(confidence: detection.confidence)
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatCount(2, autoreverses: true)) {
                pulse = true
            }
        }
    }
}

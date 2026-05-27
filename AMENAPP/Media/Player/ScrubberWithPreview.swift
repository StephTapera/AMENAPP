import SwiftUI
import AVFoundation

struct ScrubberWithPreview: View {
    @Binding var progress: Double   // 0.0–1.0
    var duration: TimeInterval
    var assetURL: URL?

    @State private var isDragging = false
    @State private var thumbImage: UIImage?
    @State private var sliderWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            VStack(spacing: 4) {
                // Thumb bubble floats above the slider
                GlassThumbBubble(
                    xOffset: (progress - 0.5) * w,
                    image: thumbImage,
                    isVisible: isDragging
                )
                .frame(width: w)

                Slider(value: $progress, in: 0...1)
                    .onChange(of: progress) { _, newVal in
                        guard isDragging, let url = assetURL else { return }
                        loadThumbnail(url: url, at: newVal * duration)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in isDragging = true }
                            .onEnded   { _ in
                                isDragging = false
                                thumbImage = nil
                            }
                    )
                    .accessibilityValue("\(Int(progress * duration))s of \(Int(duration))s")
            }
            .onAppear { sliderWidth = w }
        }
        .frame(height: 60)
    }

    private func loadThumbnail(url: URL, at seconds: TimeInterval) {
        Task {
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 192, height: 128)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            if let cgImage = try? await generator.image(at: time).image {
                await MainActor.run { thumbImage = UIImage(cgImage: cgImage) }
            }
        }
    }
}

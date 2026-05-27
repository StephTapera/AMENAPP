import SwiftUI
import AVFoundation

// MARK: - ScrubberWithPreview
// Scrubber slider with a GlassThumbBubble that floats above the thumb showing
// a video frame thumbnail at the current scrub position.
// Thumbnail generation is async via AVAssetImageGenerator.

@MainActor
struct ScrubberWithPreview: View {
    @Binding var progress: Double        // 0.0 – 1.0
    var duration: TimeInterval
    var assetURL: URL?

    @State private var isDragging = false
    @State private var thumbImage: UIImage?
    @State private var sliderWidth: CGFloat = 0
    @State private var thumbGenTask: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .bottom) {
                // Thumb bubble sits above the slider track
                GlassThumbBubble(
                    xOffset: thumbXOffset(sliderWidth: w),
                    image: thumbImage,
                    isVisible: isDragging
                )
                .offset(y: -44)   // raise above the slider

                Slider(value: $progress, in: 0...1)
                    .accentColor(Color.amenGold)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !isDragging { isDragging = true }
                                scheduleThumbnailLoad()
                            }
                            .onEnded { _ in
                                isDragging = false
                                thumbImage = nil
                                thumbGenTask?.cancel()
                            }
                    )
                    .accessibilityValue(accessibilityTimeString)
            }
            .onAppear { sliderWidth = w }
            .onChange(of: geo.size.width) { _, newW in sliderWidth = newW }
        }
        .frame(height: 60)
    }

    // MARK: - Helpers

    private func thumbXOffset(sliderWidth: CGFloat) -> CGFloat {
        // Center of slider is 0; thumb at progress 0 → -(w/2), at 1 → +(w/2)
        (progress - 0.5) * sliderWidth
    }

    private var accessibilityTimeString: String {
        let currentSec = Int(progress * duration)
        let totalSec = Int(duration)
        return "\(currentSec)s of \(totalSec)s"
    }

    private func scheduleThumbnailLoad() {
        guard let url = assetURL else { return }
        thumbGenTask?.cancel()
        let scrubTime = progress * duration
        thumbGenTask = Task {
            guard !Task.isCancelled else { return }
            let image = await generateThumbnail(url: url, at: scrubTime)
            guard !Task.isCancelled else { return }
            thumbImage = image
        }
    }

    private func generateThumbnail(url: URL, at seconds: TimeInterval) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 192, height: 128)
        let cmTime = CMTime(seconds: seconds, preferredTimescale: 600)
        do {
            let (cgImage, _) = try await generator.image(at: cmTime)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
}

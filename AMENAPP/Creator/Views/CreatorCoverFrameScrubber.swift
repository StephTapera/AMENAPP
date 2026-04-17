import SwiftUI
import AVFoundation
import UIKit

struct CreatorCoverFrameScrubber: View {
    let videoURL: URL
    let durationMs: Int
    @Binding var frameTimeMs: Int
    let onConfirm: () -> Void

    @State private var previewImage: Image?
    @State private var isLoading: Bool = false
    @State private var updateTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cover frame")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.05))

                if let previewImage {
                    previewImage
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if isLoading {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: "film")
                        .foregroundStyle(Color.black.opacity(0.4))
                }
            }
            .frame(height: 140)

            Slider(
                value: Binding(
                    get: { Double(frameTimeMs) / Double(max(durationMs, 1)) },
                    set: { newValue in
                        frameTimeMs = Int(Double(durationMs) * newValue)
                        schedulePreviewUpdate()
                    }
                ),
                in: 0...1
            )

            Text(timeLabel)
                .font(AMENFont.medium(12))
                .foregroundStyle(Color.black.opacity(0.5))

            CreatorSecondaryCTA(title: "Set Cover Frame", action: onConfirm)
        }
        .onAppear {
            schedulePreviewUpdate()
        }
    }

    private var timeLabel: String {
        let seconds = Double(frameTimeMs) / 1000
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }

    private func schedulePreviewUpdate() {
        updateTask?.cancel()
        updateTask = Task {
            isLoading = true
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            if let image = await generatePreviewImage() {
                previewImage = image
            }
            isLoading = false
        }
    }

    private func generatePreviewImage() async -> Image? {
        await withCheckedContinuation { continuation in
            let asset = AVAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let time = CMTime(seconds: Double(frameTimeMs) / 1000, preferredTimescale: 600)
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, _ in
                if let cgImage {
                    let uiImage = UIImage(cgImage: cgImage)
                    continuation.resume(returning: Image(uiImage: uiImage))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

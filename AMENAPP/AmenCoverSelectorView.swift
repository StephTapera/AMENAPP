// AmenCoverSelectorView.swift
// AMENAPP
// Cover frame selector for videos.

import SwiftUI
import AVFoundation

struct AmenCoverSelectorView: View {
    let videoURL: URL
    let onSelect: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTime: Double = 0
    @State private var duration: Double = 1
    @State private var previewImage: UIImage? = nil

    var body: some View {
        VStack(spacing: 16) {
            Text("Select Cover")
                .font(.systemScaled(18, weight: .bold))

            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 200)
            }

            Slider(value: $selectedTime, in: 0...max(duration, 1), step: 0.5) {
                Text("Cover time")
            }
            .onChange(of: selectedTime) { _, _ in
                previewImage = AmenMediaExportService.generateThumbnail(from: videoURL, at: selectedTime)
            }

            Button("Use Cover") {
                onSelect(selectedTime)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Use selected cover")
        }
        .padding(24)
        .task {
            let asset = AVAsset(url: videoURL)
            duration = asset.duration.seconds
            previewImage = AmenMediaExportService.generateThumbnail(from: videoURL, at: 0)
        }
    }
}

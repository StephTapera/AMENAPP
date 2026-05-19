// AmenVideoEditorView.swift
// AMENAPP
// Minimal video trim editor.

import SwiftUI
import AVKit
import AVFoundation

struct AmenVideoEditorView: View {
    let videoURL: URL
    let onTrimmed: (URL?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var startTime: Double = 0
    @State private var endTime: Double = 0
    @State private var duration: Double = 0
    @State private var isExporting = false

    var body: some View {
        VStack(spacing: 16) {
            VideoPlayer(player: AVPlayer(url: videoURL))
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                Text("Trim Start")
                Slider(value: $startTime, in: 0...max(duration - 1, 1), step: 0.5)

                Text("Trim End")
                Slider(value: $endTime, in: max(startTime + 0.5, 0)...max(duration, 1), step: 0.5)
            }
            .font(.systemScaled(12, weight: .regular))

            Button(isExporting ? "Trimming..." : "Apply Trim") {
                Task { await trimVideo() }
            }
            .disabled(isExporting)
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Apply trim")
        }
        .padding(24)
        .task {
            let asset = AVAsset(url: videoURL)
            duration = asset.duration.seconds
            endTime = duration
        }
    }

    private func trimVideo() async {
        guard !isExporting else { return }
        isExporting = true
        do {
            let trimmed = try await AmenMediaExportService.trimVideo(sourceURL: videoURL, startTime: startTime, endTime: endTime)
            onTrimmed(trimmed)
            isExporting = false
            dismiss()
        } catch {
            dlog("[AmenVideoEditorView] Trim failed: \(error)")
            isExporting = false
        }
    }
}

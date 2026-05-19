// AmenMediaProcessingStatusView.swift
// AMENAPP
// UI status badge for media processing.

import SwiftUI

struct AmenMediaProcessingStatusView: View {
    let state: MediaProcessingState
    let progress: Double
    let errorMessage: String?

    var body: some View {
        HStack(spacing: 6) {
            switch state {
            case .uploading, .processing, .queued:
                ProgressView(value: max(0, min(progress, 1)))
                    .progressViewStyle(.linear)
                    .frame(width: 80)
                Text(state == .uploading ? "Uploading" : "Processing")
                    .font(.systemScaled(10, weight: .semibold))
            case .ready, .partial:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Ready")
                    .font(.systemScaled(10, weight: .semibold))
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Failed")
                    .font(.systemScaled(10, weight: .semibold))
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch state {
        case .uploading: return "Uploading media"
        case .queued, .processing: return "Processing media"
        case .ready, .partial: return "Media ready"
        case .failed: return errorMessage ?? "Media upload failed"
        }
    }
}

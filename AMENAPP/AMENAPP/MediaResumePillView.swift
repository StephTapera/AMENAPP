// MediaResumePillView.swift
// AMENAPP
//
// Liquid Glass pill overlay showing "Resume 0:43" with a progress indicator.
// Displayed on video thumbnails when a resume position is available.

import SwiftUI

struct MediaResumePillView: View {
    let state: MediaPlaybackState

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(AmenTheme.Colors.iconPrimary.opacity(0.28), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: state.progress)
                    .stroke(AmenTheme.Colors.iconPrimary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Image(systemName: "play.fill")
                    .font(.systemScaled(7, weight: .bold))
                    .foregroundColor(AmenTheme.Colors.iconPrimary)
            }
            .frame(width: 16, height: 16)

            Text("Resume \(state.formattedPosition)")
                .font(.systemScaled(11, weight: .semibold))
                .foregroundColor(AmenTheme.Colors.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(AmenTheme.Colors.surfaceGlassDark))
        )
        .overlay(
            Capsule()
                .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
        )
    }
}

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
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: state.progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Image(systemName: "play.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 16, height: 16)

            Text("Resume \(state.formattedPosition)")
                .font(AMENFont.semiBold(11))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
        )
    }
}

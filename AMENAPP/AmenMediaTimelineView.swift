// AmenMediaTimelineView.swift
// AMENAPP
// Minimal timeline scrubber for media previews.

import SwiftUI

struct AmenMediaTimelineView: View {
    let duration: Double
    @Binding var currentTime: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Slider(value: $currentTime, in: 0...max(duration, 1), step: 0.5)
            Text("\(Int(currentTime))s / \(Int(duration))s")
                .font(.systemScaled(10, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }
}

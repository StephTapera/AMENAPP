// BereanVoiceView.swift
// AMENAPP
//
// Live waveform bar that overlays the Berean input bar during voice recording.

import SwiftUI
import Combine

struct BereanWaveformBar: View {
    let isActive: Bool
    @State private var heights: [CGFloat] = Array(repeating: 4, count: 20)
    private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<20, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: "#e07050"))
                    .frame(width: 3, height: heights[i])
                    .animation(.easeInOut(duration: 0.08), value: heights[i])
            }
        }
        .frame(height: 36)
        .padding(.horizontal, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .opacity(isActive ? 1 : 0)
        .scaleEffect(isActive ? 1 : 0.92, anchor: .bottom)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isActive)
        .onReceive(timer) { _ in
            guard isActive else { return }
            heights = heights.map { _ in CGFloat.random(in: 4...26) }
        }
    }
}

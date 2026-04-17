// AudioMiniPlayerBar.swift
// AMEN App — Accessibility Intelligence Layer (Phase 3)
//
// 56pt glass bar above tab bar. Shows play/pause, title, speed, close.
// Appears when SpeechSynthesisService is playing or paused.
// Uses GlassEffectStyle.prominent, Motion.adaptive show/hide.

import SwiftUI

struct AudioMiniPlayerBar: View {

    @ObservedObject private var speechService = SpeechSynthesisService.shared
    @State private var showSpeedPicker = false

    var body: some View {
        if speechService.isPlaying || speechService.isPaused {
            HStack(spacing: 12) {
                // Play/Pause button
                Button {
                    HapticManager.impact(style: .light)
                    speechService.togglePlayPause()
                } label: {
                    Image(systemName: speechService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(.label))
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(speechService.isPlaying ? "Pause" : "Play")

                // Title + progress
                VStack(alignment: .leading, spacing: 2) {
                    Text(speechService.currentItemTitle ?? "Playing")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(Color(.label))
                        .lineLimit(1)

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.tertiarySystemFill))
                                .frame(height: 3)
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: geo.size.width * speechService.progress, height: 3)
                        }
                    }
                    .frame(height: 3)
                }

                // Speed button
                Button {
                    showSpeedPicker.toggle()
                } label: {
                    Text(speedLabel)
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(Color(.secondaryLabel))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
                .accessibilityLabel("Playback speed \(speedLabel)")

                // Close button
                Button {
                    HapticManager.impact(style: .light)
                    speechService.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .frame(width: 28, height: 28)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Stop playback")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            // HIGH FIX: minHeight so the bar grows with Dynamic Type; exact height clips title at AX5+
            .frame(minHeight: 56)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.85)), value: speechService.isPlaying)
            .sheet(isPresented: $showSpeedPicker) {
                speedPickerSheet
                    .presentationDetents([.height(200)])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Speed

    private var speedLabel: String {
        let rate = speechService.playbackRate
        if rate == 1.0 { return "1x" }
        if rate == floor(rate) { return "\(Int(rate))x" }
        return String(format: "%.1fx", rate)
    }

    private var speedPickerSheet: some View {
        VStack(spacing: 16) {
            Text("Playback Speed")
                .font(AMENFont.bold(16))
                .foregroundStyle(Color(.label))

            HStack(spacing: 12) {
                speedButton(rate: 0.5, label: "0.5x")
                speedButton(rate: 0.75, label: "0.75x")
                speedButton(rate: 1.0, label: "1x")
                speedButton(rate: 1.25, label: "1.25x")
                speedButton(rate: 1.5, label: "1.5x")
                speedButton(rate: 2.0, label: "2x")
            }
        }
        .padding(20)
    }

    private func speedButton(rate: Double, label: String) -> some View {
        let isSelected = abs(Double(speechService.playbackRate) - rate) < 0.01
        return Button {
            speechService.updateRate(Float(rate))
            showSpeedPicker = false
        } label: {
            Text(label)
                .font(AMENFont.semiBold(14))
                .foregroundStyle(isSelected ? Color.accentColor : Color(.secondaryLabel))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill))
                .clipShape(Capsule())
        }
        .accessibilityLabel("\(label) speed")
    }
}

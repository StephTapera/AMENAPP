import SwiftUI
import AVFoundation

struct VoiceNoteBubble: View {
    var audioURL: URL
    var duration: TimeInterval

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var playbackTimer: Timer?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let barCount = 20

    var body: some View {
        HStack(spacing: 10) {
            playButton
            waveform
            timeLabel
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background { bubbleBackground }
        .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous))
        .shadow(
            color: LiquidGlassTokens.shadowSoft.color,
            radius: LiquidGlassTokens.shadowSoft.radius,
            y: LiquidGlassTokens.shadowSoft.y
        )
        .accessibilityLabel("Voice note, \(formattedDuration(duration)) seconds")
        .onDisappear { stopPlayback() }
    }

    private var playButton: some View {
        Button {
            isPlaying ? stopPlayback() : startPlayback()
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.purple.opacity(0.8)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause voice note" : "Play voice note")
    }

    private var waveform: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                let height = barHeight(for: i)
                let filled = Double(i) / Double(barCount) < progress
                RoundedRectangle(cornerRadius: 2)
                    .fill(filled ? Color.purple : Color.white.opacity(0.45))
                    .frame(width: 3, height: height)
            }
        }
        .frame(height: 36)
    }

    private var timeLabel: some View {
        let elapsed = progress * duration
        return Text(formattedDuration(isPlaying ? elapsed : duration))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: 36)
    }

    @ViewBuilder private var bubbleBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .fill(Color(.systemBackground))
        } else {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .fill(LiquidGlassTokens.blurThin)
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.6)
                }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let seed = abs(audioURL.absoluteString.hashValue &+ index * 7919)
        let normalized = CGFloat(seed % 100) / 100.0
        return 8 + normalized * 28
    }

    private func formattedDuration(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func startPlayback() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: audioURL)
        player?.play()
        isPlaying = true
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard let p = player else { return }
            progress = p.currentTime / max(p.duration, 0.001)
            if !p.isPlaying { stopPlayback() }
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
}

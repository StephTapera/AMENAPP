import SwiftUI

// MARK: - ListenModeOverlay
// Frosted glass ambient player shown when the user switches to listen (audio-only) mode.
// Animates a 5-bar waveform with a sine-wave pattern.
// Respects reduceMotion: static bars when enabled.

@MainActor
struct ListenModeOverlay: View {
    @Binding var isListenMode: Bool
    var trackTitle: String
    var artistName: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if isListenMode {
                // Dim scrim
                Color.black.opacity(0.70)
                    .ignoresSafeArea()
                    .transition(.opacity)

                // Frosted ambient player card
                VStack(spacing: 24) {
                    WaveformView(isAnimating: !reduceMotion)
                        .frame(height: 60)

                    VStack(spacing: 6) {
                        Text(trackTitle)
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .accessibilityAddTraits(.isHeader)

                        Text(artistName)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 40)
                .background { ambientBackground }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            // Toggle button — always visible
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        withAnimation(toggleAnimation) { isListenMode.toggle() }
                    } label: {
                        Image(systemName: isListenMode ? "headphones.circle.fill" : "headphones")
                            .font(.title2)
                            .foregroundStyle(isListenMode ? Color.amenGold : .white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isListenMode ? "Exit listen mode" : "Enter listen mode")
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    @ViewBuilder
    private var ambientBackground: some View {
        let r = LiquidGlassTokens.cornerRadiusLarge
        if reduceTransparency {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(Color.black)
                .overlay {
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(LiquidGlassTokens.blurElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.34), lineWidth: 0.75)
                }
        }
    }

    private var toggleAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: LiquidGlassTokens.motionFast)
            : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.80)
    }
}

// MARK: - WaveformView
// Five animated bars with a sine-wave phase offset per bar.

private struct WaveformView: View {
    var isAnimating: Bool

    private let barCount = 5
    private let barWidth: CGFloat = 6
    private let maxBarHeight: CGFloat = 56
    private let minBarHeight: CGFloat = 8
    private let spacing: CGFloat = 7

    @State private var phase: Double = 0

    var body: some View {
        TimelineView(isAnimating ? .animation(minimumInterval: 1/30) : .animation(minimumInterval: .infinity)) { context in
            let t = isAnimating ? context.date.timeIntervalSinceReferenceDate : 0
            HStack(spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let height = barHeight(bar: i, time: t)
                    Capsule()
                        .fill(Color.white.opacity(0.90))
                        .frame(width: barWidth, height: height)
                        .animation(nil, value: height)
                }
            }
        }
        .accessibilityLabel("Waveform animation")
        .accessibilityHidden(true)
    }

    private func barHeight(bar: Int, time: Double) -> CGFloat {
        let phaseOffset = Double(bar) * .pi / Double(barCount - 1)
        let sine = (sin(time * 3.0 + phaseOffset) + 1) / 2  // 0…1
        return minBarHeight + CGFloat(sine) * (maxBarHeight - minBarHeight)
    }
}

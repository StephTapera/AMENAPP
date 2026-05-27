import SwiftUI

struct ListenModeOverlay: View {
    @Binding var isListenMode: Bool
    var trackTitle: String = ""
    var artistName: String = ""

    @State private var wavePhase: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if isListenMode {
                Color.black.opacity(0.72).ignoresSafeArea()

                VStack(spacing: 24) {
                    // Waveform
                    HStack(spacing: 4) {
                        ForEach(0..<5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.85))
                                .frame(width: 6, height: barHeight(for: i))
                                .animation(
                                    reduceMotion ? nil : .easeInOut(duration: 0.5 + Double(i) * 0.1).repeatForever(autoreverses: true),
                                    value: wavePhase
                                )
                        }
                    }
                    .frame(height: 60)
                    .onAppear { if !reduceMotion { wavePhase = 1 } }

                    VStack(spacing: 4) {
                        if !trackTitle.isEmpty {
                            Text(trackTitle).font(.headline).foregroundStyle(.white)
                        }
                        if !artistName.isEmpty {
                            Text(artistName).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }

            // Toggle button — always visible
            VStack {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            isListenMode.toggle()
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: isListenMode ? "waveform.slash" : "headphones")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(.black.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isListenMode ? "Exit listen mode" : "Enter listen mode")
                    .padding(16)
                }
                Spacer()
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let base: [CGFloat] = [20, 40, 55, 35, 25]
        guard !reduceMotion else { return base[index] }
        let offset = sin(wavePhase * .pi + Double(index) * 0.8) * 15
        return base[index] + CGFloat(offset)
    }
}

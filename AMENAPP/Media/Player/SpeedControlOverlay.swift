import SwiftUI

// MARK: - SpeedControlOverlay
// Transparent overlay that handles double-tap (cycle speed) and pinch (map to rate bracket).
// Shows a GlassHUD with the current rate on each change.
// Pass `isActive = true` to capture gestures; when false it passes through.

@MainActor
struct SpeedControlOverlay: View {
    @Binding var playbackRate: Float   // 0.5, 0.75, 1.0, 1.25, 1.5, 2.0
    var isActive: Bool = true

    private static let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .glassHUD(for: playbackRate, timeout: 1.2) {
                Text(rateLabel)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
            }
            .simultaneousGesture(doubleTapGesture, including: isActive ? .all : .subviews)
            .simultaneousGesture(pinchGesture, including: isActive ? .all : .subviews)
            .allowsHitTesting(isActive)
    }

    // MARK: - Gestures

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2).onEnded { cycleRate() }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onEnded { scale in
                applyPinchScale(scale)
            }
    }

    // MARK: - Helpers

    private var rateLabel: String {
        let formatted = String(format: "%.2g", playbackRate)
        return "\(formatted)\u{00D7}"   // e.g. "1.5×"
    }

    private func cycleRate() {
        let rates = Self.rates
        let currentIndex = rates.firstIndex(of: playbackRate) ?? 2
        let nextIndex = (currentIndex + 1) % rates.count
        playbackRate = rates[nextIndex]
    }

    private func applyPinchScale(_ scale: CGFloat) {
        // Map scale to nearest rate bracket:
        // scale < 0.6 → slowest, scale > 1.6 → fastest
        let rates = Self.rates
        let targetRate = Float(scale) * playbackRate
        let nearest = rates.min(by: { abs($0 - targetRate) < abs($1 - targetRate) }) ?? 1.0
        playbackRate = nearest
    }
}

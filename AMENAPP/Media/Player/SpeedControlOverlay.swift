import SwiftUI

private let rateSteps: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

struct SpeedControlOverlay: View {
    @Binding var playbackRate: Float
    var isActive: Bool = true

    @State private var hudTrigger: Float = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(doubleTapGesture)
            .gesture(pinchGesture)
            .allowsHitTesting(isActive)
            .glassHUD(for: hudTrigger, timeout: 1.2) {
                Text(String(format: "%.2g×", playbackRate))
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
            }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2).onEnded {
            let idx = rateSteps.firstIndex(of: playbackRate) ?? 2
            let next = rateSteps[(idx + 1) % rateSteps.count]
            playbackRate = next
            hudTrigger = next
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onEnded { val in
                let factor = Float(val.magnification)
                let target = playbackRate * factor
                let snapped = rateSteps.min(by: { abs($0 - target) < abs($1 - target) }) ?? 1.0
                playbackRate = snapped
                hudTrigger = snapped
            }
    }
}

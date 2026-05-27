import SwiftUI
import AVKit

struct PiPCardView: View {
    var player: AVPlayer
    @Binding var position: CGPoint
    var onDismiss: () -> Void

    @GestureState private var dragOffset: CGSize = .zero
    @State private var snappedPosition: CGPoint = CGPoint(x: 60, y: 120)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VideoPlayer(player: player)
            .frame(width: 160, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Circle().fill(.black.opacity(0.55)))
                }
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityLabel("Close picture-in-picture")
            }
            .shadow(
                color: LiquidGlassTokens.shadowFloating.color,
                radius: LiquidGlassTokens.shadowFloating.radius,
                y: LiquidGlassTokens.shadowFloating.y
            )
            .offset(dragOffset)
            .position(snappedPosition)
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        let newPos = CGPoint(
                            x: snappedPosition.x + value.translation.width,
                            y: snappedPosition.y + value.translation.height
                        )
                        snappedPosition = snap(newPos)
                        position = snappedPosition
                    }
            )
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75), value: snappedPosition)
    }

    private func snap(_ pt: CGPoint) -> CGPoint {
        // Snap to nearest screen corner (assumes ~390×844 screen; use screen bounds)
        let screen = UIScreen.main.bounds
        let x = pt.x < screen.midX ? 88.0 : screen.width - 88.0
        let y = pt.y < screen.midY ? 120.0 : screen.height - 160.0
        return CGPoint(x: x, y: y)
    }
}

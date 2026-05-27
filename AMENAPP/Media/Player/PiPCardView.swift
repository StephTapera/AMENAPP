import SwiftUI
import AVKit

// MARK: - PiPCardView
// A 160×90pt floating draggable video card — the SwiftUI PiP equivalent.
// Snaps to the nearest screen corner on drag end.
// AVPictureInPictureController requires a special entitlement; this card
// provides the same UX without that entitlement.

@MainActor
struct PiPCardView: View {
    var player: AVPlayer
    @Binding var position: CGPoint
    var onDismiss: () -> Void

    private let cardWidth:  CGFloat = 160
    private let cardHeight: CGFloat = 90   // 16:9

    @State private var dragOffset: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VideoPlayer(player: player)
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: LiquidGlassTokens.cornerRadiusSmall,
                        style: .continuous
                    )
                )

            // Close badge
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle().fill(Color.black.opacity(0.60))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6))
                    )
            }
            .buttonStyle(.plain)
            .offset(x: 8, y: -8)
            .accessibilityLabel("Close picture-in-picture")
        }
        .shadow(
            color: LiquidGlassTokens.shadowFloating.color,
            radius: LiquidGlassTokens.shadowFloating.radius,
            y: LiquidGlassTokens.shadowFloating.y
        )
        .offset(
            x: position.x + dragOffset.width,
            y: position.y + dragOffset.height
        )
        .gesture(dragGesture)
        .accessibilityLabel("Picture in picture video")
        .accessibilityAddTraits(.isImage)
    }

    // MARK: - Drag & corner snap

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let newX = position.x + value.translation.width
                let newY = position.y + value.translation.height
                let snapped = snapToCorner(x: newX, y: newY)
                let animation: Animation = reduceMotion
                    ? .easeOut(duration: LiquidGlassTokens.motionFast)
                    : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.72)
                withAnimation(animation) {
                    position = snapped
                    dragOffset = .zero
                }
            }
    }

    private func snapToCorner(x: CGFloat, y: CGFloat) -> CGPoint {
        let screenBounds = UIScreen.main.bounds
        let margin: CGFloat = 16
        let snapX = x < screenBounds.midX
            ? -(screenBounds.width / 2) + cardWidth / 2 + margin
            :  (screenBounds.width / 2) - cardWidth / 2 - margin
        let snapY = y < screenBounds.midY
            ? -(screenBounds.height / 2) + cardHeight / 2 + margin + 44  // below status bar
            :  (screenBounds.height / 2) - cardHeight / 2 - margin - 34  // above home indicator
        return CGPoint(x: snapX, y: snapY)
    }
}

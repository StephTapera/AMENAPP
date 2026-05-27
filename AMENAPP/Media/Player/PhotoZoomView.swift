import SwiftUI

// MARK: - PhotoZoomView
// Full-screen photo viewer with pinch-to-zoom (1×–4×) and pan (when zoomed).
// Double-tap snaps back to 1×. Crosshair drawn at the pinch centroid.
// Uses AmenFloatingGlassBackButton from AmenGlassKit.

@MainActor
struct PhotoZoomView: View {
    var image: UIImage
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var crosshairLocation: CGPoint = .zero
    @State private var showCrosshair = false

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0
    private let crosshairArmLength: CGFloat = 20
    private let crosshairLineWidth: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Zoomable image
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnificationGesture)
                .gesture(panGesture)
                .gesture(doubleTapGesture)
                .accessibilityZoomAction { action in
                    switch action.direction {
                    case .zoomIn:
                        applyZoom(newScale: min(scale * 1.5, maxScale))
                    case .zoomOut:
                        applyZoom(newScale: max(scale / 1.5, minScale))
                    @unknown default:
                        break
                    }
                }
                .accessibilityLabel(image.accessibilityIdentifier ?? "Photo")

            // Crosshair
            if showCrosshair {
                CrosshairView(
                    color: .blue,
                    armLength: crosshairArmLength,
                    lineWidth: crosshairLineWidth
                )
                .position(crosshairLocation)
                .allowsHitTesting(false)
            }

            // Back button
            VStack {
                HStack {
                    AmenFloatingGlassBackButton(action: { dismiss() })
                        .padding(.leading, 16)
                        .padding(.top, 8)
                    Spacer()
                }
                Spacer()
            }
        }
    }

    // MARK: - Gestures

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let proposed = lastScale * value
                scale = min(max(proposed, minScale), maxScale)
                // Try to approximate center — GeometryReader would be needed for true centroid;
                // for now use screen center as the crosshair anchor.
                crosshairLocation = CGPoint(
                    x: UIScreen.main.bounds.midX,
                    y: UIScreen.main.bounds.midY
                )
                showCrosshair = true
            }
            .onEnded { value in
                lastScale = scale
                withAnimation(.easeOut(duration: 0.3)) { showCrosshair = false }
                clampOffset()
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1.0 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
                clampOffset()
            }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2).onEnded {
            let animation: Animation = reduceMotion
                ? .easeOut(duration: LiquidGlassTokens.motionFast)
                : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.78)
            withAnimation(animation) {
                scale = minScale
                lastScale = minScale
                offset = .zero
                lastOffset = .zero
            }
        }
    }

    // MARK: - Helpers

    private func applyZoom(newScale: CGFloat) {
        let animation: Animation = reduceMotion
            ? .easeOut(duration: LiquidGlassTokens.motionFast)
            : .spring(response: 0.30, dampingFraction: 0.80)
        withAnimation(animation) {
            scale = newScale
            lastScale = newScale
            if newScale <= minScale {
                offset = .zero
                lastOffset = .zero
            }
        }
    }

    private func clampOffset() {
        // Prevent panning beyond image bounds
        let maxOffsetX = UIScreen.main.bounds.width * (scale - 1) / 2
        let maxOffsetY = UIScreen.main.bounds.height * (scale - 1) / 2
        let clampedX = min(max(offset.width, -maxOffsetX), maxOffsetX)
        let clampedY = min(max(offset.height, -maxOffsetY), maxOffsetY)
        if clampedX != offset.width || clampedY != offset.height {
            withAnimation(.easeOut(duration: 0.18)) {
                offset = CGSize(width: clampedX, height: clampedY)
                lastOffset = offset
            }
        }
    }
}

// MARK: - CrosshairView

private struct CrosshairView: View {
    var color: Color
    var armLength: CGFloat
    var lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            // Horizontal arm
            var hPath = Path()
            hPath.move(to: CGPoint(x: center.x - armLength, y: center.y))
            hPath.addLine(to: CGPoint(x: center.x + armLength, y: center.y))
            // Vertical arm
            var vPath = Path()
            vPath.move(to: CGPoint(x: center.x, y: center.y - armLength))
            vPath.addLine(to: CGPoint(x: center.x, y: center.y + armLength))

            context.stroke(hPath, with: .color(color), lineWidth: lineWidth)
            context.stroke(vPath, with: .color(color), lineWidth: lineWidth)
        }
        .frame(width: armLength * 2 + 4, height: armLength * 2 + 4)
    }
}

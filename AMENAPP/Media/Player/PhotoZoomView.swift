import SwiftUI

struct PhotoZoomView: View {
    var image: UIImage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var showCrosshair = false
    @State private var crosshairPosition: CGPoint = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnifyGesture)
                .gesture(dragGesture)
                .onTapGesture(count: 2) {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.80)) {
                        scale = 1.0
                        offset = .zero
                    }
                }
                .accessibilityZoomAction { action in
                    switch action.direction {
                    case .zoomIn:  scale = min(scale * 1.5, 4.0)
                    case .zoomOut: scale = max(scale / 1.5, 1.0)
                    @unknown default: break
                    }
                }

            // Crosshair indicator at pinch center
            if showCrosshair {
                CrosshairView()
                    .position(crosshairPosition)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // Back button
            VStack {
                HStack {
                    AmenFloatingGlassBackButton(action: { dismiss() })
                        .padding(16)
                    Spacer()
                }
                Spacer()
            }
        }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { val in
                scale = max(1.0, min(4.0, val.magnification))
                showCrosshair = true
                crosshairPosition = CGPoint(
                    x: val.startLocation.x,
                    y: val.startLocation.y
                )
            }
            .onEnded { _ in
                withAnimation(.easeOut(duration: 0.2)) { showCrosshair = false }
                if scale < 1.05 {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.80)) {
                        scale = 1.0; offset = .zero
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { val in
                guard scale > 1.0 else { return }
                offset = val.translation
            }
            .onEnded { _ in
                guard scale <= 1.0 else { return }
                withAnimation(reduceMotion ? nil : .spring()) { offset = .zero }
            }
    }
}

private struct CrosshairView: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Color.blue).frame(width: 1, height: 20)
            Rectangle().fill(Color.blue).frame(width: 20, height: 1)
        }
    }
}

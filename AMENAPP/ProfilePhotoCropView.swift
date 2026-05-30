//
//  ProfilePhotoCropView.swift
//  AMENAPP
//
//  Instagram/Threads-style circular crop view.
//  User pinches to zoom and drags to reposition the photo inside the circle.
//  Tapping "Use Photo" renders a square crop and calls onCrop(UIImage).
//

import SwiftUI

// MARK: - Crop View

struct ProfilePhotoCropView: View {
    let image: UIImage
    var onCrop: (UIImage) -> Void
    var onCancel: () -> Void

    // Geometry
    private let cropDiameter: CGFloat = 300

    // Current transform (live)
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    // Committed transform (before each new gesture)
    @State private var baseScale: CGFloat = 1.0
    @State private var baseOffset: CGSize = .zero

    // Minimum scale so the image always fills the circle
    private var minScale: CGFloat {
        let size = imageSize
        guard size.width > 0, size.height > 0 else { return 1 }
        let widthRatio  = cropDiameter / size.width
        let heightRatio = cropDiameter / size.height
        return max(widthRatio, heightRatio)
    }

    private var imageSize: CGSize {
        image.size
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmenLiquidWhiteBackdrop()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .blur(radius: 34)
                    .saturation(0.92)
                    .opacity(0.26)
                    .overlay(Color.white.opacity(0.42))

                VStack(spacing: 0) {
                    HStack {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onCancel()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.systemScaled(16, weight: .bold))
                                .frame(width: 46, height: 46)
                        }
                        .buttonStyle(AmenLiquidWhiteCircleButtonStyle())

                        Spacer()

                        Text("Crop Image")
                            .font(AMENFont.bold(16))
                            .foregroundStyle(.black)

                        Spacer()

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            commitCrop()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.systemScaled(17, weight: .bold))
                                .frame(width: 46, height: 46)
                        }
                        .buttonStyle(AmenLiquidWhiteCircleButtonStyle(isProminent: true))
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)

                    Spacer()

                    // ── Crop Frame ───────────────────────────────────────────
                    ZStack {
                        AmenLiquidWhiteSurface(cornerRadius: 999, shadow: .floating) {
                            Color.clear
                                .frame(width: cropDiameter + 34, height: cropDiameter + 34)
                        }

                        ZStack {
                            // The image, transformed
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width:  imageSize.width  > 0 ? imageSize.width  * scale : 300,
                                    height: imageSize.height > 0 ? imageSize.height * scale : 300
                                )
                                .offset(offset)

                            // Bright overlay with circular lens cut out.
                            CropOverlay(diameter: cropDiameter)
                                .allowsHitTesting(false)

                            // Grid lines inside circle (appears only during gesture)
                            CropGridLines(diameter: cropDiameter)
                                .opacity(isDragging || isPinching ? 0.45 : 0)
                                .animation(.easeOut(duration: 0.2), value: isDragging || isPinching)
                                .allowsHitTesting(false)
                        }
                        .frame(width: cropDiameter, height: cropDiameter)
                        .clipShape(Rectangle())
                        .contentShape(Rectangle())
                        .gesture(
                            SimultaneousGesture(
                                dragGesture,
                                magnifyGesture
                            )
                        )
                    }

                    Spacer()

                    // ── Hint text ────────────────────────────────────────────
                    AmenLiquidWhiteSurface(cornerRadius: 999, shadow: .soft) {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.systemScaled(13, weight: .semibold))

                            Text("Pinch to zoom · Drag to reposition")
                                .font(AMENFont.semiBold(13))
                        }
                        .foregroundStyle(.black.opacity(0.64))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                    }
                    .padding(.bottom, 28)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                // Start with image filling the circle
                let initial = max(minScale, 1.0)
                scale = initial
                baseScale = initial
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Gesture state helpers

    @GestureState private var isDragging = false
    @GestureState private var isPinching = false

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                var proposed = CGSize(
                    width:  baseOffset.width  + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
                proposed = clampOffset(proposed, scale: scale)
                offset = proposed
            }
            .onEnded { value in
                var finalOffset = CGSize(
                    width:  baseOffset.width  + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
                finalOffset = clampOffset(finalOffset, scale: scale)
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                    offset = finalOffset
                }
                baseOffset = finalOffset
            }
    }

    // MARK: - Magnify Gesture

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($isPinching) { _, state, _ in state = true }
            .onChanged { value in
                let proposed = max(minScale, baseScale * value.magnification)
                scale = proposed
                // Re-clamp offset at new scale
                offset = clampOffset(baseOffset, scale: proposed)
            }
            .onEnded { value in
                let final = max(minScale, baseScale * value.magnification)
                let clampedOffset = clampOffset(baseOffset, scale: final)
                withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.8))) {
                    scale = final
                    offset = clampedOffset
                }
                baseScale = final
                baseOffset = clampedOffset
            }
    }

    // MARK: - Offset Clamping

    /// Prevents the image from exposing the background inside the crop circle.
    private func clampOffset(_ proposed: CGSize, scale: CGFloat) -> CGSize {
        let scaledW = imageSize.width  * scale
        let scaledH = imageSize.height * scale

        // Maximum offset before the edge of the image enters the crop circle
        let maxX = max(0, (scaledW - cropDiameter) / 2)
        let maxY = max(0, (scaledH - cropDiameter) / 2)

        return CGSize(
            width:  proposed.width .clamped(to: -maxX ... maxX),
            height: proposed.height.clamped(to: -maxY ... maxY)
        )
    }

    // MARK: - Crop & Render

    private func commitCrop() {
        let cropSize = CGSize(width: cropDiameter, height: cropDiameter)
        let renderer = UIGraphicsImageRenderer(size: cropSize)

        let cropped = renderer.image { _ in
            // The image is rendered centred at (cropDiameter/2, cropDiameter/2)
            // with the current scale and offset applied.
            let scaledW = imageSize.width  * scale
            let scaledH = imageSize.height * scale

            let x = (cropDiameter - scaledW) / 2 + offset.width
            let y = (cropDiameter - scaledH) / 2 + offset.height

            image.draw(in: CGRect(x: x, y: y, width: scaledW, height: scaledH))
        }

        // Ensure the cropped image has a valid CGImage by re-rendering if needed
        // This prevents crashes during EXIF stripping in FirebaseManager
        guard let validImage = ensureValidCGImage(cropped) else {
            dlog("⚠️ Failed to create valid CGImage from crop")
            onCancel()
            return
        }

        onCrop(validImage)
    }

    /// Ensures the UIImage has a valid CGImage backing, re-rendering if necessary
    private func ensureValidCGImage(_ image: UIImage) -> UIImage? {
        // If already has cgImage, return as-is
        if image.cgImage != nil {
            return image
        }

        // Otherwise, re-render to create a CGImage-backed UIImage
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Crop Overlay (soft diffusion with circular lens)

private struct CropOverlay: View {
    let diameter: CGFloat

    var body: some View {
        GeometryReader { geo in
            Color.white.opacity(0.36)
                // Cut out the circle
                .mask(
                    ZStack {
                        Rectangle()
                        Circle()
                            .frame(width: diameter, height: diameter)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                )
                // White circle border
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.98),
                                    Color.black.opacity(0.18),
                                    Color.white.opacity(0.72)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.6
                        )
                        .frame(width: diameter, height: diameter)
                        .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
                )
        }
    }
}

// MARK: - Crop Grid Lines

private struct CropGridLines: View {
    let diameter: CGFloat

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(
                x: (size.width - diameter) / 2,
                y: (size.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            let third = diameter / 3
            let white = Color.white.opacity(0.82)

            // Vertical thirds
            for i in 1 ..< 3 {
                let x = rect.minX + CGFloat(i) * third
                var path = Path()
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
                context.stroke(path, with: .color(white), lineWidth: 0.5)
            }

            // Horizontal thirds
            for i in 1 ..< 3 {
                let y = rect.minY + CGFloat(i) * third
                var path = Path()
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
                context.stroke(path, with: .color(white), lineWidth: 0.5)
            }
        }
    }
}

// MARK: - Comparable clamping helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        max(range.lowerBound, min(range.upperBound, self))
    }
}

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
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // ── Crop Frame ───────────────────────────────────────────
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

                        // Darkened overlay with circular hole cut out
                        CropOverlay(diameter: cropDiameter)
                            .allowsHitTesting(false)

                        // Grid lines inside circle (appears only during gesture)
                        CropGridLines(diameter: cropDiameter)
                            .opacity(isDragging || isPinching ? 0.35 : 0)
                            .animation(.easeOut(duration: 0.2), value: isDragging || isPinching)
                            .allowsHitTesting(false)
                    }
                    .frame(width: cropDiameter, height: cropDiameter)
                    .clipShape(Rectangle())  // prevent image bleeding during drag
                    .contentShape(Rectangle())
                    .gesture(
                        SimultaneousGesture(
                            dragGesture,
                            magnifyGesture
                        )
                    )

                    Spacer()

                    // ── Hint text ────────────────────────────────────────────
                    Text("Pinch to zoom · Drag to reposition")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.bottom, 32)
                }
            }
            .navigationTitle("Crop Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onCancel()
                    }
                    .foregroundStyle(.white)
                    .font(.custom("OpenSans-Regular", size: 16))
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        commitCrop()
                    } label: {
                        Text("Use Photo")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.white)
                    }
                }
            }
            .onAppear {
                // Start with image filling the circle
                let initial = max(minScale, 1.0)
                scale = initial
                baseScale = initial
            }
        }
        .preferredColorScheme(.dark)
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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
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

        onCrop(cropped)
    }
}

// MARK: - Crop Overlay (dark vignette with circular hole)

private struct CropOverlay: View {
    let diameter: CGFloat

    var body: some View {
        GeometryReader { geo in
            // Dark overlay
            Color.black.opacity(0.55)
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
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5)
                        .frame(width: diameter, height: diameter)
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
            let white = Color.white

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

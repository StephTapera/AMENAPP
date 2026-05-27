import SwiftUI
import PencilKit

struct PhotoMarkupView: View {
    var image: UIImage
    var onSend: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var canvasView = PKCanvasView()
    @State private var toolPicker = PKToolPicker()
    @State private var isSending = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Background image
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .ignoresSafeArea(edges: .horizontal)

            // PencilKit canvas
            MarkupCanvas(canvasView: $canvasView, toolPicker: toolPicker)
                .ignoresSafeArea()

            // Toolbar
            VStack {
                Spacer()
                toolbar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
        .navigationBarHidden(true)
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")

            Spacer()

            Button {
                sendMarkup()
            } label: {
                HStack(spacing: 8) {
                    if isSending {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.body.weight(.semibold))
                        Text("Send")
                            .font(.body.weight(.semibold))
                    }
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
            .disabled(isSending)
            .accessibilityLabel("Send marked up photo")
        }
        .padding(12)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(Color.black.opacity(0.85))
            } else {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(LiquidGlassTokens.blurElevated)
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.6)
                    }
            }
        }
    }

    @MainActor
    private func sendMarkup() {
        isSending = true
        let drawing = canvasView.drawing
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let result = renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            let drawingImage = drawing.image(from: CGRect(origin: .zero, size: image.size), scale: image.scale)
            drawingImage.draw(in: CGRect(origin: .zero, size: image.size))
        }
        onSend(result)
        dismiss()
    }
}

// MARK: - UIViewRepresentable for PKCanvasView

private struct MarkupCanvas: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    var toolPicker: PKToolPicker

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        DispatchQueue.main.async { canvasView.becomeFirstResponder() }
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}

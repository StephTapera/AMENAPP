import SwiftUI
import PhotosUI
import UIKit

/// Captures or selects a photo of a whiteboard, screen, or slide for OCR text extraction.
/// Feature flag `churchNotesPhotoOCREnabled` must be true before this view is shown.
struct ChurchNotesPhotoOCRCaptureView: View {

    let noteId: String
    @ObservedObject var processingService: ChurchNotesMediaProcessingService
    var onDismiss: () -> Void

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var showCamera = false
    @State private var isCompressing = false
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var showSizeWarning = false

    private let maxImageDimension: CGFloat = 2048
    private let jpegQuality: CGFloat = 0.82

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    imagePreviewArea
                    Spacer()
                    captureSourcePicker
                    controlDock
                        .padding(.bottom, 36)
                }
            }
            .navigationTitle("Capture for OCR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                        .accessibilityLabel("Cancel photo capture")
                }
            }
            .sheet(isPresented: $showCamera) {
                ChurchNotesCameraView(capturedImage: $capturedImage)
            }
            .onChange(of: selectedPhotoItem) { _, item in
                Task { await loadSelectedPhoto(item: item) }
            }
            .alert("Image Too Large", isPresented: $showSizeWarning) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please choose an image under 20 MB.")
            }
        }
    }

    // MARK: - Image preview

    @ViewBuilder
    private var imagePreviewArea: some View {
        if let image = capturedImage {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .accessibilityLabel("Captured photo preview")

                Button {
                    capturedImage     = nil
                    selectedPhotoItem = nil
                    submitError       = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .background(Color(.systemBackground), in: Circle())
                }
                .padding(.top, 20)
                .padding(.trailing, 28)
                .accessibilityLabel("Remove photo")
            }

            Text("Photo ready. Tap 'Extract Text' to run OCR.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 8)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.systemScaled(72))
                    .foregroundStyle(Color.accentColor.opacity(0.6))
                    .padding(.top, 40)
                    .accessibilityHidden(true)

                Text("Capture a whiteboard, slide, screen, or handout.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    // MARK: - Source picker

    private var captureSourcePicker: some View {
        HStack(spacing: 20) {
            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("Photo Library", systemImage: "photo.on.rectangle")
                    .font(.callout)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("Choose from photo library")
            .accessibilityHint("Opens your photo library to select an image")

            Button {
                showCamera = true
            } label: {
                Label("Camera", systemImage: "camera")
                    .font(.callout)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("Take photo with camera")
            .accessibilityHint("Opens camera to photograph a board or screen")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Control dock

    @ViewBuilder
    private var controlDock: some View {
        if isCompressing {
            HStack(spacing: 10) {
                ProgressView()
                Text("Preparing image…")
                    .foregroundStyle(.secondary)
            }
            .padding()
        } else if isSubmitting {
            VStack(spacing: 8) {
                if case .uploading(let p) = processingService.uploadState.phase {
                    ProgressView(value: p)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 32)
                    Text("Uploading \(Int(p * 100))%")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text("Processing…")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        } else if let err = submitError {
            VStack(spacing: 12) {
                Text(err)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Retry") { Task { await submitImage() } }
                    .buttonStyle(ChurchNotesActionButtonStyle(color: .accentColor))
                    .accessibilityLabel("Retry upload")
            }
        } else if capturedImage != nil {
            Button("Extract Text") {
                Task { await submitImage() }
            }
            .buttonStyle(ChurchNotesActionButtonStyle(color: .accentColor))
            .accessibilityLabel("Extract text from photo using OCR")
            .accessibilityHint("Uploads photo and extracts text for review before adding to notes")
        } else {
            EmptyView()
        }
    }

    // MARK: - Actions

    private func loadSelectedPhoto(item: PhotosPickerItem?) async {
        guard let item else { return }
        isCompressing = true
        defer { isCompressing = false }

        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            capturedImage = image
            submitError   = nil
        }
    }

    private func submitImage() async {
        guard let image = capturedImage else { return }
        isSubmitting = true
        submitError  = nil

        let compressed = compress(image: image)
        guard let data = compressed else {
            submitError  = "Could not prepare image. Please try again."
            isSubmitting = false
            return
        }

        guard data.count <= 20 * 1024 * 1024 else {
            showSizeWarning = true
            isSubmitting    = false
            return
        }

        await processingService.uploadImageAndCreateJob(imageData: data, noteId: noteId)
        isSubmitting = false

        if case .failed(let msg) = processingService.uploadState.phase {
            submitError = msg
        } else {
            onDismiss()
        }
    }

    private func compress(image: UIImage) -> Data? {
        let targetSize = CGSize(width: maxImageDimension, height: maxImageDimension)
        let size       = image.size

        guard size.width > 0, size.height > 0 else { return nil }

        let scale   = min(targetSize.width / size.width, targetSize.height / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized  = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }

        return resized.jpegData(compressionQuality: jpegQuality)
    }
}

// MARK: - Camera view

struct ChurchNotesCameraView: UIViewControllerRepresentable {

    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType    = .camera
        picker.delegate      = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ChurchNotesCameraView
        init(_ parent: ChurchNotesCameraView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.capturedImage = info[.originalImage] as? UIImage
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

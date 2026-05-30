import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

enum BereanAttachmentPickerMode {
    case file
    case photo
    case camera

    var title: String {
        switch self {
        case .file: return "Attach File"
        case .photo: return "Choose Photo"
        case .camera: return "Capture Photo"
        }
    }

    var analyticsName: String {
        switch self {
        case .file:   return "file"
        case .photo:  return "photo"
        case .camera: return "camera"
        }
    }
}

struct BereanAttachmentResult: Equatable {
    var displayName: String
    var promptPrefix: String
    var contextText: String? = nil
    var contentType: String? = nil
    var byteCount: Int? = nil
    var storagePath: String? = nil
    var downloadURL: String? = nil
}

struct BereanAttachmentPickerSheet: View {
    let mode: BereanAttachmentPickerMode
    let onAttach: (BereanAttachmentResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: iconName)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 72, height: 72)
                    .background(Color.blue.opacity(0.12), in: Circle())

                Text(mode.title)
                    .font(.title3.bold())

                Text(helpText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                actionControl

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.pdf, .plainText, .rtf, .image, .movie, .audio, .data],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .fullScreenCover(isPresented: $showCamera) {
                AmenCameraView { capture in
                    if let capture {
                        let name: String
                        switch capture {
                        case .image:
                            name = "Camera photo"
                        case .video(let url):
                            name = url.lastPathComponent
                        }
                        onAttach(BereanAttachmentResult(displayName: name, promptPrefix: "Use this captured media as context: "))
                    }
                    dismiss()
                }
                .ignoresSafeArea()
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task { await handlePhotoSelection(newItem) }
            }
        }
    }

    @ViewBuilder
    private var actionControl: some View {
        switch mode {
        case .file:
            Button {
                showFileImporter = true
            } label: {
                Label("Browse Files", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        case .photo:
            PhotosPicker(selection: $selectedPhotoItem, matching: .any(of: [.images, .videos])) {
                Label("Open Photo Library", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        case .camera:
            Button {
                guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                    errorMessage = "Camera is not available on this device."
                    return
                }
                showCamera = true
            } label: {
                Label("Open Camera", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var iconName: String {
        switch mode {
        case .file: return "paperclip"
        case .photo: return "photo.on.rectangle"
        case .camera: return "camera"
        }
    }

    private var helpText: String {
        switch mode {
        case .file: return "Choose a document or media file to attach as Berean context."
        case .photo: return "Choose a photo or video from your library to attach as Berean context."
        case .camera: return "Capture a photo or video and attach it as Berean context."
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                errorMessage = "No file was selected."
                return
            }
            onAttach(BereanAttachmentResult(displayName: url.lastPathComponent, promptPrefix: "Use this attached file as context: "))
            dismiss()
        case .failure:
            errorMessage = "The selected file could not be attached."
        }
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
            let name = item.supportedContentTypes.first?.preferredFilenameExtension.map { "Photo.\($0)" } ?? "Photo attachment"
            await MainActor.run {
                onAttach(BereanAttachmentResult(displayName: name, promptPrefix: "Use this selected media as context: "))
                dismiss()
            }
        } else {
            await MainActor.run {
                errorMessage = "The selected media could not be loaded."
            }
        }
    }
}

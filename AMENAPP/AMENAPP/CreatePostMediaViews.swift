import SwiftUI
import UniformTypeIdentifiers

struct ImagePreviewGrid: View {
    @Binding var images: [Data]
    var onAddMore: (() -> Void)? = nil
    @State private var draggingItem: Data?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(images, id: \.self) { imageData in
                    DraggableImageCell(
                        imageData: imageData,
                        images: $images,
                        draggingItem: $draggingItem
                    )
                }

                // "+" add more cell (up to 4 images)
                if images.count < 4, let onAddMore {
                    AddImageButton(onAddMore: onAddMore)
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: images.count)
    }
}

// MARK: - Draggable Image Cell

private struct DraggableImageCell: View {
    let imageData: Data
    @Binding var images: [Data]
    @Binding var draggingItem: Data?
    
    var body: some View {
        if let uiImage = UIImage(data: imageData) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(draggingItem == imageData ? 0.5 : 1.0)

                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                        images.removeAll { $0 == imageData }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.7))
                            .frame(width: 28, height: 28)

                        Image(systemName: "xmark")
                            .font(.systemScaled(12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(8)
            }
            .transition(.scale.combined(with: .opacity))
            .onDrag {
                draggingItem = imageData
                let provider = NSItemProvider()
                provider.suggestedName = UUID().uuidString
                return provider
            }
            .onDrop(of: [.data], delegate: ImageDropDelegate(
                item: imageData,
                items: $images,
                draggingItem: $draggingItem
            ))
        }
    }
}

private struct AddImageButton: View {
    let onAddMore: () -> Void
    
    var body: some View {
        Button(action: onAddMore) {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .frame(width: 120, height: 120)
                .overlay(
                    Image(systemName: "plus")
                        .font(.systemScaled(24, weight: .light))
                        .foregroundStyle(.secondary)
                )
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }
}

// Drag and drop delegate for image reordering
struct ImageDropDelegate: DropDelegate {
    let item: Data
    @Binding var items: [Data]
    @Binding var draggingItem: Data?
    
    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggingItem = draggingItem,
              draggingItem != item,
              let fromIndex = items.firstIndex(of: draggingItem),
              let toIndex = items.firstIndex(of: item) else { return }
        
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
            items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }
}


struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraImagePicker
        init(_ parent: CameraImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.image = img
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Camera Attachment Preview

/// Shows the captured photo inside the composer with a remove button.
struct CameraAttachmentPreview: View {
    let image: UIImage
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Remove button
            Button(action: onRemove) {
                ZStack {
                    Circle()
                        .fill(Color(.systemBackground).opacity(0.92))
                        .frame(width: 30, height: 30)
                    Image(systemName: "xmark")
                        .font(.systemScaled(12, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(8)
            .accessibilityLabel("Remove photo")
        }
    }
}

// MARK: - Poll Composer Card

/// Inline poll creation card inserted beneath the text editor.

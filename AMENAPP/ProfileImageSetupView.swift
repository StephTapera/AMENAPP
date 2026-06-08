import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

// MARK: - Liquid White Profile Image Flow

@MainActor
final class ProfileImageFlowViewModel: ObservableObject {
    enum Step: Equatable {
        case select
        case cropping
        case preview
        case saving
        case success
        case failed(String)
    }

    enum Source: String, Identifiable {
        case photoLibrary
        case camera
        case memoji

        var id: String { rawValue }
        var title: String {
            switch self {
            case .photoLibrary: return "Photo Library"
            case .camera: return "Take Photo"
            case .memoji: return "Use Memoji"
            }
        }
        var icon: String {
            switch self {
            case .photoLibrary: return "photo.on.rectangle"
            case .camera: return "camera"
            case .memoji: return "face.smiling"
            }
        }
    }

    @Published var selectedSource: Source?
    @Published var selectedImage: UIImage?
    @Published var croppedImage: UIImage?
    @Published var currentStep: Step = .select
    @Published var errorMessage: String?
    @Published var isSourceSheetPresented = false
    @Published var zoom: Double = 1

    private let uploadService: ProfileImageUploadService

    init(uploadService: ProfileImageUploadService = ProfileImageUploadService()) {
        self.uploadService = uploadService
    }

    var displayImage: UIImage? { croppedImage ?? selectedImage }
    var hasImage: Bool { displayImage != nil }

    func openSourceSheet() {
        errorMessage = nil
        isSourceSheetPresented = true
    }

    func choose(_ source: Source) {
        selectedSource = source
        isSourceSheetPresented = false
        if source == .memoji {
            selectedImage = UIImage(systemName: "person.crop.circle.fill")
            croppedImage = selectedImage
            currentStep = .preview
        }
    }

    func applyLibraryData(_ data: Data?) {
        guard let data, let image = UIImage(data: data) else {
            fail("We couldn't read that image. Try another one.")
            return
        }
        selectedImage = image
        croppedImage = nil
        currentStep = .cropping
    }

    func useCameraImage(_ image: UIImage) {
        selectedImage = image
        croppedImage = nil
        currentStep = .cropping
    }

    func finishCrop() {
        guard let selectedImage else {
            fail("Choose an image before cropping.")
            return
        }
        croppedImage = selectedImage.normalizedForProfileCrop(maxDimension: 1024)
        currentStep = .preview
    }

    func cancelCrop() {
        currentStep = .select
    }

    func removeImage() {
        selectedImage = nil
        croppedImage = nil
        selectedSource = nil
        errorMessage = nil
        currentStep = .select
    }

    func save() async {
        guard let image = displayImage else {
            fail("Choose an image before saving.")
            return
        }
        currentStep = .saving
        do {
            try await uploadService.uploadProfileImage(image)
            currentStep = .success
        } catch {
            fail(error.localizedDescription)
        }
    }

    func done() {
        currentStep = .select
    }

    private func fail(_ message: String) {
        errorMessage = message
        currentStep = .failed(message)
    }
}

struct ProfileImageUploadService {
    func uploadProfileImage(_ image: UIImage) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ProfileImageUpload", code: 401, userInfo: [NSLocalizedDescriptionKey: "Sign in before saving a profile image."])
        }
        guard let data = image.jpegData(compressionQuality: 0.86), data.count <= 5 * 1024 * 1024 else {
            throw NSError(domain: "ProfileImageUpload", code: 413, userInfo: [NSLocalizedDescriptionKey: "Choose an image under 5 MB."])
        }

        let path = "users/\(uid)/profile/profileImage.jpg"
        let ref = Storage.storage().reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()

        try await Firestore.firestore().collection("users").document(uid).setData([
            "profileImageURL": url.absoluteString,
            "profileImageStoragePath": path,
            "profileImageUpdatedAt": FieldValue.serverTimestamp(),
            "profileImageVisibility": "friends"
        ], merge: true)
    }
}

struct ProfileImageSetupView: View {
    @StateObject private var vm = ProfileImageFlowViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            switch vm.currentStep {
            case .select, .failed:
                selectView
            case .cropping:
                ProfileImageCropView(vm: vm)
            case .preview:
                ProfileImagePreviewView(vm: vm)
            case .saving:
                savingView
            case .success:
                ProfileImageSuccessView(vm: vm)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: vm.currentStep)
        .sheet(isPresented: $vm.isSourceSheetPresented) {
            ImageSourceBottomSheet(vm: vm, pickerItem: $pickerItem, showCamera: $showCamera)
                .presentationDetents([.height(310)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCamera) {
            ProfileImageCameraPicker { image in
                vm.useCameraImage(image)
            }
        }
        .onChange(of: pickerItem) { _, newValue in
            guard let newValue else { return }
            Task {
                let data = try? await newValue.loadTransferable(type: Data.self)
                vm.applyLibraryData(data)
                pickerItem = nil
            }
        }
    }

    private var selectView: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 24)
            Button(action: vm.openSourceSheet) {
                LiquidWhiteAvatarPlaceholder(image: vm.displayImage)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(vm.hasImage ? "Change profile image" : "Add profile image")
            Spacer()
            LiquidWhiteBottomActionCard(
                primaryTitle: vm.hasImage ? "Change Photo" : "Tap to Add Image",
                showRemove: vm.hasImage,
                errorMessage: vm.errorMessage,
                primaryAction: vm.openSourceSheet,
                libraryAction: { vm.choose(.photoLibrary) },
                removeAction: vm.removeImage
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.systemScaled(16, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(liquidWhiteMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text("Add an Image to your Profile")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.75)
            Text("Your image will be visible only to friends.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private var savingView: some View {
        VStack(spacing: 18) {
            if let image = vm.displayImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 156, height: 156)
                    .clipShape(Circle())
            }
            ProgressView("Saving Image")
                .tint(.primary)
        }
        .padding(28)
        .background(liquidWhiteMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(24)
    }

    private var liquidWhiteMaterial: some ShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color.white) : AnyShapeStyle(.regularMaterial)
    }
}

struct LiquidWhiteAvatarPlaceholder: View {
    let image: UIImage?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(reduceTransparency ? Color(.secondarySystemBackground) : .regularMaterial)
                    .overlay(Circle().stroke(.primary.opacity(0.12), lineWidth: 1.2))
                    .shadow(color: .black.opacity(0.08), radius: 26, y: 14)
                Circle()
                    .inset(by: 16)
                    .fill(.primary.opacity(0.04))
                    .blur(radius: 1)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                        .padding(8)
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.systemScaled(86, weight: .ultraLight))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 224, height: 224)

            Image(systemName: "plus")
                .font(.systemScaled(19, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 54, height: 54)
                .background(reduceTransparency ? Color(.secondarySystemBackground) : .ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.primary.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 14, y: 7)
                .accessibilityHidden(true)
        }
    }
}

struct LiquidWhiteBottomActionCard: View {
    let primaryTitle: String
    let showRemove: Bool
    let errorMessage: String?
    let primaryAction: () -> Void
    let libraryAction: () -> Void
    let removeAction: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: primaryAction) {
                Text(primaryTitle)
                    .font(.headline)
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color(.label), in: Capsule())
            }
            .accessibilityLabel(primaryTitle)

            Button("Choose from Library", action: libraryAction)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.primary.opacity(0.10), in: Capsule())
                .accessibilityLabel("Choose profile image from photo library")

            if showRemove {
                Button("Remove Current Image", role: .destructive, action: removeAction)
                    .font(.footnote.weight(.medium))
            }
        }
        .padding(18)
        .background(reduceTransparency ? Color(.secondarySystemBackground) : Color(.secondarySystemBackground).opacity(0.68), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.78), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 24, y: 12)
    }
}

struct ImageSourceBottomSheet: View {
    @ObservedObject var vm: ProfileImageFlowViewModel
    @Binding var pickerItem: PhotosPickerItem?
    @Binding var showCamera: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose Image Source")
                .font(.headline)
                .foregroundStyle(.primary)
            VStack(spacing: 10) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    sourceRow(.photoLibrary)
                }
                Button { dismiss(); showCamera = true } label: { sourceRow(.camera) }
                    .buttonStyle(.plain)
                Button { vm.choose(.memoji); dismiss() } label: { sourceRow(.memoji) }
                    .buttonStyle(.plain)
            }
            Button("Cancel") { dismiss() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(22)
        .background(.regularMaterial)
    }

    private func sourceRow(_ source: ProfileImageFlowViewModel.Source) -> some View {
        HStack(spacing: 14) {
            Image(systemName: source.icon)
                .frame(width: 28)
            Text(source.title)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.primary.opacity(0.08)))
        .accessibilityLabel(source.title)
    }
}

struct ProfileImageCropView: View {
    @ObservedObject var vm: ProfileImageFlowViewModel

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button("Cancel") { vm.cancelCrop() }
                Spacer()
                Text("Crop Image").font(.headline)
                Spacer()
                Button("Done") { vm.finishCrop() }.fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()
            ZStack {
                if let image = vm.selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(vm.zoom)
                        .frame(width: 300, height: 300)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .overlay(cropHandles)
                        .shadow(color: .black.opacity(0.12), radius: 24, y: 12)
                }
            }
            .accessibilityLabel("Circular crop preview")

            VStack(alignment: .leading, spacing: 8) {
                Text("Zoom")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                Slider(value: $vm.zoom, in: 1...2.4)
                    .accessibilityLabel("Crop zoom")
            }
            .padding(.horizontal, 28)
            Spacer()
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private var cropHandles: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Circle()
                    .fill(.white)
                    .frame(width: 9, height: 9)
                    .shadow(color: .black.opacity(0.16), radius: 3)
                    .offset(handleOffset(index))
            }
        }
        .accessibilityHidden(true)
    }

    private func handleOffset(_ index: Int) -> CGSize {
        let radius: CGFloat = 150
        let angle = Double(index) * .pi / 4
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }
}

struct ProfileImagePreviewView: View {
    @ObservedObject var vm: ProfileImageFlowViewModel

    var body: some View {
        VStack(spacing: 28) {
            Text("Preview")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.top, 48)
            if let image = vm.displayImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 190, height: 190)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.10), radius: 24, y: 10)
            }
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Profile Photo").font(.headline)
                    Text("Visible to friends only").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.primary.opacity(0.06)))
            .padding(.horizontal, 24)
            Spacer()
            Button { Task { await vm.save() } } label: {
                Text("Save Image")
                    .font(.headline)
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color(.label), in: Capsule())
            }
            .padding(.horizontal, 24)
            Button("Cancel") { vm.currentStep = .select }
                .foregroundStyle(.secondary)
                .padding(.bottom, 28)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}

struct ProfileImageSuccessView: View {
    @ObservedObject var vm: ProfileImageFlowViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack(alignment: .bottomTrailing) {
                if let image = vm.displayImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 178, height: 178)
                        .clipShape(Circle())
                }
                Image(systemName: "checkmark")
                    .font(.systemScaled(20, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 48, height: 48)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.8)))
            }
            Text("Profile Updated")
                .font(.largeTitle.weight(.semibold))
            Text("Your profile image has been updated.")
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: vm.done) {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color(.label), in: Capsule())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}

struct ProfileImageCameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ProfileImageCameraPicker
        init(parent: ProfileImageCameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

private extension UIImage {
    func normalizedForProfileCrop(maxDimension: CGFloat) -> UIImage {
        let side = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        let cropRect = CGRect(origin: origin, size: CGSize(width: side, height: side))
        guard let cgImage = cgImage?.cropping(to: cropRect) else { return self }
        let cropped = UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
        let target = CGSize(width: maxDimension, height: maxDimension)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in cropped.draw(in: CGRect(origin: .zero, size: target)) }
    }
}

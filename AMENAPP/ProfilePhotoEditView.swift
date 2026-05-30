//
//  ProfilePhotoEditView.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  View for editing profile photo with camera/library options
//

import SwiftUI
import PhotosUI
import Photos
import AVFoundation

struct ProfilePhotoEditView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var socialService = SocialService.shared
    @StateObject private var userService = UserService()
    
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var rawPickedImage: UIImage?      // straight from picker — goes to crop
    @State private var selectedImage: UIImage?       // cropped result — goes to upload
    @State private var showCropView = false
    @State private var isUploading = false
    @State private var showCamera = false
    @State private var showDeleteConfirmation = false
    @State private var showSuccessMessage = false
    @State private var showPhotoPermissionAlert = false
    @State private var showCameraPermissionAlert = false
    @State private var photoPermissionDenied = false
    @State private var cameraPermissionDenied = false
    
    let currentImageURL: String?
    let onPhotoUpdated: (String?) -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                AmenLiquidWhiteBackdrop()

                ScrollView {
                    VStack(spacing: 28) {
                        VStack(spacing: 14) {
                            Text(selectedImage == nil && currentImageURL == nil ? "Add an Image" : "Profile Image")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(.black)
                                .multilineTextAlignment(.center)

                            Text("Choose a clear photo that stays readable across Amen.")
                                .font(AMENFont.regular(16))
                                .foregroundStyle(.black.opacity(0.56))
                                .multilineTextAlignment(.center)
                                .lineSpacing(2)
                        }
                        .padding(.top, 42)
                        .padding(.horizontal, 28)

                        VStack(spacing: 18) {
                            currentPhotoView

                            Text(photoStatusText)
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(.black.opacity(0.58))
                        }

                        AmenLiquidWhiteSurface(cornerRadius: 32, shadow: .floating) {
                            VStack(spacing: 14) {
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    AmenLiquidWhiteButtonLabel(
                                        title: selectedImage == nil ? "Choose from Library" : "Choose Different Photo",
                                        systemImage: "photo.on.rectangle"
                                    )
                                }
                                .buttonStyle(AmenLiquidWhiteButtonStyle(kind: .primary))
                                .disabled(isUploading)

                                Button {
                                    requestCameraPermission()
                                } label: {
                                    AmenLiquidWhiteButtonLabel(title: "Take Photo", systemImage: "camera.fill")
                                }
                                .buttonStyle(AmenLiquidWhiteButtonStyle(kind: .secondary))
                                .disabled(isUploading)

                                if currentImageURL != nil && selectedImage == nil {
                                    Button {
                                        showDeleteConfirmation = true
                                    } label: {
                                        AmenLiquidWhiteButtonLabel(title: "Remove Photo", systemImage: "trash")
                                    }
                                    .buttonStyle(AmenLiquidWhiteButtonStyle(kind: .destructive))
                                    .disabled(isUploading)
                                }
                            }
                            .padding(18)
                        }
                        .padding(.horizontal, 18)

                        AmenLiquidWhiteSurface(cornerRadius: 28, shadow: .soft) {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 9) {
                                    Image(systemName: "sparkles")
                                        .font(.systemScaled(15, weight: .semibold))
                                        .foregroundStyle(.black.opacity(0.68))

                                    Text("Photo Tips")
                                        .font(AMENFont.bold(16))
                                        .foregroundStyle(.black)
                                }

                                tipRow(icon: "checkmark.circle.fill", text: "Use a clear, recent photo of yourself", color: .green)
                                tipRow(icon: "checkmark.circle.fill", text: "Face should be clearly visible", color: .green)
                                tipRow(icon: "checkmark.circle.fill", text: "Good lighting works best", color: .green)
                                tipRow(icon: "xmark.circle.fill", text: "Avoid group photos", color: .red)
                            }
                            .padding(20)
                        }
                        .padding(.horizontal, 18)

                        Spacer(minLength: 40)
                    }
                }
                .scrollIndicators(.hidden)
                
                // Success Message Overlay
                if showSuccessMessage {
                    VStack {
                        Spacer()
                        
                        AmenLiquidWhiteSurface(cornerRadius: 999, shadow: .floating) {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.systemScaled(20))
                                    .foregroundStyle(.green)

                                Text("Profile photo updated")
                                    .font(AMENFont.semiBold(15))
                                    .foregroundStyle(.black)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                        }
                        .padding(.bottom, 100)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Profile Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        uploadPhoto()
                    } label: {
                        if isUploading {
                            ProgressView()
                        } else {
                            Text("Save")
                                .font(AMENFont.bold(16))
                        }
                    }
                    .disabled(selectedImage == nil || isUploading)
                }
            }
            .sheet(isPresented: $showCamera) {
                ImagePicker(sourceType: .camera, selectedImage: $rawPickedImage)
            }
            .fullScreenCover(isPresented: $showCropView) {
                if let raw = rawPickedImage {
                    ProfilePhotoCropView(
                        image: raw,
                        onCrop: { cropped in
                            selectedImage = cropped
                            showCropView = false
                        },
                        onCancel: {
                            rawPickedImage = nil
                            showCropView = false
                        }
                    )
                }
            }
            .alert("Photo Library Access Required", isPresented: $photoPermissionDenied) {
                Button("Cancel", role: .cancel) { }
                Button("Open Settings") {
                    openAppSettings()
                }
            } message: {
                Text("Please allow access to your photo library in Settings to choose a profile photo.")
            }
            .alert("Camera Access Required", isPresented: $cameraPermissionDenied) {
                Button("Cancel", role: .cancel) { }
                Button("Open Settings") {
                    openAppSettings()
                }
            } message: {
                Text("Please allow camera access in Settings to take a profile photo.")
            }
            .alert("Remove Photo?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Remove", role: .destructive) {
                    deletePhoto()
                }
            } message: {
                Text("Are you sure you want to remove your profile photo?")
            }
        }
        .onChange(of: selectedPhoto) { _, newPhoto in
            Task {
                if let data = try? await newPhoto?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        rawPickedImage = uiImage
                        showCropView = true
                    }
                }
            }
        }
        .onChange(of: rawPickedImage) { _, raw in
            // Camera path: ImagePicker sets rawPickedImage directly
            if raw != nil && !showCropView {
                showCropView = true
            }
        }
    }
    
    // MARK: - Permission Handling
    
    private func requestPhotoLibraryPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch status {
        case .authorized, .limited:
            // Already authorized - show photo picker
            showPhotoPermissionAlert = true
            
        case .notDetermined:
            // Request permission
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        showPhotoPermissionAlert = true
                        
                        // Haptic feedback
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.success)
                    } else {
                        photoPermissionDenied = true
                        
                        // Haptic feedback
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.warning)
                    }
                }
            }
            
        case .denied, .restricted:
            // Show alert to go to settings
            photoPermissionDenied = true
            
            // Haptic feedback
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.warning)
            
        @unknown default:
            photoPermissionDenied = true
        }
    }
    
    private func requestCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            // Already authorized - show camera
            showCamera = true
            
        case .notDetermined:
            // Request permission
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCamera = true
                        
                        // Haptic feedback
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.success)
                    } else {
                        cameraPermissionDenied = true
                        
                        // Haptic feedback
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.warning)
                    }
                }
            }
            
        case .denied, .restricted:
            // Show alert to go to settings
            cameraPermissionDenied = true
            
            // Haptic feedback
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.warning)
            
        @unknown default:
            cameraPermissionDenied = true
        }
    }
    
    private func openAppSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
    
    // MARK: - UI Components

    private var photoStatusText: String {
        if selectedImage != nil { return "New Photo" }
        if currentImageURL != nil { return "Current Photo" }
        return "No Photo"
    }

    @ViewBuilder
    private var currentPhotoView: some View {
        if let selectedImage {
            profilePhotoImage(Image(uiImage: selectedImage))
        } else if let currentImageURL, let url = URL(string: currentImageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    profilePhotoImage(image)
                case .empty, .failure:
                    placeholderImage
                @unknown default:
                    placeholderImage
                }
            }
        } else {
            placeholderImage
        }
    }

    private func profilePhotoImage(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFill()
            .frame(width: 214, height: 214)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.2)
            }
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 72, height: 72)
                    .blur(radius: 18)
                    .offset(x: 20, y: 18)
            }
            .shadow(color: .black.opacity(0.12), radius: 34, x: 0, y: 18)
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 238, height: 238)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.94), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 40, y: 18)
            }
    }
    
    private var placeholderImage: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .frame(width: 214, height: 214)
            .overlay {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.96),
                                Color.white.opacity(0.62),
                                Color.black.opacity(0.035)
                            ],
                            center: UnitPoint(x: 0.38, y: 0.24),
                            startRadius: 4,
                            endRadius: 118
                        )
                    )
            }
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "person.fill")
                        .font(.systemScaled(58, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.14))
                    
                    Text("No Photo")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.black.opacity(0.38))
                }
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.95), lineWidth: 1.2)
            }
            .shadow(color: .black.opacity(0.09), radius: 34, x: 0, y: 16)
    }
    
    private func tipRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.systemScaled(14))
                .foregroundStyle(color.opacity(0.82))
                .frame(width: 20)
            
            Text(text)
                .font(AMENFont.regular(14))
                .foregroundStyle(.black.opacity(0.72))
        }
    }
    
    // MARK: - Actions
    
    private func uploadPhoto() {
        guard let selectedImage = selectedImage else { return }
        
        isUploading = true
        
        Task {
            do {
                // Upload to Firebase Storage
                let imageURL = try await socialService.uploadProfilePicture(selectedImage)
                
                await MainActor.run {
                    isUploading = false
                    
                    // Show success message
                    withAnimation {
                        showSuccessMessage = true
                    }
                    
                    // Call completion handler
                    onPhotoUpdated(imageURL)
                    
                    // ✅ Post notification to update tab bar profile photo
                    NotificationCenter.default.post(
                        name: Notification.Name("profilePhotoUpdated"),
                        object: nil,
                        userInfo: ["profileImageURL": imageURL]
                    )
                    dlog("✅ Posted profilePhotoUpdated notification with URL: \(imageURL)")
                    
                    // Haptic feedback
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    
                    // Dismiss after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    dlog("❌ Error uploading photo: \(error)")
                    
                    // Haptic feedback
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
    
    private func deletePhoto() {
        isUploading = true
        
        Task {
            do {
                try await socialService.deleteProfilePicture()
                
                await MainActor.run {
                    isUploading = false
                    
                    // Show success message
                    withAnimation {
                        showSuccessMessage = true
                    }
                    
                    // Call completion handler with nil
                    onPhotoUpdated(nil)
                    
                    // ✅ Post notification to remove tab bar profile photo
                    NotificationCenter.default.post(
                        name: Notification.Name("profilePhotoUpdated"),
                        object: nil,
                        userInfo: ["profileImageURL": ""]
                    )
                    dlog("✅ Posted profilePhotoUpdated notification (photo removed)")
                    
                    // Haptic feedback
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    
                    // Dismiss after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    dlog("❌ Error deleting photo: \(error)")
                    
                    // Haptic feedback
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Image Picker (Camera)

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    ProfilePhotoEditView(
        currentImageURL: nil,
        onPhotoUpdated: { _ in }
    )
}

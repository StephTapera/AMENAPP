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
    @StateObject private var socialService = SocialService.shared
    @StateObject private var userService = UserService()
    
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
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
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Current/Selected Photo
                        VStack(spacing: 16) {
                            if let selectedImage = selectedImage {
                                // Newly selected photo
                                Image(uiImage: selectedImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 200, height: 200)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.black.opacity(0.1), lineWidth: 4)
                                    )
                                    .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
                                
                                Text("New Photo")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.secondary)
                                
                            } else if let currentImageURL = currentImageURL,
                                      let url = URL(string: currentImageURL) {
                                // Current photo from server
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 200, height: 200)
                                            .clipShape(Circle())
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.black.opacity(0.1), lineWidth: 4)
                                            )
                                            .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
                                    case .empty, .failure:
                                        placeholderImage
                                    @unknown default:
                                        placeholderImage
                                    }
                                }
                                
                                Text("Current Photo")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.secondary)
                                
                            } else {
                                // No photo
                                placeholderImage
                                
                                Text("No Photo")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 40)
                        
                        // Action Buttons
                        VStack(spacing: 16) {
                            // Choose from Library
                            Button {
                                requestPhotoLibraryPermission()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "photo.on.rectangle")
                                        .font(.system(size: 20, weight: .semibold))
                                    
                                    Text("Choose from Library")
                                        .font(.custom("OpenSans-Bold", size: 16))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.black)
                                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                                )
                            }
                            
                            // Take Photo (Camera)
                            Button {
                                requestCameraPermission()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                    
                                    Text("Take Photo")
                                        .font(.custom("OpenSans-Bold", size: 16))
                                }
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                            }
                            
                            // Delete Current Photo (if exists)
                            if currentImageURL != nil && selectedImage == nil {
                                Button {
                                    showDeleteConfirmation = true
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 20, weight: .semibold))
                                        
                                        Text("Remove Photo")
                                            .font(.custom("OpenSans-Bold", size: 16))
                                    }
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.red.opacity(0.1))
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Tips
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.orange)
                                
                                Text("Photo Tips")
                                    .font(.custom("OpenSans-Bold", size: 16))
                            }
                            
                            tipRow(icon: "checkmark.circle.fill", text: "Use a clear, recent photo of yourself", color: .green)
                            tipRow(icon: "checkmark.circle.fill", text: "Face should be clearly visible", color: .green)
                            tipRow(icon: "checkmark.circle.fill", text: "Good lighting works best", color: .green)
                            tipRow(icon: "xmark.circle.fill", text: "Avoid group photos", color: .red)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                        )
                        .padding(.horizontal, 20)
                        
                        Spacer(minLength: 40)
                    }
                }
                
                // Success Message Overlay
                if showSuccessMessage {
                    VStack {
                        Spacer()
                        
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.green)
                            
                            Text("Profile photo updated!")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                        )
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
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                    }
                    .disabled(selectedImage == nil || isUploading)
                }
            }
            .sheet(isPresented: $showCamera) {
                ImagePicker(sourceType: .camera, selectedImage: $selectedImage)
            }
            .sheet(isPresented: $showPhotoPermissionAlert) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    EmptyView()
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
                    selectedImage = uiImage
                }
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
    
    private var placeholderImage: some View {
        Circle()
            .fill(Color(.systemGray5))
            .frame(width: 200, height: 200)
            .overlay(
                VStack(spacing: 12) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    
                    Text("No Photo")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.secondary)
                }
            )
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.1), lineWidth: 4)
            )
    }
    
    private func tipRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 20)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.primary)
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
                    print("❌ Error uploading photo: \(error)")
                    
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
                    print("❌ Error deleting photo: \(error)")
                    
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

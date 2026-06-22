//
//  ProfilePicturePicker.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//

import SwiftUI
import PhotosUI

/// A view for selecting and uploading profile pictures
struct ProfilePicturePicker: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var socialService = SocialService.shared
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var rawPickedImage: UIImage?
    @State private var selectedImage: UIImage?
    @State private var showCropView = false
    @State private var isUploading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var onImageUploaded: ((String) -> Void)?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 32) {
                    if let selectedImage {
                        // Preview
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 280, height: 280)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.85), Color.white.opacity(0.30)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 3
                                    )
                            )
                            .shadow(color: .black.opacity(0.12), radius: 20, y: 10)

                        // Upload Button
                        Button {
                            uploadImage()
                        } label: {
                            HStack(spacing: 12) {
                                if isUploading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color(.systemBackground)))
                                } else {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.systemScaled(20))
                                }

                                Text(isUploading ? "Uploading..." : "Upload Photo")
                                    .font(AMENFont.bold(16))
                            }
                            .foregroundStyle(Color(.systemBackground))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color(.label), in: Capsule())
                        }
                        .disabled(isUploading)
                        .padding(.horizontal, 40)

                        // Change Photo Button
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Text("Choose Different Photo")
                                .font(AMENFont.semiBold(15))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(.regularMaterial, in: Capsule())
                                .padding(.horizontal, 40)
                        }

                    } else {
                        // Photo Picker
                        VStack(spacing: 24) {
                            Image(systemName: "person.crop.circle.fill.badge.plus")
                                .font(.systemScaled(100))
                                .foregroundStyle(.secondary)

                            VStack(spacing: 12) {
                                Text("Add Profile Photo")
                                    .font(AMENFont.bold(24))
                                    .foregroundStyle(.primary)

                                Text("Choose a photo that represents you")
                                    .font(AMENFont.regular(15))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }

                            PhotosPicker(selection: $selectedItem, matching: .images) {
                                HStack(spacing: 12) {
                                    Image(systemName: "photo.on.rectangle")
                                        .font(.systemScaled(18))

                                    Text("Choose Photo")
                                        .font(AMENFont.bold(16))
                                }
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(.primary.opacity(0.12), lineWidth: 1)
                                )
                            }
                            .padding(.horizontal, 40)
                        }
                    }

                    Spacer()
                }
                .padding(.top, 60)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(28))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    guard let item = newItem else { return }
                    // loadTransferable can return nil data, and UIImage(data:) can fail
                    // for unsupported formats or corrupted files. Show an error rather
                    // than silently discarding the selection.
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            rawPickedImage = image
                            showCropView = true
                        }
                    } else {
                        await MainActor.run {
                            errorMessage = "Couldn't load the selected photo. Please try a different image."
                            showError = true
                        }
                    }
                }
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
            .alert("Upload Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func uploadImage() {
        guard let image = selectedImage else { return }
        
        // Validate the image has valid data before attempting upload
        guard image.cgImage != nil || image.ciImage != nil else {
            errorMessage = "Invalid image format. Please try selecting a different photo."
            showError = true
            return
        }
        
        isUploading = true
        
        Task {
            do {
                let imageURL = try await socialService.uploadProfilePicture(image)
                
                await MainActor.run {
                    isUploading = false
                    onImageUploaded?(imageURL)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    // Provide user-friendly error messages
                    if error.localizedDescription.contains("compression") {
                        errorMessage = "Failed to process image. Please try a different photo or reduce the image size."
                    } else if error.localizedDescription.contains("network") {
                        errorMessage = "Network error. Please check your connection and try again."
                    } else {
                        errorMessage = error.localizedDescription
                    }
                    showError = true
                    dlog("❌ Profile picture upload failed: \(error)")
                }
            }
        }
    }
}

#Preview {
    ProfilePicturePicker()
}

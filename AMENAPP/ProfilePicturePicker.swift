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
                AmenLiquidWhiteBackdrop()
                
                VStack(spacing: 28) {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.systemScaled(16, weight: .bold))
                                .frame(width: 46, height: 46)
                        }
                        .buttonStyle(AmenLiquidWhiteCircleButtonStyle())

                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)

                    if let selectedImage {
                        // Preview
                        VStack(spacing: 18) {
                            Image(uiImage: selectedImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 238, height: 238)
                                .clipShape(Circle())
                                .overlay {
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.92), lineWidth: 1.2)
                                }
                                .overlay(alignment: .topLeading) {
                                    Circle()
                                        .fill(Color.white.opacity(0.56))
                                        .frame(width: 78, height: 78)
                                        .blur(radius: 20)
                                        .offset(x: 22, y: 20)
                                }
                                .shadow(color: .black.opacity(0.13), radius: 34, x: 0, y: 18)
                                .background {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .frame(width: 266, height: 266)
                                        .overlay {
                                            Circle()
                                                .strokeBorder(Color.white.opacity(0.94), lineWidth: 1)
                                        }
                                        .shadow(color: .black.opacity(0.08), radius: 40, y: 18)
                                }

                            Text("Preview")
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(.black.opacity(0.58))
                        }
                        
                        // Upload Button
                        AmenLiquidWhiteSurface(cornerRadius: 32, shadow: .floating) {
                            VStack(spacing: 14) {
                                Button {
                                    uploadImage()
                                } label: {
                                    if isUploading {
                                        HStack(spacing: 12) {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))

                                            Text("Uploading...")
                                                .font(AMENFont.bold(16))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 58)
                                    } else {
                                        AmenLiquidWhiteButtonLabel(title: "Upload Photo", systemImage: "arrow.up.circle.fill")
                                    }
                                }
                                .buttonStyle(AmenLiquidWhiteButtonStyle(kind: .primary))
                                .disabled(isUploading)

                                PhotosPicker(selection: $selectedItem, matching: .images) {
                                    AmenLiquidWhiteButtonLabel(title: "Choose Different Photo", systemImage: "photo.on.rectangle")
                                }
                                .buttonStyle(AmenLiquidWhiteButtonStyle(kind: .secondary))
                                .disabled(isUploading)
                            }
                            .padding(18)
                        }
                        .padding(.horizontal, 18)
                        
                    } else {
                        // Photo Picker
                        VStack(spacing: 26) {
                            ZStack(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 222, height: 222)
                                    .overlay {
                                        Circle()
                                            .fill(
                                                RadialGradient(
                                                    colors: [
                                                        Color.white.opacity(0.96),
                                                        Color.white.opacity(0.58),
                                                        Color.black.opacity(0.035)
                                                    ],
                                                    center: UnitPoint(x: 0.38, y: 0.24),
                                                    startRadius: 4,
                                                    endRadius: 118
                                                )
                                            )
                                    }
                                    .overlay {
                                        Image(systemName: "person.fill")
                                            .font(.systemScaled(62, weight: .semibold))
                                            .foregroundStyle(.black.opacity(0.14))
                                    }
                                    .overlay {
                                        Circle()
                                            .strokeBorder(Color.white.opacity(0.95), lineWidth: 1.1)
                                    }
                                    .shadow(color: .black.opacity(0.09), radius: 34, x: 0, y: 16)

                                Image(systemName: "plus")
                                    .font(.systemScaled(25, weight: .semibold))
                                    .foregroundStyle(.black)
                                    .frame(width: 64, height: 64)
                                    .background {
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                            .overlay {
                                                Circle()
                                                    .strokeBorder(Color.white.opacity(0.95), lineWidth: 1)
                                            }
                                            .shadow(color: .black.opacity(0.12), radius: 22, y: 12)
                                    }
                                    .offset(x: -12, y: -10)
                            }

                            VStack(spacing: 12) {
                                Text("Add Profile Photo")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundStyle(.black)
                                
                                Text("Choose a photo that represents you")
                                    .font(AMENFont.regular(15))
                                    .foregroundStyle(.black.opacity(0.56))
                                    .multilineTextAlignment(.center)
                            }
                            
                            AmenLiquidWhiteSurface(cornerRadius: 32, shadow: .floating) {
                                PhotosPicker(selection: $selectedItem, matching: .images) {
                                    AmenLiquidWhiteButtonLabel(title: "Choose Photo", systemImage: "photo.on.rectangle")
                                }
                                .buttonStyle(AmenLiquidWhiteButtonStyle(kind: .primary))
                                .padding(18)
                            }
                            .padding(.horizontal, 18)
                        }
                    }
                    
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
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

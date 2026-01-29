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
    @StateObject private var socialService = SocialService.shared
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isUploading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var onImageUploaded: ((String) -> Void)?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.08)
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
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.orange, Color(red: 1.0, green: 0.6, blue: 0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 4
                                    )
                            )
                            .shadow(color: .orange.opacity(0.3), radius: 20, y: 10)
                        
                        // Upload Button
                        Button {
                            uploadImage()
                        } label: {
                            HStack(spacing: 12) {
                                if isUploading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 20))
                                }
                                
                                Text(isUploading ? "Uploading..." : "Upload Photo")
                                    .font(.custom("OpenSans-Bold", size: 16))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 28)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.orange, Color(red: 1.0, green: 0.6, blue: 0.2)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: .orange.opacity(0.5), radius: 15, y: 8)
                            )
                        }
                        .disabled(isUploading)
                        .padding(.horizontal, 40)
                        
                        // Change Photo Button
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Text("Choose Different Photo")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        
                    } else {
                        // Photo Picker
                        VStack(spacing: 24) {
                            Image(systemName: "person.crop.circle.fill.badge.plus")
                                .font(.system(size: 100))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.orange, Color(red: 1.0, green: 0.6, blue: 0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            VStack(spacing: 12) {
                                Text("Add Profile Photo")
                                    .font(.custom("OpenSans-Bold", size: 24))
                                    .foregroundStyle(.white)
                                
                                Text("Choose a photo that represents you")
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                            }
                            
                            PhotosPicker(selection: $selectedItem, matching: .images) {
                                HStack(spacing: 12) {
                                    Image(systemName: "photo.on.rectangle")
                                        .font(.system(size: 18))
                                    
                                    Text("Choose Photo")
                                        .font(.custom("OpenSans-Bold", size: 16))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 28)
                                        .fill(Color.white.opacity(0.15))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 28)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
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
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImage = image
                    }
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
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

#Preview {
    ProfilePicturePicker()
}

//
//  OnboardingStepViews.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import SwiftUI
import PhotosUI

// MARK: - Display Name View

struct OnboardingDisplayNameView: View {
    @EnvironmentObject var coordinator: OnboardingCoordinator
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: coordinator.currentStep.icon)
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.top, 60)
            
            // Title and subtitle
            VStack(spacing: 8) {
                Text(coordinator.currentStep.title)
                    .font(.custom("OpenSans-Bold", size: 28))
                    .foregroundStyle(.black)
                
                Text(coordinator.currentStep.subtitle)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.black.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            
            // Input field
            VStack(alignment: .leading, spacing: 8) {
                Text("Display Name")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.black.opacity(0.6))
                    .padding(.horizontal, 20)
                
                TextField("Enter your name", text: $coordinator.userData.displayName)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isTextFieldFocused
                                    ? LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    : LinearGradient(
                                        colors: [Color.black.opacity(0.1)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                lineWidth: 2
                            )
                    )
                    .focused($isTextFieldFocused)
                    .autocorrectionDisabled()
                    .textContentType(.name)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Character count
            if !coordinator.userData.displayName.isEmpty {
                Text("\(coordinator.userData.displayName.count) characters")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.black.opacity(0.4))
            }
            
            Spacer()
        }
        .onAppear {
            // Auto-focus text field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
    }
}

// MARK: - Profile Photo View

struct OnboardingProfilePhotoView: View {
    @EnvironmentObject var coordinator: OnboardingCoordinator
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: coordinator.currentStep.icon)
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.top, 60)
            
            // Title and subtitle
            VStack(spacing: 8) {
                Text(coordinator.currentStep.title)
                    .font(.custom("OpenSans-Bold", size: 28))
                    .foregroundStyle(.black)
                
                Text(coordinator.currentStep.subtitle)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.black.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            
            // Profile photo preview
            ZStack {
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 160, height: 160)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 4
                                )
                        )
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.1), .purple.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 160, height: 160)
                        .overlay(
                            Text(coordinator.userData.displayName.prefix(2).uppercased())
                                .font(.custom("OpenSans-Bold", size: 48))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                }
                
                // Camera button overlay
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            showImagePicker = true
                        } label: {
                            Image(systemName: selectedImage == nil ? "camera.fill" : "pencil.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [.blue, .purple],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                )
                                .shadow(color: .blue.opacity(0.4), radius: 8, y: 4)
                        }
                    }
                }
                .frame(width: 160, height: 160)
            }
            .padding(.top, 20)
            
            // Hint text
            Text(selectedImage == nil ? "Tap to add a photo" : "Tap to change photo")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.black.opacity(0.5))
            
            Spacer()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { _, newImage in
            if let image = newImage {
                // Convert to data
                coordinator.userData.profileImage = image.jpegData(compressionQuality: 0.8)
            }
        }
    }
}

// MARK: - Bio View

struct OnboardingBioView: View {
    @EnvironmentObject var coordinator: OnboardingCoordinator
    @FocusState private var isTextEditorFocused: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: coordinator.currentStep.icon)
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.top, 60)
            
            // Title and subtitle
            VStack(spacing: 8) {
                Text(coordinator.currentStep.title)
                    .font(.custom("OpenSans-Bold", size: 28))
                    .foregroundStyle(.black)
                
                Text(coordinator.currentStep.subtitle)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.black.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            
            // Bio text editor
            VStack(alignment: .leading, spacing: 8) {
                Text("Bio (Optional)")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.black.opacity(0.6))
                    .padding(.horizontal, 20)
                
                ZStack(alignment: .topLeading) {
                    if coordinator.userData.bio.isEmpty {
                        Text("Share your testimony, interests, or what brings you to AMEN...")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.black.opacity(0.3))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                    
                    TextEditor(text: $coordinator.userData.bio)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .focused($isTextEditorFocused)
                }
                .frame(height: 150)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isTextEditorFocused
                                ? LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                : LinearGradient(
                                    colors: [Color.black.opacity(0.1)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                            lineWidth: 2
                        )
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Character count
            HStack {
                Spacer()
                Text("\(coordinator.userData.bio.count)/300")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.black.opacity(0.4))
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .onChange(of: coordinator.userData.bio) { _, newValue in
            // Limit to 300 characters
            if newValue.count > 300 {
                coordinator.userData.bio = String(newValue.prefix(300))
            }
        }
    }
}

// MARK: - Simple Image Picker Placeholder

struct ImagePickerView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedImage: UIImage?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 64))
                    .foregroundStyle(.black.opacity(0.3))
                    .padding(.top, 40)
                
                Text("Photo Picker")
                    .font(.custom("OpenSans-Bold", size: 20))
                
                Text("In production, this would open the system photo picker")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                // Demo: Select a placeholder image
                Button {
                    // Create a placeholder image with initials
                    let renderer = ImageRenderer(content: PlaceholderImageView())
                    if let image = renderer.uiImage {
                        selectedImage = image
                        dismiss()
                    }
                } label: {
                    Text("Use Placeholder Image")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .navigationTitle("Select Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct PlaceholderImageView: View {
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 300, height: 300)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(.white)
            )
    }
}

#Preview("Display Name") {
    OnboardingDisplayNameView()
        .environmentObject(OnboardingCoordinator())
}

#Preview("Profile Photo") {
    OnboardingProfilePhotoView()
        .environmentObject(OnboardingCoordinator())
}

#Preview("Bio") {
    OnboardingBioView()
        .environmentObject(OnboardingCoordinator())
}

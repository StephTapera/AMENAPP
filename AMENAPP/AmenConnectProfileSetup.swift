//
//  AmenConnectProfileSetup.swift
//  AMENAPP
//
//  Created by Steph on 1/14/26.
//

import SwiftUI
import PhotosUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

struct AmenConnectProfileSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ProfileSetupViewModel()
    
    // ✅ FIX CR-15: Email verification gate
    @State private var isEmailVerified = false
    @State private var showEmailVerificationAlert = false
    @State private var isCheckingVerification = true
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Create Your Profile")
                            .font(.custom("OpenSans-Bold", size: 28))
                            .foregroundStyle(.primary)
                        
                        Text("Let others know who you are and what you're looking for")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Profile Photo Section
                    let profileImage = viewModel.profileImage
                    VStack(spacing: 12) {
                        PhotosPicker(selection: $viewModel.selectedPhoto, matching: .images) {
                            ZStack {
                                if let image = profileImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 140, height: 140)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    LinearGradient(
                                                        colors: [.pink, .purple],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 3
                                                )
                                        )
                                } else {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .frame(width: 140, height: 140)
                                        .overlay(Circle().stroke(.primary.opacity(0.10), lineWidth: 1))
                                        .overlay(
                                            VStack(spacing: 8) {
                                                Image(systemName: "camera.fill")
                                                    .font(.systemScaled(32))
                                                    .foregroundStyle(.secondary)

                                                Text("Add Photo")
                                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                                    .foregroundStyle(.secondary)
                                            }
                                        )
                                }
                                
                                // Edit button overlay
                                if profileImage != nil {
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Spacer()
                                            Circle()
                                                .fill(.ultraThinMaterial)
                                                .frame(width: 36, height: 36)
                                                .overlay(
                                                    Image(systemName: "pencil")
                                                        .font(.systemScaled(14))
                                                        .foregroundStyle(.primary)
                                                )
                                                .overlay(Circle().stroke(.primary.opacity(0.12), lineWidth: 1))
                                        }
                                    }
                                    .frame(width: 140, height: 140)
                                }
                            }
                        }
                        
                        Text("Upload your best photo")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                    
                    // Form Fields
                    VStack(spacing: 20) {
                        // Basic Info Section
                        SectionHeader(title: "Basic Information")
                        
                        ProfileTextField(
                            title: "Name",
                            text: $viewModel.name,
                            placeholder: "Enter your name"
                        )
                        
                        HStack(spacing: 16) {
                            ProfileTextField(
                                title: "Birth Year",
                                text: Binding(
                                    get: { viewModel.birthYear == 0 ? "" : "\(viewModel.birthYear)" },
                                    set: { viewModel.birthYear = Int($0) ?? 0 }
                                ),
                                placeholder: "1990",
                                keyboardType: .numberPad
                            )
                            
                            ProfileTextField(
                                title: "Age",
                                text: Binding(
                                    get: { viewModel.age == 0 ? "" : "\(viewModel.age)" },
                                    set: { viewModel.age = Int($0) ?? 0 }
                                ),
                                placeholder: "25",
                                keyboardType: .numberPad
                            )
                        }
                        
                        // Bio Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About You")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.primary)
                            
                            ZStack(alignment: .topLeading) {
                                if viewModel.bio.isEmpty {
                                    Text("Tell others about yourself, your interests, and what you're looking for...")
                                        .font(.custom("OpenSans-Regular", size: 15))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 14)
                                }
                                
                                TextEditor(text: $viewModel.bio)
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .foregroundStyle(.primary)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 120)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(.systemGray6))
                            )
                            
                            Text("\(viewModel.bio.count)/500")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        
                        // Faith Information Section
                        SectionHeader(title: "Faith Journey")
                        
                        HStack(spacing: 16) {
                            ProfileTextField(
                                title: "Years Saved",
                                text: Binding(
                                    get: { viewModel.yearsSaved == 0 ? "" : "\(viewModel.yearsSaved)" },
                                    set: { viewModel.yearsSaved = Int($0) ?? 0 }
                                ),
                                placeholder: "5",
                                keyboardType: .numberPad
                            )
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Baptized")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                    .foregroundStyle(.primary)
                                
                                Toggle("", isOn: $viewModel.isBaptized)
                                    .labelsHidden()
                                    .tint(.accentColor)
                            }
                        }
                        
                        ProfileTextField(
                            title: "Denomination (Optional)",
                            text: Binding(
                                get: { viewModel.denomination ?? "" },
                                set: { viewModel.denomination = $0.isEmpty ? nil : $0 }
                            ),
                            placeholder: "e.g., Baptist, Non-denominational"
                        )
                        
                        // Church Information Section
                        SectionHeader(title: "Church Information")
                        
                        ProfileTextField(
                            title: "Church Name",
                            text: $viewModel.churchName,
                            placeholder: "Enter your church name"
                        )
                        
                        HStack(spacing: 16) {
                            ProfileTextField(
                                title: "City",
                                text: $viewModel.churchCity,
                                placeholder: "City"
                            )
                            
                            ProfileTextField(
                                title: "State",
                                text: $viewModel.churchState,
                                placeholder: "TX"
                            )
                        }
                        
                        // Looking For Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("I'm Looking For")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.primary)
                            
                            HStack(spacing: 12) {
                                ForEach(["Fellowship", "Dating", "Friendship"], id: \.self) { option in
                                    Button {
                                        viewModel.lookingFor = option
                                    } label: {
                                        Text(option)
                                            .font(.custom("OpenSans-SemiBold", size: 14))
                                            .foregroundStyle(viewModel.lookingFor == option ? Color(.systemBackground) : .primary)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 12)
                                            .background(
                                                viewModel.lookingFor == option
                                                ? AnyShapeStyle(Color(.label))
                                                : AnyShapeStyle(.regularMaterial),
                                                in: RoundedRectangle(cornerRadius: 20)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .stroke(.primary.opacity(0.10), lineWidth: 1)
                                            )
                                    }
                                }
                            }
                        }
                        
                        // Interests Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Interests (Select up to 5)")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.primary)
                            
                            let allInterests = [
                                "Worship", "Music", "Photography", "Literature",
                                "Outdoor", "Design", "Diving", "Technology",
                                "Sports", "Cooking", "Travel", "Art",
                                "Fitness", "Volunteering", "Youth Ministry"
                            ]
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                                ForEach(allInterests, id: \.self) { interest in
                                    Button {
                                        if viewModel.interests.contains(interest) {
                                            viewModel.interests.removeAll { $0 == interest }
                                        } else if viewModel.interests.count < 5 {
                                            viewModel.interests.append(interest)
                                        }
                                    } label: {
                                        Text(interest)
                                            .font(.custom("OpenSans-SemiBold", size: 13))
                                            .foregroundStyle(
                                                viewModel.interests.contains(interest) ? Color(.systemBackground) : .primary
                                            )
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .background(
                                                viewModel.interests.contains(interest)
                                                ? AnyShapeStyle(Color(.label))
                                                : AnyShapeStyle(.regularMaterial),
                                                in: RoundedRectangle(cornerRadius: 16)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16)
                                                    .stroke(.primary.opacity(0.10), lineWidth: 1)
                                            )
                                    }
                                }
                            }
                        }
                    }
                    
                    // Save Button
                    Button {
                        if !viewModel.isSaving {
                            viewModel.saveProfile()
                            // Only dismiss if save succeeds (handle in saveProfile)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isSaving {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(viewModel.isSaving ? "Saving..." : "Save Profile")
                                .font(.custom("OpenSans-Bold", size: 17))
                            
                            Image(systemName: "checkmark.circle.fill")
                                .font(.systemScaled(20))
                        }
                        .foregroundStyle(
                            viewModel.isProfileValid ? Color(.systemBackground) : Color(.secondaryLabel)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            viewModel.isProfileValid
                            ? AnyShapeStyle(Color(.label))
                            : AnyShapeStyle(Color(.systemGray4)),
                            in: Capsule()
                        )
                    }
                    .disabled(!viewModel.isProfileValid || viewModel.isSaving)
                    .padding(.top, 12)
                    .alert("Error", isPresented: $viewModel.showError) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(viewModel.errorMessage ?? "An error occurred")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.systemScaled(16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            // ✅ FIX CR-15: Check email verification on appear
            .task {
                await checkEmailVerification()
            }
            // ✅ FIX CR-15: Block profile setup if email not verified
            .blur(radius: isEmailVerified || isCheckingVerification ? 0 : 20)
            .overlay {
                if !isEmailVerified && !isCheckingVerification {
                    VStack(spacing: 24) {
                        Image(systemName: "envelope.badge.shield.half.filled")
                            .font(.systemScaled(60))
                            .foregroundStyle(.secondary)
                        
                        VStack(spacing: 12) {
                            Text("Verify Your Email")
                                .font(.custom("OpenSans-Bold", size: 24))
                                .foregroundStyle(.primary)
                            
                            Text("Please verify your email address before setting up your profile. Check your inbox for a verification link.")
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        
                        VStack(spacing: 12) {
                            Button {
                                Task {
                                    await sendVerificationEmail()
                                }
                            } label: {
                                Text("Resend Verification Email")
                                    .font(.custom("OpenSans-Bold", size: 16))
                                    .foregroundStyle(Color(.systemBackground))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color(.label), in: Capsule())
                            }
                            .padding(.horizontal, 32)

                            Button {
                                Task {
                                    await checkEmailVerification()
                                }
                            } label: {
                                Text("I've Verified My Email")
                                    .font(.custom("OpenSans-SemiBold", size: 16))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                }
            }
            .alert("Email Sent", isPresented: $showEmailVerificationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("A verification email has been sent. Please check your inbox and spam folder.")
            }
        }
    }
    
    // ✅ FIX CR-15: Check email verification status
    private func checkEmailVerification() async {
        isCheckingVerification = true
        
        // Reload user to get fresh verification status
        try? await Auth.auth().currentUser?.reload()
        
        await MainActor.run {
            isEmailVerified = Auth.auth().currentUser?.isEmailVerified ?? false
            isCheckingVerification = false
            
            if !isEmailVerified {
                dlog("⚠️ Email not verified - blocking profile setup")
            }
        }
    }
    
    // ✅ FIX CR-15: Send verification email
    private func sendVerificationEmail() async {
        guard let user = Auth.auth().currentUser else { return }
        
        do {
            try await user.sendEmailVerification()
            await MainActor.run {
                showEmailVerificationAlert = true
            }
            dlog("✅ Verification email sent")
        } catch {
            dlog("❌ Failed to send verification email: \(error)")
            await MainActor.run {
                viewModel.errorMessage = "Failed to send verification email. Please try again."
                viewModel.showError = true
            }
        }
    }
}

// MARK: - Supporting Views

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.custom("OpenSans-Bold", size: 18))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

struct ProfileTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.custom("OpenSans-SemiBold", size: 15))
                .foregroundStyle(.primary)
            
            TextField(placeholder, text: $text)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.systemGray6))
                )
                .keyboardType(keyboardType)
        }
    }
}

// MARK: - ViewModel

@MainActor
class ProfileSetupViewModel: ObservableObject {
    @Published var selectedPhoto: PhotosPickerItem?
    @Published var profileImage: UIImage?
    
    // Basic Info
    @Published var name: String = ""
    @Published var age: Int = 0
    @Published var birthYear: Int = 0
    @Published var bio: String = ""
    
    // Faith Info
    @Published var yearsSaved: Int = 0
    @Published var isBaptized: Bool = false
    @Published var denomination: String?
    
    // Church Info
    @Published var churchName: String = ""
    @Published var churchCity: String = ""
    @Published var churchState: String = ""
    
    // Preferences
    @Published var lookingFor: String = "Fellowship"
    @Published var interests: [String] = []
    
    // ✅ FIX CR-11: Error handling state
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var isSaving = false
    
    var isProfileValid: Bool {
        !name.isEmpty &&
        age > 0 &&
        birthYear > 0 &&
        !bio.isEmpty &&
        !churchName.isEmpty &&
        !churchCity.isEmpty &&
        !churchState.isEmpty &&
        profileImage != nil
    }
    
    init() {
        // Watch for photo selection changes
        Task { @MainActor in
            for await newValue in $selectedPhoto.values {
                if let newValue {
                    await loadImage(from: newValue)
                }
            }
        }
    }
    
    private func loadImage(from item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                self.profileImage = image
            }
        } catch {
            dlog("Error loading image: \(error)")
        }
    }
    
    func saveProfile() {
        Task { @MainActor in
            isSaving = true
            do {
                try await self.performSave()
                isSaving = false
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func performSave() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ProfileSetup", code: -2, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        lazy var db = Firestore.firestore()
        var photoURL: String? = nil

        // Upload profile photo to Firebase Storage if one was selected
        if let imageData = profileImage?.jpegData(compressionQuality: 0.8) {
            let storageRef = Storage.storage().reference()
                .child("amenConnect/\(userId)/profile.jpg")
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"

            do {
                _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
                photoURL = try await storageRef.downloadURL().absoluteString
            } catch {
                // ✅ FIX CR-11: Throw error instead of silent failure
                dlog("❌ AmenConnect: Photo upload failed — \(error.localizedDescription)")
                throw NSError(
                    domain: "ProfileSetup",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to upload profile photo. Please check your connection and try again."]
                )
            }
        }

        var profileData: [String: Any] = [
            "name": name,
            "age": age,
            "birthYear": birthYear,
            "bio": bio,
            "yearsSaved": yearsSaved,
            "isBaptized": isBaptized,
            "churchName": churchName,
            "churchCity": churchCity,
            "churchState": churchState,
            "interests": interests,
            "lookingFor": lookingFor,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let denomination = denomination { profileData["denomination"] = denomination }
        if let url = photoURL { profileData["profilePhotoURL"] = url }

        do {
            try await db.collection("amenConnect").document(userId).setData(profileData, merge: true)
            dlog("✅ AmenConnect: Profile saved for user \(userId)")
        } catch {
            dlog("❌ AmenConnect: Failed to save profile — \(error.localizedDescription)")
            throw NSError(
                domain: "ProfileSetup",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to save profile data. Please try again."]
            )
        }
    }
}

#Preview {
    AmenConnectProfileSetupView()
}

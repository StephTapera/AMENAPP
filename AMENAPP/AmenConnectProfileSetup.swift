//
//  AmenConnectProfileSetup.swift
//  AMENAPP
//
//  Created by Steph on 1/14/26.
//

import SwiftUI
import PhotosUI
import Combine

struct AmenConnectProfileSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ProfileSetupViewModel()
    
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
                    VStack(spacing: 12) {
                        PhotosPicker(selection: $viewModel.selectedPhoto, matching: .images) {
                            ZStack {
                                if let image = viewModel.profileImage {
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
                                        .fill(Color(.systemGray5))
                                        .frame(width: 140, height: 140)
                                        .overlay(
                                            VStack(spacing: 8) {
                                                Image(systemName: "camera.fill")
                                                    .font(.system(size: 32))
                                                    .foregroundStyle(.secondary)
                                                
                                                Text("Add Photo")
                                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                                    .foregroundStyle(.secondary)
                                            }
                                        )
                                }
                                
                                // Edit button overlay
                                if viewModel.profileImage != nil {
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Spacer()
                                            Circle()
                                                .fill(Color.pink)
                                                .frame(width: 36, height: 36)
                                                .overlay(
                                                    Image(systemName: "pencil")
                                                        .font(.system(size: 14))
                                                        .foregroundStyle(.white)
                                                )
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
                                    .tint(.pink)
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
                                            .foregroundStyle(viewModel.lookingFor == option ? .white : .primary)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .fill(
                                                        viewModel.lookingFor == option ?
                                                        LinearGradient(
                                                            colors: [.pink, .purple],
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        ) :
                                                        LinearGradient(
                                                            colors: [Color(.systemGray6), Color(.systemGray6)],
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                    )
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
                                                viewModel.interests.contains(interest) ? .white : .primary
                                            )
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 16)
                                                    .fill(
                                                        viewModel.interests.contains(interest) ?
                                                        Color.pink : Color(.systemGray6)
                                                    )
                                            )
                                    }
                                }
                            }
                        }
                    }
                    
                    // Save Button
                    Button {
                        viewModel.saveProfile()
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Text("Save Profile")
                                .font(.custom("OpenSans-Bold", size: 17))
                            
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    viewModel.isProfileValid ?
                                    LinearGradient(
                                        colors: [.pink, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ) :
                                    LinearGradient(
                                        colors: [Color(.systemGray4), Color(.systemGray4)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(
                                    color: viewModel.isProfileValid ? .pink.opacity(0.4) : .clear,
                                    radius: 12,
                                    y: 6
                                )
                        )
                    }
                    .disabled(!viewModel.isProfileValid)
                    .padding(.top, 12)
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
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
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
        Task {
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
            print("Error loading image: \(error)")
        }
    }
    
    func saveProfile() {
        // Convert image to data
        let photoData = profileImage?.jpegData(compressionQuality: 0.8)
        
        let profile = AmenConnectProfile(
            name: name,
            age: age,
            birthYear: birthYear,
            bio: bio,
            profilePhoto: photoData,
            yearsSaved: yearsSaved,
            isBaptized: isBaptized,
            churchName: churchName,
            churchCity: churchCity,
            churchState: churchState,
            interests: interests,
            denomination: denomination,
            lookingFor: lookingFor
        )
        
        // TODO: Save to backend/database
        print("Profile saved: \(profile)")
    }
}

#Preview {
    AmenConnectProfileSetupView()
}

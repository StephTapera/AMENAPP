//
//  UsernameSelectionView.swift
//  AMENAPP
//
//  Username and display name selection for social sign-in users
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct UsernameSelectionView: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    @Environment(\.colorScheme) var colorScheme
    
    @State private var displayName = ""
    @State private var username = ""
    @State private var isCheckingUsername = false
    @State private var usernameAvailable: Bool?
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var usernameCheckTask: Task<Void, Never>?
    
    private var isFormValid: Bool {
        !displayName.isEmpty &&
        username.count >= 3 &&
        username.count <= 20 &&
        usernameAvailable == true &&
        !isSaving
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // Icon
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue.opacity(0.9))
                    .symbolEffect(.pulse, options: .repeating)
                
                // Title
                VStack(spacing: 12) {
                    Text("Customize Your Profile")
                        .font(.custom("OpenSans-Bold", size: 28))
                        .foregroundStyle(.white)
                    
                    Text("Choose your display name and unique username")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                Spacer()
                
                // Form Fields
                VStack(spacing: 20) {
                    // Display Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Display Name")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                        
                        TextField("John Doe", text: $displayName)
                            .font(.custom("OpenSans-Regular", size: 16))
                            .foregroundStyle(.white)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.white.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                            .autocapitalization(.words)
                    }
                    
                    // Username
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Username")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                        
                        HStack(spacing: 12) {
                            HStack {
                                Text("@")
                                    .font(.custom("OpenSans-Regular", size: 16))
                                    .foregroundStyle(.white.opacity(0.5))
                                
                                TextField("johndoe", text: $username)
                                    .font(.custom("OpenSans-Regular", size: 16))
                                    .foregroundStyle(.white)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.white.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                            
                            // Availability Indicator
                            Group {
                                if isCheckingUsername {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else if let available = usernameAvailable {
                                    Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(available ? .green : .red)
                                        .font(.system(size: 24))
                                }
                            }
                            .frame(width: 24, height: 24)
                        }
                        
                        // Username validation message
                        if !username.isEmpty {
                            if username.count < 3 {
                                Text("Username must be at least 3 characters")
                                    .font(.custom("OpenSans-Regular", size: 11))
                                    .foregroundStyle(.orange)
                            } else if username.count > 20 {
                                Text("Username must be 20 characters or less")
                                    .font(.custom("OpenSans-Regular", size: 11))
                                    .foregroundStyle(.orange)
                            } else if !isValidUsername(username) {
                                Text("Only letters, numbers, and underscores allowed")
                                    .font(.custom("OpenSans-Regular", size: 11))
                                    .foregroundStyle(.orange)
                            } else if usernameAvailable == false {
                                Text("@\(username) is already taken")
                                    .font(.custom("OpenSans-Regular", size: 11))
                                    .foregroundStyle(.red)
                            } else if usernameAvailable == true {
                                Text("@\(username) is available!")
                                    .font(.custom("OpenSans-Regular", size: 11))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Continue Button
                Button {
                    saveUsername()
                } label: {
                    HStack(spacing: 12) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        } else {
                            Text("Continue")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                        }
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 26)
                            .fill(isFormValid ? .white : .white.opacity(0.3))
                    )
                }
                .disabled(!isFormValid)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            loadUserData()
        }
        .onChange(of: username) { _, newValue in
            checkUsernameAvailability(newValue)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .interactiveDismissDisabled()  // Cannot be dismissed - must complete
    }
    
    private func loadUserData() {
        guard let user = Auth.auth().currentUser else { return }
        
        // Pre-fill display name from social provider
        displayName = user.displayName ?? ""
        
        // Suggest username from email or random
        if let email = user.email {
            let emailPrefix = email.components(separatedBy: "@").first ?? ""
            let cleanUsername = emailPrefix.replacingOccurrences(of: "[^a-zA-Z0-9_]", with: "", options: .regularExpression)
            username = String(cleanUsername.prefix(20))
        }
        
        // If no suggestion, start empty
        if username.isEmpty || username.hasPrefix("user") {
            username = ""
        }
    }
    
    private func isValidUsername(_ username: String) -> Bool {
        let usernameRegex = "^[a-zA-Z0-9_]{3,20}$"
        return NSPredicate(format: "SELF MATCHES %@", usernameRegex).evaluate(with: username)
    }
    
    private func checkUsernameAvailability(_ username: String) {
        // Cancel previous task
        usernameCheckTask?.cancel()
        
        // Reset state
        usernameAvailable = nil
        
        // Validate format first
        guard isValidUsername(username) else {
            return
        }
        
        // Debounce checking
        usernameCheckTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms delay
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                isCheckingUsername = true
            }
            
            // Check Firestore
            let db = Firestore.firestore()
            let usernameLower = username.lowercased()
            
            do {
                let snapshot = try await db.collection("users")
                    .whereField("usernameLowercase", isEqualTo: usernameLower)
                    .limit(to: 1)
                    .getDocuments()
                
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    // Check if the result is the current user (editing their own username)
                    let isCurrentUser = snapshot.documents.first?.documentID == Auth.auth().currentUser?.uid
                    usernameAvailable = snapshot.documents.isEmpty || isCurrentUser
                    isCheckingUsername = false
                }
                
            } catch {
                print("❌ Error checking username: \(error.localizedDescription)")
                await MainActor.run {
                    usernameAvailable = nil  // Allow nil state on error
                    isCheckingUsername = false
                }
            }
        }
    }
    
    private func saveUsername() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isSaving = true
        
        Task {
            do {
                let db = Firestore.firestore()
                let usernameLower = username.lowercased()
                let displayNameLower = displayName.lowercased()
                
                // Generate initials
                let initials = displayName
                    .components(separatedBy: " ")
                    .prefix(2)
                    .compactMap { $0.first }
                    .map { String($0).uppercased() }
                    .joined()
                
                // Generate name keywords for search
                let nameKeywords = generateNameKeywords(displayName: displayName, username: username)
                
                // Update Firestore
                try await db.collection("users").document(userId).updateData([
                    "displayName": displayName,
                    "displayNameLowercase": displayNameLower,
                    "username": username,
                    "usernameLowercase": usernameLower,
                    "initials": initials,
                    "nameKeywords": nameKeywords,
                    "usernameUpdatedAt": Timestamp(date: Date())
                ])
                
                print("✅ Username and display name updated successfully")
                
                // Mark selection complete
                await MainActor.run {
                    isSaving = false
                    viewModel.completeUsernameSelection()
                }
                
            } catch {
                print("❌ Failed to save username: \(error.localizedDescription)")
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save username. Please try again."
                    showError = true
                }
            }
        }
    }
    
    private func generateNameKeywords(displayName: String, username: String) -> [String] {
        var keywords = Set<String>()
        
        // Add full display name
        keywords.insert(displayName.lowercased())
        
        // Add username
        keywords.insert(username.lowercased())
        
        // Add individual words from display name
        let words = displayName.lowercased().components(separatedBy: " ")
        words.forEach { word in
            if !word.isEmpty {
                keywords.insert(word)
            }
        }
        
        // Add combinations of first and last name
        if words.count >= 2 {
            keywords.insert("\(words[0]) \(words[1])")
        }
        
        return Array(keywords)
    }
}

#Preview {
    UsernameSelectionView()
        .environmentObject(AuthenticationViewModel())
}

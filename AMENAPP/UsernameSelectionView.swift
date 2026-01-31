//
//  UsernameSelectionView.swift
//  AMENAPP
//
//  Production-ready username and display name selection for social sign-in users
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct UsernameSelectionView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var displayName: String = ""
    @State private var username: String = ""
    @State private var isCheckingUsername = false
    @State private var usernameAvailable: Bool?
    @State private var usernameCheckTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        ZStack {
            // Soft gradient background matching app design
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.94, blue: 0.98),
                    Color(red: 0.98, green: 0.95, blue: 0.97),
                    Color(red: 1.0, green: 0.97, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 32) {
                    Spacer()
                        .frame(height: 40)
                    
                    // Header
                    VStack(spacing: 16) {
                        // Icon
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.blue.opacity(0.15),
                                            Color.purple.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        Text("One Last Thing")
                            .font(.custom("OpenSans-Bold", size: 28))
                            .foregroundStyle(.black)
                        
                        Text("Choose your display name and username")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.black.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    
                    // Input Fields
                    VStack(spacing: 16) {
                        // Display Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Display Name")
                                .font(.custom("OpenSans-SemiBold", size: 13))
                                .foregroundStyle(.black.opacity(0.7))
                                .padding(.horizontal, 4)
                            
                            CleanTextField(
                                icon: "person.fill",
                                placeholder: "Your Name",
                                text: $displayName,
                                keyboardType: .default
                            )
                        }
                        
                        // Username
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username")
                                .font(.custom("OpenSans-SemiBold", size: 13))
                                .foregroundStyle(.black.opacity(0.7))
                                .padding(.horizontal, 4)
                            
                            UsernameTextField(
                                text: $username,
                                isChecking: $isCheckingUsername,
                                isAvailable: $usernameAvailable
                            )
                            .onChange(of: username) { _, newValue in
                                checkUsernameAvailability(newValue)
                            }
                        }
                        
                        // Info box
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.blue.opacity(0.7))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your username is how others will find you")
                                    .font(.custom("OpenSans-SemiBold", size: 12))
                                    .foregroundStyle(.black)
                                
                                Text("You can change these later in your profile settings")
                                    .font(.custom("OpenSans-Regular", size: 11))
                                    .foregroundStyle(.black.opacity(0.6))
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.08))
                        )
                    }
                    .padding(.horizontal, 32)
                    
                    // Continue Button
                    Button {
                        saveUsernameAndContinue()
                    } label: {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Continue")
                                    .font(.custom("OpenSans-Bold", size: 16))
                                
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 16, weight: .bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 26)
                                .fill(.black)
                                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                        )
                    }
                    .disabled(!isFormValid || isSaving)
                    .opacity(isFormValid ? 1.0 : 0.5)
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
                    
                    Spacer()
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            loadCurrentUserInfo()
        }
        .interactiveDismissDisabled(true) // Prevent dismissal - user must complete this
    }
    
    // MARK: - Form Validation
    
    private var isFormValid: Bool {
        // Display name must not be empty
        guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }
        
        // Username must not be empty and valid format
        guard !username.isEmpty, isValidUsernameFormat(username) else {
            return false
        }
        
        // Username must be available (or still checking - we allow that for better UX)
        return usernameAvailable == true || usernameAvailable == nil
    }
    
    // MARK: - Load Current User Info
    
    /// Pre-fill fields with info from social sign-in
    private func loadCurrentUserInfo() {
        Task {
            guard let userId = FirebaseManager.shared.currentUser?.uid else { return }
            
            do {
                let userData = try await FirebaseManager.shared.fetchUserDocument(userId: userId)
                
                await MainActor.run {
                    // Pre-fill display name from social provider
                    if let name = userData["displayName"] as? String, !name.isEmpty {
                        displayName = name
                    }
                    
                    // Pre-fill username suggestion
                    if let suggestedUsername = userData["username"] as? String, !suggestedUsername.isEmpty {
                        username = suggestedUsername
                        // Check if it's available
                        checkUsernameAvailability(suggestedUsername)
                    }
                }
            } catch {
                print("⚠️ Failed to load user info: \(error)")
            }
        }
    }
    
    // MARK: - Username Validation
    
    private func checkUsernameAvailability(_ username: String) {
        // Cancel any existing check
        usernameCheckTask?.cancel()
        
        // Clean the username
        let cleaned = username.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Only check if username is valid format
        guard isValidUsernameFormat(cleaned) else {
            usernameAvailable = nil
            isCheckingUsername = false
            return
        }
        
        // Start checking
        isCheckingUsername = true
        
        // Create new task
        usernameCheckTask = Task {
            // Small delay to avoid checking on every keystroke
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Check if cancelled
            guard !Task.isCancelled else {
                await MainActor.run {
                    isCheckingUsername = false
                }
                return
            }
            
            do {
                let db = Firestore.firestore()
                let snapshot = try await db.collection("users")
                    .whereField("username", isEqualTo: cleaned)
                    .limit(to: 1)
                    .getDocuments()
                
                // Check if this username belongs to current user (editing existing)
                let currentUserId = FirebaseManager.shared.currentUser?.uid
                let isOwnUsername = snapshot.documents.first?.documentID == currentUserId
                
                let available = snapshot.documents.isEmpty || isOwnUsername
                
                // Only update if not cancelled
                guard !Task.isCancelled else {
                    await MainActor.run {
                        isCheckingUsername = false
                    }
                    return
                }
                
                await MainActor.run {
                    usernameAvailable = available
                    isCheckingUsername = false
                }
            } catch {
                await MainActor.run {
                    usernameAvailable = nil
                    isCheckingUsername = false
                }
            }
        }
    }
    
    private func isValidUsernameFormat(_ username: String) -> Bool {
        let usernameRegex = "^[a-z0-9_]{3,20}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", usernameRegex)
        return predicate.evaluate(with: username.lowercased())
    }
    
    // MARK: - Save and Continue
    
    private func saveUsernameAndContinue() {
        guard isFormValid else { return }
        
        isSaving = true
        
        Task {
            do {
                guard let userId = FirebaseManager.shared.currentUser?.uid else {
                    throw NSError(domain: "UsernameSelection", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user logged in"])
                }
                
                let cleanedUsername = username.lowercased().trimmingCharacters(in: .whitespaces)
                let cleanedDisplayName = displayName.trimmingCharacters(in: .whitespaces)
                
                // Create initials from display name
                let names = cleanedDisplayName.components(separatedBy: " ")
                let firstName = names.first ?? ""
                let lastName = names.count > 1 ? names.last ?? "" : ""
                let initials = "\(firstName.prefix(1))\(lastName.prefix(1))".uppercased()
                
                // Create searchable keywords
                let nameKeywords = createNameKeywords(from: cleanedDisplayName)
                
                print("💾 Updating user profile with username and display name...")
                print("   - Display Name: \(cleanedDisplayName)")
                print("   - Username: @\(cleanedUsername)")
                print("   - Initials: \(initials)")
                
                // Update Firestore
                try await FirebaseManager.shared.firestore
                    .collection("users")
                    .document(userId)
                    .updateData([
                        "displayName": cleanedDisplayName,
                        "displayNameLowercase": cleanedDisplayName.lowercased(),
                        "username": cleanedUsername,
                        "usernameLowercase": cleanedUsername,
                        "initials": initials,
                        "nameKeywords": nameKeywords,
                        "updatedAt": Timestamp(date: Date())
                    ])
                
                print("✅ User profile updated successfully!")
                
                // Sync to Algolia for search
                do {
                    let userData: [String: Any] = [
                        "displayName": cleanedDisplayName,
                        "displayNameLowercase": cleanedDisplayName.lowercased(),
                        "username": cleanedUsername,
                        "usernameLowercase": cleanedUsername,
                        "initials": initials,
                        "nameKeywords": nameKeywords
                    ]
                    try await AlgoliaSyncService.shared.syncUser(userId: userId, userData: userData)
                    print("✅ User synced to Algolia for search")
                } catch {
                    print("⚠️ Algolia sync failed (non-critical): \(error)")
                }
                
                // Cache user name for messaging
                await FirebaseMessagingService.shared.fetchAndCacheCurrentUserName()
                
                await MainActor.run {
                    isSaving = false
                    
                    // Success haptic
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    
                    // Continue to regular onboarding
                    // The ContentView will handle the transition based on hasCompletedOnboarding
                    dismiss()
                }
                
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save: \(error.localizedDescription)"
                    showError = true
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func createNameKeywords(from displayName: String) -> [String] {
        var keywords: [String] = []
        let lowercasedName = displayName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add full name
        keywords.append(lowercasedName)
        
        // Add individual words
        let words = lowercasedName.components(separatedBy: " ").filter { !$0.isEmpty }
        keywords.append(contentsOf: words)
        
        // Add first name + last name combinations
        if words.count >= 2 {
            let firstName = words[0]
            let lastName = words[words.count - 1]
            keywords.append("\(firstName) \(lastName)")
        }
        
        // Remove duplicates and return
        return Array(Set(keywords))
    }
}

// MARK: - Supporting Views (Reused from SignInView)

private struct CleanTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.black.opacity(0.4))
                .frame(width: 20)
            
            TextField(placeholder, text: $text)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.black)
                .autocorrectionDisabled()
                .textInputAutocapitalization(keyboardType == .default ? .words : .never)
                .keyboardType(keyboardType)
                .focused($isFocused)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isFocused ? Color.black.opacity(0.3) : Color.black.opacity(0.1),
                    lineWidth: 1
                )
        )
    }
}

private struct UsernameTextField: View {
    @Binding var text: String
    @Binding var isChecking: Bool
    @Binding var isAvailable: Bool?
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Image(systemName: "at")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.black.opacity(0.4))
                    .frame(width: 20)
                
                TextField("Username", text: $text)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.black)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isFocused)
                
                // Status indicator
                if isChecking {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let available = isAvailable {
                    Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(available ? .green : .red)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        statusBorderColor,
                        lineWidth: 1
                    )
            )
            
            // Validation message
            if !text.isEmpty {
                if isChecking {
                    Text("Checking availability...")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.black.opacity(0.6))
                } else if let available = isAvailable {
                    Text(available ? "@\(text) is available ✓" : "@\(text) is already taken")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(available ? .green : .red)
                } else if !isValidFormat {
                    Text("3-20 characters (letters, numbers, underscores)")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.orange)
                }
            }
        }
    }
    
    private var statusBorderColor: Color {
        if isFocused {
            return .black.opacity(0.3)
        }
        
        guard !text.isEmpty else {
            return .black.opacity(0.1)
        }
        
        if let available = isAvailable {
            return available ? .green.opacity(0.3) : .red.opacity(0.3)
        }
        
        return .black.opacity(0.1)
    }
    
    private var isValidFormat: Bool {
        let usernameRegex = "^[a-z0-9_]{3,20}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", usernameRegex)
        return predicate.evaluate(with: text.lowercased())
    }
}

#Preview {
    UsernameSelectionView()
        .environmentObject(AuthenticationViewModel())
}

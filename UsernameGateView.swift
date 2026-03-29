//
//  UsernameGateView.swift
//  AMENAPP
//
//  App Store Readiness: Forces users with auto-generated fallback usernames
//  to choose a proper username before accessing the app.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct UsernameGateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authViewModel: AuthenticationViewModel
    
    @State private var username = ""
    @State private var isAvailable = false
    @State private var isChecking = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var suggestions: [String] = []
    
    private let db = Firestore.firestore()
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 64, height: 64)
                        
                        Image(systemName: "at")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.7))
                    }
                    .padding(.top, 40)
                    
                    Text("Choose your username")
                        .font(.title2.bold())
                        .foregroundStyle(Color.black.opacity(0.85))
                    
                    Text("This is how others will find and mention you on AMEN")
                        .font(.subheadline)
                        .foregroundStyle(Color.black.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 32)
                
                // Username input
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("@")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.4))
                        
                        TextField("username", text: $username)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.85))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: username) { _, newValue in
                                checkUsernameAvailability(newValue)
                            }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        isAvailable && !username.isEmpty ? Color.green.opacity(0.3) :
                                        !errorMessage.isEmpty ? Color.red.opacity(0.3) :
                                        Color.black.opacity(0.08),
                                        lineWidth: 1
                                    )
                            )
                    )
                    
                    // Status message
                    if isChecking {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Checking availability...")
                                .font(.caption)
                                .foregroundStyle(Color.black.opacity(0.5))
                        }
                    } else if !errorMessage.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } else if isAvailable && !username.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text("@\(username) is available!")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    
                    // Requirements
                    Text("• 3-20 characters\n• Letters, numbers, and underscores only\n• Must be unique")
                        .font(.caption)
                        .foregroundStyle(Color.black.opacity(0.4))
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                
                // Suggestions
                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Suggestions")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.black.opacity(0.5))
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestions, id: \.self) { suggestion in
                                    Button {
                                        username = suggestion
                                    } label: {
                                        Text("@\(suggestion)")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(Color.black.opacity(0.7))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .fill(Color.black.opacity(0.06))
                                            )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                }
                
                Spacer()
                
                // Continue button
                Button {
                    saveUsername()
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Continue")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(isAvailable && !username.isEmpty ? Color.black : Color.black.opacity(0.3))
                    )
                }
                .disabled(!isAvailable || username.isEmpty || isSaving)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            loadSuggestions()
        }
    }
    
    // MARK: - Check Availability
    
    private func checkUsernameAvailability(_ input: String) {
        let cleaned = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Reset state
        errorMessage = ""
        isAvailable = false
        
        // Validation
        guard !cleaned.isEmpty else { return }
        
        guard cleaned.count >= 3 else {
            errorMessage = "Too short (minimum 3 characters)"
            return
        }
        
        guard cleaned.count <= 20 else {
            errorMessage = "Too long (maximum 20 characters)"
            return
        }
        
        let usernameRegex = "^[a-z0-9_]{3,20}$"
        guard cleaned.range(of: usernameRegex, options: .regularExpression) != nil else {
            errorMessage = "Only letters, numbers, and underscores"
            return
        }
        
        // Check Firestore availability
        isChecking = true
        
        db.collection("usernames")
            .document(cleaned)
            .getDocument { snapshot, error in
                DispatchQueue.main.async {
                    isChecking = false
                    
                    if let exists = snapshot?.exists, exists {
                        errorMessage = "Username already taken"
                        isAvailable = false
                    } else {
                        isAvailable = true
                    }
                }
            }
    }
    
    // MARK: - Save Username
    
    private func saveUsername() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        isSaving = true
        let cleaned = username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task {
            do {
                // Reserve username in usernames collection
                try await db.collection("usernames")
                    .document(cleaned)
                    .setData([
                        "userId": uid,
                        "createdAt": Timestamp(date: Date())
                    ])
                
                // Update user document
                try await db.collection("users")
                    .document(uid)
                    .setData([
                        "username": cleaned,
                        "usernameSetAt": Timestamp(date: Date())
                    ], merge: true)
                
                await MainActor.run {
                    isSaving = false
                    authViewModel.completeUsernameSelection()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save username. Try again."
                }
            }
        }
    }
    
    // MARK: - Load Suggestions
    
    private func loadSuggestions() {
        guard let displayName = Auth.auth().currentUser?.displayName else { return }
        
        let base = displayName
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        
        guard !base.isEmpty else { return }
        
        suggestions = [
            base,
            "\(base)\(Int.random(in: 10...99))",
            "\(base)_amen",
            "amen_\(base)",
            "\(base)\(Int.random(in: 100...999))"
        ].filter { $0.count >= 3 && $0.count <= 20 }
    }
}

//
//  AuthenticationViewModel.swift
//  AMENAPP
//
//  Unified AuthenticationViewModel with Email, Google, and Apple Sign-In
//

import Foundation
import SwiftUI
import Combine
import FirebaseAuth

@MainActor
class AuthenticationViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var isAuthenticated = false
    @Published var needsOnboarding = false
    @Published var needsUsernameSelection = false  // NEW: For social sign-in users
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var showWelcomeToAMEN = false  // NEW: Exciting welcome screen
    // @Published var showAppTutorial = false  // DISABLED - App tutorial removed
    
    // MARK: - Private Properties
    
    private let firebaseManager = FirebaseManager.shared
    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var isAuthenticating = false  // Prevent concurrent auth requests
    
    // MARK: - Initialization
    
    init() {
        setupAuthStateListener()
    }
    
    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
    
    // MARK: - Auth State Listener
    
    private func setupAuthStateListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let user = user {
                    print("🔐 Auth state changed: User logged in (\(user.email ?? "no email"))")
                    
                    // ✅ FIX: Check onboarding status BEFORE setting isAuthenticated
                    // This prevents the UI glitch where main content flashes before onboarding
                    await self.checkOnboardingStatus(userId: user.uid)
                    
                    // Now set isAuthenticated - onboarding state is already correct
                    self.isAuthenticated = true
                } else {
                    print("🔐 Auth state changed: User logged out")
                    self.isAuthenticated = false
                    self.needsOnboarding = false
                    self.needsUsernameSelection = false
                }
            }
        }
    }
    
    // MARK: - Check Onboarding Status
    
    private func checkOnboardingStatus(userId: String) async {
        do {
            let userData = try await firebaseManager.fetchUserDocument(userId: userId)
            
            let hasCompletedOnboarding = userData["hasCompletedOnboarding"] as? Bool ?? false
            
            // ✅ FIX: Set needsOnboarding immediately to prevent UI glitch
            // This ensures the state is updated before the view hierarchy re-renders
            await MainActor.run {
                self.needsOnboarding = !hasCompletedOnboarding
            }
            
            // NEW: Check if user needs to select username (social sign-in)
            // Social sign-in users have auto-generated usernames that start with "user" followed by random numbers
            // or are derived from email (before @). We want them to customize.
            let username = userData["username"] as? String ?? ""
            let authProvider = userData["authProvider"] as? String ?? ""
            
            // Check if this is a social sign-in user who hasn't customized their username
            let isSocialSignIn = authProvider == "google" || authProvider == "apple"
            let hasGenericUsername = username.hasPrefix("user") || username.isEmpty
            
            if isSocialSignIn && hasGenericUsername && !hasCompletedOnboarding {
                await MainActor.run {
                    self.needsUsernameSelection = true
                }
            } else {
                await MainActor.run {
                    self.needsUsernameSelection = false
                }
            }
            
            print("📋 Onboarding status: \(needsOnboarding ? "Needs onboarding" : "Completed")")
            print("📋 Username selection: \(needsUsernameSelection ? "Needs username" : "Has username")")
            
        } catch {
            print("⚠️ Failed to check onboarding status: \(error)")
            // Default to needing onboarding if we can't check
            await MainActor.run {
                self.needsOnboarding = true
                self.needsUsernameSelection = false
            }
        }
    }
    
    // MARK: - Sign In
    
    func signIn(email: String, password: String) async {
        // Prevent concurrent auth requests
        guard !isAuthenticating else {
            print("⚠️ Sign-in already in progress, ignoring duplicate request")
            return
        }
        
        isAuthenticating = true
        defer { isAuthenticating = false }
        
        print("🔐 Starting sign in for: \(email)")
        isLoading = true
        errorMessage = nil
        
        defer {
            Task { @MainActor in
                self.isLoading = false
            }
        }
        
        do {
            _ = try await firebaseManager.signIn(email: email, password: password)
            print("✅ Sign in successful")
            
            // Success haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            // isAuthenticated and needsOnboarding are handled by auth state listener
            
        } catch {
            print("❌ Sign in failed: \(error.localizedDescription)")
            errorMessage = handleAuthError(error)
            showError = true
            
            // Error haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
    }
    
    // MARK: - Sign Up
    
    func signUp(email: String, password: String, displayName: String, username: String) async {
        // Prevent concurrent auth requests
        guard !isAuthenticating else {
            print("⚠️ Sign-up already in progress, ignoring duplicate request")
            return
        }
        
        isAuthenticating = true
        defer { isAuthenticating = false }
        
        print("🔐 Starting sign up for: \(email)")
        isLoading = true
        errorMessage = nil
        
        defer {
            Task { @MainActor in
                self.isLoading = false
            }
        }
        
        do {
            _ = try await firebaseManager.signUp(
                email: email,
                password: password,
                displayName: displayName,
                username: username
            )
            print("✅ Sign up successful")
            
            // Success haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            // ✅ FIX: Set needsOnboarding BEFORE isAuthenticated to prevent UI glitch
            // This ensures the onboarding screen shows immediately without flashing content
            needsOnboarding = true
            
            // Small delay to ensure state is set before auth listener fires
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
            
            // Auth state listener will set isAuthenticated = true
            // but needsOnboarding is already true, preventing the glitch
            
        } catch {
            print("❌ Sign up failed: \(error.localizedDescription)")
            errorMessage = handleAuthError(error)
            showError = true
            
            // Error haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
    }
    
    // MARK: - Sign Out
    
    func signOut() {
        do {
            try firebaseManager.signOut()
            print("✅ Sign out successful")
            
            // Reset state
            isAuthenticated = false
            needsOnboarding = false
            errorMessage = nil
            
        } catch {
            print("❌ Sign out failed: \(error.localizedDescription)")
            errorMessage = "Failed to sign out: \(error.localizedDescription)"
            showError = true
        }
    }
    
    // MARK: - Password Reset
    
    func sendPasswordReset(email: String) async throws {
        print("📧 Sending password reset email to: \(email)")
        try await firebaseManager.sendPasswordReset(email: email)
        print("✅ Password reset email sent")
    }
    
    // MARK: - Change Password
    
    func changePassword(currentPassword: String, newPassword: String) async throws {
        print("🔐 Changing password")
        
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user is currently signed in"])
        }
        
        guard let email = user.email else {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User email not found"])
        }
        
        // Re-authenticate user with current password
        let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
        
        do {
            try await user.reauthenticate(with: credential)
            print("✅ Re-authentication successful")
            
            // Update password
            try await user.updatePassword(to: newPassword)
            print("✅ Password changed successfully")
            
        } catch {
            print("❌ Password change failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Update Email
    
    /// Update user email address
    func updateEmail(newEmail: String) async throws {
        print("📧 Updating email to: \(newEmail)")
        
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user is currently signed in"])
        }
        
        do {
            try await user.updateEmail(to: newEmail)
            print("✅ Email updated successfully in Firebase Auth")
        } catch {
            print("❌ Email update failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Re-authenticate user with current password
    func reauthenticate(password: String) async throws {
        print("🔐 Re-authenticating user")
        
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user is currently signed in"])
        }
        
        guard let email = user.email else {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User email not found"])
        }
        
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        
        do {
            try await user.reauthenticate(with: credential)
            print("✅ Re-authentication successful")
        } catch {
            print("❌ Re-authentication failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Delete Account
    
    /// Delete account - works for both password-based and Apple/Google Sign-In users
    func deleteAccount(password: String?) async throws {
        print("🗑️ Deleting account")
        
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user is currently signed in"])
        }
        
        let userId = user.uid
        
        // Determine authentication provider
        let isAppleSignIn = user.providerData.contains { $0.providerID == "apple.com" }
        let isGoogleSignIn = user.providerData.contains { $0.providerID == "google.com" }
        let isEmailSignIn = user.providerData.contains { $0.providerID == "password" }
        
        do {
            // Re-authenticate based on provider
            if isAppleSignIn {
                print("🍎 Apple Sign-In user - re-authentication not required for deletion")
                // Apple Sign-In users can delete without re-authentication
                // The user already confirmed with multiple steps in the UI
            } else if isGoogleSignIn {
                print("🔍 Google Sign-In user - re-authentication not required for deletion")
                // Google Sign-In users can delete without re-authentication
                // The user already confirmed with multiple steps in the UI
            } else if isEmailSignIn {
                // Email/password users must re-authenticate
                guard let password = password, !password.isEmpty else {
                    throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Password is required for email users"])
                }
                
                guard let email = user.email else {
                    throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User email not found"])
                }
                
                print("📧 Email user - re-authenticating with password")
                let credential = EmailAuthProvider.credential(withEmail: email, password: password)
                try await user.reauthenticate(with: credential)
                print("✅ Re-authentication successful")
            } else {
                throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown authentication provider"])
            }
            
            // Delete user data from Firestore
            try await firebaseManager.deleteUserData(userId: userId)
            print("✅ User data deleted from Firestore")
            
            // Delete user account from Firebase Auth
            try await user.delete()
            print("✅ User account deleted")
            
            // Reset state
            await MainActor.run {
                isAuthenticated = false
                needsOnboarding = false
            }
            
        } catch {
            print("❌ Account deletion failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Check if current user signed in with Apple/Google (passwordless)
    func isPasswordlessUser() -> Bool {
        guard let user = Auth.auth().currentUser else { return false }
        
        let isAppleSignIn = user.providerData.contains { $0.providerID == "apple.com" }
        let isGoogleSignIn = user.providerData.contains { $0.providerID == "google.com" }
        
        return isAppleSignIn || isGoogleSignIn
    }
    
    /// Get the authentication provider name for display
    func getAuthProviderName() -> String {
        guard let user = Auth.auth().currentUser else { return "Unknown" }
        
        if user.providerData.contains(where: { $0.providerID == "apple.com" }) {
            return "Apple ID"
        } else if user.providerData.contains(where: { $0.providerID == "google.com" }) {
            return "Google"
        } else if user.providerData.contains(where: { $0.providerID == "password" }) {
            return "Email"
        }
        
        return "Unknown"
    }
    
    // MARK: - Complete Onboarding
    
    func completeOnboarding() {
        needsOnboarding = false
        print("✅ Onboarding completed")
    }
    
    // MARK: - Complete Username Selection
    
    func completeUsernameSelection() {
        needsUsernameSelection = false
        print("✅ Username selection completed")
    }
    
    // MARK: - Welcome to AMEN
    
    func showWelcomeToAMENScreen() {
        showWelcomeToAMEN = true
    }
    
    func dismissWelcomeToAMEN() {
        showWelcomeToAMEN = false
        // Now goes directly to main app
    }
    
    // MARK: - App Tutorial (DISABLED)
    
    // Tutorial feature removed - users go directly to main app after onboarding
    /*
    func showAppTutorialScreen() {
        showAppTutorial = true
    }
    
    func dismissAppTutorial() {
        showAppTutorial = false
    }
    */
    
    // MARK: - Error Handling
    
    private func handleAuthError(_ error: Error) -> String {
        let nsError = error as NSError
        
        switch nsError.code {
        case AuthErrorCode.invalidEmail.rawValue:
            return "Please enter a valid email address"
        case AuthErrorCode.emailAlreadyInUse.rawValue:
            return "This email is already registered"
        case AuthErrorCode.weakPassword.rawValue:
            return "Password must be at least 6 characters"
        case AuthErrorCode.wrongPassword.rawValue:
            return "Incorrect password. Please try again"
        case AuthErrorCode.userNotFound.rawValue:
            return "No account found with this email"
        case AuthErrorCode.networkError.rawValue:
            return "Network error. Please check your connection"
        case AuthErrorCode.tooManyRequests.rawValue:
            return "Too many attempts. Please try again later"
        case AuthErrorCode.userDisabled.rawValue:
            return "This account has been disabled"
        default:
            return error.localizedDescription
        }
    }
}

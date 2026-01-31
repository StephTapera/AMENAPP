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
    @Published var showWelcomeValues = false
    @Published var showAppTutorial = false
    
    // MARK: - Private Properties
    
    private let firebaseManager = FirebaseManager.shared
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
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
    
    // MARK: - Delete Account
    
    func deleteAccount(password: String) async throws {
        print("🗑️ Deleting account")
        
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user is currently signed in"])
        }
        
        guard let email = user.email else {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User email not found"])
        }
        
        let userId = user.uid
        
        // Re-authenticate user with password
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        
        do {
            try await user.reauthenticate(with: credential)
            print("✅ Re-authentication successful")
            
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
    
    // MARK: - Welcome Values
    
    func showWelcomeValuesScreen() {
        showWelcomeValues = true
    }
    
    func dismissWelcomeValues() {
        showWelcomeValues = false
    }
    
    // MARK: - App Tutorial
    
    func showAppTutorialScreen() {
        showAppTutorial = true
    }
    
    func dismissAppTutorial() {
        showAppTutorial = false
    }
    
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

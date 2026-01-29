//
//  AuthenticationViewModel.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class AuthenticationViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var needsOnboarding = false
    @Published var showWelcomeValues = false // Show values screen after sign-in
    @Published var showAppTutorial = false // Show tutorial after onboarding
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    private let firebaseManager = FirebaseManager.shared
    private let userService = UserService()
    
    init() {
        checkAuthenticationStatus()
        
        // Debug: Print auth status on init
        print("🔐 AuthViewModel Init - isAuthenticated: \(isAuthenticated)")
    }
    
    /// Check if user is already authenticated
    func checkAuthenticationStatus() {
        isAuthenticated = firebaseManager.isAuthenticated
        
        // Debug: Print current user info
        if let currentUser = firebaseManager.currentUser {
            print("✅ User is authenticated: \(currentUser.uid)")
            print("📧 Email: \(currentUser.email ?? "No email")")
        } else {
            print("❌ No user is authenticated")
        }
        
        if isAuthenticated {
            Task {
                await userService.fetchCurrentUser()
            }
        }
    }
    
    /// Sign in with email and password
    func signIn(email: String, password: String) async {
        print("🔐 Starting sign in for: \(email)")
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let user = try await firebaseManager.signIn(email: email, password: password)
            print("✅ Sign in successful! User ID: \(user.uid)")
            isAuthenticated = true
            // showWelcomeValues = true // Disabled - goes directly to main app
            print("🔐 isAuthenticated set to: \(isAuthenticated)")
            await userService.fetchCurrentUser()
            
            // Haptic feedback
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        } catch {
            print("❌ Sign in failed: \(error.localizedDescription)")
            errorMessage = handleAuthError(error)
            showError = true
            
            // Haptic feedback
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
    }
    
    /// Sign up with email and password only (profile completion happens in onboarding)
    func signUpWithEmail(email: String, password: String) async {
        print("🔐 Starting sign up for: \(email)")
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            // Create Firebase Auth account and user profile
            print("📝 Creating Firebase Auth account and profile...")
            let user = try await firebaseManager.signUp(
                email: email,
                password: password,
                displayName: "User"  // Temporary - will be updated in onboarding
            )
            print("✅ Sign up successful! User ID: \(user.uid)")
            
            // Set state to show onboarding
            isAuthenticated = true
            needsOnboarding = true
            print("✅ State updated - isAuthenticated: \(isAuthenticated), needsOnboarding: \(needsOnboarding)")
            
            // Haptic feedback
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            print("🎉 Sign up complete! User will complete profile in onboarding.")
            
        } catch {
            print("❌ Sign up failed: \(error.localizedDescription)")
            errorMessage = handleAuthError(error)
            showError = true
            
            // Haptic feedback
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
    }
    
    /// Sign up with email and password (legacy method - kept for compatibility)
    func signUp(email: String, password: String, displayName: String, username: String) async {
        print("🔐 Starting sign up for: \(email) with username: @\(username)")
        
        // Ensure we're on main actor for UI updates
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }
        
        do {
            // Step 1: Create Firebase Auth account with user profile
            print("📝 Step 1: Creating Firebase Auth account and profile...")
            let user = try await firebaseManager.signUp(
                email: email,
                password: password,
                displayName: displayName,
                username: username  // Pass the username here!
            )
            print("✅ Sign up successful! User ID: \(user.uid)")
            
            // Step 2: SKIP UserService.createUserProfile - FirebaseManager already created the profile!
            // NOTE: FirebaseManager.signUp() already creates the complete Firestore document
            // Calling UserService.createUserProfile might cause conflicts or overwrites
            print("📝 Step 2: Profile already created by FirebaseManager, skipping UserService...")
            // try await userService.createUserProfile(email: email, displayName: displayName, username: username)
            print("✅ Using profile created by FirebaseManager with username: @\(username)")
            
            // Step 3: Update UI state on MainActor
            print("📝 Step 3: Updating authentication state...")
            await MainActor.run {
                self.isAuthenticated = true
                self.needsOnboarding = true
                print("✅ State updated - isAuthenticated: \(self.isAuthenticated), needsOnboarding: \(self.needsOnboarding)")
            }
            
            // Haptic feedback
            await MainActor.run {
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            }
            
            print("🎉 Sign up complete! User should see onboarding next.")
            
        } catch {
            print("❌ Sign up failed at some step: \(error.localizedDescription)")
            print("❌ Error details: \(error)")
            
            await MainActor.run {
                errorMessage = handleAuthError(error)
                showError = true
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
    }
    
    /// Sign out current user
    func signOut() {
        do {
            try firebaseManager.signOut()
            isAuthenticated = false
            needsOnboarding = false
            userService.currentUser = nil
            
            // Haptic feedback
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        } catch {
            errorMessage = "Failed to sign out: \(error.localizedDescription)"
            showError = true
            
            // Haptic feedback
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
    }
    
    /// Complete onboarding flow
    func completeOnboarding() {
        needsOnboarding = false
        showAppTutorial = true // Show tutorial after onboarding
        print("✅ Onboarding completed, showing app tutorial")
    }
    
    /// Dismiss welcome values screen
    func dismissWelcomeValues() {
        showWelcomeValues = false
        print("✅ Welcome values screen dismissed")
    }
    
    /// Dismiss app tutorial
    func dismissAppTutorial() {
        showAppTutorial = false
        print("✅ App tutorial dismissed, user ready for main app")
    }
    
    /// Send password reset email
    func sendPasswordReset(email: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            try await firebaseManager.sendPasswordReset(email: email)
            errorMessage = "Password reset email sent! Check your inbox."
            showError = true
            
            // Haptic feedback
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        } catch {
            errorMessage = handleAuthError(error)
            showError = true
            
            // Haptic feedback
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
    }
    
    /// Handle authentication errors with user-friendly messages
    private func handleAuthError(_ error: Error) -> String {
        let nsError = error as NSError
        
        // Cast to AuthErrorCode directly
        guard let errorCode = AuthErrorCode(_bridgedNSError: nsError) else {
            return error.localizedDescription
        }
        
        switch errorCode.code {
        case .invalidEmail:
            return "Invalid email address."
        case .wrongPassword:
            return "Incorrect password."
        case .userNotFound:
            return "No account found with this email."
        case .emailAlreadyInUse:
            return "This email is already registered."
        case .weakPassword:
            return "Password should be at least 6 characters."
        case .networkError:
            return "Network error. Please check your connection."
        case .tooManyRequests:
            return "Too many attempts. Please try again later."
        default:
            return error.localizedDescription
        }
    }
    
    /// Validate email format
    func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    /// Validate password strength
    func isValidPassword(_ password: String) -> Bool {
        return password.count >= 6
    }
    
    // MARK: - Change Password
    
    /// Change user's password
    func changePassword(currentPassword: String, newPassword: String) async throws {
        print("🔐 Attempting to change password...")
        
        guard let user = firebaseManager.currentUser else {
            throw NSError(domain: "AuthError", code: 401, userInfo: [NSLocalizedDescriptionKey: "No user logged in"])
        }
        
        guard let email = user.email else {
            throw NSError(domain: "AuthError", code: 400, userInfo: [NSLocalizedDescriptionKey: "User email not found"])
        }
        
        // Re-authenticate user first (required by Firebase for sensitive operations)
        let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
        
        do {
            try await user.reauthenticate(with: credential)
            print("✅ Re-authentication successful")
            
            // Now update password
            try await user.updatePassword(to: newPassword)
            print("✅ Password changed successfully!")
            
            // Haptic feedback
            await MainActor.run {
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            }
        } catch {
            print("❌ Failed to change password: \(error)")
            throw error
        }
    }
    
    // MARK: - Delete Account
    
    /// Permanently delete user account and all associated data
    func deleteAccount(password: String) async throws {
        print("🗑️ Attempting to delete account...")
        
        guard let user = firebaseManager.currentUser else {
            throw NSError(domain: "AuthError", code: 401, userInfo: [NSLocalizedDescriptionKey: "No user logged in"])
        }
        
        guard let email = user.email else {
            throw NSError(domain: "AuthError", code: 400, userInfo: [NSLocalizedDescriptionKey: "User email not found"])
        }
        
        let userId = user.uid
        
        // Re-authenticate user first (required by Firebase for account deletion)
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        
        do {
            try await user.reauthenticate(with: credential)
            print("✅ Re-authentication successful")
            
            // Delete user data from Firestore first
            print("🗑️ Deleting user data from Firestore...")
            try await deleteUserData(userId: userId)
            
            // Delete Firebase Auth account
            try await user.delete()
            print("✅ Account deleted successfully!")
            
            // Update state - sign out the user
            await MainActor.run {
                self.isAuthenticated = false
                self.needsOnboarding = false
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.warning)
            }
        } catch {
            print("❌ Failed to delete account: \(error)")
            throw error
        }
    }
    
    /// Delete all user data from Firestore
    private func deleteUserData(userId: String) async throws {
        let db = Firestore.firestore()
        let batch = db.batch()
        
        // 1. Delete user document
        let userRef = db.collection("users").document(userId)
        batch.deleteDocument(userRef)
        
        // 2. Delete user's posts
        let postsSnapshot = try await db.collection("posts")
            .whereField("authorId", isEqualTo: userId)
            .getDocuments()
        
        for doc in postsSnapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        
        print("🗑️ Deleting \(postsSnapshot.documents.count) posts")
        
        // 3. Delete user's comments
        let commentsSnapshot = try await db.collection("comments")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        
        for doc in commentsSnapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        
        print("🗑️ Deleting \(commentsSnapshot.documents.count) comments")
        
        // 4. Delete user's follows (as follower)
        let followingSnapshot = try await db.collection("follows")
            .whereField("followerId", isEqualTo: userId)
            .getDocuments()
        
        for doc in followingSnapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        
        // 5. Delete user's follows (as following)
        let followersSnapshot = try await db.collection("follows")
            .whereField("followingId", isEqualTo: userId)
            .getDocuments()
        
        for doc in followersSnapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        
        print("🗑️ Deleting \(followingSnapshot.documents.count + followersSnapshot.documents.count) follow relationships")
        
        // 6. Delete user's blocks (as blocker)
        let blocksSnapshot = try await db.collection("blocks")
            .whereField("blockerId", isEqualTo: userId)
            .getDocuments()
        
        for doc in blocksSnapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        
        // 7. Delete blocks where user is blocked
        let blockedSnapshot = try await db.collection("blocks")
            .whereField("blockedUserId", isEqualTo: userId)
            .getDocuments()
        
        for doc in blockedSnapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        
        print("🗑️ Deleting \(blocksSnapshot.documents.count + blockedSnapshot.documents.count) block relationships")
        
        // 8. Delete user's reposts
        let repostsSnapshot = try await db.collection("reposts")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        
        for doc in repostsSnapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        
        print("🗑️ Deleting \(repostsSnapshot.documents.count) reposts")
        
        // Commit batch delete
        try await batch.commit()
        
        print("✅ All user data deleted from Firestore")
    }
}

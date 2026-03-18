//
//  FCM_TOKEN_INTEGRATION_GUIDE.swift
//  AMENAPP
//
//  Complete guide for integrating FCM token storage
//  This ensures push notifications work properly
//

import SwiftUI
import FirebaseAuth
import FirebaseMessaging
import FirebaseFirestore
import UserNotifications

#if canImport(FCMGuideNeverImport)

// ============================================================================
// MARK: - STEP 1: Request Permissions & Setup FCM on Login
// ============================================================================

// Add this code to your login/authentication flow
// Example: After successful login in SignInView or wherever you handle auth

extension SignInView {
    
    /// Call this after successful login to setup FCM
    private func setupFCMAfterLogin() async {
        dlog("🔐 User logged in, setting up FCM...")
        
        // 1. Request notification permissions
        let granted = await PushNotificationManager.shared.requestNotificationPermissions()
        
        if granted {
            dlog("✅ Notification permission granted")
            
            // 2. Setup FCM token (this will automatically save to Firestore)
            PushNotificationManager.shared.setupFCMToken()
            
            // 3. Optional: Schedule daily reminders
            await PushNotificationManager.shared.scheduleDailyReminders()
        } else {
            dlog("⚠️ Notification permission denied")
            // You can still use the app, but no push notifications
        }
    }
}

// ============================================================================
// MARK: - STEP 2: Add to Your ContentView or Root View
// ============================================================================

// Add this to your main ContentView to ensure FCM is setup on app launch

extension ContentView {
    
    /// Setup FCM when app launches and user is already logged in
    private func setupFCMOnAppear() {
        // Only setup if user is already authenticated
        guard Auth.auth().currentUser != nil else {
            dlog("⚠️ No authenticated user, skipping FCM setup")
            return
        }
        
        Task {
            // Check if we already have permission
            let hasPermission = await PushNotificationManager.shared.checkNotificationPermissions()
            
            if hasPermission {
                // We have permission, setup FCM
                PushNotificationManager.shared.setupFCMToken()
                dlog("✅ FCM setup on app launch")
            } else {
                // No permission yet, you can prompt user or wait for login flow
                dlog("⚠️ No notification permission on app launch")
            }
        }
    }
}

// ============================================================================
// MARK: - STEP 3: Complete Login Flow Example
// ============================================================================

/// Example of a complete login flow with FCM token storage
struct CompleteLoginExample: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
            
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
            
            Button("Sign In") {
                Task {
                    await handleLogin()
                }
            }
            .disabled(isLoading)
            
            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding()
    }
    
    private func handleLogin() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 1. Sign in with Firebase Auth
            let authResult = try await Auth.auth().signIn(
                withEmail: email,
                password: password
            )
            
            dlog("✅ User signed in: \(authResult.user.uid)")
            
            // 2. Request notification permissions
            let granted = await PushNotificationManager.shared.requestNotificationPermissions()
            
            if granted {
                dlog("✅ Notification permission granted")
                
                // 3. Setup FCM token (this automatically saves to Firestore)
                PushNotificationManager.shared.setupFCMToken()
                
                // 4. Optional: Setup daily reminders
                await PushNotificationManager.shared.scheduleDailyReminders()
            } else {
                dlog("⚠️ Notification permission denied by user")
            }
            
            // 5. Navigate to main app
            await MainActor.run {
                isLoading = false
                // Navigate to ContentView or wherever
            }
            
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
            dlog("❌ Login failed: \(error)")
        }
    }
}

// ============================================================================
// MARK: - STEP 4: Handle Token Refresh
// ============================================================================

// Your PushNotificationManager already handles token refresh automatically!
// The MessagingDelegate method `messaging(_:didReceiveRegistrationToken:)`
// is called whenever the token changes and saves it to Firestore.

// No additional code needed - this is already implemented in PushNotificationManager.swift

// ============================================================================
// MARK: - STEP 5: Remove Token on Logout
// ============================================================================

/// Add this to your logout flow
extension AuthenticationService {
    
    func logout() async throws {
        // 1. Remove FCM token from Firestore
        await PushNotificationManager.shared.removeFCMTokenFromFirestore()
        
        // 2. Clear badge
        PushNotificationManager.shared.clearBadge()
        
        // 3. Cancel daily reminders (optional)
        await PushNotificationManager.shared.cancelDailyReminders()
        
        // 4. Sign out from Firebase Auth
        try Auth.auth().signOut()
        
        dlog("✅ User logged out and FCM token removed")
    }
}

// ============================================================================
// MARK: - STEP 6: Verify FCM Token in Firestore
// ============================================================================

/// Helper function to check if FCM token is saved in Firestore
func verifyFCMTokenInFirestore() async {
    guard let userId = Auth.auth().currentUser?.uid else {
        dlog("⚠️ No authenticated user")
        return
    }
    
    do {
        let db = Firestore.firestore()
        let userDoc = try await db.collection("users").document(userId).getDocument()
        
        if let fcmToken = userDoc.data()?["fcmToken"] as? String {
            dlog("✅ FCM token stored in Firestore: \(fcmToken)")
        } else {
            dlog("❌ No FCM token found in Firestore")
        }
        
        if let updatedAt = userDoc.data()?["fcmTokenUpdatedAt"] as? Timestamp {
            dlog("📅 Token last updated: \(updatedAt.dateValue())")
        }
        
        if let platform = userDoc.data()?["platform"] as? String {
            dlog("📱 Platform: \(platform)")
        }
    } catch {
        dlog("❌ Error verifying FCM token: \(error)")
    }
}

// ============================================================================
// MARK: - STEP 7: Test Push Notifications
// ============================================================================

/// Test function to verify everything is working
func testPushNotificationSetup() async {
    dlog("🧪 Testing push notification setup...")
    
    // 1. Check authentication
    guard let userId = Auth.auth().currentUser?.uid else {
        dlog("❌ Not authenticated")
        return
    }
    dlog("✅ User authenticated: \(userId)")
    
    // 2. Check notification permission
    let hasPermission = await PushNotificationManager.shared.checkNotificationPermissions()
    if hasPermission {
        dlog("✅ Notification permission granted")
    } else {
        dlog("❌ Notification permission not granted")
        return
    }
    
    // 3. Check FCM token
    if let fcmToken = PushNotificationManager.shared.fcmToken {
        dlog("✅ FCM token available: \(fcmToken)")
    } else {
        dlog("⚠️ FCM token not available yet (may still be loading)")
    }
    
    // 4. Verify token in Firestore
    await verifyFCMTokenInFirestore()
    
    // 5. Schedule test notification
    await PushNotificationManager.shared.scheduleTestNotification()
    dlog("✅ Test notification scheduled (should appear in 5 seconds)")
    
    dlog("🧪 Test complete!")
}

// ============================================================================
// MARK: - STEP 8: Integration Checklist
// ============================================================================

/*
 ✅ INTEGRATION CHECKLIST:
 
 1. AppDelegate Setup (ALREADY DONE ✅)
    - AMENAPPApp.swift has @UIApplicationDelegateAdaptor
    - AppDelegate+Messaging.swift configures FCM
 
 2. PushNotificationManager (ALREADY DONE ✅)
    - setupFCMToken() fetches and saves token
    - MessagingDelegate handles token refresh
    - saveFCMTokenToFirestore() stores token
 
 3. Request Permissions on Login (DO THIS 👇)
    - Call requestNotificationPermissions() after login
    - Call setupFCMToken() after permission granted
 
 4. Setup on App Launch (DO THIS 👇)
    - Add setupFCMOnAppear() to ContentView
    - Call it in .onAppear { }
 
 5. Remove Token on Logout (DO THIS 👇)
    - Call removeFCMTokenFromFirestore() before sign out
    - Clear badge and cancel reminders
 
 6. Firestore Security Rules (ALREADY DONE ✅)
    - Your rules allow any authenticated user to create notifications
    - Rules allow users to update their own fcmToken field
 
 7. Cloud Functions (ALREADY HAVE ✅)
    - onUserFollow, onFollowRequestAccepted, etc.
    - sendPushNotification function ready
 
 8. Test Everything (DO THIS 👇)
    - Run testPushNotificationSetup()
    - Test follow notification
    - Test comment notification
    - Test message notification
 */

// ============================================================================
// MARK: - STEP 9: Where to Add the Code
// ============================================================================

/*
 📝 WHERE TO ADD FCM TOKEN REGISTRATION:
 
 1. In SignInView.swift (or wherever you handle login):
 
    private func handleSignIn() async {
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
            
            // ✅ ADD THIS AFTER SUCCESSFUL LOGIN
            let granted = await PushNotificationManager.shared.requestNotificationPermissions()
            if granted {
                PushNotificationManager.shared.setupFCMToken()
                await PushNotificationManager.shared.scheduleDailyReminders()
            }
            
            // Navigate to main app
        } catch {
            dlog("Login error: \(error)")
        }
    }
 
 2. In ContentView.swift (for users already logged in):
 
    .onAppear {
        // ✅ ADD THIS IN YOUR onAppear
        if Auth.auth().currentUser != nil {
            Task {
                let hasPermission = await PushNotificationManager.shared.checkNotificationPermissions()
                if hasPermission {
                    PushNotificationManager.shared.setupFCMToken()
                }
            }
        }
    }
 
 3. In your logout function:
 
    func logout() async {
        // ✅ ADD THIS BEFORE SIGNING OUT
        await PushNotificationManager.shared.removeFCMTokenFromFirestore()
        PushNotificationManager.shared.clearBadge()
        
        try? Auth.auth().signOut()
    }
 */

// ============================================================================
// MARK: - STEP 10: Debugging Tips
// ============================================================================

/*
 🐛 DEBUGGING TIPS:
 
 1. Check FCM Token in Console:
    - Run the app in Xcode
    - Look for "🔑 FCM Token:" in console
    - Copy the token for testing
 
 2. Verify Token in Firestore:
    - Open Firebase Console → Firestore
    - Navigate to users/{userId}
    - Check if fcmToken field exists
 
 3. Test Cloud Functions Locally:
    - Use Firebase Emulator Suite
    - firebase emulators:start
 
 4. Test Push Notification:
    - Firebase Console → Cloud Messaging
    - "Send test message"
    - Paste your FCM token
    - Send to device
 
 5. Common Issues:
    - ❌ "FCM token unavailable on simulator"
      → This is normal, use real device for testing
    
    - ❌ "No FCM token for user"
      → User hasn't granted notification permission
      → Call requestNotificationPermissions()
    
    - ❌ "Failed to send notification"
      → Check Cloud Functions logs
      → Verify token is saved in Firestore
      → Check APNs certificate in Firebase Console
 
 6. Enable Debug Logging:
    - Edit Scheme → Arguments
    - Add: -FIRMessagingDebugEnabled
    - Run app and check detailed logs
 */

// ============================================================================
// MARK: - EXAMPLE: Complete Authentication Flow with FCM
// ============================================================================

/// Complete example showing FCM integration in authentication
@MainActor
class AuthenticationViewModelFCMGuide: ObservableObject {
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    
    func signIn(email: String, password: String) async {
        do {
            // 1. Sign in with Firebase Auth
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            dlog("✅ Signed in: \(result.user.uid)")
            
            // 2. Setup FCM (CRITICAL FOR PUSH NOTIFICATIONS)
            await setupFCMForUser()
            
            // 3. Update UI
            await MainActor.run {
                isAuthenticated = true
            }
            
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    func signUp(email: String, password: String, displayName: String) async {
        do {
            // 1. Create account
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            dlog("✅ Account created: \(result.user.uid)")
            
            // 2. Create user document in Firestore
            let db = Firestore.firestore()
            try await db.collection("users").document(result.user.uid).setData([
                "email": email,
                "displayName": displayName,
                "username": email.components(separatedBy: "@").first ?? "",
                "createdAt": FieldValue.serverTimestamp()
            ])
            
            // 3. Setup FCM
            await setupFCMForUser()
            
            // 4. Update UI
            await MainActor.run {
                isAuthenticated = true
            }
            
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    func signOut() async {
        do {
            // 1. Remove FCM token from Firestore
            await PushNotificationManager.shared.removeFCMTokenFromFirestore()
            
            // 2. Clear local state
            PushNotificationManager.shared.clearBadge()
            await PushNotificationManager.shared.cancelDailyReminders()
            
            // 3. Sign out from Firebase
            try Auth.auth().signOut()
            
            // 4. Update UI
            await MainActor.run {
                isAuthenticated = false
            }
            
            dlog("✅ Signed out successfully")
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to sign out: \(error.localizedDescription)"
            }
        }
    }
    
    /// Setup FCM token for the current user
    private func setupFCMForUser() async {
        // 1. Request notification permissions
        let granted = await PushNotificationManager.shared.requestNotificationPermissions()
        
        if granted {
            dlog("✅ Notification permission granted")
            
            // 2. Setup FCM token (automatically saves to Firestore)
            PushNotificationManager.shared.setupFCMToken()
            
            // 3. Schedule daily reminders (optional)
            await PushNotificationManager.shared.scheduleDailyReminders()
            
            dlog("✅ FCM setup complete")
        } else {
            dlog("⚠️ User denied notification permission")
            // App still works, but no push notifications
        }
    }
}

// ============================================================================
// MARK: - FINAL NOTES
// ============================================================================

/*
 🎉 YOU'RE ALMOST DONE!
 
 Your PushNotificationManager is already excellent and handles:
 ✅ FCM token fetching
 ✅ Token refresh listening
 ✅ Saving to Firestore
 ✅ Removing on logout
 ✅ Badge management
 ✅ Daily reminders
 
 You just need to:
 1. Call requestNotificationPermissions() after login
 2. Call setupFCMToken() after permission granted
 3. Call removeFCMTokenFromFirestore() before logout
 
 That's it! 🚀
 
 Your Cloud Functions already expect:
 - fcmToken field in users/{userId}
 - platform: "ios"
 - fcmTokenUpdatedAt timestamp
 
 Which your PushNotificationManager already provides!
 */

// This file is for reference only - DO NOT add to your Xcode project
// Copy the relevant code snippets to your existing files

#endif

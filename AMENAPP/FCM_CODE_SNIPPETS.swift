//
//  FCM_CODE_SNIPPETS.swift
//  AMENAPP
//
//  Ready-to-use code snippets for FCM integration
//  Copy these into your existing files
//

import SwiftUI
import FirebaseAuth
import UserNotifications

#if canImport(FCMGuideNeverImport)

// ============================================================================
// SNIPPET 1: Add to Your Login View
// ============================================================================
// File: SignInView.swift (or wherever you handle login)

/*
 Add this function to your SignInView and call it after successful login:
*/

private func setupFCMAfterLogin() async {
    print("🔐 Setting up FCM after login...")
    
    // Request notification permissions
    let granted = await PushNotificationManager.shared.requestNotificationPermissions()
    
    if granted {
        print("✅ Notification permission granted")
        
        // Setup FCM token (automatically saves to Firestore)
        PushNotificationManager.shared.setupFCMToken()
        
        // Optional: Schedule daily reminders
        await PushNotificationManager.shared.scheduleDailyReminders()
    } else {
        print("⚠️ User denied notification permission")
        // App still works, just no push notifications
    }
}

/*
 Then call it in your login handler:

 func handleLogin() async {
     do {
         try await Auth.auth().signIn(withEmail: email, password: password)
         
         // ✅ ADD THIS LINE:
         await setupFCMAfterLogin()
         
         // Continue with navigation...
     } catch {
         // Handle error
     }
 }
*/

// ============================================================================
// SNIPPET 2: Add to Your ContentView or Root View
// ============================================================================
// File: ContentView.swift

/*
 Add this to your ContentView's .onAppear modifier:
*/

/*
.onAppear {
    // Your existing onAppear code...

    // ✅ ADD THIS:
    setupFCMIfAlreadyLoggedIn()
}
*/

/*
 Then add this function to your ContentView:
*/

private func setupFCMIfAlreadyLoggedIn() {
    // Only setup if user is already authenticated
    guard Auth.auth().currentUser != nil else {
        print("⚠️ No authenticated user, skipping FCM setup")
        return
    }
    
    Task {
        print("🚀 User already logged in, setting up FCM...")
        
        // Check if we already have notification permission
        let hasPermission = await PushNotificationManager.shared.checkNotificationPermissions()
        
        if hasPermission {
            // We have permission, setup FCM token
            PushNotificationManager.shared.setupFCMToken()
            print("✅ FCM setup complete on app launch")
        } else {
            print("⚠️ No notification permission (user hasn't granted yet)")
            // Don't show permission prompt on launch
            // Wait for user to login/trigger it manually
        }
    }
}

// ============================================================================
// SNIPPET 3: Add to Your Logout Handler
// ============================================================================
// File: SettingsView.swift or ProfileView.swift or AuthenticationService.swift

/*
 Add this to your logout function BEFORE signing out:
*/

func logout() async {
    print("🚪 Logging out...")
    
    // ✅ ADD THESE LINES FIRST:
    // Remove FCM token from Firestore
    await PushNotificationManager.shared.removeFCMTokenFromFirestore()
    
    // Clear badge count
    await MainActor.run {
        PushNotificationManager.shared.clearBadge()
    }
    
    // Cancel daily reminders (optional)
    await PushNotificationManager.shared.cancelDailyReminders()
    
    // Then your existing sign out code:
    do {
        try Auth.auth().signOut()
        print("✅ Signed out successfully")
    } catch {
        print("❌ Sign out error: \(error)")
    }
}

// ============================================================================
// SNIPPET 4: Optional - Test Notification Setup
// ============================================================================
// Add this to any view to test your FCM setup

struct FCMDebugView: View {
    @State private var testResult = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("FCM Debug Tools")
                .font(.title)
            
            Button("Test FCM Setup") {
                Task {
                    await testFCMSetup()
                }
            }
            
            Button("Schedule Test Notification") {
                Task {
                    await PushNotificationManager.shared.scheduleTestNotification()
                    testResult = "✅ Test notification scheduled (5 seconds)"
                }
            }
            
            Button("Check Permission Status") {
                Task {
                    let hasPermission = await PushNotificationManager.shared.checkNotificationPermissions()
                    testResult = hasPermission ? "✅ Permission granted" : "❌ Permission denied"
                }
            }
            
            Text(testResult)
                .foregroundStyle(.secondary)
                .padding()
        }
    }
    
    func testFCMSetup() async {
        testResult = "Testing..."
        
        var results: [String] = []
        
        // 1. Check auth
        if Auth.auth().currentUser != nil {
            results.append("✅ User authenticated")
        } else {
            results.append("❌ Not authenticated")
            testResult = results.joined(separator: "\n")
            return
        }
        
        // 2. Check permission
        let hasPermission = await PushNotificationManager.shared.checkNotificationPermissions()
        if hasPermission {
            results.append("✅ Notification permission granted")
        } else {
            results.append("❌ No notification permission")
        }
        
        // 3. Check FCM token
        if let token = PushNotificationManager.shared.fcmToken {
            results.append("✅ FCM token: \(token.prefix(20))...")
        } else {
            results.append("⚠️ FCM token not available")
        }
        
        // 4. Check Firestore
        await checkFirestoreToken(results: &results)
        
        await MainActor.run {
            testResult = results.joined(separator: "\n")
        }
    }
    
    func checkFirestoreToken(results: inout [String]) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let db = Firestore.firestore()
            let doc = try await db.collection("users").document(userId).getDocument()
            
            if let token = doc.data()?["fcmToken"] as? String {
                results.append("✅ Token saved in Firestore")
                
                if let timestamp = doc.data()?["fcmTokenUpdatedAt"] as? Timestamp {
                    let date = timestamp.dateValue()
                    let formatter = RelativeDateTimeFormatter()
                    let timeAgo = formatter.localizedString(for: date, relativeTo: Date())
                    results.append("📅 Updated \(timeAgo)")
                }
            } else {
                results.append("❌ No token in Firestore")
            }
        } catch {
            results.append("❌ Firestore error: \(error.localizedDescription)")
        }
    }
}

// ============================================================================
// SNIPPET 5: Optional - Add Settings Toggle for Notifications
// ============================================================================

struct NotificationSettingsRow: View {
    @State private var notificationsEnabled = true
    @State private var showPermissionAlert = false
    
    var body: some View {
        Section("Notifications") {
            Toggle("Push Notifications", isOn: $notificationsEnabled)
                .onChange(of: notificationsEnabled) { oldValue, newValue in
                    handleNotificationToggle(newValue)
                }
            
            if notificationsEnabled {
                Button("Schedule Daily Reminders") {
                    Task {
                        await PushNotificationManager.shared.scheduleDailyReminders()
                    }
                }
                
                Button("Cancel Daily Reminders") {
                    Task {
                        await PushNotificationManager.shared.cancelDailyReminders()
                    }
                }
            }
        }
        .onAppear {
            checkNotificationStatus()
        }
        .alert("Enable Notifications", isPresented: $showPermissionAlert) {
            Button("Settings") {
                openAppSettings()
            }
            Button("Cancel", role: .cancel) {
                notificationsEnabled = false
            }
        } message: {
            Text("Please enable notifications in Settings to receive updates.")
        }
    }
    
    func checkNotificationStatus() {
        Task {
            let hasPermission = await PushNotificationManager.shared.checkNotificationPermissions()
            await MainActor.run {
                notificationsEnabled = hasPermission
            }
        }
    }
    
    func handleNotificationToggle(_ enabled: Bool) {
        if enabled {
            // User wants to enable notifications
            Task {
                let granted = await PushNotificationManager.shared.requestNotificationPermissions()
                
                if granted {
                    PushNotificationManager.shared.setupFCMToken()
                } else {
                    // Permission denied, show alert to go to settings
                    await MainActor.run {
                        showPermissionAlert = true
                        notificationsEnabled = false
                    }
                }
            }
        } else {
            // User wants to disable - remove token
            Task {
                await PushNotificationManager.shared.removeFCMTokenFromFirestore()
            }
        }
    }
    
    func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// ============================================================================
// SNIPPET 6: Optional - Banner to Prompt Notification Permission
// ============================================================================

struct NotificationPermissionBanner: View {
    @State private var showBanner = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        if showBanner {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Notifications")
                            .font(.headline)
                        
                        Text("Get notified when someone follows you, comments on your posts, or sends you a message.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                HStack(spacing: 12) {
                    Button("Not Now") {
                        withAnimation {
                            showBanner = false
                        }
                    }
                    .foregroundStyle(.secondary)
                    
                    Button("Enable") {
                        Task {
                            let granted = await PushNotificationManager.shared.requestNotificationPermissions()
                            if granted {
                                PushNotificationManager.shared.setupFCMToken()
                                withAnimation {
                                    showBanner = false
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(radius: 8)
            )
            .padding()
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// Usage in your ContentView:
/*
 ZStack(alignment: .top) {
     // Your main content
     
     NotificationPermissionBanner()
 }
*/

// ============================================================================
// SNIPPET 7: Complete Sign-In Example
// ============================================================================

struct CompleteSignInExample: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isSignedIn = false
    
    var body: some View {
        if isSignedIn {
            Text("Signed In Successfully!")
        } else {
            VStack(spacing: 20) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                
                Button {
                    Task {
                        await signIn()
                    }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Sign In")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || email.isEmpty || password.isEmpty)
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding()
        }
    }
    
    func signIn() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 1. Sign in with Firebase Auth
            try await Auth.auth().signIn(withEmail: email, password: password)
            print("✅ Sign in successful")
            
            // 2. Setup FCM for push notifications
            let granted = await PushNotificationManager.shared.requestNotificationPermissions()
            
            if granted {
                print("✅ Notification permission granted")
                
                // Setup FCM token (saves to Firestore automatically)
                PushNotificationManager.shared.setupFCMToken()
                
                // Optional: Schedule daily reminders
                await PushNotificationManager.shared.scheduleDailyReminders()
            } else {
                print("⚠️ Notification permission denied")
            }
            
            // 3. Update UI
            await MainActor.run {
                isLoading = false
                isSignedIn = true
            }
            
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
            print("❌ Sign in failed: \(error)")
        }
    }
}

// ============================================================================
// SUMMARY: WHERE TO ADD EACH SNIPPET
// ============================================================================

/*
 📝 QUICK REFERENCE:
 
 1. SNIPPET 1 → Add to SignInView.swift
    - Call after successful login
    - Requests permission and sets up FCM
 
 2. SNIPPET 2 → Add to ContentView.swift
    - Add to .onAppear
    - Sets up FCM for already logged-in users
 
 3. SNIPPET 3 → Add to your logout function
    - Add BEFORE Auth.auth().signOut()
    - Removes token from Firestore
 
 4. SNIPPET 4 → Optional debug view
    - Use during development to test FCM
 
 5. SNIPPET 5 → Optional settings toggle
    - Add to SettingsView or ProfileView
 
 6. SNIPPET 6 → Optional permission banner
    - Add to ContentView or HomeView
 
 7. SNIPPET 7 → Complete sign-in example
    - Use as reference for your login flow
 
 ✅ THAT'S IT! Just add snippets 1, 2, and 3 and you're done!
*/

#endif

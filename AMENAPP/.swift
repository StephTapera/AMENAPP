//
//  AuthDebugView.swift
//  AMENAPP
//
//  Created to diagnose authentication issues
//

import SwiftUI
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

struct AuthDebugView: View {
    @State private var testResults: [String] = []
    @State private var isRunning = false
    
    @State private var testEmail = "test@example.com"
    @State private var testPassword = "password123"
    @State private var testDisplayName = "Test User"
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("🔧 Authentication Debugger")
                            .font(.custom("OpenSans-Bold", size: 24))
                        
                        Text("This tool will diagnose authentication issues")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    
                    Divider()
                    
                    // Test Credentials
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Test Credentials")
                            .font(.custom("OpenSans-Bold", size: 18))
                        
                        VStack(spacing: 12) {
                            HStack {
                                Text("Email:")
                                    .frame(width: 100, alignment: .leading)
                                TextField("Email", text: $testEmail)
                                    .textFieldStyle(.roundedBorder)
                                    .autocapitalization(.none)
                            }
                            
                            HStack {
                                Text("Password:")
                                    .frame(width: 100, alignment: .leading)
                                TextField("Password", text: $testPassword)
                                    .textFieldStyle(.roundedBorder)
                                    .autocapitalization(.none)
                            }
                            
                            HStack {
                                Text("Display Name:")
                                    .frame(width: 100, alignment: .leading)
                                TextField("Name", text: $testDisplayName)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    .padding()
                    
                    Divider()
                    
                    // Run Tests Button
                    Button {
                        runDiagnostics()
                    } label: {
                        HStack {
                            if isRunning {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(isRunning ? "Running Tests..." : "Run Full Diagnostic")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isRunning ? Color.gray : Color.blue)
                        )
                    }
                    .disabled(isRunning)
                    .padding(.horizontal)
                    
                    // Quick Test Buttons
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Button {
                                testSignUp()
                            } label: {
                                Text("Test Sign Up")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.green))
                            }
                            .disabled(isRunning)
                            
                            Button {
                                testSignIn()
                            } label: {
                                Text("Test Sign In")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange))
                            }
                            .disabled(isRunning)
                        }
                        
                        // Sign Out Button
                        if Auth.auth().currentUser != nil {
                            Button {
                                signOutUser()
                            } label: {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                    Text("Sign Out Current User")
                                }
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.red))
                            }
                            .disabled(isRunning)
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    
                    // Database Management
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Database Management")
                            .font(.custom("OpenSans-Bold", size: 18))
                        
                        Button {
                            clearSamplePosts()
                        } label: {
                            HStack {
                                Image(systemName: "trash.fill")
                                Text("Clear All Sample Posts")
                            }
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.red))
                        }
                        .disabled(isRunning)
                        
                        Button {
                            clearSampleUsers()
                        } label: {
                            HStack {
                                Image(systemName: "person.2.slash")
                                Text("Clear Sample Users")
                            }
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange))
                        }
                        .disabled(isRunning)
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    
                    // Results
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Diagnostic Results")
                                .font(.custom("OpenSans-Bold", size: 18))
                            
                            Spacer()
                            
                            if !testResults.isEmpty {
                                Button {
                                    testResults.removeAll()
                                } label: {
                                    Text("Clear")
                                        .font(.custom("OpenSans-SemiBold", size: 14))
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        
                        if testResults.isEmpty {
                            Text("No tests run yet. Tap 'Run Full Diagnostic' to start.")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                                .padding()
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(testResults.indices, id: \.self) { index in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(index + 1).")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 30, alignment: .leading)
                                        
                                        Text(testResults[index])
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(resultColor(testResults[index]))
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.1))
                            )
                        }
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func resultColor(_ text: String) -> Color {
        if text.contains("✅") || text.contains("SUCCESS") {
            return .green
        } else if text.contains("❌") || text.contains("ERROR") || text.contains("FAIL") {
            return .red
        } else if text.contains("⚠️") || text.contains("WARNING") {
            return .orange
        } else if text.contains("🔍") {
            return .blue
        } else {
            return .primary
        }
    }
    
    private func log(_ message: String) {
        testResults.append(message)
        print(message)
    }
    
    private func runDiagnostics() {
        testResults.removeAll()
        isRunning = true
        
        Task {
            await performDiagnostics()
            await MainActor.run {
                isRunning = false
            }
        }
    }
    
    private func performDiagnostics() async {
        log("🔍 Starting Full Diagnostic...")
        log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Test 1: Firebase Configuration
        log("🔍 Test 1: Firebase Configuration")
        if FirebaseApp.app() != nil {
            log("✅ Firebase is configured")
            if let app = FirebaseApp.app() {
                log("   App Name: \(app.name)")
                log("   Google App ID: \(app.options.googleAppID)")
            }
        } else {
            log("❌ Firebase NOT configured!")
            log("   Solution: Check GoogleService-Info.plist")
            log("   1. Download GoogleService-Info.plist from Firebase Console")
            log("   2. Add it to your Xcode project")
            log("   3. Ensure 'Copy items if needed' is checked")
            return
        }
        
        // Test 2: Auth Instance
        log("🔍 Test 2: Auth Instance")
        let auth = Auth.auth()
        log("✅ Auth instance created")
        log("   Auth domain: \(auth.app?.options.projectID ?? "unknown")")
        
        // Test 3: Current User
        log("🔍 Test 3: Current User Status")
        if let user = auth.currentUser {
            log("✅ User is logged in")
            log("   UID: \(user.uid)")
            log("   Email: \(user.email ?? "No email")")
            log("   Display Name: \(user.displayName ?? "No name")")
            log("   Email Verified: \(user.isEmailVerified)")
        } else {
            log("⚠️ No user currently logged in")
        }
        
        // Test 4: Firebase Auth Settings
        log("🔍 Test 4: Firebase Auth Settings")
        log("⚠️ Check Firebase Console:")
        log("   1. Go to Authentication → Sign-in method")
        log("   2. Ensure Email/Password is ENABLED")
        log("   3. Check if there are any domain restrictions")
        
        // Test 5: Firestore Connection
        log("🔍 Test 5: Firestore Connection")
        let db = Firestore.firestore()
        do {
            // Try to read from Firestore
            let testRef = db.collection("_test_").document("connection_test")
            try await testRef.setData(["timestamp": Date(), "test": true])
            log("✅ Firestore write successful")
            try await testRef.delete()
            log("✅ Firestore delete successful")
        } catch {
            log("❌ Firestore connection failed")
            log("   Error: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                log("   Error Code: \(nsError.code)")
                log("   Error Domain: \(nsError.domain)")
            }
        }
        
        // Test 6: Network Connectivity
        log("🔍 Test 6: Network Connectivity")
        do {
            // Try to reach Firebase Auth REST API
            let url = URL(string: "https://www.googleapis.com/identitytoolkit/v3/relyingparty/publicKeys")!
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    log("✅ Network connection to Firebase working")
                } else {
                    log("⚠️ Network issue - Status code: \(httpResponse.statusCode)")
                }
            }
        } catch {
            log("❌ Network connection failed")
            log("   Error: \(error.localizedDescription)")
            log("   Check: WiFi/cellular is connected")
            log("   Check: No VPN or firewall blocking Firebase")
        }
        
        // Test 7: FirebaseManager
        log("🔍 Test 7: FirebaseManager Singleton")
        let firebaseManager = FirebaseManager.shared
        log("✅ FirebaseManager initialized")
        log("   Is Authenticated: \(firebaseManager.isAuthenticated)")
        
        // Test 8: AuthenticationViewModel
        log("🔍 Test 8: AuthenticationViewModel")
        let authViewModel = AuthenticationViewModel()
        log("✅ AuthenticationViewModel initialized")
        log("   Is Authenticated: \(authViewModel.isAuthenticated)")
        log("   Needs Onboarding: \(authViewModel.needsOnboarding)")
        
        log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        log("🎯 Diagnostic Complete!")
        log("")
        log("Next Steps:")
        log("1. Check all ✅ tests passed")
        log("2. If network failed, check internet connection")
        log("3. Try 'Test Sign Up' button above")
        log("4. Check Xcode console for detailed errors")
    }
    
    private func testSignUp() {
        testResults.removeAll()
        isRunning = true
        log("🔍 Testing Sign Up...")
        
        Task {
            do {
                // Validate inputs first
                log("📋 Validating inputs...")
                if testEmail.isEmpty {
                    log("❌ Email is empty!")
                    await MainActor.run { isRunning = false }
                    return
                }
                if testPassword.isEmpty {
                    log("❌ Password is empty!")
                    await MainActor.run { isRunning = false }
                    return
                }
                if testPassword.count < 6 {
                    log("⚠️ Warning: Password should be at least 6 characters")
                }
                
                log("📝 Creating account with email: \(testEmail)")
                log("   Password length: \(testPassword.count) characters")
                
                let auth = Auth.auth()
                let result = try await auth.createUser(withEmail: testEmail, password: testPassword)
                
                log("✅ SUCCESS! User created")
                log("   UID: \(result.user.uid)")
                log("   Email: \(result.user.email ?? "")")
                
                // Create Firestore profile
                log("📝 Creating Firestore profile...")
                let db = Firestore.firestore()
                try await db.collection("users").document(result.user.uid).setData([
                    "displayName": testDisplayName,
                    "email": testEmail,
                    "createdAt": Timestamp(date: Date()),
                    "updatedAt": Timestamp(date: Date())
                ])
                
                log("✅ Firestore profile created!")
                log("")
                log("🎉 SIGN UP SUCCESSFUL!")
                log("   You can now sign in with:")
                log("   Email: \(testEmail)")
                log("   Password: \(testPassword)")
                
            } catch let error as NSError {
                log("❌ Sign Up FAILED")
                log("   Error Domain: \(error.domain)")
                log("   Error Code: \(error.code)")
                log("   Error: \(error.localizedDescription)")
                
                // Common Firebase Auth error codes
                switch error.code {
                case 17007: // ERROR_EMAIL_ALREADY_IN_USE
                    log("")
                    log("ℹ️ This email is already registered")
                    log("   Try signing in instead")
                    log("   Or use a different email")
                    log("   Or delete the existing account from Firebase Console")
                    
                case 17026: // ERROR_WEAK_PASSWORD
                    log("")
                    log("ℹ️ Password is too weak")
                    log("   Use at least 6 characters")
                    log("   Current length: \(testPassword.count)")
                    
                case 17008: // ERROR_INVALID_EMAIL
                    log("")
                    log("ℹ️ Invalid email format")
                    log("   Check the email address is valid")
                    
                case 17020: // ERROR_NETWORK_REQUEST_FAILED
                    log("")
                    log("ℹ️ Network connection failed")
                    log("   Check your internet connection")
                    log("   Make sure Firebase is not blocked")
                    
                case 17999: // ERROR_INTERNAL_ERROR
                    log("")
                    log("ℹ️ Internal Firebase error")
                    log("   Check Firebase Console configuration")
                    log("   Ensure Email/Password auth is enabled")
                    
                default:
                    log("")
                    log("ℹ️ Unknown error occurred")
                    log("   Check Firebase Console for issues")
                    log("   Verify Email/Password authentication is enabled")
                    log("   Error details: \(error.userInfo)")
                }
            }
            
            await MainActor.run {
                isRunning = false
            }
        }
    }
    
    private func testSignIn() {
        testResults.removeAll()
        isRunning = true
        log("🔍 Testing Sign In...")
        
        Task {
            do {
                // Validate inputs first
                log("📋 Validating inputs...")
                if testEmail.isEmpty {
                    log("❌ Email is empty!")
                    await MainActor.run { isRunning = false }
                    return
                }
                if testPassword.isEmpty {
                    log("❌ Password is empty!")
                    await MainActor.run { isRunning = false }
                    return
                }
                
                log("📝 Signing in with email: \(testEmail)")
                
                let auth = Auth.auth()
                let result = try await auth.signIn(withEmail: testEmail, password: testPassword)
                
                log("✅ SUCCESS! Signed in")
                log("   UID: \(result.user.uid)")
                log("   Email: \(result.user.email ?? "")")
                log("   Email Verified: \(result.user.isEmailVerified)")
                
                // Check Firestore profile
                log("🔍 Checking Firestore profile...")
                let db = Firestore.firestore()
                let doc = try await db.collection("users").document(result.user.uid).getDocument()
                
                if doc.exists {
                    log("✅ Firestore profile exists")
                    if let data = doc.data() {
                        log("   Display Name: \(data["displayName"] as? String ?? "N/A")")
                        log("   Email: \(data["email"] as? String ?? "N/A")")
                        if let createdAt = data["createdAt"] as? Timestamp {
                            log("   Account Created: \(createdAt.dateValue())")
                        }
                    }
                } else {
                    log("⚠️ No Firestore profile found")
                    log("   Account exists but no profile data")
                    log("   Creating profile now...")
                    
                    // Create missing profile
                    try await db.collection("users").document(result.user.uid).setData([
                        "displayName": testDisplayName,
                        "email": testEmail,
                        "createdAt": Timestamp(date: Date()),
                        "updatedAt": Timestamp(date: Date())
                    ])
                    log("✅ Profile created!")
                }
                
                log("")
                log("🎉 SIGN IN SUCCESSFUL!")
                
            } catch let error as NSError {
                log("❌ Sign In FAILED")
                log("   Error Domain: \(error.domain)")
                log("   Error Code: \(error.code)")
                log("   Error: \(error.localizedDescription)")
                
                // Common Firebase Auth error codes
                switch error.code {
                case 17011: // ERROR_USER_NOT_FOUND
                    log("")
                    log("ℹ️ No account found with this email")
                    log("   Email: \(testEmail)")
                    log("   Try signing up first")
                    log("   Or check if email is correct")
                    
                case 17009: // ERROR_WRONG_PASSWORD
                    log("")
                    log("ℹ️ Wrong password")
                    log("   Check your password and try again")
                    log("   Or use 'Forgot Password' to reset")
                    
                case 17008: // ERROR_INVALID_EMAIL
                    log("")
                    log("ℹ️ Invalid email format")
                    log("   Check the email address is valid")
                    
                case 17020: // ERROR_NETWORK_REQUEST_FAILED
                    log("")
                    log("ℹ️ Network connection failed")
                    log("   Check your internet connection")
                    log("   Make sure Firebase is not blocked")
                    
                case 17010: // ERROR_USER_DISABLED
                    log("")
                    log("ℹ️ This account has been disabled")
                    log("   Contact support or check Firebase Console")
                    
                default:
                    log("")
                    log("ℹ️ Unknown error occurred")
                    log("   Check Firebase Console for issues")
                    log("   Verify Email/Password authentication is enabled")
                    log("   Error details: \(error.userInfo)")
                }
            }
            
            await MainActor.run {
                isRunning = false
            }
        }
    }
    
    private func signOutUser() {
        testResults.removeAll()
        log("🔍 Signing out current user...")
        
        do {
            try Auth.auth().signOut()
            log("✅ Sign out successful!")
            log("   You can now test sign up/sign in again")
        } catch {
            log("❌ Sign out failed")
            log("   Error: \(error.localizedDescription)")
        }
    }
    
    private func clearSamplePosts() {
        testResults.removeAll()
        isRunning = true
        log("🗑️ Clearing all sample posts...")
        
        Task {
            do {
                let db = Firestore.firestore()
                
                // Check authentication
                guard Auth.auth().currentUser != nil else {
                    log("❌ Not authenticated!")
                    log("   You must be signed in to delete posts")
                    await MainActor.run { isRunning = false }
                    return
                }
                
                // Get all posts
                log("📋 Fetching all posts...")
                let snapshot = try await db.collection("posts").getDocuments()
                
                let totalPosts = snapshot.documents.count
                log("   Found \(totalPosts) posts to delete")
                
                if totalPosts == 0 {
                    log("⚠️ No posts found in database")
                    await MainActor.run { isRunning = false }
                    return
                }
                
                // Delete one by one to get better error messages
                var deletedCount = 0
                var failedCount = 0
                
                for (index, document) in snapshot.documents.enumerated() {
                    do {
                        try await document.reference.delete()
                        deletedCount += 1
                        
                        // Log progress every 10 posts
                        if (index + 1) % 10 == 0 || index == snapshot.documents.count - 1 {
                            log("   Deleted \(deletedCount)/\(totalPosts) posts...")
                        }
                    } catch let deleteError as NSError {
                        failedCount += 1
                        
                        if failedCount == 1 {
                            // Only log detailed error for first failure
                            log("⚠️ Failed to delete post: \(document.documentID)")
                            log("   Error: \(deleteError.localizedDescription)")
                            log("   Error Code: \(deleteError.code)")
                            log("   Error Domain: \(deleteError.domain)")
                            
                            if deleteError.code == 7 {
                                log("")
                                log("❌ PERMISSION DENIED ERROR")
                                log("")
                                log("🔧 FIX: Update Firestore Security Rules")
                                log("   1. Go to Firebase Console")
                                log("   2. Firestore Database → Rules")
                                log("   3. Add this rule:")
                                log("")
                                log("   match /posts/{postId} {")
                                log("     allow read: if true;")
                                log("     allow write, delete: if request.auth != null;")
                                log("   }")
                                log("")
                                log("   4. Click Publish")
                                log("   5. Wait 60 seconds")
                                log("   6. Try again")
                                
                                // Stop trying after first permission error
                                break
                            }
                        }
                    }
                }
                
                log("")
                if deletedCount > 0 {
                    log("✅ Successfully deleted \(deletedCount) posts!")
                }
                if failedCount > 0 {
                    log("⚠️ Failed to delete \(failedCount) posts")
                    log("   See error message above for fix")
                }
                
                if deletedCount == totalPosts {
                    log("🎉 All posts have been removed!")
                    log("")
                    log("Note: Refresh your app to see changes")
                }
                
            } catch {
                log("❌ Failed to fetch posts")
                log("   Error: \(error.localizedDescription)")
                
                if let nsError = error as NSError? {
                    log("   Error Code: \(nsError.code)")
                    log("   Error Domain: \(nsError.domain)")
                }
            }
            
            await MainActor.run {
                isRunning = false
            }
        }
    }
    
    private func clearSampleUsers() {
        testResults.removeAll()
        isRunning = true
        log("🗑️ Clearing sample users...")
        
        Task {
            do {
                let db = Firestore.firestore()
                
                // Check authentication
                guard Auth.auth().currentUser != nil else {
                    log("❌ Not authenticated!")
                    log("   You must be signed in to delete users")
                    await MainActor.run { isRunning = false }
                    return
                }
                
                // Define sample user IDs (from FirebaseDataSeeder)
                let sampleUserIds = [
                    "sample_user_1", "sample_user_2", "sample_user_3", "sample_user_4",
                    "sample_user_5", "sample_user_6", "sample_user_7", "sample_user_8",
                    "sample_user_9", "sample_user_10", "sample_user_11", "sample_user_12",
                    "sample_user_13", "sample_user_14", "sample_user_15", "sample_user_16"
                ]
                
                log("📋 Deleting \(sampleUserIds.count) sample users...")
                
                var deletedCount = 0
                var failedCount = 0
                
                for userId in sampleUserIds {
                    do {
                        let userRef = db.collection("users").document(userId)
                        try await userRef.delete()
                        deletedCount += 1
                    } catch let deleteError as NSError {
                        failedCount += 1
                        
                        if failedCount == 1 {
                            log("⚠️ Failed to delete user: \(userId)")
                            log("   Error: \(deleteError.localizedDescription)")
                            log("   Error Code: \(deleteError.code)")
                            
                            if deleteError.code == 7 {
                                log("")
                                log("❌ PERMISSION DENIED ERROR")
                                log("")
                                log("🔧 FIX: Update Firestore Security Rules")
                                log("   1. Go to Firebase Console")
                                log("   2. Firestore Database → Rules")
                                log("   3. Add this rule:")
                                log("")
                                log("   match /users/{userId} {")
                                log("     allow read: if request.auth != null;")
                                log("     allow write, delete: if request.auth != null;")
                                log("   }")
                                log("")
                                log("   4. Click Publish")
                                log("   5. Wait 60 seconds")
                                log("   6. Try again")
                                
                                break
                            }
                        }
                    }
                }
                
                log("")
                if deletedCount > 0 {
                    log("✅ Successfully deleted \(deletedCount) sample users!")
                }
                if failedCount > 0 {
                    log("⚠️ Failed to delete \(failedCount) users")
                }
                
                if deletedCount == sampleUserIds.count {
                    log("🎉 All sample user profiles removed")
                    log("")
                    log("Note: This only removes Firestore profiles")
                    log("      Auth accounts (if any) remain")
                }
                
            } catch {
                log("❌ Failed to delete sample users")
                log("   Error: \(error.localizedDescription)")
                
                if let nsError = error as NSError? {
                    log("   Error Code: \(nsError.code)")
                    log("   Error Domain: \(nsError.domain)")
                }
            }
            
            await MainActor.run {
                isRunning = false
            }
        }
    }
}

#Preview {
    AuthDebugView()
}

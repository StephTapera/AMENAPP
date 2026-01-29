//
//  QuickAuthTest.swift
//  AMENAPP
//
//  Quick test to diagnose sign in/up issues
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseCore

struct QuickAuthTest: View {
    @State private var testEmail = "test@test.com"
    @State private var testPassword = "test123"
    @State private var testDisplayName = "Test User"
    @State private var testUsername = "testuser\(Int.random(in: 1000...9999))" // Random username
    @State private var message = ""
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Quick Auth Test")
                .font(.title.bold())
            
            TextField("Email", text: $testEmail)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .padding(.horizontal)
            
            SecureField("Password", text: $testPassword)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            
            TextField("Display Name", text: $testDisplayName)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            
            TextField("Username", text: $testUsername)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .padding(.horizontal)
            
            HStack(spacing: 12) {
                Button("Test Sign Up") {
                    testSignUp()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
                
                Button("Test Sign In") {
                    testSignIn()
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }
            
            HStack(spacing: 12) {
                Button("Check Profile") {
                    checkProfile()
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
                
                Button("Sign Out") {
                    signOut()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(isLoading)
            }
            
            HStack(spacing: 12) {
                Button("Check Username") {
                    checkUsername()
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .disabled(isLoading)
                
                Button("Delete Current User") {
                    deleteCurrentUser()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(isLoading)
            }
            
            if isLoading {
                ProgressView()
            }
            
            ScrollView {
                Text(message)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
            }
            .frame(height: 300)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .padding()
        }
        .padding()
    }
    
    private func testSignUp() {
        message = "🔍 Testing Sign Up...\n"
        isLoading = true
        
        Task {
            do {
                // Step 1: Check Firebase
                message += "✅ Firebase configured: \(FirebaseApp.app() != nil)\n"
                
                // Step 2: Use FirebaseManager to sign up (like the real app does)
                message += "📝 Using FirebaseManager.signUp()...\n"
                let firebaseManager = FirebaseManager.shared
                
                let user = try await firebaseManager.signUp(
                    email: testEmail,
                    password: testPassword,
                    displayName: testDisplayName,
                    username: testUsername
                )
                
                message += "✅ SUCCESS! User created\n"
                message += "   UID: \(user.uid)\n"
                message += "   Email: \(user.email ?? "")\n"
                
                // Step 3: Verify profile was created in Firestore
                message += "📝 Checking Firestore profile...\n"
                let db = Firestore.firestore()
                let doc = try await db.collection("users").document(user.uid).getDocument()
                
                if doc.exists {
                    let data = doc.data() ?? [:]
                    message += "✅ Firestore profile found!\n"
                    message += "   Display Name: \(data["displayName"] as? String ?? "N/A")\n"
                    message += "   Username: @\(data["username"] as? String ?? "N/A")\n"
                    message += "   Email: \(data["email"] as? String ?? "N/A")\n"
                } else {
                    message += "❌ Profile NOT found in Firestore!\n"
                }
                
                message += "\n🎉 SIGN UP COMPLETE!\n"
                
            } catch let error as NSError {
                message += "❌ ERROR:\n"
                message += "   Code: \(error.code)\n"
                message += "   Domain: \(error.domain)\n"
                message += "   Message: \(error.localizedDescription)\n"
                
                // Specific error codes
                switch error.code {
                case 17007:
                    message += "\n💡 Email already in use - try signing in instead\n"
                case 17026:
                    message += "\n💡 Password too weak - use 6+ characters\n"
                case 17008:
                    message += "\n💡 Invalid email format\n"
                case 17999:
                    message += "\n💡 Go to Firebase Console:\n"
                    message += "   1. Authentication → Sign-in method\n"
                    message += "   2. Enable Email/Password\n"
                default:
                    message += "\n💡 Check Firebase Console settings\n"
                }
            }
            
            isLoading = false
        }
    }
    
    private func checkProfile() {
        message = "🔍 Checking Current User Profile...\n"
        isLoading = true
        
        Task {
            do {
                guard let currentUser = Auth.auth().currentUser else {
                    message += "❌ No user is signed in\n"
                    message += "\n💡 Sign in first, then check profile\n"
                    isLoading = false
                    return
                }
                
                message += "✅ Firebase Auth User:\n"
                message += "   UID: \(currentUser.uid)\n"
                message += "   Email: \(currentUser.email ?? "N/A")\n"
                message += "   Display Name (Auth): \(currentUser.displayName ?? "N/A")\n"
                message += "\n"
                
                let db = Firestore.firestore()
                message += "📝 Fetching Firestore document...\n"
                message += "   Path: users/\(currentUser.uid)\n\n"
                
                let doc = try await db.collection("users").document(currentUser.uid).getDocument()
                
                if doc.exists {
                    let data = doc.data() ?? [:]
                    message += "✅ Firestore Document Found!\n\n"
                    message += "📋 COMPLETE Profile Data:\n"
                    message += "─────────────────────────────\n"
                    message += "Display Name: '\(data["displayName"] as? String ?? "N/A")'\n"
                    message += "Username: '@\(data["username"] as? String ?? "N/A")'\n"
                    message += "Email: '\(data["email"] as? String ?? "N/A")'\n"
                    message += "Bio: '\(data["bio"] as? String ?? "")'\n"
                    message += "Initials: '\(data["initials"] as? String ?? "N/A")'\n"
                    message += "Followers: \(data["followersCount"] as? Int ?? 0)\n"
                    message += "Following: \(data["followingCount"] as? Int ?? 0)\n"
                    message += "Posts: \(data["postsCount"] as? Int ?? 0)\n"
                    message += "─────────────────────────────\n\n"
                    
                    // Check if it's old data
                    let username = data["username"] as? String ?? ""
                    let displayName = data["displayName"] as? String ?? ""
                    
                    if displayName == "User" || username == testEmail.components(separatedBy: "@").first?.lowercased() {
                        message += "⚠️ WARNING: This looks like OLD DATA!\n"
                        message += "   The account was created before the fix.\n\n"
                        message += "💡 Solutions:\n"
                        message += "   1. Delete this user (tap 'Delete Current User')\n"
                        message += "   2. Sign up with a new account\n"
                        message += "   3. Or use Edit Profile to update manually\n"
                    } else {
                        message += "✅ Data looks correct!\n"
                        message += "   This account has proper display name and username\n"
                    }
                } else {
                    message += "❌ Firestore Document NOT FOUND!\n\n"
                    message += "⚠️ CRITICAL: Auth account exists but no Firestore profile!\n\n"
                    message += "💡 This means:\n"
                    message += "   - Firebase Auth account was created\n"
                    message += "   - But Firestore profile creation failed\n"
                    message += "   - ProfileView won't show any data\n\n"
                    message += "🔧 Fix:\n"
                    message += "   1. Delete this user\n"
                    message += "   2. Sign up again (with new email)\n"
                    message += "   3. Check console logs during sign-up\n"
                }
                
            } catch {
                message += "❌ ERROR: \(error.localizedDescription)\n"
            }
            
            isLoading = false
        }
    }
    
    private func testSignIn() {
        message = "🔍 Testing Sign In...\n"
        isLoading = true
        
        Task {
            do {
                message += "✅ Firebase configured: \(FirebaseApp.app() != nil)\n"
                
                let auth = Auth.auth()
                message += "📝 Email: \(testEmail)\n"
                message += "📝 Password length: \(testPassword.count) characters\n"
                message += "📝 Attempting sign in...\n"
                
                let result = try await auth.signIn(withEmail: testEmail, password: testPassword)
                message += "✅ SUCCESS! Signed in\n"
                message += "   UID: \(result.user.uid)\n"
                message += "   Email: \(result.user.email ?? "")\n"
                
                // Check Firestore profile
                message += "📝 Checking Firestore profile...\n"
                let db = Firestore.firestore()
                let doc = try await db.collection("users").document(result.user.uid).getDocument()
                
                if doc.exists {
                    let data = doc.data() ?? [:]
                    message += "✅ Profile exists!\n"
                    message += "   Display Name: \(data["displayName"] as? String ?? "N/A")\n"
                    message += "   Username: @\(data["username"] as? String ?? "N/A")\n"
                } else {
                    message += "⚠️ No Firestore profile found (Auth account exists though)\n"
                }
                
                message += "\n🎉 SIGN IN COMPLETE!\n"
                
            } catch let error as NSError {
                message += "❌ SIGN IN FAILED\n\n"
                message += "Error Details:\n"
                message += "   Code: \(error.code)\n"
                message += "   Domain: \(error.domain)\n"
                message += "   Message: \(error.localizedDescription)\n\n"
                
                // Detailed error handling
                switch error.code {
                case 17011: // ERROR_USER_NOT_FOUND
                    message += "💡 No account exists with email: \(testEmail)\n"
                    message += "   → Tap 'Test Sign Up' to create account first\n"
                    
                case 17009: // ERROR_WRONG_PASSWORD
                    message += "💡 Password is incorrect for: \(testEmail)\n"
                    message += "   → Check your password and try again\n"
                    message += "   → Current password attempt: '\(testPassword)'\n"
                    
                case 17008: // ERROR_INVALID_EMAIL
                    message += "💡 Email format is invalid: \(testEmail)\n"
                    message += "   → Check for typos in email address\n"
                    
                case 17020: // ERROR_NETWORK_REQUEST_FAILED
                    message += "💡 Network error - check your internet connection\n"
                    
                case 17010: // ERROR_USER_DISABLED
                    message += "💡 This account has been disabled\n"
                    
                default:
                    message += "💡 Unexpected error (code \(error.code))\n"
                    message += "   → Try checking Firebase Console\n"
                }
                
                message += "\n🔍 Debug Info:\n"
                message += "   Email entered: '\(testEmail)'\n"
                message += "   Password length: \(testPassword.count) chars\n"
            }
            
            isLoading = false
        }
    }
    
    private func signOut() {
        message = "🔍 Signing out...\n"
        
        do {
            try Auth.auth().signOut()
            message += "✅ Signed out successfully!\n"
            message += "   You can now sign in with a different account\n"
        } catch {
            message += "❌ Sign out failed: \(error.localizedDescription)\n"
        }
    }
    
    private func checkUsername() {
        message = "🔍 Checking if username '\(testUsername)' is available...\n"
        isLoading = true
        
        Task {
            do {
                let db = Firestore.firestore()
                
                // Query for users with this username
                let snapshot = try await db.collection("users")
                    .whereField("username", isEqualTo: testUsername.lowercased())
                    .getDocuments()
                
                if snapshot.documents.isEmpty {
                    message += "✅ Username '@\(testUsername)' is AVAILABLE!\n"
                    message += "   You can use this username for sign up\n"
                } else {
                    message += "❌ Username '@\(testUsername)' is TAKEN\n"
                    message += "   Found \(snapshot.documents.count) user(s) with this username:\n\n"
                    
                    for doc in snapshot.documents {
                        let data = doc.data()
                        message += "   User ID: \(doc.documentID)\n"
                        message += "   Display Name: \(data["displayName"] as? String ?? "N/A")\n"
                        message += "   Email: \(data["email"] as? String ?? "N/A")\n"
                        message += "   ─────────────────\n"
                    }
                    
                    message += "\n💡 Try a different username or delete the existing user\n"
                }
                
            } catch {
                message += "❌ Error checking username: \(error.localizedDescription)\n"
            }
            
            isLoading = false
        }
    }
    
    private func deleteCurrentUser() {
        message = "🗑️ Deleting current user account...\n"
        isLoading = true
        
        Task {
            do {
                guard let currentUser = Auth.auth().currentUser else {
                    message += "❌ No user is currently signed in\n"
                    message += "   Please sign in first, then try deleting\n"
                    isLoading = false
                    return
                }
                
                let userId = currentUser.uid
                let email = currentUser.email ?? "unknown"
                
                message += "⚠️ Deleting user:\n"
                message += "   UID: \(userId)\n"
                message += "   Email: \(email)\n\n"
                
                // Delete Firestore document
                message += "📝 Deleting Firestore profile...\n"
                let db = Firestore.firestore()
                try await db.collection("users").document(userId).delete()
                message += "✅ Firestore profile deleted\n"
                
                // Delete Auth account
                message += "📝 Deleting Firebase Auth account...\n"
                try await currentUser.delete()
                message += "✅ Auth account deleted\n"
                
                message += "\n🎉 User completely deleted!\n"
                message += "   You can now sign up with the same email/username\n"
                
            } catch let error as NSError {
                message += "❌ Delete failed:\n"
                message += "   Code: \(error.code)\n"
                message += "   Message: \(error.localizedDescription)\n"
                
                if error.code == 17014 {
                    message += "\n💡 You need to re-authenticate first:\n"
                    message += "   1. Sign out\n"
                    message += "   2. Sign in again\n"
                    message += "   3. Try deleting again\n"
                }
            }
            
            isLoading = false
        }
    }
}

#Preview {
    QuickAuthTest()
}

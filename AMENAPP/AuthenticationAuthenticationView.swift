//
//  AuthenticationView.swift
//  AMENAPP
//
//  Created by Steph on 1/18/26.
//
//  Modern authentication with email/social login and smooth animations
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct AuthenticationView: View {
    var initialMode: AppLaunchView.AuthMode = .login
    
    @State private var isLogin = true
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var fullName = ""
    @State private var username = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var shakeOffset: CGFloat = 0
    
    @Environment(\.dismiss) var dismiss
    
    init(initialMode: AppLaunchView.AuthMode = .login) {
        self.initialMode = initialMode
        self._isLogin = State(initialValue: initialMode == .login)
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.5, green: 0.3, blue: 0.9),
                    Color(red: 0.6, green: 0.4, blue: 1.0),
                    Color(red: 0.4, green: 0.2, blue: 0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Floating circles background
            GeometryReader { geometry in
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 200, height: 200)
                    .blur(radius: 40)
                    .offset(x: -50, y: -50)
                
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 300, height: 300)
                    .blur(radius: 60)
                    .offset(x: geometry.size.width - 150, y: geometry.size.height - 200)
            }
            
            ScrollView {
                VStack(spacing: 32) {
                    // Logo and Header
                    VStack(spacing: 16) {
                        // App Icon/Logo
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 100, height: 100)
                                .blur(radius: 20)
                            
                            Circle()
                                .fill(Color.white)
                                .frame(width: 80, height: 80)
                                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                            
                            Image(systemName: "cross.fill")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(red: 0.5, green: 0.3, blue: 0.9), Color(red: 0.6, green: 0.4, blue: 1.0)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .padding(.top, 60)
                        
                        Text("AMEN")
                            .font(.custom("OpenSans-Bold", size: 36))
                            .foregroundStyle(.white)
                        
                        Text(isLogin ? "Welcome Back!" : "Join Our Community")
                            .font(.custom("OpenSans-Regular", size: 16))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    
                    // Auth Form Card
                    VStack(spacing: 24) {
                        // Toggle between Login/Signup
                        HStack(spacing: 0) {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    isLogin = true
                                    errorMessage = nil
                                }
                            } label: {
                                Text("Login")
                                    .font(.custom("OpenSans-Bold", size: 16))
                                    .foregroundStyle(isLogin ? Color(red: 0.5, green: 0.3, blue: 0.9) : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(isLogin ? Color.white : Color.clear)
                                            .shadow(color: isLogin ? .black.opacity(0.1) : .clear, radius: 8, y: 2)
                                    )
                            }
                            
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    isLogin = false
                                    errorMessage = nil
                                }
                            } label: {
                                Text("Sign Up")
                                    .font(.custom("OpenSans-Bold", size: 16))
                                    .foregroundStyle(!isLogin ? Color(red: 0.5, green: 0.3, blue: 0.9) : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(!isLogin ? Color.white : Color.clear)
                                            .shadow(color: !isLogin ? .black.opacity(0.1) : .clear, radius: 8, y: 2)
                                    )
                            }
                        }
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.3))
                        )
                        
                        // Error Message
                        if let errorMessage = errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14))
                                Text(errorMessage)
                                    .font(.custom("OpenSans-SemiBold", size: 13))
                            }
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.red.opacity(0.1))
                            )
                            .offset(x: shakeOffset)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        
                        // Input Fields
                        VStack(spacing: 16) {
                            // Full Name (Sign up only)
                            if !isLogin {
                                AuthInputField(
                                    icon: "person.fill",
                                    placeholder: "Full Name",
                                    text: $fullName,
                                    isSecure: false
                                )
                                .transition(.opacity.combined(with: .move(edge: .top)))
                                
                                AuthInputField(
                                    icon: "at",
                                    placeholder: "Username",
                                    text: $username,
                                    isSecure: false
                                )
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                            
                            // Email or Username
                            AuthInputField(
                                icon: isLogin ? "at" : "envelope.fill",
                                placeholder: isLogin ? "Email or Username" : "Email",
                                text: $email,
                                isSecure: false,
                                keyboardType: isLogin ? .default : .emailAddress
                            )
                            
                            // Password
                            AuthInputField(
                                icon: "lock.fill",
                                placeholder: "Password",
                                text: $password,
                                isSecure: !showPassword,
                                showPasswordToggle: true,
                                showPassword: $showPassword
                            )
                            
                            // Confirm Password (Sign up only)
                            if !isLogin {
                                AuthInputField(
                                    icon: "lock.fill",
                                    placeholder: "Confirm Password",
                                    text: $confirmPassword,
                                    isSecure: !showPassword
                                )
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        
                        // Forgot Password (Login only)
                        if isLogin {
                            Button {
                                // Handle forgot password
                            } label: {
                                Text("Forgot Password?")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(Color(red: 0.5, green: 0.3, blue: 0.9))
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .transition(.opacity)
                        }
                        
                        // Submit Button
                        Button {
                            handleAuthentication()
                        } label: {
                            HStack(spacing: 10) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text(isLogin ? "Login" : "Create Account")
                                        .font(.custom("OpenSans-Bold", size: 17))
                                    
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 16, weight: .bold))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(red: 0.5, green: 0.3, blue: 0.9), Color(red: 0.6, green: 0.4, blue: 1.0)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                            )
                        }
                        .disabled(isLoading || !isFormValid)
                        .opacity(isFormValid ? 1.0 : 0.6)
                        
                        // Divider
                        HStack(spacing: 16) {
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 1)
                            
                            Text("OR")
                                .font(.custom("OpenSans-SemiBold", size: 13))
                                .foregroundStyle(.white.opacity(0.7))
                            
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 1)
                        }
                        
                        // Social Login Buttons
                        VStack(spacing: 12) {
                            SocialLoginButton(
                                icon: "apple.logo",
                                title: "Continue with Apple",
                                backgroundColor: .black
                            ) {
                                // Handle Apple login
                            }
                            
                            SocialLoginButton(
                                icon: "g.circle.fill",
                                title: "Continue with Google",
                                backgroundColor: .white,
                                foregroundColor: .black
                            ) {
                                // Handle Google login
                            }
                            
                            SocialLoginButton(
                                icon: "envelope.fill",
                                title: "Continue with Email",
                                backgroundColor: Color(red: 0.3, green: 0.5, blue: 0.9)
                            ) {
                                // Handle email login
                            }
                        }
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.white.opacity(0.95))
                            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                    )
                    .padding(.horizontal, 20)
                    
                    // Terms and Privacy
                    Text(!isLogin ? "By signing up, you agree to our\n[Terms of Service](https://amenapp.com/terms) and [Privacy Policy](https://amenapp.com/privacy)" : "")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .opacity(!isLogin ? 1 : 0)
                    
                    Spacer(minLength: 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
    
    private var isFormValid: Bool {
        if isLogin {
            return !email.isEmpty && !password.isEmpty
        } else {
            return !fullName.isEmpty && !username.isEmpty && !email.isEmpty && !password.isEmpty && !confirmPassword.isEmpty && password == confirmPassword
        }
    }
    
    private func handleAuthentication() {
        // Validate
        guard isFormValid else {
            showError("Please fill in all fields")
            return
        }
        
        if !isLogin && password != confirmPassword {
            showError("Passwords don't match")
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // REAL Firebase authentication
        Task {
            do {
                if isLogin {
                    // Try to determine if input is email or username
                    let loginEmail: String
                    if email.contains("@") {
                        // It's an email
                        loginEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        // It's a username - look up the email
                        print("🔍 Looking up email for username: \(email)")
                        loginEmail = try await lookupEmailByUsername(email.lowercased())
                    }
                    
                    // Sign in with email
                    _ = try await Auth.auth().signIn(withEmail: loginEmail, password: password)
                    print("✅ Successfully signed in")
                } else {
                    // Validate username format
                    let cleanUsername = username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    guard cleanUsername.count >= 3 else {
                        throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Username must be at least 3 characters"])
                    }
                    
                    // Check if username is already taken
                    let isUsernameTaken = try await checkUsernameExists(cleanUsername)
                    if isUsernameTaken {
                        throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Username is already taken"])
                    }
                    
                    // Sign up
                    let cleanEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    let result = try await Auth.auth().createUser(withEmail: cleanEmail, password: password)
                    
                    // Update display name
                    let changeRequest = result.user.createProfileChangeRequest()
                    changeRequest.displayName = fullName
                    try await changeRequest.commitChanges()
                    
                    // Create initials from full name
                    let names = fullName.components(separatedBy: " ")
                    let firstName = names.first ?? ""
                    let lastName = names.count > 1 ? names.last ?? "" : ""
                    let initials = "\(firstName.prefix(1))\(lastName.prefix(1))".uppercased()
                    
                    // Create searchable name keywords
                    let nameKeywords = createNameKeywords(from: fullName)
                    
                    // Create user profile in Firestore
                    let db = Firestore.firestore()
                    try await db.collection("users").document(result.user.uid).setData([
                        "displayName": fullName,
                        "displayNameLowercase": fullName.lowercased(),
                        "username": cleanUsername,
                        "usernameLowercase": cleanUsername,
                        "email": cleanEmail,
                        "initials": initials,
                        "bio": "",
                        "profileImageURL": NSNull(),
                        "nameKeywords": nameKeywords,
                        "createdAt": FieldValue.serverTimestamp(),
                        "updatedAt": FieldValue.serverTimestamp(),
                        "followersCount": 0,
                        "followingCount": 0,
                        "postsCount": 0,
                        "isPrivate": false,
                        "notificationsEnabled": true,
                        "hasCompletedOnboarding": false
                    ])
                    
                    print("✅ Successfully created account with username: \(cleanUsername)")
                }
                
                // ✅ NEW: Setup push notifications after successful auth
                await MainActor.run {
                    Task {
                        let granted = await PushNotificationManager.shared.requestNotificationPermissions()
                        if granted {
                            print("✅ Notification permission granted, setting up FCM...")
                            PushNotificationManager.shared.setupFCMToken()
                        } else {
                            print("⚠️ Notification permission denied")
                        }
                    }
                    
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    let errorMsg = error.localizedDescription
                    // Provide better error messages
                    if errorMsg.contains("network") {
                        showError("Network error. Please check your connection.")
                    } else if errorMsg.contains("password") {
                        showError("Invalid password. Please try again.")
                    } else if errorMsg.contains("email") {
                        showError("Invalid email address.")
                    } else if errorMsg.contains("user-not-found") || errorMsg.contains("wrong-password") {
                        showError("Invalid email/username or password.")
                    } else {
                        showError(errorMsg)
                    }
                }
            }
        }
    }
    
    /// Look up email address by username
    private func lookupEmailByUsername(_ username: String) async throws -> String {
        let db = Firestore.firestore()
        
        do {
            let querySnapshot = try await db.collection("users")
                .whereField("usernameLowercase", isEqualTo: username.lowercased())
                .limit(to: 1)
                .getDocuments()
            
            guard let document = querySnapshot.documents.first,
                  let email = document.data()["email"] as? String else {
                throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Username not found"])
            }
            
            print("✅ Found email for username: \(username)")
            return email
        } catch {
            print("❌ Failed to look up username: \(error.localizedDescription)")
            throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Username not found"])
        }
    }
    
    /// Check if username already exists
    private func checkUsernameExists(_ username: String) async throws -> Bool {
        let db = Firestore.firestore()
        
        let querySnapshot = try await db.collection("users")
            .whereField("usernameLowercase", isEqualTo: username.lowercased())
            .limit(to: 1)
            .getDocuments()
        
        return !querySnapshot.documents.isEmpty
    }
    
    /// Create searchable keywords from a display name
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
    
    private func showError(_ message: String) {
        errorMessage = message
        
        // Shake animation
        withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) {
            shakeOffset = 10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) {
                shakeOffset = -10
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) {
                shakeOffset = 0
            }
        }
    }
}

// MARK: - Auth Input Field

struct AuthInputField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var showPasswordToggle: Bool = false
    @Binding var showPassword: Bool
    
    init(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool = false,
        keyboardType: UIKeyboardType = .default,
        showPasswordToggle: Bool = false,
        showPassword: Binding<Bool> = .constant(false)
    ) {
        self.icon = icon
        self.placeholder = placeholder
        self._text = text
        self.isSecure = isSecure
        self.keyboardType = keyboardType
        self.showPasswordToggle = showPasswordToggle
        self._showPassword = showPassword
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color(red: 0.5, green: 0.3, blue: 0.9))
                .frame(width: 24)
            
            if isSecure {
                SecureField(placeholder, text: $text)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } else {
                TextField(placeholder, text: $text)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .words)
                    .keyboardType(keyboardType)
            }
            
            if showPasswordToggle {
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Social Login Button

struct SocialLoginButton: View {
    let icon: String
    let title: String
    let backgroundColor: Color
    var foregroundColor: Color = .white
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 15))
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor)
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

#Preview {
    AuthenticationView()
}

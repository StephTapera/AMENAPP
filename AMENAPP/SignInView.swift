//
//  SignInView.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//
//  Dark glassmorphic design inspired by modern auth flows
//

import SwiftUI
import FirebaseFirestore
import AuthenticationServices
import CryptoKit
import GoogleSignIn

// Import for scene phase monitoring
@preconcurrency import SwiftUI

struct SignInView: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLogin = true
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var username = ""
    @State private var showPassword = false
    @State private var isCheckingUsername = false
    @State private var usernameAvailable: Bool?
    @State private var usernameCheckTask: Task<Void, Never>? // Track the task
    @State private var authTask: Task<Void, Never>? // Track auth request to prevent duplicates
    @State private var showPasswordReset = false
    @State private var resetEmail = ""
    @State private var showResetSuccess = false
    @State private var currentNonce: String?
    @State private var nonceGeneratedAt: Date?
    @State private var appleSignInCoordinator: AppleSignInCoordinator?
    @State private var showAmenTitle = false
    @State private var amenTitleOpacity: Double = 0
    
    // Password strength
    private var passwordStrength: PasswordStrength {
        calculatePasswordStrength(password)
    }
    
    var body: some View {
        ZStack {
            // Dark background matching the design image
            Color.black
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // AMEN Title at top with subtle animation
                    if showAmenTitle {
                        Text("AMEN")
                            .font(.custom("OpenSans-Bold", size: 32))
                            .foregroundStyle(.white)
                            .opacity(amenTitleOpacity)
                            .padding(.top, 80)
                            .padding(.bottom, 20)
                            .transition(.opacity)
                    }

                    // Glassmorphic Card Container - Dark Style
                    VStack(spacing: 24) {
                        // Icon at top (matching design)
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.top, 32)

                        // Title Section
                        VStack(spacing: 8) {
                            Text(isLogin ? "Sign In" : "Sign Up")
                                .font(.custom("OpenSans-Bold", size: 24))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)

                            Text(isLogin ? "Please enter your details to sign in" : "Create your AMEN account")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 32)
                
                        // Input Fields Section
                        VStack(spacing: 14) {
                            // Display Name (signup only)
                            if !isLogin {
                                DarkGlassmorphicTextField(
                                    icon: "person",
                                    placeholder: "Display Name",
                                    text: $displayName
                                )
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            // Username (signup only)
                            if !isLogin {
                                DarkGlassmorphicUsernameField(
                                    text: $username,
                                    isChecking: $isCheckingUsername,
                                    isAvailable: $usernameAvailable
                                )
                                .transition(.opacity.combined(with: .move(edge: .top)))
                                .onChange(of: username) { _, newValue in
                                    checkUsernameAvailability(newValue)
                                }
                            }

                            // Email
                            DarkGlassmorphicTextField(
                                icon: "envelope",
                                placeholder: isLogin ? "Enter your email address" : "Email",
                                text: $email,
                                keyboardType: isLogin ? .default : .emailAddress
                            )
                            .onChange(of: email) { _, _ in
                                if viewModel.showError {
                                    viewModel.showError = false
                                    viewModel.errorMessage = nil
                                }
                            }

                            // Password
                            DarkGlassmorphicPasswordField(
                                placeholder: "Password",
                                text: $password,
                                showPassword: $showPassword
                            )
                            .onChange(of: password) { _, _ in
                                if viewModel.showError {
                                    viewModel.showError = false
                                    viewModel.errorMessage = nil
                                }
                            }

                            // Forgot Password link
                            if isLogin {
                                Button {
                                    showPasswordReset = true
                                } label: {
                                    Text("Forgot Password?")
                                        .font(.custom("OpenSans-Regular", size: 12))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.trailing, 4)
                            }
                            
                            // Error Message
                            if let errorMessage = viewModel.errorMessage, viewModel.showError {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 12))
                                    Text(errorMessage)
                                        .font(.custom("OpenSans-Regular", size: 12))
                                }
                                .foregroundStyle(.red.opacity(0.9))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.red.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(.red.opacity(0.3), lineWidth: 1)
                                        )
                                )
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            // Password Strength (signup only)
                            if !isLogin && !password.isEmpty {
                                DarkPasswordStrengthIndicator(strength: passwordStrength)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(.horizontal, 32)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isLogin)
                
                        // Primary Action Button (White background, dark text)
                        Button {
                            handleAuth()
                        } label: {
                            HStack(spacing: 12) {
                                if viewModel.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                } else {
                                    Text(isLogin ? "Sign In" : "Sign Up")
                                        .font(.custom("OpenSans-SemiBold", size: 15))
                                }
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(.white)
                                    .shadow(color: .white.opacity(0.2), radius: 8, y: 4)
                            )
                        }
                        .disabled(viewModel.isLoading || !isFormValid)
                        .opacity(isFormValid ? 1.0 : 0.5)
                        .padding(.horizontal, 32)
                        .padding(.top, 12)

                        // Google Sign-In Button
                        Button {
                            handleGoogleSignIn()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "g.circle.fill")
                                    .font(.system(size: 18))
                                Text("Continue with Google")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                            }
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(.white.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 24)
                                            .stroke(.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                        
                        // Sign in with Apple Button
                        Button {
                            handleAppleSignIn()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Continue with Apple")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                            }
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(.white.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 24)
                                            .stroke(.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 8)

                        // Toggle Sign In/Sign Up
                        HStack(spacing: 6) {
                            Text(isLogin ? "Don't have an account?" : "Already have an account?")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.white.opacity(0.5))

                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    isLogin.toggle()
                                }
                            } label: {
                                Text(isLogin ? "Sign up" : "Sign in")
                                    .font(.custom("OpenSans-SemiBold", size: 13))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                    }
                    .frame(maxWidth: 420)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.08),
                                        Color.white.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(.ultraThinMaterial.opacity(0.3))
                                    .blur(radius: 1)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.2),
                                                Color.white.opacity(0.05)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 60)
                }
            }
            .onTapGesture {
                // Dismiss keyboard when tapping background
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        .ignoresSafeArea()
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .sheet(isPresented: $showPasswordReset) {
            PasswordResetSheet(
                resetEmail: $resetEmail,
                showSuccess: $showResetSuccess,
                onSend: {
                    Task {
                        do {
                            try await viewModel.sendPasswordReset(email: resetEmail)
                            showPasswordReset = false
                            showResetSuccess = true
                            
                            // Success haptic
                            let haptic = UINotificationFeedbackGenerator()
                            haptic.notificationOccurred(.success)
                        } catch {
                            viewModel.errorMessage = "Failed to send reset email. Please check the email address."
                            viewModel.showError = true
                            showPasswordReset = false
                            
                            // Error haptic
                            let haptic = UINotificationFeedbackGenerator()
                            haptic.notificationOccurred(.error)
                        }
                    }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .alert("Email Sent! ✅", isPresented: $showResetSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Check your inbox for password reset instructions")
        }
        .onAppear {
            // Subtle AMEN title animation
            withAnimation(.easeIn(duration: 0.6)) {
                showAmenTitle = true
            }
            withAnimation(.easeIn(duration: 0.8).delay(0.2)) {
                amenTitleOpacity = 1.0
            }
            
            // Pre-generate Apple Sign-In nonce for faster auth flow
            generateAppleNonce()
        }
        .onChange(of: scenePhase) { newPhase in
            // Regenerate nonce if app was backgrounded for >5 minutes
            if newPhase == .active,
               let timestamp = nonceGeneratedAt {
                let elapsed = Date().timeIntervalSince(timestamp)
                if elapsed > 300 {  // 5 minutes
                    print("🔄 Regenerating expired Apple nonce")
                    generateAppleNonce()
                }
            }
        }
    }
    
    private var isFormValid: Bool {
        if isLogin {
            return !email.isEmpty && !password.isEmpty
        } else {
            // Full validation - all fields required for sign up
            let basicValidation = !email.isEmpty && 
                   !password.isEmpty && 
                   !displayName.isEmpty && 
                   !username.isEmpty
            
            if !basicValidation {
                print("⚠️ Form validation failed: Basic fields not filled")
                return false
            }
            
            // Email format validation
            if !isValidEmailFormat(email) {
                print("⚠️ Form validation failed: Invalid email format")
                return false
            }
            
            // Password strength validation - require at least medium strength
            let strength = calculatePasswordStrength(password)
            if strength == .weak {
                print("⚠️ Form validation failed: Password too weak")
                return false
            }
            
            // Username must be checked and available
            let usernameValid = usernameAvailable == true
            if !usernameValid {
                print("⚠️ Form validation failed: Username not available (status: \(String(describing: usernameAvailable)))")
            } else {
                print("✅ Form validation passed!")
            }
            return usernameValid
        }
    }
    
    private func isValidEmailFormat(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let predicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return predicate.evaluate(with: email)
    }
    
    private func handleAuth() {
        // Dismiss keyboard
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        // Cancel any existing auth request to prevent duplicates
        authTask?.cancel()
        
        // Create new auth task
        authTask = Task {
            // Early exit if already cancelled
            guard !Task.isCancelled else {
                print("⚠️ Auth request cancelled before starting")
                return
            }
            if isLogin {
                // Check if user entered @username instead of email
                let loginIdentifier = email.trimmingCharacters(in: .whitespaces).lowercased()
                
                print("📧 Sign-in attempt with: \(loginIdentifier.contains("@") && !loginIdentifier.hasPrefix("@") ? "email" : "username")")
                
                if loginIdentifier.hasPrefix("@") {
                    // User entered @username - need to look up email
                    print("🔍 Looking up email for username: \(loginIdentifier)")
                    await signInWithUsername(loginIdentifier)
                } else if loginIdentifier.contains("@") {
                    // Regular email sign-in
                    print("📧 Email sign-in")
                    await viewModel.signIn(email: loginIdentifier, password: password)
                } else {
                    // Assume it's username without @ prefix
                    print("🔍 Looking up email for username: @\(loginIdentifier)")
                    await signInWithUsername("@\(loginIdentifier)")
                }
                
                // ✅ Cache user name for messaging after successful login
                if viewModel.isAuthenticated {
                    await FirebaseMessagingService.shared.fetchAndCacheCurrentUserName()
                    print("✅ User name cached for messaging")
                }
            } else {
                print("📝 Sign-up attempt")
                print("   Email: \(email)")
                print("   Display name: \(displayName)")
                print("   Username: @\(username)")
                
                // Lowercase email for sign up
                await viewModel.signUp(
                    email: email.lowercased().trimmingCharacters(in: .whitespaces),
                    password: password,
                    displayName: displayName,
                    username: username
                )
                
                // ✅ Cache user name after successful signup
                if viewModel.isAuthenticated {
                    await FirebaseMessagingService.shared.fetchAndCacheCurrentUserName()
                    print("✅ User name cached for messaging")
                }
            }
            
            // Clear task reference when complete
            await MainActor.run {
                authTask = nil
            }
        }
    }
    
    private func signInWithUsername(_ usernameInput: String) async {
        // Remove @ if present
        let cleanUsername = usernameInput.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "@", with: "")
        
        print("🔍 Username lookup: @\(cleanUsername)")
        
        // Look up email by username in Firestore
        let db = Firestore.firestore()
        
        do {
            // Use usernameLowercase for case-insensitive search
            let snapshot = try await db.collection("users")
                .whereField("usernameLowercase", isEqualTo: cleanUsername.lowercased())
                .limit(to: 1)
                .getDocuments()
            
            guard let userDoc = snapshot.documents.first,
                  let userEmail = userDoc.data()["email"] as? String else {
                // Username not found
                print("❌ Username @\(cleanUsername) not found")
                await MainActor.run {
                    viewModel.errorMessage = "No account found with username @\(cleanUsername)"
                    viewModel.showError = true
                }
                return
            }
            
            print("✅ Found email for @\(cleanUsername)")
            
            // Found email - now sign in with it
            await viewModel.signIn(email: userEmail, password: password)
            
        } catch {
            print("❌ Username lookup failed: \(error.localizedDescription)")
            await MainActor.run {
                viewModel.errorMessage = "Failed to look up username: \(error.localizedDescription)"
                viewModel.showError = true
            }
        }
    }
    
    private func checkUsernameAvailability(_ username: String) {
        // Cancel any existing check
        usernameCheckTask?.cancel()
        
        // Clean the username
        let cleaned = username.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Only check if username is valid format (3-20 chars, alphanumeric + underscores)
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
                // Direct Firestore query (case-insensitive)
                let db = Firestore.firestore()
                let snapshot = try await db.collection("users")
                    .whereField("usernameLowercase", isEqualTo: cleaned.lowercased())
                    .limit(to: 1)
                    .getDocuments()
                
                let available = snapshot.documents.isEmpty
                
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
                print("❌ Username availability check error: \(error)")
                print("   Error details: \(error.localizedDescription)")
                await MainActor.run {
                    // On error, assume available to not block signup
                    // The backend will do final validation anyway
                    usernameAvailable = true
                    isCheckingUsername = false
                }
            }
        }
    }
    
    private func isValidUsernameFormat(_ username: String) -> Bool {
        let usernameRegex = "^[a-z0-9_]{3,20}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", usernameRegex)
        return predicate.evaluate(with: username)
    }
    
    private func handleGoogleSignIn() {
        Task {
            do {
                viewModel.isLoading = true
                print("🔵 Google Sign-In initiated")
                
                let _ = try await FirebaseManager.shared.signInWithGoogle()
                
                print("✅ Google Sign-In successful")
                
                await MainActor.run {
                    viewModel.isAuthenticated = true
                    viewModel.needsOnboarding = true
                    viewModel.isLoading = false
                }
                
                // Cache user name for messaging
                await FirebaseMessagingService.shared.fetchAndCacheCurrentUserName()
                print("✅ User name cached for messaging")
                
            } catch {
                let nsError = error as NSError
                print("❌ Google Sign-In failed")
                print("   Error domain: \(nsError.domain)")
                print("   Error code: \(nsError.code)")
                print("   Description: \(error.localizedDescription)")
                
                await MainActor.run {
                    // Provide more specific error messages
                    if nsError.domain == "FIRAuthErrorDomain" {
                        switch nsError.code {
                        case 17999: // Invalid credential
                            viewModel.errorMessage = "Google authentication expired. Please try again."
                        case 17011: // User not found
                            viewModel.errorMessage = "No account found with this Google account."
                        case 17020: // Network error
                            viewModel.errorMessage = "Network error. Please check your connection."
                        default:
                            viewModel.errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                        }
                    } else if nsError.code == -5 { // User cancelled
                        print("ℹ️ User cancelled Google Sign-In")
                        // Don't show error for cancellation
                    } else {
                        viewModel.errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                        viewModel.showError = true
                    }
                    
                    viewModel.isLoading = false
                }
            }
        }
    }
    
    // MARK: - Apple Sign-In Helpers
    
    /// Pre-generate Apple Sign-In nonce for faster authentication flow
    /// Called on view appear and when app returns from background after 5+ minutes
    private func generateAppleNonce() {
        let nonce = randomNonceString()
        currentNonce = nonce
        nonceGeneratedAt = Date()
        print("🍎 Apple nonce pre-generated: \(nonce.prefix(10))... (length: \(nonce.count))")
    }
    
    private func handleAppleSignIn() {
        // Generate fresh nonce with timestamp
        let nonce = randomNonceString()
        currentNonce = nonce
        nonceGeneratedAt = Date()
        
        print("🍎 Apple Sign-In initiated")
        print("📋 Nonce generated: \(nonce.prefix(10))... (length: \(nonce.count))")
        print("⏰ Timestamp: \(Date())")
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        print("🔐 SHA256 nonce: \(sha256(nonce).prefix(10))...")
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        let coordinator = AppleSignInCoordinator(onCompletion: { result in
            self.handleAppleSignInResult(result)
            self.appleSignInCoordinator = nil // Clean up after completion
        })
        
        // Retain coordinator to prevent deallocation
        appleSignInCoordinator = coordinator
        
        authorizationController.delegate = coordinator
        authorizationController.presentationContextProvider = coordinator
        authorizationController.performRequests()
    }
    
    private func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            // Check if nonce has expired (5 minute timeout)
            if let timestamp = nonceGeneratedAt {
                let elapsed = Date().timeIntervalSince(timestamp)
                print("⏱️ Time elapsed since nonce generation: \(elapsed) seconds")
                
                if elapsed > 300 { // 5 minutes
                    print("❌ Nonce expired (>5 minutes old)")
                    Task { @MainActor in
                        viewModel.errorMessage = "Sign-in session expired. Please try again."
                        viewModel.showError = true
                        
                        // Clear expired nonce
                        currentNonce = nil
                        nonceGeneratedAt = nil
                    }
                    return
                }
            }
            
            // Check if nonce still exists
            guard currentNonce != nil else {
                print("❌ No nonce available - session may have expired")
                Task { @MainActor in
                    viewModel.errorMessage = "Sign-in session expired. Please try again."
                    viewModel.showError = true
                }
                return
            }
            
            handleAppleSignIn(authorization)
            
        case .failure(let error):
            let nsError = error as NSError
            let errorCode = nsError.code
            
            print("❌ Apple Sign-In failed with code: \(errorCode)")
            print("   Error domain: \(nsError.domain)")
            print("   Description: \(error.localizedDescription)")
            
            Task { @MainActor in
                // Don't show error for user cancellation
                if errorCode == 1001 { // ASAuthorizationError.canceled
                    print("ℹ️ User cancelled Apple Sign-In")
                    return
                }
                
                // Clear nonce on failure
                currentNonce = nil
                nonceGeneratedAt = nil
                
                viewModel.errorMessage = "Apple Sign-In failed: \(error.localizedDescription)"
                viewModel.showError = true
            }
        }
    }
    
    private func handleAppleSignIn(_ authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            print("❌ Failed to get ASAuthorizationAppleIDCredential")
            Task { @MainActor in
                viewModel.errorMessage = "Unable to process Apple Sign-In credentials"
                viewModel.showError = true
            }
            return
        }
        
        guard let nonce = currentNonce else {
            print("❌ No nonce available")
            Task { @MainActor in
                viewModel.errorMessage = "Sign-in session expired. Please try again."
                viewModel.showError = true
            }
            return
        }
        
        guard let appleIDToken = appleIDCredential.identityToken else {
            print("❌ No identity token in credential")
            Task { @MainActor in
                viewModel.errorMessage = "Unable to get identity token from Apple"
                viewModel.showError = true
            }
            return
        }
        
        guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            print("❌ Failed to convert token data to string")
            Task { @MainActor in
                viewModel.errorMessage = "Invalid token format"
                viewModel.showError = true
            }
            return
        }
        
        // Validate token and nonce
        guard !idTokenString.isEmpty, idTokenString.count > 100 else {
            print("❌ Token string too short or empty (length: \(idTokenString.count))")
            Task { @MainActor in
                viewModel.errorMessage = "Invalid authentication token"
                viewModel.showError = true
            }
            return
        }
        
        guard nonce.count == 32 else {
            print("❌ Nonce has invalid length: \(nonce.count) (expected 32)")
            Task { @MainActor in
                viewModel.errorMessage = "Invalid authentication session"
                viewModel.showError = true
            }
            return
        }
        
        print("✅ Apple Sign-In credentials validated")
        print("📋 User ID: \(appleIDCredential.user)")
        print("📋 Token length: \(idTokenString.count)")
        print("📋 Nonce length: \(nonce.count)")
        print("📧 Email: \(appleIDCredential.email ?? "none")")
        print("👤 Full name: \(appleIDCredential.fullName?.givenName ?? "none") \(appleIDCredential.fullName?.familyName ?? "")")
        
        Task {
            do {
                print("🔄 Attempting Firebase authentication...")
                let _ = try await FirebaseManager.shared.signInWithApple(
                    idToken: idTokenString,
                    nonce: nonce,
                    fullName: appleIDCredential.fullName
                )
                
                print("✅ Firebase authentication successful")
                
                await MainActor.run {
                    viewModel.isAuthenticated = true
                    viewModel.needsOnboarding = true
                    
                    // Clear nonce after successful auth
                    currentNonce = nil
                    nonceGeneratedAt = nil
                }
                
                // Cache user name for messaging
                await FirebaseMessagingService.shared.fetchAndCacheCurrentUserName()
                print("✅ User name cached for messaging")
                
            } catch {
                let nsError = error as NSError
                print("❌ Firebase authentication failed")
                print("   Error domain: \(nsError.domain)")
                print("   Error code: \(nsError.code)")
                print("   Description: \(error.localizedDescription)")
                print("   User info: \(nsError.userInfo)")
                
                await MainActor.run {
                    // Clear nonce on failure
                    currentNonce = nil
                    nonceGeneratedAt = nil
                    
                    // Provide more specific error messages
                    if nsError.domain == "FIRAuthErrorDomain" {
                        switch nsError.code {
                        case 17999: // Invalid credential
                            viewModel.errorMessage = "Authentication credential expired. Please try signing in again."
                        case 17011: // User not found
                            viewModel.errorMessage = "No account found. Please sign up first."
                        case 17020: // Network error
                            viewModel.errorMessage = "Network error. Please check your connection and try again."
                        default:
                            viewModel.errorMessage = "Sign-in failed: \(error.localizedDescription)"
                        }
                    } else {
                        viewModel.errorMessage = "Sign-in failed: \(error.localizedDescription)"
                    }
                    
                    viewModel.showError = true
                }
            }
        }
    }
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        
        return String(nonce)
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
    
    private func calculatePasswordStrength(_ password: String) -> PasswordStrength {
        var score = 0
        
        // Length
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        
        // Has uppercase
        if password.range(of: "[A-Z]", options: .regularExpression) != nil { score += 1 }
        
        // Has lowercase
        if password.range(of: "[a-z]", options: .regularExpression) != nil { score += 1 }
        
        // Has numbers
        if password.range(of: "[0-9]", options: .regularExpression) != nil { score += 1 }
        
        // Has special characters
        if password.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil { score += 1 }
        
        switch score {
        case 0...2: return .weak
        case 3...4: return .medium
        default: return .strong
        }
    }
}

// MARK: - Password Strength

enum PasswordStrength {
    case weak
    case medium
    case strong
    
    var color: Color {
        switch self {
        case .weak: return .red
        case .medium: return .orange
        case .strong: return .green
        }
    }
    
    var text: String {
        switch self {
        case .weak: return "Weak"
        case .medium: return "Medium"
        case .strong: return "Strong"
        }
    }
    
    var progress: CGFloat {
        switch self {
        case .weak: return 0.33
        case .medium: return 0.66
        case .strong: return 1.0
        }
    }
}

// MARK: - Password Reset Sheet

struct PasswordResetSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var resetEmail: String
    @Binding var showSuccess: Bool
    let onSend: () -> Void
    
    @State private var isValidEmail = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.5, green: 0.3, blue: 0.9).opacity(0.2),
                                    Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.5, green: 0.3, blue: 0.9),
                                    Color(red: 0.6, green: 0.4, blue: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .padding(.top, 20)
                
                // Title & Description
                VStack(spacing: 8) {
                    Text("Reset Password")
                        .font(.custom("OpenSans-Bold", size: 24))
                        .foregroundStyle(.black)
                    
                    Text("Enter your email address and we'll send you instructions to reset your password")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.black.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                
                // Email Input
                SimpleCleanTextField(
                    icon: "envelope",
                    placeholder: "Email",
                    text: $resetEmail,
                    keyboardType: .emailAddress
                )
                .padding(.horizontal, 32)
                .onChange(of: resetEmail) { _, newValue in
                    isValidEmail = isValidEmailFormat(newValue)
                }
                
                // Send Button
                Button {
                    onSend()
                } label: {
                    Text("Send Reset Link")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 26)
                                .fill(.black)
                        )
                }
                .disabled(!isValidEmail)
                .opacity(isValidEmail ? 1.0 : 0.5)
                .padding(.horizontal, 32)
                .padding(.top, 8)
                
                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    
    private func isValidEmailFormat(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let predicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return predicate.evaluate(with: email)
    }
}

// MARK: - Dark Glassmorphic Text Fields

private struct DarkGlassmorphicTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 14) {
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.4)))
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.white.opacity(0.9))
                .autocorrectionDisabled()
                .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .words)
                .keyboardType(keyboardType)
                .focused($isFocused)
                .tint(.white)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(isFocused ? 0.12 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(isFocused ? 0.25 : 0.15), lineWidth: 1)
                )
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isFocused)
    }
}


private struct DarkGlassmorphicPasswordField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var showPassword: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 14) {
            if showPassword {
                TextField(placeholder, text: $text)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.white.opacity(0.9))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isFocused)
                    .tint(.white)
            } else {
                SecureField(placeholder, text: $text)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.white.opacity(0.9))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isFocused)
                    .tint(.white)
            }

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    showPassword.toggle()
                }
            } label: {
                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(isFocused ? 0.12 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(isFocused ? 0.25 : 0.15), lineWidth: 1)
                )
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isFocused)
    }
}

private struct DarkGlassmorphicUsernameField: View {
    @Binding var text: String
    @Binding var isChecking: Bool
    @Binding var isAvailable: Bool?

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                TextField("@username", text: $text)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.white.opacity(0.9))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isFocused)
                    .tint(.white)

                if isChecking {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else if let available = isAvailable {
                    Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(available ? .green : .red)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(isFocused ? 0.12 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(statusBorderColor, lineWidth: 1)
                    )
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isFocused)

            if !text.isEmpty, let available = isAvailable {
                Text(available ? "✓ @\(text) is available" : "✗ @\(text) is taken")
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(available ? .green.opacity(0.9) : .red.opacity(0.9))
                    .padding(.leading, 4)
            }
        }
    }

    private var statusBorderColor: Color {
        if isFocused {
            return .white.opacity(0.25)
        }

        guard !text.isEmpty, let available = isAvailable else {
            return .white.opacity(0.15)
        }

        return available ? .green.opacity(0.4) : .red.opacity(0.4)
    }
}

private struct DarkPasswordStrengthIndicator: View {
    let strength: PasswordStrength

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Password strength:")
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(.white.opacity(0.5))

                Text(strength.text)
                    .font(.custom("OpenSans-SemiBold", size: 11))
                    .foregroundStyle(strength.color)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.1))
                        .frame(height: 3)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(strength.color.opacity(0.9))
                        .frame(width: geometry.size.width * strength.progress, height: 3)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: strength.progress)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Apple Sign-In Coordinator
class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let onCompletion: (Result<ASAuthorization, Error>) -> Void
    
    init(onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.onCompletion = onCompletion
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        onCompletion(.success(authorization))
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onCompletion(.failure(error))
    }
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("No window available")
        }
        return window
    }
}

#Preview {
    SignInView()
        .environmentObject(AuthenticationViewModel())
}

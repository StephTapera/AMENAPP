//
//  SignInView.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//
//  Clean minimal design inspired by modern web apps
//

import SwiftUI
import FirebaseFirestore
import AuthenticationServices
import CryptoKit
import GoogleSignIn

struct SignInView: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    @State private var isLogin = true
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var username = ""
    @State private var showPassword = false
    @State private var isCheckingUsername = false
    @State private var usernameAvailable: Bool?
    @State private var usernameCheckTask: Task<Void, Never>? // Track the task
    @State private var showPasswordReset = false
    @State private var resetEmail = ""
    @State private var showResetSuccess = false
    
    private let userService = UserService()
    
    // Password strength
    private var passwordStrength: PasswordStrength {
        calculatePasswordStrength(password)
    }
    
    var body: some View {
        ZStack {
            // Soft gradient background (light purple/pink like the design)
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.94, blue: 0.98),
                    Color(red: 0.98, green: 0.95, blue: 0.97),
                    Color(red: 1.0, green: 0.97, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Logo and Title
                VStack(spacing: 24) {
                    Text("AMEN")
                        .font(.custom("OpenSans-Bold", size: 32))
                        .foregroundStyle(.black)
                        .tracking(2)
                    
                    Text(isLogin ? "Welcome back" : "Create your account")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.black.opacity(0.6))
                }
                .padding(.bottom, 60)
                
                // Input fields
                VStack(spacing: 16) {
                    // Display Name (signup only)
                    if !isLogin {
                        CleanTextField(
                            icon: "person",
                            placeholder: "Display Name",
                            text: $displayName,
                            keyboardType: .default
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Username (signup only)
                    if !isLogin {
                        UsernameTextField(
                            text: $username,
                            isChecking: $isCheckingUsername,
                            isAvailable: $usernameAvailable
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .onChange(of: username) { _, newValue in
                            checkUsernameAvailability(newValue)
                        }
                    }
                    
                    // Email or Username
                    CleanTextField(
                        icon: "envelope",
                        placeholder: isLogin ? "Email or @username" : "Email",
                        text: $email,
                        keyboardType: isLogin ? .default : .emailAddress
                    )
                    .onChange(of: email) { _, _ in
                        // Clear error when user starts typing
                        if viewModel.showError {
                            viewModel.showError = false
                            viewModel.errorMessage = nil
                        }
                    }
                    
                    // Password
                    CleanTextField(
                        icon: "lock",
                        placeholder: "Password",
                        text: $password,
                        isSecure: !showPassword,
                        showPasswordToggle: true,
                        showPassword: $showPassword
                    )
                    .onChange(of: password) { _, _ in
                        // Clear error when user starts typing
                        if viewModel.showError {
                            viewModel.showError = false
                            viewModel.errorMessage = nil
                        }
                    }
                    
                    // Show error message if there is one
                    if let errorMessage = viewModel.errorMessage, viewModel.showError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.red)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red.opacity(0.1))
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Password strength indicator (signup only)
                    if !isLogin && !password.isEmpty {
                        PasswordStrengthIndicator(strength: passwordStrength)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Password warning for login (too short)
                    if isLogin && !password.isEmpty && password.count < 6 {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                            Text("Password must be at least 6 characters")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                    }
                    
                    // Forgot Password Button (login only)
                    if isLogin {
                        HStack {
                            Spacer()
                            Button {
                                showPasswordReset = true
                            } label: {
                                Text("Forgot Password?")
                                    .font(.custom("OpenSans-SemiBold", size: 13))
                                    .foregroundStyle(.black.opacity(0.6))
                            }
                        }
                        .padding(.top, 4)
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 32)
                .animation(.easeInOut(duration: 0.3), value: isLogin)
                
                // Primary Action Button
                Button {
                    handleAuth()
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text(isLogin ? "Sign In" : "Create Account")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 26)
                            .fill(.black)
                    )
                }
                .disabled(viewModel.isLoading || !isFormValid)
                .opacity(isFormValid ? 1.0 : 0.5)
                .padding(.horizontal, 32)
                .padding(.top, 32)
                
                // Toggle Login/Signup
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isLogin.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isLogin ? "Don't have an account?" : "Already have an account?")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.black.opacity(0.6))
                        
                        Text(isLogin ? "Sign Up" : "Sign In")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.black)
                    }
                }
                .padding(.top, 20)
                
                // OR Divider
                HStack(spacing: 16) {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(.black.opacity(0.1))
                    
                    Text("OR")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.black.opacity(0.4))
                    
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(.black.opacity(0.1))
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                
                // Social Sign-In Buttons
                VStack(spacing: 12) {
                    // Apple Sign-In Button
                    AppleSignInButton()
                        .frame(height: 52)
                        .padding(.horizontal, 32)
                    
                    // Google Sign-In Button
                    GoogleSignInButton()
                        .frame(height: 52)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 16)
                
                Spacer()
                Spacer()
            }
        }
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
                return false
            }
            
            // Email format validation
            if !isValidEmailFormat(email) {
                return false
            }
            
            // Username must be checked and available
            // Allow sign-up if username check is still pending (nil) for better UX
            return usernameAvailable == true || usernameAvailable == nil
        }
    }
    
    private func isValidEmailFormat(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let predicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return predicate.evaluate(with: email)
    }
    
    private func handleAuth() {
        Task {
            if isLogin {
                // Check if user entered @username instead of email
                let loginIdentifier = email.trimmingCharacters(in: .whitespaces)
                
                if loginIdentifier.hasPrefix("@") {
                    // User entered @username - need to look up email
                    await signInWithUsername(loginIdentifier)
                } else if loginIdentifier.contains("@") {
                    // Regular email sign-in
                    await viewModel.signIn(email: loginIdentifier, password: password)
                } else {
                    // Assume it's username without @ prefix
                    await signInWithUsername("@\(loginIdentifier)")
                }
                
                // ✅ Cache user name for messaging after successful login
                if viewModel.isAuthenticated {
                    await FirebaseMessagingService.shared.fetchAndCacheCurrentUserName()
                    print("✅ User name cached for messaging")
                }
            } else {
                await viewModel.signUp(
                    email: email,
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
        }
    }
    
    private func signInWithUsername(_ usernameInput: String) async {
        // Remove @ if present
        let cleanUsername = usernameInput.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "@", with: "")
        
        // Look up email by username in Firestore
        let db = Firestore.firestore()
        
        do {
            let snapshot = try await db.collection("users")
                .whereField("username", isEqualTo: cleanUsername)
                .limit(to: 1)
                .getDocuments()
            
            guard let userDoc = snapshot.documents.first,
                  let userEmail = userDoc.data()["email"] as? String else {
                // Username not found
                await MainActor.run {
                    viewModel.errorMessage = "No account found with username @\(cleanUsername)"
                    viewModel.showError = true
                }
                return
            }
            
            // Found email - now sign in with it
            await viewModel.signIn(email: userEmail, password: password)
            
        } catch {
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
                // Direct Firestore query
                let db = Firestore.firestore()
                let snapshot = try await db.collection("users")
                    .whereField("username", isEqualTo: cleaned)
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
                await MainActor.run {
                    // On error, set to nil (neutral state)
                    usernameAvailable = nil
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

// MARK: - Password Strength Indicator

private struct PasswordStrengthIndicator: View {
    let strength: PasswordStrength
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Password strength:")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.black.opacity(0.6))
                
                Text(strength.text)
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundStyle(strength.color)
            }
            
            // Strength bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.black.opacity(0.1))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(strength.color)
                        .frame(width: geometry.size.width * strength.progress, height: 4)
                        .animation(.easeInOut(duration: 0.3), value: strength.progress)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Clean Text Field

private struct CleanTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var showPasswordToggle: Bool = false
    @Binding var showPassword: Bool
    
    @FocusState private var isFocused: Bool
    
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
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.black.opacity(0.4))
                .frame(width: 20)
            
            if isSecure {
                SecureField(placeholder, text: $text)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.black)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isFocused)
            } else {
                TextField(placeholder, text: $text)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.black)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .words)
                    .keyboardType(keyboardType)
                    .focused($isFocused)
            }
            
            if showPasswordToggle {
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.black.opacity(0.4))
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isFocused ? Color.black.opacity(0.3) : Color.black.opacity(0.1),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Username Text Field

private struct UsernameTextField: View {
    @Binding var text: String
    @Binding var isChecking: Bool
    @Binding var isAvailable: Bool?
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Image(systemName: "at")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.black.opacity(0.4))
                    .frame(width: 20)
                
                TextField("Username", text: $text)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.black)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isFocused)
                
                // Status indicator
                if isChecking {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let available = isAvailable {
                    Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(available ? .green : .red)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        statusBorderColor,
                        lineWidth: 1
                    )
            )
            
            // Validation message
            if !text.isEmpty {
                if isChecking {
                    Text("Checking availability...")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.black.opacity(0.6))
                } else if let available = isAvailable {
                    Text(available ? "@\(text) is available" : "@\(text) is already taken")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(available ? .green : .red)
                } else if !isValidFormat {
                    Text("3-20 characters (letters, numbers, underscores)")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.orange)
                }
            }
        }
    }
    
    private var statusBorderColor: Color {
        if isFocused {
            return .black.opacity(0.3)
        }
        
        guard !text.isEmpty else {
            return .black.opacity(0.1)
        }
        
        if let available = isAvailable {
            return available ? .green.opacity(0.3) : .red.opacity(0.3)
        }
        
        return .black.opacity(0.1)
    }
    
    private var isValidFormat: Bool {
        let usernameRegex = "^[a-z0-9_]{3,20}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", usernameRegex)
        return predicate.evaluate(with: text.lowercased())
    }
}

// MARK: - Apple Sign-In Button

struct AppleSignInButton: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    @State private var currentNonce: String?
    
    var body: some View {
        SignInWithAppleButton(
            onRequest: { request in
                let nonce = randomNonceString()
                currentNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = sha256(nonce)
            },
            onCompletion: { result in
                switch result {
                case .success(let authorization):
                    handleAppleSignIn(authorization)
                case .failure(let error):
                    Task { @MainActor in
                        viewModel.errorMessage = "Apple Sign-In failed: \(error.localizedDescription)"
                        viewModel.showError = true
                    }
                }
            }
        )
        .signInWithAppleButtonStyle(.black)
        .frame(height: 52)
        .cornerRadius(26)
    }
    
    private func handleAppleSignIn(_ authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let nonce = currentNonce,
              let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            Task { @MainActor in
                viewModel.errorMessage = "Unable to process Apple Sign-In"
                viewModel.showError = true
            }
            return
        }
        
        Task {
            do {
                let _ = try await FirebaseManager.shared.signInWithApple(
                    idToken: idTokenString,
                    nonce: nonce,
                    fullName: appleIDCredential.fullName
                )
                
                await MainActor.run {
                    viewModel.isAuthenticated = true
                    viewModel.needsOnboarding = true
                }
                
                // Cache user name for messaging
                await FirebaseMessagingService.shared.fetchAndCacheCurrentUserName()
                
            } catch {
                await MainActor.run {
                    viewModel.errorMessage = "Sign-in failed: \(error.localizedDescription)"
                    viewModel.showError = true
                }
            }
        }
    }
    
    // Helper functions for Apple Sign-In nonce
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
}

// MARK: - Google Sign-In Button

struct GoogleSignInButton: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    
    var body: some View {
        Button {
            handleGoogleSignIn()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "g.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                
                Text("Continue with Google")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.26, green: 0.52, blue: 0.96),
                                Color(red: 0.20, green: 0.43, blue: 0.86)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
        .disabled(viewModel.isLoading)
    }
    
    private func handleGoogleSignIn() {
        Task {
            do {
                viewModel.isLoading = true
                
                let _ = try await FirebaseManager.shared.signInWithGoogle()
                
                await MainActor.run {
                    viewModel.isAuthenticated = true
                    viewModel.needsOnboarding = true
                    viewModel.isLoading = false
                }
                
                // Cache user name for messaging
                await FirebaseMessagingService.shared.fetchAndCacheCurrentUserName()
                
            } catch {
                await MainActor.run {
                    viewModel.errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                    viewModel.showError = true
                    viewModel.isLoading = false
                }
            }
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
                CleanTextField(
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

#Preview {
    SignInView()
        .environmentObject(AuthenticationViewModel())
}

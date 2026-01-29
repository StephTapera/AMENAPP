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
            
            // Username must be checked and available
            // Allow sign-up if username check is still pending (nil) for better UX
            return usernameAvailable == true || usernameAvailable == nil
        }
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
            } else {
                await viewModel.signUp(
                    email: email,
                    password: password,
                    displayName: displayName,
                    username: username
                )
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

#Preview {
    SignInView()
        .environmentObject(AuthenticationViewModel())
}

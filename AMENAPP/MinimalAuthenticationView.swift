//
//  MinimalAuthenticationView.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Minimal, clean authentication UI consistent with app design
//

import SwiftUI
import FirebaseAuth

struct MinimalAuthenticationView: View {
    var initialMode: AppLaunchView.AuthMode = .login
    
    @State private var isLogin = true
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var fullName = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    @Environment(\.dismiss) var dismiss
    
    init(initialMode: AppLaunchView.AuthMode = .login) {
        self.initialMode = initialMode
        self._isLogin = State(initialValue: initialMode == .login)
    }
    
    var body: some View {
        ZStack {
            // Simple dark background
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.08),
                    Color(red: 0.12, green: 0.10, blue: 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 24) {
                        // Simple logo
                        VStack(spacing: 12) {
                            Image(systemName: "cross.fill")
                                .font(.system(size: 44, weight: .light))
                                .foregroundStyle(.white)
                            
                            Text("AMEN")
                                .font(.custom("OpenSans-Bold", size: 32))
                                .foregroundStyle(.white)
                                .tracking(2)
                        }
                        .padding(.top, 80)
                        
                        Text(isLogin ? "Welcome back" : "Create your account")
                            .font(.custom("OpenSans-Regular", size: 16))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.bottom, 60)
                    
                    // Form
                    VStack(spacing: 24) {
                        // Mode Toggle
                        HStack(spacing: 40) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isLogin = true
                                    errorMessage = nil
                                }
                            } label: {
                                VStack(spacing: 8) {
                                    Text("Login")
                                        .font(.custom("OpenSans-SemiBold", size: 16))
                                        .foregroundStyle(isLogin ? .white : .white.opacity(0.4))
                                    
                                    if isLogin {
                                        Rectangle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.orange, Color(red: 1.0, green: 0.6, blue: 0.2)],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(height: 2)
                                            .matchedGeometryEffect(id: "underline", in: namespace)
                                    }
                                }
                            }
                            
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isLogin = false
                                    errorMessage = nil
                                }
                            } label: {
                                VStack(spacing: 8) {
                                    Text("Sign Up")
                                        .font(.custom("OpenSans-SemiBold", size: 16))
                                        .foregroundStyle(!isLogin ? .white : .white.opacity(0.4))
                                    
                                    if !isLogin {
                                        Rectangle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.orange, Color(red: 1.0, green: 0.6, blue: 0.2)],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(height: 2)
                                            .matchedGeometryEffect(id: "underline", in: namespace)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 16)
                        
                        // Error Message
                        if let errorMessage = errorMessage {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.circle")
                                    .font(.system(size: 14))
                                Text(errorMessage)
                                    .font(.custom("OpenSans-Regular", size: 13))
                            }
                            .foregroundStyle(.red.opacity(0.9))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.red.opacity(0.15))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                    )
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        
                        // Input Fields
                        VStack(spacing: 16) {
                            // Full Name (Sign up only)
                            if !isLogin {
                                MinimalInputField(
                                    icon: "person",
                                    placeholder: "Full Name",
                                    text: $fullName
                                )
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                            
                            // Email
                            MinimalInputField(
                                icon: "envelope",
                                placeholder: "Email",
                                text: $email,
                                keyboardType: .emailAddress
                            )
                            
                            // Password
                            MinimalInputField(
                                icon: "lock",
                                placeholder: "Password",
                                text: $password,
                                isSecure: !showPassword,
                                showPasswordToggle: true,
                                showPassword: $showPassword
                            )
                            
                            // Confirm Password (Sign up only)
                            if !isLogin {
                                MinimalInputField(
                                    icon: "lock",
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
                                Text("Forgot password?")
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, 4)
                            .transition(.opacity)
                        }
                        
                        // Submit Button
                        Button {
                            handleAuthentication()
                        } label: {
                            HStack(spacing: 12) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text(isLogin ? "Continue" : "Create Account")
                                        .font(.custom("OpenSans-SemiBold", size: 16))
                                    
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.orange, Color(red: 1.0, green: 0.6, blue: 0.2)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        }
                        .disabled(isLoading || !isFormValid)
                        .opacity(isFormValid ? 1.0 : 0.5)
                        .padding(.top, 8)
                        
                        // Divider
                        HStack(spacing: 16) {
                            Rectangle()
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 1)
                            
                            Text("or")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.white.opacity(0.4))
                            
                            Rectangle()
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 1)
                        }
                        .padding(.vertical, 8)
                        
                        // Social Login Buttons
                        VStack(spacing: 12) {
                            MinimalSocialButton(
                                icon: "apple.logo",
                                title: "Continue with Apple"
                            ) {
                                // Handle Apple login
                            }
                            
                            MinimalSocialButton(
                                icon: "g.circle.fill",
                                title: "Continue with Google"
                            ) {
                                // Handle Google login
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    
                    // Terms (Sign up only)
                    if !isLogin {
                        Text("By continuing, you agree to our [Terms](https://example.com) & [Privacy Policy](https://example.com)")
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.top, 32)
                            .transition(.opacity)
                    }
                    
                    Spacer(minLength: 60)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
    
    @Namespace private var namespace
    
    private var isFormValid: Bool {
        if isLogin {
            return !email.isEmpty && !password.isEmpty
        } else {
            return !fullName.isEmpty && !email.isEmpty && !password.isEmpty && 
                   !confirmPassword.isEmpty && password == confirmPassword
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
        
        Task {
            do {
                if isLogin {
                    // LOGIN with Firebase
                    try await FirebaseManager.shared.signIn(
                        email: email,
                        password: password
                    )
                    
                    print("✅ User logged in successfully")
                    
                } else {
                    // SIGN UP with Firebase - Use fullName for displayName
                    try await FirebaseManager.shared.signUp(
                        email: email,
                        password: password,
                        displayName: fullName  // ← fullName is captured from the form!
                    )
                    
                    print("✅ User created successfully: \(fullName)")
                }
                
                // Success!
                await MainActor.run {
                    isLoading = false
                    
                    // Haptic feedback
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    
                    // Dismiss
                    dismiss()
                }
                
            } catch {
                print("❌ Authentication error: \(error.localizedDescription)")
                
                await MainActor.run {
                    isLoading = false
                    showError(getErrorMessage(for: error))
                }
            }
        }
    }
    
    private func getErrorMessage(for error: Error) -> String {
        // Convert Firebase errors to user-friendly messages
        if let authError = error as? AuthErrorCode {
            switch authError.code {
            case .emailAlreadyInUse:
                return "This email is already registered"
            case .invalidEmail:
                return "Please enter a valid email address"
            case .weakPassword:
                return "Password must be at least 6 characters"
            case .userNotFound:
                return "No account found with this email"
            case .wrongPassword:
                return "Incorrect password"
            case .networkError:
                return "Network error. Please check your connection"
            default:
                return error.localizedDescription
            }
        }
        return error.localizedDescription
    }
    
    private func showError(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            errorMessage = message
        }
    }
}

// MARK: - Minimal Input Field

private struct MinimalInputField: View {
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
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 20)
            
            if isSecure {
                SecureField(placeholder, text: $text)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isFocused)
            } else {
                TextField(placeholder, text: $text)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.white)
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
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isFocused ? 
                    LinearGradient(
                        colors: [Color.orange.opacity(0.5), Color(red: 1.0, green: 0.6, blue: 0.2).opacity(0.5)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ) :
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), Color.white.opacity(0.1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Minimal Social Button

private struct MinimalSocialButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                
                Text(title)
                    .font(.custom("OpenSans-Regular", size: 15))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }
    }
}

#Preview {
    MinimalAuthenticationView()
}

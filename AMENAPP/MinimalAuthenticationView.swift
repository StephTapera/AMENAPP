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
import CryptoKit
import AuthenticationServices

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

    // Age collection (sign-up only)
    @State private var birthDate: Date = Calendar.current.date(
        byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var showDatePicker = false
    @State private var hasPickedBirthDate = false

    // Apple Sign-In state
    @State private var currentNonce: String?
    @State private var appleSignInCoordinator: MinimalAppleSignInCoordinator?

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

                            // Date of Birth (Sign up only)
                            if !isLogin {
                                MinimalDateField(
                                    birthDate: $birthDate,
                                    showPicker: $showDatePicker,
                                    hasPicked: $hasPickedBirthDate
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
                                handleAppleSignIn()
                            }
                            
                            MinimalSocialButton(
                                icon: "g.circle.fill",
                                title: "Continue with Google"
                            ) {
                                handleGoogleSignIn()
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    
                    // Terms (Sign up only)
                    if !isLogin {
                        Text("By continuing, you agree to our [Terms](https://amenapp.com/terms) & [Privacy Policy](https://amenapp.com/privacy)")
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
    
    private var birthYear: Int {
        Calendar.current.component(.year, from: birthDate)
    }

    private var isFormValid: Bool {
        if isLogin {
            return !email.isEmpty && !password.isEmpty
        } else {
            return !fullName.isEmpty && !email.isEmpty && !password.isEmpty &&
                   !confirmPassword.isEmpty && password == confirmPassword &&
                   hasPickedBirthDate
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

        // Under-13 hard block (COPPA)
        if !isLogin {
            if AgeAssuranceService.shouldBlockSignup(birthDate: birthDate) {
                showError("You must be 13 or older to create an account.")
                return
            }
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                if isLogin {
                    // LOGIN with Firebase
                    _ = try await FirebaseManager.shared.signIn(
                        email: email,
                        password: password
                    )

                    print("✅ User logged in successfully")

                } else {
                    // SIGN UP with Firebase
                    _ = try await FirebaseManager.shared.signUp(
                        email: email,
                        password: password,
                        displayName: fullName,
                        birthYear: birthYear
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

    // MARK: - Social Auth Handlers

    private func handleGoogleSignIn() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                _ = try await FirebaseManager.shared.signInWithGoogle()
                await MainActor.run {
                    isLoading = false
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    dismiss()
                }
            } catch let error as NSError {
                await MainActor.run {
                    isLoading = false
                    // Code -5 = user cancelled Google sheet
                    if error.code != -5 {
                        showError(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func handleAppleSignIn() {
        // Generate a fresh nonce for this sign-in attempt
        let nonce = randomNonceString()
        currentNonce = nonce

        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        let coordinator = MinimalAppleSignInCoordinator { [self] result in
            appleSignInCoordinator = nil
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = credential.identityToken,
                      let idToken = String(data: tokenData, encoding: .utf8),
                      let nonce = currentNonce else { return }
                isLoading = true
                Task {
                    do {
                        _ = try await FirebaseManager.shared.signInWithApple(
                            idToken: idToken,
                            nonce: nonce,
                            fullName: credential.fullName
                        )
                        await MainActor.run {
                            isLoading = false
                            let haptic = UINotificationFeedbackGenerator()
                            haptic.notificationOccurred(.success)
                            dismiss()
                        }
                    } catch {
                        await MainActor.run {
                            isLoading = false
                            showError(error.localizedDescription)
                        }
                    }
                }
            case .failure(let error):
                let nsError = error as NSError
                // Code 1001 = user cancelled Apple Sign-In
                if nsError.code != 1001 {
                    showError(error.localizedDescription)
                }
            }
        }
        appleSignInCoordinator = coordinator
        controller.delegate = coordinator
        controller.presentationContextProvider = coordinator
        controller.performRequests()
    }

    private func randomNonceString(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Apple Sign-In Coordinator (Minimal)

private class MinimalAppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
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
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first else {
            // Fallback: use any available window scene
            let fallbackScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            return fallbackScene?.windows.first(where: { $0.isKeyWindow }) ?? fallbackScene?.windows.first ?? UIWindow(frame: .zero)
        }
        return window
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

// MARK: - Minimal Date Field

private struct MinimalDateField: View {
    @Binding var birthDate: Date
    @Binding var showPicker: Bool
    @Binding var hasPicked: Bool

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    // Latest allowed date: user must be at least 13 to proceed past the picker
    private var maxDate: Date {
        Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tappable row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showPicker.toggle()
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 20)

                    Text(hasPicked
                         ? Self.formatter.string(from: birthDate)
                         : "Date of Birth")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(hasPicked ? .white : .white.opacity(0.35))

                    Spacer()

                    Image(systemName: showPicker ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 18)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(showPicker ? 0.3 : 0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Inline wheel picker
            if showPicker {
                DatePicker(
                    "",
                    selection: $birthDate,
                    in: ...maxDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .onChange(of: birthDate) {
                    hasPicked = true
                }
            }
        }
    }
}

#Preview {
    MinimalAuthenticationView()
}

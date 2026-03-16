//
//  MinimalAuthenticationView.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Editorial, minimal, white-palette auth UI — Login + Sign-Up + Age Verification
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

    // Sign-up stepper: 0 = Your Info, 1 = Security, 2 = Birthday
    @State private var signUpStep: Int = 0

    // Apple Sign-In state
    @State private var currentNonce: String?
    @State private var appleSignInCoordinator: MinimalAppleSignInCoordinator?

    // Entrance animation
    @State private var appeared = false

    @Environment(\.dismiss) var dismiss
    @Namespace private var namespace

    // Forgot password flow
    @State private var showPasswordResetAlert = false
    @State private var resetEmail = ""
    @State private var showResetConfirmation = false
    @State private var isResettingPassword = false

    init(initialMode: AppLaunchView.AuthMode = .login) {
        self.initialMode = initialMode
        self._isLogin = State(initialValue: initialMode == .login)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Off-white canvas — matches launch screen
            Color(red: 0.976, green: 0.973, blue: 0.969)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Navigation bar ─────────────────────────────────────
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(Color(white: 0.30))
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(Color(white: 0.92))
                            )
                    }
                    .accessibilityLabel("Close")
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .opacity(appeared ? 1 : 0)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // ── Header ─────────────────────────────────────
                        VStack(spacing: 0) {
                            Spacer().frame(height: 32)

                            // Small wordmark
                            Text("AMEN")
                                .font(.system(size: 20, weight: .light))
                                .tracking(6)
                                .foregroundStyle(Color(white: 0.62))

                            Spacer().frame(height: 32)

                            // Headline
                            Text(isLogin ? "Welcome\nback." : "Join the\ncommunity.")
                                .font(.system(size: 40, weight: .light))
                                .lineSpacing(2)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 32)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 10)
                                .animation(.easeOut(duration: 0.5).delay(0.08), value: isLogin)

                            Spacer().frame(height: 8)

                            // Sub-headline
                            Text(isLogin
                                 ? "Sign in to continue your journey."
                                 : "Create your free account below.")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(Color(white: 0.48))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 32)
                                .opacity(appeared ? 1 : 0)

                            Spacer().frame(height: 40)

                            // ── Mode toggle — underline tab style ──────
                            HStack(spacing: 0) {
                                modeTab(title: "Log In", selected: isLogin) {
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        isLogin = true; errorMessage = nil; signUpStep = 0
                                    }
                                }
                                modeTab(title: "Sign Up", selected: !isLogin) {
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        isLogin = false; errorMessage = nil; signUpStep = 0
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 32)
                            .opacity(appeared ? 1 : 0)

                            // Rule
                            Rectangle()
                                .fill(Color(white: 0.88))
                                .frame(height: 1)
                                .padding(.horizontal, 32)
                                .opacity(appeared ? 1 : 0)

                            Spacer().frame(height: 36)
                        }

                        // ── Form fields ────────────────────────────────
                        VStack(spacing: 0) {
                            // Error banner
                            if let errorMessage {
                                EditorialErrorBanner(message: errorMessage)
                                    .padding(.horizontal, 32)
                                    .padding(.bottom, 24)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            if isLogin {
                                // ── Login: flat fields ──────────────────
                                VStack(spacing: 16) {
                                    EditorialInputField(
                                        label: "Email",
                                        placeholder: "you@example.com",
                                        text: $email,
                                        keyboardType: .emailAddress
                                    )
                                    EditorialInputField(
                                        label: "Password",
                                        placeholder: "Your password",
                                        text: $password,
                                        isSecure: !showPassword,
                                        showPasswordToggle: true,
                                        showPassword: $showPassword
                                    )
                                }
                                .padding(.horizontal, 32)
                            } else {
                                // ── Sign-up: vertical stepper card ─────
                                SignUpStepperCard(
                                    step: $signUpStep,
                                    fullName: $fullName,
                                    email: $email,
                                    password: $password,
                                    confirmPassword: $confirmPassword,
                                    showPassword: $showPassword,
                                    birthDate: $birthDate,
                                    showDatePicker: $showDatePicker,
                                    hasPickedBirthDate: $hasPickedBirthDate
                                )
                                .padding(.horizontal, 24)
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                            }

                            // Forgot password (login only)
                            if isLogin {
                                Button {
                                    resetEmail = email
                                    showPasswordResetAlert = true
                                } label: {
                                    Text("Forgot password?")
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundStyle(Color(white: 0.48))
                                        .underline()
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.horizontal, 32)
                                .padding(.top, 12)
                                .transition(.opacity)
                            }

                            Spacer().frame(height: 28)

                            // ── Primary CTA ────────────────────────────
                            Button {
                                if !isLogin && signUpStep < 2 {
                                    // Advance stepper
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                        signUpStep += 1
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } else {
                                    handleAuthentication()
                                }
                            } label: {
                                ZStack {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.9)
                                    } else {
                                        HStack(spacing: 8) {
                                            Text(ctaLabel)
                                                .font(.system(size: 15, weight: .semibold))
                                            Image(systemName: isLogin || signUpStep == 2 ? "arrow.right" : "chevron.right")
                                                .font(.system(size: 13, weight: .semibold))
                                        }
                                        .foregroundStyle(.white)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 17)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(isCurrentStepValid ? Color.black : Color(white: 0.72))
                                )
                                .animation(.easeInOut(duration: 0.2), value: isCurrentStepValid)
                            }
                            .disabled(isLoading || !isCurrentStepValid)
                            .padding(.horizontal, 32)

                            // Back button for sign-up steps 1 & 2
                            if !isLogin && signUpStep > 0 {
                                Button {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                        signUpStep -= 1
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    Text("Back")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(Color(white: 0.48))
                                }
                                .padding(.top, 8)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }

                            Spacer().frame(height: 24)

                            // ── Divider ────────────────────────────────
                            HStack(spacing: 12) {
                                Rectangle().fill(Color(white: 0.84)).frame(height: 1)
                                Text("or")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(Color(white: 0.56))
                                Rectangle().fill(Color(white: 0.84)).frame(height: 1)
                            }
                            .padding(.horizontal, 32)

                            Spacer().frame(height: 20)

                            // ── Social sign-in ─────────────────────────
                            VStack(spacing: 10) {
                                EditorialSocialButton(
                                    systemIcon: "apple.logo",
                                    title: "Continue with Apple"
                                ) { handleAppleSignIn() }

                                EditorialSocialButton(
                                    systemIcon: "g.circle.fill",
                                    title: "Continue with Google"
                                ) { handleGoogleSignIn() }
                            }
                            .padding(.horizontal, 32)

                            // Terms (sign-up only)
                            if !isLogin {
                                Text("By creating an account you agree to our\n**Terms of Service** and **Privacy Policy**.")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(Color(white: 0.52))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                                    .padding(.top, 28)
                                    .transition(.opacity)
                            }

                            Spacer().frame(height: 60)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.60).delay(0.08)) {
                appeared = true
            }
        }
        .alert("Reset Password", isPresented: $showPasswordResetAlert) {
            TextField("Email address", text: $resetEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Send Reset Link") {
                guard !resetEmail.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                handlePasswordReset()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter your email address and we'll send you a link to reset your password.")
        }
        .alert("Email Sent", isPresented: $showResetConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("A password reset link has been sent to \(resetEmail). Please check your inbox.")
        }
    }

    // MARK: - Mode tab helper

    @ViewBuilder
    private func modeTab(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .black : Color(white: 0.58))
                    .padding(.horizontal, 4)

                if selected {
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 2)
                        .matchedGeometryEffect(id: "tab_underline", in: namespace)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 2)
                }
            }
            .padding(.trailing, 24)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Validation

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

    // Per-step CTA label
    private var ctaLabel: String {
        if isLogin { return "Log In" }
        switch signUpStep {
        case 0: return "Continue"
        case 1: return "Continue"
        default: return "Create Account"
        }
    }

    // Per-step validation so the CTA enables/disables per step
    private var isCurrentStepValid: Bool {
        if isLogin { return !email.isEmpty && !password.isEmpty }
        switch signUpStep {
        case 0: return !fullName.trimmingCharacters(in: .whitespaces).isEmpty && !email.isEmpty
        case 1: return !password.isEmpty && !confirmPassword.isEmpty && password == confirmPassword
        default: return hasPickedBirthDate
        }
    }

    // MARK: - Auth handlers

    private func handleAuthentication() {
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
                    _ = try await FirebaseManager.shared.signIn(
                        email: email,
                        password: password
                    )
                } else {
                    _ = try await FirebaseManager.shared.signUp(
                        email: email,
                        password: password,
                        displayName: fullName,
                        birthYear: birthYear
                    )
                }
                await MainActor.run {
                    isLoading = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    showError(getErrorMessage(for: error))
                }
            }
        }
    }

    private func getErrorMessage(for error: Error) -> String {
        if let authError = error as? AuthErrorCode {
            switch authError.code {
            case .emailAlreadyInUse:    return "This email is already registered"
            case .invalidEmail:         return "Please enter a valid email address"
            case .weakPassword:         return "Password must be at least 6 characters"
            case .userNotFound:         return "No account found with this email"
            case .wrongPassword:        return "Incorrect password"
            case .networkError:         return "Network error — please check your connection"
            default:                    return error.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private func showError(_ message: String) {
        withAnimation(.easeInOut(duration: 0.22)) {
            errorMessage = message
        }
    }

    // MARK: - Password Reset

    private func handlePasswordReset() {
        let trimmedEmail = resetEmail.trimmingCharacters(in: .whitespaces)
        guard !trimmedEmail.isEmpty else { return }
        isResettingPassword = true
        Task {
            do {
                try await Auth.auth().sendPasswordReset(withEmail: trimmedEmail)
                await MainActor.run {
                    isResettingPassword = false
                    showResetConfirmation = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    isResettingPassword = false
                    showError(getErrorMessage(for: error))
                }
            }
        }
    }

    // MARK: - Social Auth

    private func handleGoogleSignIn() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                _ = try await FirebaseManager.shared.signInWithGoogle()
                await MainActor.run {
                    isLoading = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
            } catch let error as NSError {
                await MainActor.run {
                    isLoading = false
                    if error.code != -5 { showError(error.localizedDescription) }
                }
            }
        }
    }

    private func handleAppleSignIn() {
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
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
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
                if nsError.code != 1001 { showError(error.localizedDescription) }
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

// MARK: - Apple Sign-In Coordinator

private class MinimalAppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private let onCompletion: (Result<ASAuthorization, Error>) -> Void

    init(onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.onCompletion = onCompletion
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        onCompletion(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        onCompletion(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Prefer the foreground-active scene; fall back to any connected UIWindowScene.
        let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        if let scene = windowScene {
            return scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first ?? UIWindow(windowScene: scene)
        }
        // Last-resort fallback — should never reach here in a normal app lifecycle.
        // Use the screen bounds from any available UIWindowScene to avoid UIScreen.main deprecation.
        let fallbackScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let bounds = fallbackScene?.screen.bounds ?? CGRect(x: 0, y: 0, width: 390, height: 844)
        return UIWindow(frame: bounds)
    }
}

// MARK: - Editorial Input Field

private struct EditorialInputField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var showPasswordToggle: Bool = false
    @Binding var showPassword: Bool

    @FocusState private var isFocused: Bool

    init(
        label: String,
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool = false,
        keyboardType: UIKeyboardType = .default,
        showPasswordToggle: Bool = false,
        showPassword: Binding<Bool> = .constant(false)
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.isSecure = isSecure
        self.keyboardType = keyboardType
        self.showPasswordToggle = showPasswordToggle
        self._showPassword = showPassword
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Label
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(white: 0.42))
                .tracking(0.5)

            // Input row
            HStack(spacing: 0) {
                Group {
                    if isSecure {
                        SecureField(placeholder, text: $text)
                            .focused($isFocused)
                    } else {
                        TextField(placeholder, text: $text)
                            .keyboardType(keyboardType)
                            .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .words)
                            .focused($isFocused)
                    }
                }
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.black)
                .autocorrectionDisabled()

                if showPasswordToggle {
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(Color(white: 0.50))
                    }
                    .padding(.leading, 8)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? Color.white : Color(white: 0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isFocused ? Color.black.opacity(0.22) : Color(white: 0.86),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .animation(.easeInOut(duration: 0.18), value: isFocused)
        }
    }
}

// MARK: - Editorial Date Field

private struct EditorialDateField: View {
    @Binding var birthDate: Date
    @Binding var showPicker: Bool
    @Binding var hasPicked: Bool

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    private var maxDate: Date {
        Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Date of Birth")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(white: 0.42))
                .tracking(0.5)

            VStack(spacing: 0) {
                // Tap row
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showPicker.toggle()
                    }
                } label: {
                    HStack {
                        Text(hasPicked
                             ? Self.formatter.string(from: birthDate)
                             : "Select your date of birth")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(hasPicked ? .black : Color(white: 0.56))

                        Spacer()

                        Image(systemName: showPicker ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(Color(white: 0.50))
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(showPicker ? Color.white : Color(white: 0.95))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            showPicker ? Color.black.opacity(0.22) : Color(white: 0.86),
                            lineWidth: showPicker ? 1.5 : 1
                        )
                )

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
                    .colorScheme(.light)
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .onChange(of: birthDate) {
                        hasPicked = true
                    }
                }
            }

            // Age compliance note
            Text("You must be 13 or older to join.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color(white: 0.56))
                .padding(.top, 2)
        }
    }
}

// MARK: - Editorial Social Button

private struct EditorialSocialButton: View {
    let systemIcon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemIcon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.black)

                Text(title)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.black)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(white: 0.84), lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Editorial Error Banner

private struct EditorialErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14, weight: .regular))

            Text(message)
                .font(.system(size: 13, weight: .regular))
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(Color(red: 0.78, green: 0.18, blue: 0.18))
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.78, green: 0.18, blue: 0.18).opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(red: 0.78, green: 0.18, blue: 0.18).opacity(0.20), lineWidth: 1)
                )
        )
    }
}

// MARK: - SignUpStepperCard
// Vertical stepper card matching the reference design:
// active step = filled black circle + bold label + expanded fields
// pending step = outlined gray circle + gray label

private struct SignUpStepperCard: View {
    @Binding var step: Int
    @Binding var fullName: String
    @Binding var email: String
    @Binding var password: String
    @Binding var confirmPassword: String
    @Binding var showPassword: Bool
    @Binding var birthDate: Date
    @Binding var showDatePicker: Bool
    @Binding var hasPickedBirthDate: Bool

    private let steps: [(icon: String, label: String)] = [
        ("person.fill",     "Your Info"),
        ("lock.fill",       "Security"),
        ("calendar",        "Birthday"),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            // White card
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 6)
                .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(steps.indices, id: \.self) { index in
                    stepRow(index: index)

                    // Connector line — not after last step
                    if index < steps.count - 1 {
                        stepConnector(active: step > index)
                    }
                }
            }
            .padding(.vertical, 20)
        }
    }

    // MARK: - Step row

    @ViewBuilder
    private func stepRow(index: Int) -> some View {
        let isActive   = step == index
        let isComplete = step > index

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                // Circle indicator
                ZStack {
                    Circle()
                        .fill(isActive || isComplete ? Color.black : Color(white: 0.94))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle()
                                .stroke(isActive || isComplete ? Color.clear : Color(white: 0.82), lineWidth: 1)
                        )
                        .shadow(color: isActive ? Color.black.opacity(0.18) : .clear, radius: 6, x: 0, y: 3)

                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: steps[index].icon)
                            .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? .white : Color(white: 0.62))
                    }
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.76), value: step)

                // Step label
                Text(steps[index].label)
                    .font(.system(size: isActive ? 20 : 16,
                                  weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.black : Color(white: 0.56))
                    .animation(.easeInOut(duration: 0.2), value: step)

                Spacer()
            }
            .padding(.horizontal, 20)

            // Expanded fields for the active step
            if isActive {
                stepFields(index: index)
                    .padding(.leading, 76)   // align under the label (40 circle + 16 gap + 20 pad)
                    .padding(.trailing, 20)
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Connector line

    @ViewBuilder
    private func stepConnector(active: Bool) -> some View {
        HStack(spacing: 0) {
            // Horizontally aligned under the center of the 40pt circle
            // left padding = 20 (card) + 20 (half circle) = 40 → center
            Spacer().frame(width: 39)   // 20 pad + half of 40pt circle - 1 for line width
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: active
                            ? [Color.black.opacity(0.6), Color.black.opacity(0.2)]
                            : [Color(white: 0.82), Color(white: 0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2, height: 24)
            Spacer()
        }
        .animation(.easeInOut(duration: 0.3), value: active)
    }

    // MARK: - Step fields

    @ViewBuilder
    private func stepFields(index: Int) -> some View {
        switch index {
        case 0:
            VStack(spacing: 12) {
                EditorialInputField(
                    label: "Full Name",
                    placeholder: "Your name",
                    text: $fullName
                )
                EditorialInputField(
                    label: "Email",
                    placeholder: "you@example.com",
                    text: $email,
                    keyboardType: .emailAddress
                )
            }
        case 1:
            VStack(spacing: 12) {
                EditorialInputField(
                    label: "Password",
                    placeholder: "Create a password",
                    text: $password,
                    isSecure: !showPassword,
                    showPasswordToggle: true,
                    showPassword: $showPassword
                )
                EditorialInputField(
                    label: "Confirm Password",
                    placeholder: "Re-enter password",
                    text: $confirmPassword,
                    isSecure: !showPassword
                )
                // Inline password match indicator
                if !password.isEmpty && !confirmPassword.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: password == confirmPassword ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(password == confirmPassword ? Color.green : Color.red)
                        Text(password == confirmPassword ? "Passwords match" : "Passwords don't match")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(password == confirmPassword ? Color.green : Color.red)
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.18), value: password == confirmPassword)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                EditorialDateField(
                    birthDate: $birthDate,
                    showPicker: $showDatePicker,
                    hasPicked: $hasPickedBirthDate
                )
            }
        }
    }
}

#Preview {
    MinimalAuthenticationView()
}

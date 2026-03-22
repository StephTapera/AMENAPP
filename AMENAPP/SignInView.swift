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
import FirebaseAuth
import FirebaseFunctions
import AuthenticationServices
import CryptoKit
import GoogleSignIn

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
    @State private var showPasswordlessSignIn = false
    @State private var passwordlessEmail = ""
    @State private var showEmailLinkSent = false
    
    // OTP Verification
    @State private var phoneNumber = ""
    @State private var showOTPVerification = false
    @State private var otpCode = ""
    @State private var isResendingOTP = false
    @State private var otpTimer = 60
    @State private var canResendOTP = false
    @State private var otpSentAt: Date?
    @State private var otpAttempts = 0
    @State private var otpTimerInstance: Timer?
    
    // Sign-up method selection
    @State private var signUpMethod: SignUpMethod = .email

    // Remember Me
    @State private var rememberMe = SessionTimeoutManager.shared.isRememberMeEnabled()

    enum SignUpMethod {
        case email
        case phone
    }
    
    // Password strength
    private var passwordStrength: PasswordStrength {
        calculatePasswordStrength(password)
    }
    
    var body: some View {
        mainContent
            .ignoresSafeArea()
            .modifier(AlertsModifier(viewModel: viewModel, showResetSuccess: $showResetSuccess, showEmailLinkSent: $showEmailLinkSent))
            .modifier(SheetsModifier(
                showPasswordReset: $showPasswordReset,
                showPasswordlessSignIn: $showPasswordlessSignIn,
                showOTPVerification: $showOTPVerification,
                resetEmail: $resetEmail,
                passwordlessEmail: $passwordlessEmail,
                phoneNumber: phoneNumber,
                otpCode: $otpCode,
                isResendingOTP: $isResendingOTP,
                otpTimer: $otpTimer,
                canResendOTP: $canResendOTP,
                showResetSuccess: $showResetSuccess,
                showEmailLinkSent: $showEmailLinkSent,
                viewModel: viewModel,
                otpTimerInstance: $otpTimerInstance,
                verifyOTP: verifyOTP,
                resendOTP: resendOTP
            ))
            .modifier(SignInLifecycleModifier(
                showAmenTitle: $showAmenTitle,
                amenTitleOpacity: $amenTitleOpacity,
                scenePhase: scenePhase,
                nonceGeneratedAt: nonceGeneratedAt,
                generateAppleNonce: generateAppleNonce
            ))
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        ZStack {
            // Dark background matching the design image
            Color.black
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    amenTitle
                    authCard
                }
            }
            .onTapGesture {
                // Dismiss keyboard when tapping background
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }
    
    private var amenTitle: some View {
        Group {
            if showAmenTitle {
                Text("AMEN")
                    .font(.custom("OpenSans-Bold", size: 32))
                    .foregroundStyle(.white)
                    .opacity(amenTitleOpacity)
                    .padding(.top, 80)
                    .padding(.bottom, 20)
                    .transition(.opacity)
            }
        }
    }
    
    private var authCard: some View {
        VStack(spacing: 24) {
            // Icon at top (matching design)
            Image(systemName: "person.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.top, 32)

            titleSection
            signUpMethodToggle
            inputFieldsSection
            actionButtons
            toggleSignInSignUp
        }
        .frame(maxWidth: 420)
        .background(cardBackground)
        .padding(.horizontal, 20)
        .padding(.bottom, 60)
    }
    
    private var titleSection: some View {
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
    }
    
    @ViewBuilder
    private var signUpMethodToggle: some View {
        if !isLogin {
            HStack(spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        signUpMethod = .email
                    }
                } label: {
                    Text("Email")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(signUpMethod == .email ? .black : .white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(signUpMethod == .email ? .white : .clear)
                        )
                }
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        signUpMethod = .phone
                    }
                } label: {
                    Text("Phone")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(signUpMethod == .phone ? .black : .white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(signUpMethod == .phone ? .white : .clear)
                        )
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 32)
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
    
    private var inputFieldsSection: some View {
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
            
            // Phone Number (login OR phone signup)
            if isLogin || signUpMethod == .phone {
                DarkGlassmorphicTextField(
                    icon: "phone",
                    placeholder: "Phone Number",
                    text: $phoneNumber,
                    keyboardType: .phonePad
                )
                .onChange(of: phoneNumber) { _, newValue in
                    phoneNumber = formatPhoneNumberInput(newValue)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Email or Username (login) / Email (email signup)
            if isLogin || signUpMethod == .email {
                DarkGlassmorphicTextField(
                    icon: isLogin ? "person.text.rectangle" : "envelope",
                    placeholder: isLogin ? "Email or username" : "Email",
                    text: $email,
                    keyboardType: isLogin ? .default : .emailAddress
                )
                .onChange(of: email) { _, _ in
                    if viewModel.showError {
                        viewModel.showError = false
                        viewModel.errorMessage = nil
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Password (login OR email signup)
            if isLogin || signUpMethod == .email {
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Forgot Password link and Remember Me
            if isLogin {
                HStack {
                    // Remember Me toggle
                    HStack(spacing: 8) {
                        Toggle("", isOn: $rememberMe)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                            .scaleEffect(0.8)

                        Text("Remember Me")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    // Forgot Password
                    Button {
                        showPasswordReset = true
                    } label: {
                        Text("Forgot Password?")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
            }

            errorMessageView
            passwordStrengthView
        }
        .padding(.horizontal, 32)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isLogin)
    }
    
    @ViewBuilder
    private var errorMessageView: some View {
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
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            ))
            .onAppear {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
    
    @ViewBuilder
    private var passwordStrengthView: some View {
        if !isLogin && !password.isEmpty {
            DarkPasswordStrengthIndicator(strength: passwordStrength)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 8) {
            primaryActionButton
            biometricSignInButton
            googleSignInButton
            appleSignInButton
            passwordlessSignInButton
        }
    }
    
    private var primaryActionButton: some View {
        Button {
            // Immediate haptic feedback for responsiveness
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            handleAuth()
        } label: {
            HStack(spacing: 12) {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    Text("Signing in...")
                        .font(.custom("OpenSans-SemiBold", size: 15))
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
            .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
        }
        .disabled(viewModel.isLoading || !isFormValid)
        .opacity(isFormValid ? 1.0 : 0.5)
        .padding(.horizontal, 32)
        .padding(.top, 12)
    }
    
    private var googleSignInButton: some View {
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
    }
    
    private var appleSignInButton: some View {
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
    }
    
    @ViewBuilder
    private var biometricSignInButton: some View {
        // Show biometric option if:
        // 1. User is on login screen
        // 2. Biometric hardware is available
        // 3. Either biometric is enabled OR user has a saved session
        if isLogin && BiometricAuthService.shared.isBiometricAvailable {
            let hasSession = Auth.auth().currentUser != nil
            let showBiometric = BiometricAuthService.shared.isBiometricEnabled || hasSession
            
            if showBiometric {
                Button {
                    handleBiometricSignIn()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: BiometricAuthService.shared.biometricType.icon)
                            .font(.system(size: 18))
                        Text("Sign in with \(BiometricAuthService.shared.biometricType.displayName)")
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var passwordlessSignInButton: some View {
        if isLogin {
            Button {
                showPasswordlessSignIn = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "envelope.arrow.triangle.branch")
                        .font(.system(size: 16))
                    Text("Sign in with Email Link")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                }
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(.white.opacity(0.15), lineWidth: 1)
                        )
                )
            }
            .padding(.horizontal, 32)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
    
    private var toggleSignInSignUp: some View {
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
    
    private var cardBackground: some View {
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
    }
    
    private var isFormValid: Bool {
        if isLogin {
            // Login: requires phone number OR (email + password)
            let hasValidPhone = !phoneNumber.isEmpty && phoneNumber.count >= 10
            let hasEmailPassword = !email.isEmpty && !password.isEmpty
            return hasValidPhone || hasEmailPassword
        } else {
            // Sign-up: requires display name and username for both methods
            let basicFieldsValid = !displayName.isEmpty && !username.isEmpty
            
            if !basicFieldsValid {
                return false
            }
            
            // Username must be checked and available
            guard usernameAvailable == true else {
                return false
            }
            
            // Validate based on selected sign-up method
            if signUpMethod == .email {
                // Email sign-up: requires email + password
                guard !email.isEmpty && !password.isEmpty else {
                    return false
                }
                
                // Email format validation
                guard isValidEmailFormat(email) else {
                    return false
                }
                
                // Password strength validation - require at least medium strength
                let strength = calculatePasswordStrength(password)
                guard strength != .weak else {
                    return false
                }
                
                return true
            } else {
                // Phone sign-up: requires phone number only
                let hasValidPhone = !phoneNumber.isEmpty && phoneNumber.count >= 10
                if !hasValidPhone {
                    return false
                }
                return true
            }
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
        
        authTask = Task {
            guard !Task.isCancelled else {
                dlog("⚠️ Auth request cancelled before starting")
                return
            }

            // P0 FIX: 30-second timeout on all auth operations.
            // Prevents indefinite spinner if network hangs.
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if viewModel.isLoading {
                        viewModel.isLoading = false
                        viewModel.errorMessage = "Sign-in timed out. Please check your connection and try again."
                        viewModel.showError = true
                    }
                }
            }
            defer { timeoutTask.cancel() }
            
            if isLogin {
                // Login flow: phone OR email+password
                if !phoneNumber.isEmpty && phoneNumber.count >= 10 {
                    // Phone login with OTP
                    dlog("📱 Phone login - Sending OTP")
                    await viewModel.sendPhoneVerificationCode(phoneNumber: phoneNumber)
                    
                    await MainActor.run {
                        otpSentAt = Date()
                        otpAttempts = 0
                        showOTPVerification = true
                        startOTPTimer()
                    }
                } else {
                    // Email+password login
                    let loginIdentifier = email.trimmingCharacters(in: .whitespaces).lowercased()
                    dlog("📧 Email login with: \(loginIdentifier)")

                    if loginIdentifier.hasPrefix("@") {
                        // Username login
                        await signInWithUsername(loginIdentifier)
                    } else if loginIdentifier.contains("@") {
                        // Email login
                        await viewModel.signIn(email: loginIdentifier, password: password)
                    } else {
                        // Assume username without @
                        await signInWithUsername("@\(loginIdentifier)")
                    }

                    // Apply Remember Me setting after successful login
                    if viewModel.isAuthenticated {
                        SessionTimeoutManager.shared.setRememberMe(rememberMe)
                        if !rememberMe {
                            SessionTimeoutManager.shared.startMonitoring(rememberMe: false)
                        }
                    }
                }
            } else {
                // Sign-up flow: email OR phone (based on selected method)
                if signUpMethod == .phone {
                    // Phone sign-up with OTP
                    dlog("📱 Phone sign-up - Sending OTP")
                    await viewModel.sendPhoneVerificationCode(phoneNumber: phoneNumber)
                    
                    await MainActor.run {
                        otpSentAt = Date()
                        otpAttempts = 0
                        showOTPVerification = true
                        startOTPTimer()
                    }
                } else {
                    // Email sign-up with password
                    dlog("📧 Email sign-up initiated")
                    await viewModel.signUp(
                        email: email,
                        password: password,
                        displayName: displayName,
                        username: username
                    )
                }
            }
        }
    }
    
    private func handleAuthOld() {
        // Dismiss keyboard
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        // ── Device integrity: check for login lockout before attempting auth ──
        if isLogin {
            if let lockMessage = DeviceIntegrityService.shared.checkLoginAllowed() {
                viewModel.errorMessage = lockMessage
                return
            }
        }
        // ──────────────────────────────────────────────────────────────────────
        
        // Cancel any existing auth request to prevent duplicates
        authTask?.cancel()
        
        // Create new auth task
        authTask = Task {
            // Early exit if already cancelled
            guard !Task.isCancelled else {
                dlog("⚠️ Auth request cancelled before starting")
                return
            }
            if isLogin {
                // Check if user entered @username instead of email
                let loginIdentifier = email.trimmingCharacters(in: .whitespaces).lowercased()
                
                dlog("📧 Sign-in attempt with: \(loginIdentifier.contains("@") && !loginIdentifier.hasPrefix("@") ? "email" : "username")")
                
                if loginIdentifier.hasPrefix("@") {
                    // User entered @username - need to look up email
                    dlog("🔍 Looking up email for username: \(loginIdentifier)")
                    await signInWithUsername(loginIdentifier)
                } else if loginIdentifier.contains("@") {
                    // Regular email sign-in
                    dlog("📧 Email sign-in")
                    await viewModel.signIn(email: loginIdentifier, password: password)
                } else {
                    // Assume it's username without @ prefix
                    dlog("🔍 Looking up email for username: @\(loginIdentifier)")
                    await signInWithUsername("@\(loginIdentifier)")
                }

                // ── Device integrity: record success or failure ──────────────
                if viewModel.isAuthenticated {
                    DeviceIntegrityService.shared.recordLoginSuccess()
                } else {
                    DeviceIntegrityService.shared.recordLoginFailure()
                }
                // ────────────────────────────────────────────────────────────
                
                // ✅ Cache user name for messaging after successful login
                if viewModel.isAuthenticated {
                    await FirebaseMessagingService.shared.fetchAndCacheCurrentUserName()
                    dlog("✅ User name cached for messaging")
                }
            } else {
                dlog("📝 Sign-up attempt")
                
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
                    dlog("✅ User name cached for messaging")
                }
            }
            
            // Clear task reference when complete
            await MainActor.run {
                authTask = nil
            }
        }
    }
    
    private func signInWithUsername(_ usernameInput: String) async {
        // Normalise: strip leading @, lowercase, trim whitespace
        let cleanUsername = usernameInput
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: "@", with: "")

        dlog("🔍 Username lookup: @\(cleanUsername)")

        do {
            // P0 CRASH FIX: Firebase HTTPSCallable.call() uses async let internally.
            // If the parent Task is cancelled (e.g. view dismissed mid-sign-in),
            // Swift tries to deallocate the child task → SIGABRT in asyncLet_finish.
            // Fix: use Task.detached so the callable doesn't inherit cancellation.
            let functions = Functions.functions()
            let resolvedEmail: String = try await Task.detached {
                let callable = functions.httpsCallable("resolveUsernameToEmail")
                let result = try await callable.call(["username": cleanUsername])
                guard let data = result.data as? [String: Any],
                      let email = data["email"] as? String, !email.isEmpty else {
                    throw NSError(domain: "SignIn", code: 0, userInfo: [NSLocalizedDescriptionKey: "Username not found"])
                }
                return email
            }.value

            dlog("✅ @\(cleanUsername) resolved — proceeding with sign-in")
            await viewModel.signIn(email: resolvedEmail, password: password)

        } catch let error as NSError {
            dlog("❌ resolveUsernameToEmail: domain=\(error.domain) code=\(error.code) — \(error.localizedDescription)")

            let functionsCode = FunctionsErrorCode(rawValue: error.code)
            let message: String
            switch functionsCode {
            case .notFound, .invalidArgument:
                // Username doesn't exist — same message as wrong password to avoid enumeration
                message = "Incorrect username or password."
            case .failedPrecondition:
                // Account has no password (Google/Apple sign-in only)
                message = error.localizedDescription
            case .internal, .unavailable, .unknown, .none:
                // Function not deployed yet or network error
                message = "Sign-in unavailable right now. Please use your email address to sign in."
            default:
                message = "Incorrect username or password."
            }
            await MainActor.run {
                viewModel.errorMessage = message
                viewModel.showError = true
            }
        }
    }
    
    // MARK: - OTP Functions
    
    /// P0 FIX: Improved OTP verification with proper error handling and state management
    private func verifyOTP() async {
        dlog("🔐 Verifying OTP: \(otpCode)")
        
        // Validate OTP format (6 digits)
        guard otpCode.count == 6, otpCode.allSatisfy({ $0.isNumber }) else {
            await MainActor.run {
                viewModel.errorMessage = "Please enter a valid 6-digit code."
                viewModel.showError = true
            }
            return
        }
        
        // Check OTP expiration (10 minutes)
        if let sentAt = otpSentAt {
            let timeElapsed = Date().timeIntervalSince(sentAt)
            if timeElapsed > 600 { // 10 minutes in seconds
                await MainActor.run {
                    viewModel.errorMessage = "OTP expired. Please request a new code."
                    viewModel.showError = true
                    otpCode = ""
                    otpAttempts = 0
                }
                return
            }
        }
        
        // Check retry attempt limit
        if otpAttempts >= 5 {
            await MainActor.run {
                viewModel.errorMessage = "Too many wrong attempts. Please request a new code."
                viewModel.showError = true
                showOTPVerification = false
                cleanupOTPState()
            }
            return
        }
        
        // P0 FIX: Pass isSignUp flag to properly handle login vs signup
        if isLogin {
            // Phone login: Verify code and sign in
            await viewModel.verifyPhoneCode(
                otpCode,
                displayName: "",
                username: "",
                isSignUp: false
            )
        } else {
            // Sign up with phone OTP - create new user profile
            await viewModel.verifyPhoneCode(
                otpCode,
                displayName: displayName,
                username: username,
                isSignUp: true
            )
        }
        
        // Check if verification was successful
        if viewModel.isAuthenticated {
            dlog("✅ Phone verification successful - closing OTP sheet")
            
            // Close OTP sheet and clean up state
            await MainActor.run {
                showOTPVerification = false
                cleanupOTPState()
                
                // Cache user name for messaging
                Task {
                    await FirebaseMessagingService.shared.fetchAndCacheCurrentUserName()
                    dlog("✅ User authenticated and name cached")
                }
            }
        } else {
            // Wrong OTP - increment attempts
            await MainActor.run {
                otpAttempts += 1
                otpCode = ""
                if otpAttempts < 5 {
                    viewModel.errorMessage = "Invalid code. \(5 - otpAttempts) attempts remaining."
                    viewModel.showError = true
                }
            }
        }
    }
    
    /// P1 FIX: Improved resend with duplicate prevention
    private func resendOTP() async {
        // P0: Prevent duplicate resends
        guard canResendOTP else {
            dlog("⚠️ Cannot resend yet - timer still active")
            return
        }
        
        dlog("🔄 Resending OTP")
        await viewModel.resendVerificationCode(phoneNumber: phoneNumber)
        
        // Only restart timer if send was successful (no error)
        if !viewModel.showError {
            await MainActor.run {
                otpSentAt = Date()
                otpAttempts = 0
                otpCode = ""
                startOTPTimer()
            }
        }
    }
    
    /// P1 FIX: Cleanup OTP state when dismissing sheet
    private func cleanupOTPState() {
        otpCode = ""
        otpAttempts = 0
        otpSentAt = nil
        otpTimerInstance?.invalidate()
        otpTimerInstance = nil
        canResendOTP = false
        otpTimer = 60
        
        // Clean up view model state
        viewModel.cleanupPhoneAuthState()
        
        dlog("🧹 OTP state cleaned up")
    }
    
    private func startOTPTimer() {
        // Invalidate existing timer first
        otpTimerInstance?.invalidate()
        
        otpTimer = 60
        canResendOTP = false
        
        // Store timer reference for cleanup
        otpTimerInstance = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] timer in
            if otpTimer > 0 {
                otpTimer -= 1
            } else {
                canResendOTP = true
                timer.invalidate()
                otpTimerInstance = nil
            }
        }
    }
    
    private func formatPhoneNumberInput(_ input: String) -> String {
        // Remove all non-numeric characters
        let digits = input.filter { $0.isNumber }
        
        // Limit to 15 digits (international format)
        let limited = String(digits.prefix(15))
        
        // Format as user types (US format)
        if limited.count <= 3 {
            return limited
        } else if limited.count <= 6 {
            let areaCode = limited.prefix(3)
            let rest = limited.dropFirst(3)
            return "(\(areaCode)) \(rest)"
        } else {
            let areaCode = limited.prefix(3)
            let middle = limited.dropFirst(3).prefix(3)
            let last = limited.dropFirst(6)
            return "(\(areaCode)) \(middle)-\(last)"
        }
    }
    
    private func handleBiometricSignIn() {
        Task {
            let biometricService = BiometricAuthService.shared
            
            // Authenticate with biometrics (includes passcode fallback)
            let authenticated = await biometricService.authenticateWithPasscodeFallback(
                reason: "Sign in to AMEN"
            )
            
            guard authenticated else {
                await MainActor.run {
                    viewModel.errorMessage = "Authentication failed. Please try again or use email/password."
                    viewModel.showError = true
                }
                return
            }
            
            // Check if there's a Firebase user session
            // Biometric auth is used to unlock an existing session, not create a new one
            guard let currentUser = Auth.auth().currentUser else {
                await MainActor.run {
                    viewModel.errorMessage = "No saved session found. Please sign in with email and password first to enable biometric sign-in."
                    viewModel.showError = true
                    // Disable biometric since there's no session to unlock
                    biometricService.disableBiometric()
                }
                return
            }
            
            // Biometric auth successful - user is already signed in via Firebase Auth
            // Just reload the user data to refresh the session
            await MainActor.run {
                viewModel.isLoading = true
            }
            
            do {
                // Reload user to ensure token is fresh
                try await currentUser.reload()
                
                await MainActor.run {
                    viewModel.isAuthenticated = true
                    viewModel.isLoading = false
                }
                
                dlog("✅ Biometric sign-in successful")
                
            } catch {
                await MainActor.run {
                    viewModel.errorMessage = "Failed to verify session. Please sign in again."
                    viewModel.showError = true
                    viewModel.isLoading = false
                }
                
                dlog("❌ Biometric sign-in failed: \(error.localizedDescription)")
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
                dlog("❌ Username availability check error: \(error)")
                dlog("   Error details: \(error.localizedDescription)")
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
    
    private func lookupUserByPhone(_ phoneNumber: String) async -> (displayName: String, username: String)? {
        let db = Firestore.firestore()
        
        // Format phone to E.164 for consistent lookup
        let formattedPhone = formatPhoneNumberForLookup(phoneNumber)
        
        do {
            let snapshot = try await db.collection("users")
                .whereField("phoneNumber", isEqualTo: formattedPhone)
                .limit(to: 1)
                .getDocuments()
            
            guard let userDoc = snapshot.documents.first else {
                dlog("❌ No user found for phone login")
                return nil
            }
            
            let displayName = userDoc.data()["displayName"] as? String ?? ""
            let username = userDoc.data()["username"] as? String ?? ""
            
            dlog("✅ Found user for phone login")
            return (displayName, username)
            
        } catch {
            dlog("❌ Phone lookup failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func formatPhoneNumberForLookup(_ phoneNumber: String) -> String {
        let digits = phoneNumber.filter { $0.isNumber }
        
        if phoneNumber.hasPrefix("+") {
            return phoneNumber
        }
        
        if digits.count == 11 && digits.hasPrefix("1") {
            return "+\(digits)"
        }
        
        if digits.count == 10 {
            return "+1\(digits)"
        }
        
        return "+\(digits)"
    }
    
    private func handleGoogleSignIn() {
        Task {
            do {
                viewModel.isLoading = true
                dlog("🔵 Google Sign-In initiated")
                
                let _ = try await FirebaseManager.shared.signInWithGoogle()
                
                dlog("✅ Google Sign-In successful")
                
                await MainActor.run {
                    viewModel.isAuthenticated = true
                    viewModel.needsOnboarding = true
                    viewModel.isLoading = false
                }
                
                // Cache user name for messaging
                await FirebaseMessagingService.shared.fetchAndCacheCurrentUserName()
                dlog("✅ User name cached for messaging")
                
            } catch {
                let nsError = error as NSError
                dlog("❌ Google Sign-In failed")
                dlog("   Error domain: \(nsError.domain)")
                dlog("   Error code: \(nsError.code)")
                dlog("   Description: \(error.localizedDescription)")
                
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
                        dlog("ℹ️ User cancelled Google Sign-In")
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
        dlog("🍎 Apple nonce pre-generated: \(nonce.prefix(10))... (length: \(nonce.count))")
    }
    
    private func handleAppleSignIn() {
        // Generate fresh nonce with timestamp
        let nonce = randomNonceString()
        currentNonce = nonce
        nonceGeneratedAt = Date()
        
        dlog("🍎 Apple Sign-In initiated")
        dlog("📋 Nonce generated: \(nonce.prefix(10))... (length: \(nonce.count))")
        dlog("⏰ Timestamp: \(Date())")
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        dlog("🔐 SHA256 nonce: \(sha256(nonce).prefix(10))...")
        
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
                dlog("⏱️ Time elapsed since nonce generation: \(elapsed) seconds")
                
                if elapsed > 300 { // 5 minutes
                    dlog("❌ Nonce expired (>5 minutes old)")
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
                dlog("❌ No nonce available - session may have expired")
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
            
            dlog("❌ Apple Sign-In failed with code: \(errorCode)")
            dlog("   Error domain: \(nsError.domain)")
            dlog("   Description: \(error.localizedDescription)")
            
            Task { @MainActor in
                // Don't show error for user cancellation
                if errorCode == 1001 { // ASAuthorizationError.canceled
                    dlog("ℹ️ User cancelled Apple Sign-In")
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
            dlog("❌ Failed to get ASAuthorizationAppleIDCredential")
            Task { @MainActor in
                viewModel.errorMessage = "Unable to process Apple Sign-In credentials"
                viewModel.showError = true
            }
            return
        }
        
        guard let nonce = currentNonce else {
            dlog("❌ No nonce available")
            Task { @MainActor in
                viewModel.errorMessage = "Sign-in session expired. Please try again."
                viewModel.showError = true
            }
            return
        }
        
        guard let appleIDToken = appleIDCredential.identityToken else {
            dlog("❌ No identity token in credential")
            Task { @MainActor in
                viewModel.errorMessage = "Unable to get identity token from Apple"
                viewModel.showError = true
            }
            return
        }
        
        guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            dlog("❌ Failed to convert token data to string")
            Task { @MainActor in
                viewModel.errorMessage = "Invalid token format"
                viewModel.showError = true
            }
            return
        }
        
        // Validate token and nonce
        guard !idTokenString.isEmpty, idTokenString.count > 100 else {
            dlog("❌ Token string too short or empty (length: \(idTokenString.count))")
            Task { @MainActor in
                viewModel.errorMessage = "Invalid authentication token"
                viewModel.showError = true
            }
            return
        }
        
        guard nonce.count == 32 else {
            dlog("❌ Nonce has invalid length: \(nonce.count) (expected 32)")
            Task { @MainActor in
                viewModel.errorMessage = "Invalid authentication session"
                viewModel.showError = true
            }
            return
        }
        
        dlog("✅ Apple Sign-In credentials validated")
        dlog("📋 User ID: \(appleIDCredential.user)")
        dlog("📋 Token length: \(idTokenString.count)")
        dlog("📋 Nonce length: \(nonce.count)")
        dlog("📧 Email: \(appleIDCredential.email ?? "none")")
        dlog("👤 Full name: \(appleIDCredential.fullName?.givenName ?? "none") \(appleIDCredential.fullName?.familyName ?? "")")
        
        Task {
            do {
                dlog("🔄 Attempting Firebase authentication...")
                let _ = try await FirebaseManager.shared.signInWithApple(
                    idToken: idTokenString,
                    nonce: nonce,
                    fullName: appleIDCredential.fullName
                )
                
                dlog("✅ Firebase authentication successful")
                
                await MainActor.run {
                    viewModel.isAuthenticated = true
                    viewModel.needsOnboarding = true
                    
                    // Clear nonce after successful auth
                    currentNonce = nil
                    nonceGeneratedAt = nil
                }
                
                // Cache user name for messaging
                await FirebaseMessagingService.shared.fetchAndCacheCurrentUserName()
                dlog("✅ User name cached for messaging")
                
            } catch {
                let nsError = error as NSError
                dlog("❌ Firebase authentication failed")
                dlog("   Error domain: \(nsError.domain)")
                dlog("   Error code: \(nsError.code)")
                dlog("   Description: \(error.localizedDescription)")
                dlog("   User info: \(nsError.userInfo)")
                
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
            // Fallback: use UUID-based entropy if SecRandomCopyBytes fails (should never happen on-device)
            dlog("⚠️ SecRandomCopyBytes failed (\(errorCode)), using UUID fallback for nonce")
            return UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
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

// MARK: - View Modifiers

struct AlertsModifier: ViewModifier {
    @ObservedObject var viewModel: AuthenticationViewModel
    @Binding var showResetSuccess: Bool
    @Binding var showEmailLinkSent: Bool
    
    func body(content: Content) -> some View {
        content
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
            .alert("Email Sent! ✅", isPresented: $showResetSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Check your inbox for password reset instructions")
            }
            .alert("Magic Link Sent! ✨", isPresented: $showEmailLinkSent) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Check your inbox and tap the link to sign in instantly - no password needed!")
            }
    }
}

struct SheetsModifier: ViewModifier {
    @Binding var showPasswordReset: Bool
    @Binding var showPasswordlessSignIn: Bool
    @Binding var showOTPVerification: Bool
    @Binding var resetEmail: String
    @Binding var passwordlessEmail: String
    let phoneNumber: String
    @Binding var otpCode: String
    @Binding var isResendingOTP: Bool
    @Binding var otpTimer: Int
    @Binding var canResendOTP: Bool
    @Binding var showResetSuccess: Bool
    @Binding var showEmailLinkSent: Bool
    @ObservedObject var viewModel: AuthenticationViewModel
    @Binding var otpTimerInstance: Timer?
    let verifyOTP: () async -> Void
    let resendOTP: () async -> Void
    
    func body(content: Content) -> some View {
        content
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
                                
                                let haptic = UINotificationFeedbackGenerator()
                                haptic.notificationOccurred(.success)
                            } catch let nsError as NSError where nsError.code == 429 {
                                // Rate limit hit — show message without dismissing sheet
                                viewModel.errorMessage = nsError.localizedDescription
                                viewModel.showError = true
                                
                                let haptic = UINotificationFeedbackGenerator()
                                haptic.notificationOccurred(.error)
                            } catch {
                                viewModel.errorMessage = "Failed to send reset email. Please check the email address."
                                viewModel.showError = true
                                showPasswordReset = false
                                
                                let haptic = UINotificationFeedbackGenerator()
                                haptic.notificationOccurred(.error)
                            }
                        }
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showPasswordlessSignIn) {
                PasswordlessSignInSheet(
                    email: $passwordlessEmail,
                    showSuccess: $showEmailLinkSent,
                    onSend: {
                        Task {
                            await viewModel.sendSignInLink(toEmail: passwordlessEmail)
                            showPasswordlessSignIn = false
                            showEmailLinkSent = true
                        }
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showOTPVerification, onDismiss: {
                // P1 FIX: Proper cleanup when sheet is dismissed
                otpTimerInstance?.invalidate()
                otpTimerInstance = nil
                viewModel.cleanupPhoneAuthState()
            }) {
                OTPVerificationView(
                    phoneNumber: phoneNumber,
                    otpCode: $otpCode,
                    isResending: $isResendingOTP,
                    timer: $otpTimer,
                    canResend: $canResendOTP,
                    onVerify: {
                        Task {
                            await verifyOTP()
                        }
                    },
                    onResend: {
                        Task {
                            await resendOTP()
                        }
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
            }
            .fullScreenCover(isPresented: $viewModel.showAuthSuccess) {
                AuthSuccessCheckmarkView(isPresented: $viewModel.showAuthSuccess)
            }
    }
}

struct SignInLifecycleModifier: ViewModifier {
    @Binding var showAmenTitle: Bool
    @Binding var amenTitleOpacity: Double
    let scenePhase: ScenePhase
    let nonceGeneratedAt: Date?
    let generateAppleNonce: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                withAnimation(.easeIn(duration: 0.6)) {
                    showAmenTitle = true
                }
                withAnimation(.easeIn(duration: 0.8).delay(0.2)) {
                    amenTitleOpacity = 1.0
                }
                generateAppleNonce()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active,
                   let timestamp = nonceGeneratedAt {
                    let elapsed = Date().timeIntervalSince(timestamp)
                    if elapsed > 300 {
                        dlog("🔄 Regenerating expired Apple nonce")
                        generateAppleNonce()
                    }
                }
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
    /// True while the network request is in-flight — prevents double-tap.
    @State private var isSending = false
    /// Seconds remaining in the post-send cooldown (60 s). 0 = button re-enabled.
    @State private var cooldownRemaining: Int = 0
    @State private var cooldownTimer: Timer? = nil

    private var canSend: Bool {
        isValidEmail && !isSending && cooldownRemaining == 0
    }

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

                // Send Button — disabled while in-flight or in cooldown
                Button {
                    guard canSend else { return }
                    isSending = true
                    onSend()
                    // Start 60-second cooldown immediately so rapid taps have no effect.
                    startCooldown()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 26)
                            .fill(canSend ? Color.black : Color.black.opacity(0.45))
                            .frame(height: 52)

                        if isSending {
                            ProgressView()
                                .tint(.white)
                        } else if cooldownRemaining > 0 {
                            Text("Resend in \(cooldownRemaining)s")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                                .foregroundStyle(.white.opacity(0.7))
                        } else {
                            Text("Send Reset Link")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .disabled(!canSend)
                .padding(.horizontal, 32)
                .padding(.top, 8)
                .animation(.easeInOut(duration: 0.2), value: canSend)

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
            .onDisappear {
                // Clean up timer if sheet is dismissed mid-cooldown.
                cooldownTimer?.invalidate()
                cooldownTimer = nil
            }
        }
    }

    /// Kicks off a 60-second countdown. Marks isSending = false after the first tick
    /// (request is in-flight; we let the caller decide success/failure).
    private func startCooldown(seconds: Int = 60) {
        cooldownRemaining = seconds
        cooldownTimer?.invalidate()
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            DispatchQueue.main.async {
                if cooldownRemaining > 0 {
                    cooldownRemaining -= 1
                    // Unblock the spinner after the first second — the caller handles dismiss.
                    if cooldownRemaining == seconds - 1 { isSending = false }
                } else {
                    timer.invalidate()
                    cooldownTimer = nil
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

// MARK: - Passwordless Sign-In Sheet

struct PasswordlessSignInSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var email: String
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
                                    Color(red: 0.3, green: 0.6, blue: 0.9).opacity(0.2),
                                    Color(red: 0.4, green: 0.7, blue: 1.0).opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "envelope.arrow.triangle.branch")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.3, green: 0.6, blue: 0.9),
                                    Color(red: 0.4, green: 0.7, blue: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .padding(.top, 20)
                
                // Title & Description
                VStack(spacing: 8) {
                    Text("Sign in with Magic Link ✨")
                        .font(.custom("OpenSans-Bold", size: 24))
                        .foregroundStyle(.black)
                    
                    Text("Enter your email and we'll send you a magic link to sign in instantly - no password needed!")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.black.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                
                // Email Input
                SimpleCleanTextField(
                    icon: "envelope",
                    placeholder: "Email",
                    text: $email,
                    keyboardType: .emailAddress
                )
                .padding(.horizontal, 32)
                .onChange(of: email) { _, newValue in
                    isValidEmail = isValidEmailFormat(newValue)
                }
                
                // Send Button
                Button {
                    onSend()
                } label: {
                    Text("Send Magic Link")
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
        // Search all scenes for an active key window to avoid crash when no window is immediately available
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
        }
        // Fallback: return first available window
        if let window = (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first) {
            return window
        }
        // Last resort: attach to first available window scene
        dlog("⚠️ Apple Sign-In: no window found, using fallback UIWindow")
        let anyWindowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        return UIWindow(windowScene: anyWindowScene!)
    }
}

// MARK: - OTP Verification View

struct OTPVerificationView: View {
    let phoneNumber: String
    @Binding var otpCode: String
    @Binding var isResending: Bool
    @Binding var timer: Int
    @Binding var canResend: Bool
    let onVerify: () -> Void
    let onResend: () -> Void
    
    @FocusState private var isOTPFocused: Bool
    @EnvironmentObject var viewModel: AuthenticationViewModel
    @Environment(\.dismiss) private var dismiss  // P1: For change phone number
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.white.opacity(0.9))
                    
                    Text("Verify Your Phone")
                        .font(.custom("OpenSans-Bold", size: 24))
                        .foregroundStyle(.white)
                    
                    Text("Enter the 6-digit code sent to")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                    
                    Text(phoneNumber)
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.white)
                }
                
                // OTP Input
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        ForEach(0..<6, id: \.self) { index in
                            OTPDigitBox(
                                digit: index < otpCode.count ? String(otpCode[otpCode.index(otpCode.startIndex, offsetBy: index)]) : "",
                                isFocused: isOTPFocused && index == otpCode.count
                            )
                        }
                    }
                    
                    // Hidden TextField for input
                    TextField("", text: $otpCode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($isOTPFocused)
                        .opacity(0)
                        .frame(height: 1)
                        .onChange(of: otpCode) { oldValue, newValue in
                            // Limit to 6 digits
                            if newValue.count > 6 {
                                otpCode = String(newValue.prefix(6))
                            }
                            
                            // Haptic feedback on each digit
                            if newValue.count > oldValue.count && newValue.count <= 6 {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            
                            // Auto-verify when 6 digits entered
                            if otpCode.count == 6 {
                                // Medium haptic for completion
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                // Small delay before auto-verify for user to see all digits
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    onVerify()
                                }
                            }
                        }
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
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
                
                // Verify Button
                Button {
                    onVerify()
                } label: {
                    HStack(spacing: 12) {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        } else {
                            Text("Verify Code")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                        }
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(.white)
                    )
                }
                .disabled(otpCode.count != 6 || viewModel.isLoading)
                .opacity(otpCode.count == 6 && !viewModel.isLoading ? 1.0 : 0.5)
                .animation(.easeInOut(duration: 0.2), value: otpCode.count)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
                .scaleEffect(otpCode.count == 6 && !viewModel.isLoading ? 1.0 : 0.98)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: otpCode.count)
                
                // Resend Code
                VStack(spacing: 8) {
                    if !canResend {
                        Text("Resend code in \(timer)s")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                    } else {
                        Button {
                            onResend()
                        } label: {
                            HStack(spacing: 6) {
                                if isResending {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 13))
                                    Text("Resend Code")
                                        .font(.custom("OpenSans-SemiBold", size: 14))
                                }
                            }
                            .foregroundStyle(.white)
                        }
                        .disabled(isResending)
                    }
                }
                
                // P1: Change Phone Number option
                Button {
                    viewModel.cleanupPhoneAuthState()
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "phone.badge.waveform.fill")
                            .font(.system(size: 13))
                        Text("Change Phone Number")
                            .font(.custom("OpenSans-Regular", size: 13))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 32)
        }
        .onAppear {
            // Auto-focus on OTP input with smooth transition
            withAnimation(.easeInOut(duration: 0.3).delay(0.2)) {
                isOTPFocused = true
            }
        }
    }
}

// MARK: - OTP Digit Box

struct OTPDigitBox: View {
    let digit: String
    let isFocused: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(isFocused ? 0.15 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(isFocused ? 0.4 : 0.2), lineWidth: 2)
                )
                .frame(width: 50, height: 60)
            
            Text(digit)
                .font(.custom("OpenSans-Bold", size: 28))
                .foregroundStyle(.white)
                .scaleEffect(digit.isEmpty ? 0.5 : 1.0)
                .opacity(digit.isEmpty ? 0 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: digit.isEmpty)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
    }
}

#Preview {
    SignInView()
        .environmentObject(AuthenticationViewModel())
}

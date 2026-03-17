//
//  AuthenticationViewModel.swift
//  AMENAPP
//
//  Unified AuthenticationViewModel with Email, Google, and Apple Sign-In
//

import Foundation
import SwiftUI
import Combine
import Network
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
class AuthenticationViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var isAuthenticated = false
    @Published var needsOnboarding = false
    @Published var needsUsernameSelection = false  // NEW: For social sign-in users
    @Published var needsEmailVerification = false  // P0: Email verification gate
    @Published var showAuthSuccess = false  // Success checkmark animation
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var showWelcomeToAMEN = false  // NEW: Exciting welcome screen
    // @Published var showAppTutorial = false  // DISABLED - App tutorial removed
    
    // P0 FIX: Phone auth state
    @Published var phoneVerificationId: String?
    @Published var isVerifyingPhone = false
    @Published var resendCooldown: Int = 0
    @Published var isSendingPhoneCode = false  // P0: Duplicate send prevention
    @Published var phoneNumber: String = ""  // P1: Track phone number
    private var resendCooldownTimer: Timer?  // P1: Proper timer management
    
    // P0 FIX: Duplicate send prevention
    private var lastOTPSendTimestamp: Date?
    private var lastOTPPhoneNumber: String?
    
    // Password reset rate limiting: max 3 attempts per 15 min, 60s cooldown between sends
    @Published var passwordResetCooldownRemaining: Int = 0
    private var passwordResetAttempts: Int = 0
    private var passwordResetWindowStart: Date?
    private var passwordResetLastSent: Date?
    private var passwordResetCooldownTimer: Timer?

    // ✉️ Email verification state
    @Published var isEmailVerified = false
    @Published var showEmailVerificationBanner = false

    // P1 FIX: Rate-limit sendEmailVerification — max 1 send per 60 seconds.
    @Published var emailVerificationCooldownRemaining: Int = 0
    private var emailVerificationLastSent: Date?
    private var emailVerificationCooldownTimer: Timer?

    // 🔗 Email link sign-in state
    @Published var emailLinkSent = false
    @Published var emailForLink: String = ""
    
    // 🔐 2FA state
    @Published var needs2FAVerification = false
    @Published var pending2FAUserId: String?
    @Published var pending2FAEmail: String?
    // P1-10 FIX: Store AuthCredential instead of raw password string.
    // This avoids retaining a plaintext password in memory across the 2FA wait period.
    // Set when 2FA is detected; cleared after complete2FASignIn (success or failure).
    private var pending2FACredential: AuthCredential?

    // MARK: - Private Properties
    
    private let firebaseManager = FirebaseManager.shared
    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var isAuthenticating = false  // Prevent concurrent auth requests
    private var onboardingJustCompleted = false  // Prevent race condition from checkOnboardingStatus
    private var isCheckingOnboarding = false  // Prevent duplicate concurrent checkOnboardingStatus calls
    // P0-5 FIX: Suppress auth state listener reactions during the 2FA flow.
    // When signOut() is called after initial sign-in to enforce 2FA, the listener fires
    // with user=nil. When complete2FASignIn re-signs-in, it fires with user≠nil.
    // Without this gate, the listener grants isAuthenticated=true before session2FAActive
    // is verified on the server — bypassing the 2FA gate.
    private var is2FAInProgress = false
    
    // MARK: - Initialization
    
    init() {
        dlog("🚦 [LAUNCH] AuthenticationViewModel.init() — start")
        // ✅ NETWORK FIX: Set initial auth state synchronously from cached user
        // This prevents sign-in UI from showing on slow networks
        if let currentUser = Auth.auth().currentUser {
            dlog("🚦 [LAUNCH] Cached Firebase user found: \(currentUser.uid) — checking onboarding before setting isAuthenticated")
            
            // ✅ FIX: Check onboarding status BEFORE setting isAuthenticated
            // Load onboarding status synchronously to prevent UI glitch
            Task {
                dlog("🚦 [LAUNCH] checkOnboardingStatus starting for cached user")
                await checkOnboardingStatus(userId: currentUser.uid)
                await MainActor.run {
                    dlog("🚦 [LAUNCH] Setting isAuthenticated = true (cached user path) needsOnboarding=\(self.needsOnboarding)")
                    self.isAuthenticated = true
                }
            }
        } else {
            dlog("🚦 [LAUNCH] No cached Firebase user — will show SignInView")
        }
        
        setupAuthStateListener()

        // P1 FIX: Observe .sessionTimeout so that forceLogout() (fired by SessionTimeoutManager)
        // and other non-AuthenticationViewModel sign-out paths also clean up 2FA/phone auth state.
        // The auth listener only resets isAuthenticated/needsOnboarding — it does NOT clear
        // pending2FACredential, phoneVerificationId, is2FAInProgress, etc.
        NotificationCenter.default.addObserver(
            forName: .sessionTimeout,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.cleanupPhoneAuthState()
                self.pending2FAUserId = nil
                self.pending2FAEmail = nil
                self.pending2FACredential = nil
                self.needs2FAVerification = false
                self.is2FAInProgress = false
                self.onboardingJustCompleted = false
                dlog("🔐 AuthViewModel: cleaned up on sessionTimeout notification")
            }
        }
    }
    
    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
        resendCooldownTimer?.invalidate()
        resendCooldownTimer = nil
        passwordResetCooldownTimer?.invalidate()
        passwordResetCooldownTimer = nil
        emailVerificationCooldownTimer?.invalidate()
        emailVerificationCooldownTimer = nil
    }
    
    // MARK: - Auth State Listener
    
    private func setupAuthStateListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self = self else { return }

                // P0-5 FIX: During the 2FA flow we deliberately call signOut() then signIn()
                // as part of the verification sequence. Ignore auth state changes while this
                // flag is set — complete2FASignIn will update isAuthenticated directly after
                // the server-side session2FAActive check passes.
                guard !self.is2FAInProgress else {
                    dlog("🔐 Auth state change suppressed — 2FA in progress")
                    return
                }
                
                if let user = user {
                    dlog("🚦 [LAUNCH] Auth state listener fired: user=\(user.uid) isAuthenticated=\(self.isAuthenticated)")
                    
                    // P0 FIX: For non-email providers (phone, Google, Apple), clear any stale
                    // email verification gate so users are never stuck on it after phone/social login.
                    // Use contains rather than .first to correctly handle multi-provider accounts.
                    let hasPasswordProvider = user.providerData.contains { $0.providerID == "password" }
                    if !hasPasswordProvider {
                        self.needsEmailVerification = false
                        self.showEmailVerificationBanner = false
                    }
                    
                    // ✅ FIX: Check onboarding status BEFORE setting isAuthenticated
                    // This prevents the UI glitch where main content flashes before onboarding
                    dlog("🚦 [LAUNCH] Auth listener: calling checkOnboardingStatus")
                    await self.checkOnboardingStatus(userId: user.uid)
                    
                    // Now set isAuthenticated after we know the onboarding status
                    dlog("🚦 [LAUNCH] Auth listener: setting isAuthenticated = true, needsOnboarding=\(self.needsOnboarding), needs2FA=\(self.needs2FAVerification)")
                    self.isAuthenticated = true
                } else {
                    dlog("🚦 [LAUNCH] Auth state listener fired: user logged out")
                    self.isAuthenticated = false
                    self.needsOnboarding = false
                    self.needsUsernameSelection = false
                    self.needsEmailVerification = false
                }
            }
        }
    }
    
    // MARK: - Check Onboarding Status
    
    private func checkOnboardingStatus(userId: String) async {
        // Guard: if onboarding was just completed in this session, don't overwrite needsOnboarding
        guard !onboardingJustCompleted else {
            dlog("📋 Onboarding: skipping status check — completion in progress")
            return
        }
        // Serialize: if a check is already in flight (e.g., concurrent calls from init() and
        // the auth state listener on cold launch), skip the duplicate to avoid two Firestore reads
        // and a potential UI flash from conflicting state assignments.
        guard !isCheckingOnboarding else {
            dlog("📋 Onboarding: skipping duplicate in-flight check for user \(userId)")
            return
        }
        isCheckingOnboarding = true
        defer { isCheckingOnboarding = false }
        // Check local cache first for immediate response
        let cachedCompleted = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding_\(userId)")
        dlog("🚦 [LAUNCH] checkOnboardingStatus: cache=\(cachedCompleted) for user \(userId)")
        if cachedCompleted {
            await MainActor.run {
                self.needsOnboarding = false
                self.needsUsernameSelection = false
            }
            dlog("🚦 [LAUNCH] checkOnboardingStatus: cache hit → needsOnboarding=false (fast path)")
        }

        // Always verify against Firestore (source of truth)
        dlog("🚦 [LAUNCH] checkOnboardingStatus: fetching Firestore to verify...")
        do {
            let userData = try await firebaseManager.fetchUserDocument(userId: userId)
            let hasCompletedOnboarding = userData["hasCompletedOnboarding"] as? Bool ?? false
            // Sync cache
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding_\(userId)")
            await MainActor.run {
                self.needsOnboarding = !hasCompletedOnboarding
                self.needsUsernameSelection = false
            }
            dlog("🚦 [LAUNCH] checkOnboardingStatus: Firestore returned hasCompleted=\(hasCompletedOnboarding) → needsOnboarding=\(!hasCompletedOnboarding)")
        } catch {
            // On error, fall back to cache; if no cache, show onboarding to be safe
            await MainActor.run {
                self.needsOnboarding = !cachedCompleted
                self.needsUsernameSelection = false
            }
            dlog("🚦 [LAUNCH] checkOnboardingStatus: Firestore error → fallback to cache (completed=\(cachedCompleted)): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Sign In
    
    func signIn(email: String, password: String) async {
        // Prevent concurrent auth requests
        guard !isAuthenticating else {
            dlog("⚠️ Sign-in already in progress, ignoring duplicate request")
            return
        }

        // BUG-12 FIX: Wait for any in-flight Firestore cache clear from the previous
        // sign-out to complete before authenticating a new user. This prevents the
        // next user from loading stale cached data belonging to the previous user.
        if AppLifecycleManager.shared.isClearingCache {
            dlog("⏳ Waiting for Firestore cache clear before sign-in...")
            // Poll with a short delay — clearPersistence() typically takes <200ms
            var waited = 0
            while AppLifecycleManager.shared.isClearingCache && waited < 10 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                waited += 1
            }
            dlog("✅ Cache clear complete (or timed out after 1s), proceeding with sign-in")
        }
        
        isAuthenticating = true
        defer { isAuthenticating = false }
        
        #if DEBUG
        dlog("🔐 Starting sign in")
        #endif
        isLoading = true
        errorMessage = nil
        
        // Already on @MainActor — no Task hop needed
        defer { isLoading = false }
        
        do {
            let user = try await firebaseManager.signIn(email: email, password: password)
            dlog("✅ Sign in successful")
            
            // P0 SECURITY: Check if user has 2FA enabled BEFORE allowing full authentication
            let has2FA = await TwoFactorAuthService.shared.check2FAStatus(userId: user.uid)
            
            if has2FA {
                dlog("🔐 User has 2FA enabled - requiring verification")

                // P0-5 FIX: Raise the gate BEFORE signing out so the listener's user=nil
                // event is suppressed. Without this, the sign-out fires the listener which
                // sets isAuthenticated=false (harmless) but the subsequent re-sign-in in
                // complete2FASignIn would set isAuthenticated=true before the server check.
                is2FAInProgress = true
                
                // P1-10 FIX: Store an AuthCredential rather than the raw password string
                // so the plaintext password is not retained in memory during the 2FA wait.
                pending2FACredential = EmailAuthProvider.credential(withEmail: email, password: password)
                
                // Sign out immediately - user must verify 2FA first
                try? Auth.auth().signOut()
                
                // Store pending credentials
                pending2FAUserId = user.uid
                pending2FAEmail = email
                needs2FAVerification = true
                
                // Don't set isAuthenticated - user is NOT authenticated until 2FA passes
                return
            }
            
            // Success haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            // isAuthenticated and needsOnboarding are handled by auth state listener
            
        } catch {
            dlog("❌ Sign in failed: \(error.localizedDescription)")
            errorMessage = handleAuthError(error)
            showError = true
            
            // Error haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
    }
    
    // MARK: - 2FA Completion (called by TwoFactorVerificationView after OTP verified)

    /// Called after the verify2FAOTP Cloud Function returns successfully.
    ///
    /// The function writes `userSecurity/{uid}.session2FAActive = true` via admin SDK.
    /// We re-sign-in with the stored password so Firebase Auth issues a fresh token,
    /// then reload the token so the claims are current.  Only after that do we set
    /// `isAuthenticated = true`, making the 2FA gate server-enforced rather than
    /// client-only.
    ///
    /// - Parameter sessionToken: The token returned by verify2FAOTP (stored for reference,
    ///   not used for gating — the Firestore rule reads userSecurity directly).
    func complete2FASignIn(sessionToken: String) async {
        guard let userId = pending2FAUserId,
              let credential = pending2FACredential else {
            dlog("❌ complete2FASignIn called without pending credentials")
            errorMessage = "Session expired. Please sign in again."
            showError = true
            needs2FAVerification = false
            return
        }

        isLoading = true
        // Already on @MainActor — no Task hop needed
        defer { isLoading = false }

        // P1 FIX: Use defer to guarantee is2FAInProgress is always cleared on ALL exit
        // paths — success, guard failures, and thrown errors. Previously cleared manually
        // at each site, which is fragile if new early returns are added in future.
        defer { is2FAInProgress = false }

        do {
            // P1-10 FIX: Re-authenticate using stored AuthCredential (no raw password in scope).
            // Firebase signed us out after detecting 2FA; re-sign-in issues a fresh token.
            let authResult = try await Auth.auth().signIn(with: credential)
            let user = authResult.user

            // Force-refresh the ID token so it picks up any custom claims set by the
            // Cloud Function (e.g. email_verified propagation).
            _ = try? await user.getIDToken(forcingRefresh: true)

            // Verify that the Cloud Function actually wrote session2FAActive on the
            // server before we grant access.  This prevents a race where the client
            // calls complete2FASignIn before the Firestore write has committed.
            let db = Firestore.firestore()
            let securityDoc = try await db.collection("userSecurity").document(userId).getDocument()
            let sessionActive = securityDoc.data()?["session2FAActive"] as? Bool ?? false

            guard sessionActive else {
                // Session not yet active — Cloud Function may still be writing.
                // This is a transient failure; caller should retry or show an error.
                dlog("⚠️ complete2FASignIn: userSecurity.session2FAActive not true yet")
                try? Auth.auth().signOut()
                errorMessage = "Verification is still processing. Please try again in a moment."
                showError = true
                return  // defer clears is2FAInProgress
            }

            // P0 FIX: Enforce 30-minute session TTL on the client.
            // session2FAExpiresAt is written by verify2FAOTP (admin SDK) and cannot be
            // forged by the client. If it has passed, the session is expired — reject it
            // even if the scheduled expire2FASessions function hasn't cleared the flag yet.
            if let expiresAt = securityDoc.data()?["session2FAExpiresAt"] as? Timestamp,
               expiresAt.dateValue() < Date() {
                dlog("⚠️ complete2FASignIn: 2FA session expired at \(expiresAt.dateValue())")
                try? Auth.auth().signOut()
                errorMessage = "Your verification session has expired. Please sign in again."
                showError = true
                needs2FAVerification = false
                return  // defer clears is2FAInProgress
            }

            // All checks passed — clear 2FA pending state and admit the user.
            pending2FAUserId = nil
            pending2FAEmail = nil
            pending2FACredential = nil  // P1-10: Wipe stored credential immediately
            needs2FAVerification = false

            dlog("✅ 2FA complete — userSecurity confirmed active, granting access")
            // Set isAuthenticated directly — listener was suppressed during the flow.
            // defer will clear is2FAInProgress after this returns.
            await checkOnboardingStatus(userId: userId)
            isAuthenticated = true

        } catch {
            dlog("❌ complete2FASignIn re-auth failed: \(error.localizedDescription)")
            errorMessage = handleAuthError(error)
            showError = true
            // Keep needs2FAVerification = true so the gate stays visible.
            // defer clears is2FAInProgress so future auth state changes are processed normally.
        }
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String, displayName: String, username: String) async {
        // Prevent concurrent auth requests
        guard !isAuthenticating else {
            dlog("⚠️ Sign-up already in progress, ignoring duplicate request")
            return
        }
        
        isAuthenticating = true
        defer { isAuthenticating = false }
        
        #if DEBUG
        dlog("🔐 Starting sign up")
        #endif
        isLoading = true
        errorMessage = nil
        
        // Already on @MainActor — no Task hop needed
        defer { isLoading = false }
        
        do {
            _ = try await firebaseManager.signUp(
                email: email,
                password: password,
                displayName: displayName,
                username: username
            )
            dlog("✅ Sign up successful")
            
            // Success haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            // ✅ FIX: Set needsOnboarding BEFORE isAuthenticated to prevent UI glitch
            // This ensures the onboarding screen shows immediately without flashing content
            needsOnboarding = true
            
            // P0 FIX: Auto-enable email verification gate for email-based sign-ups ONLY
            // Phone sign-ups skip email verification
            needsEmailVerification = true
            
            // Send verification email for email-based sign-ups
            await sendEmailVerification()
            
            // Small delay to ensure state is set before auth listener fires
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
            
            // Auth state listener will set isAuthenticated = true
            // but needsOnboarding is already true, preventing the glitch
            
        } catch {
            dlog("❌ Sign up failed: \(error.localizedDescription)")
            errorMessage = handleAuthError(error)
            showError = true
            
            // Error haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
    }
    
    // MARK: - Sign Out
    
    func signOut() {
        // ── Centralized service teardown ─────────────────────────────────────
        // AppLifecycleManager stops all Firebase listeners, clears safety caches,
        // resets behavioral signals, and stops session timers in one guaranteed call.
        // Must run BEFORE Auth.signOut() so listeners detach while credentials are valid.
        AppLifecycleManager.shared.performFullSignOutCleanup()

        // ── FCM token deactivation ───────────────────────────────────────────
        // Mark this device's push token inactive so the signed-out device stops
        // receiving notifications for the now-signed-out user.
        if let uid = firebaseManager.currentUser?.uid {
            Task {
                await PushNotificationHandler.shared.disableFCMToken(for: uid)
            }
        }

        // ── Auth-ViewModel-owned state ───────────────────────────────────────
        // Clear state that only this ViewModel owns (not covered by AppLifecycleManager).
        cleanupPhoneAuthState()           // phoneVerificationId, phoneNumber, resendCooldown
        pending2FAUserId = nil
        pending2FAEmail = nil
        pending2FACredential = nil        // P1-10: Wipe stored credential on sign-out
        needs2FAVerification = false
        onboardingJustCompleted = false
        showEmailVerificationBanner = false
        needsUsernameSelection = false

        // ── Firebase sign-out ────────────────────────────────────────────────
        do {
            try firebaseManager.signOut()
            dlog("✅ Sign out successful")

            // Reset published state so the UI routes to the auth screen.
            isAuthenticated = false
            needsOnboarding = false
            errorMessage = nil

        } catch {
            dlog("❌ Sign out failed: \(error.localizedDescription)")
            errorMessage = "Failed to sign out: \(error.localizedDescription)"
            showError = true
        }
    }
    
    // MARK: - Password Reset

    func sendPasswordReset(email: String) async throws {
        let now = Date()
        
        // Enforce 60-second cooldown between sends
        if let lastSent = passwordResetLastSent {
            let secondsSince = now.timeIntervalSince(lastSent)
            if secondsSince < 60 {
                let remaining = Int(60 - secondsSince)
                throw NSError(
                    domain: "AuthenticationViewModel",
                    code: 429,
                    userInfo: [NSLocalizedDescriptionKey: "Please wait \(remaining)s before requesting another reset email."]
                )
            }
        }
        
        // Enforce max 3 attempts per 15-minute window
        let windowDuration: TimeInterval = 15 * 60
        if let windowStart = passwordResetWindowStart, now.timeIntervalSince(windowStart) < windowDuration {
            if passwordResetAttempts >= 3 {
                throw NSError(
                    domain: "AuthenticationViewModel",
                    code: 429,
                    userInfo: [NSLocalizedDescriptionKey: "Too many reset attempts. Please try again in 15 minutes."]
                )
            }
        } else {
            // Start a new window
            passwordResetWindowStart = now
            passwordResetAttempts = 0
        }
        
        try await firebaseManager.sendPasswordReset(email: email)
        
        // Record this attempt
        passwordResetAttempts += 1
        passwordResetLastSent = now
        
        // Start cooldown countdown on the main actor (we're already @MainActor)
        passwordResetCooldownRemaining = 60
        passwordResetCooldownTimer?.invalidate()
        passwordResetCooldownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.passwordResetCooldownRemaining > 0 {
                    self.passwordResetCooldownRemaining -= 1
                } else {
                    self.passwordResetCooldownTimer?.invalidate()
                }
            }
        }
        
        dlog("✅ Password reset email sent")
    }

    // MARK: - Email Verification

    /// Send email verification to current user
    func sendEmailVerification() async {
        // P1 FIX: Enforce 60-second cooldown to prevent spam.
        if let lastSent = emailVerificationLastSent {
            let elapsed = Date().timeIntervalSince(lastSent)
            if elapsed < 60 {
                let remaining = Int(60 - elapsed)
                errorMessage = "Please wait \(remaining)s before requesting another verification email."
                showError = true
                return
            }
        }

        do {
            try await firebaseManager.sendEmailVerification()
            emailVerificationLastSent = Date()

            // Start countdown so callers can show a UI cooldown.
            emailVerificationCooldownRemaining = 60
            emailVerificationCooldownTimer?.invalidate()
            emailVerificationCooldownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.emailVerificationCooldownRemaining > 0 {
                        self.emailVerificationCooldownRemaining -= 1
                    } else {
                        self.emailVerificationCooldownTimer?.invalidate()
                    }
                }
            }

            dlog("✅ Verification email sent")

            // Success haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        } catch {
            dlog("❌ Failed to send verification email: \(error.localizedDescription)")
            errorMessage = "Failed to send verification email: \(error.localizedDescription)"
            showError = true

            // Error haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
    }

    /// Check email verification status
    func checkEmailVerification() async {
        do {
            guard let user = Auth.auth().currentUser else { return }
            
            // ✅ ONLY require email verification for email-based sign-ups
            // Phone, Google, and Apple sign-in don't need email verification.
            // Use contains rather than .first to correctly handle multi-provider accounts.
            let hasPasswordProvider = user.providerData.contains { $0.providerID == "password" }
            
            // Skip email verification for non-email providers
            guard hasPasswordProvider else {
                needsEmailVerification = false
                showEmailVerificationBanner = false
                return
            }
            
            // P1-1 FIX: If already verified, skip the network reload.
            // Only reload when the user is unverified (awaiting email click).
            if isEmailVerified {
                needsEmailVerification = false
                return
            }
            
            try await firebaseManager.reloadUser()
            isEmailVerified = firebaseManager.isEmailVerified
            #if DEBUG
            dlog("📧 Email verification status: \(isEmailVerified)")
            #endif

            if isEmailVerified {
                // Verified — clear any gate or banner
                needsEmailVerification = false
                showEmailVerificationBanner = false
            } else {
                // Not verified — only show banner/gate if this is a fresh sign-up flow.
                // Returning users (who have already completed onboarding) should NEVER see
                // the banner mid-session just because their email happens to be unverified.
                let userId = Auth.auth().currentUser?.uid ?? ""
                let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding_\(userId)")
                if needsEmailVerification && !hasCompletedOnboarding {
                    // New sign-up flow — keep gate and banner active
                    showEmailVerificationBanner = true
                } else {
                    // Returning user or onboarding already complete — never block them
                    needsEmailVerification = false
                    showEmailVerificationBanner = false
                }
            }
        } catch {
            dlog("❌ Failed to check email verification: \(error.localizedDescription)")
        }
    }

    // MARK: - Passwordless Email Link Sign-In

    /// Send sign-in link to email
    func sendSignInLink(toEmail email: String) async {
        isLoading = true
        errorMessage = nil

        do {
            try await firebaseManager.sendSignInLink(toEmail: email)
            emailLinkSent = true
            emailForLink = email
            #if DEBUG
            dlog("✅ Sign-in link sent to \(email)")
            #endif

            // Success haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        } catch {
            dlog("❌ Failed to send sign-in link: \(error.localizedDescription)")
            errorMessage = handleAuthError(error)
            showError = true

            // Error haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }

        isLoading = false
    }

    /// Sign in with email link (called when user opens the link)
    func signInWithEmailLink(email: String, link: String) async {
        isLoading = true
        errorMessage = nil

        do {
            _ = try await firebaseManager.signInWithEmailLink(email: email, link: link)
            dlog("✅ Signed in with email link")

            // Success haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)

            // isAuthenticated will be set by auth state listener
        } catch {
            dlog("❌ Email link sign-in failed: \(error.localizedDescription)")
            errorMessage = handleAuthError(error)
            showError = true

            // Error haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }

        isLoading = false
    }

    // MARK: - Change Password
    
    func changePassword(currentPassword: String, newPassword: String) async throws {
        dlog("🔐 Changing password")
        
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user is currently signed in"])
        }
        
        guard let email = user.email else {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User email not found"])
        }
        
        // Re-authenticate user with current password
        let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
        
        do {
            try await user.reauthenticate(with: credential)
            dlog("✅ Re-authentication successful")
            
            // Update password
            try await user.updatePassword(to: newPassword)
            dlog("✅ Password changed successfully")
            
        } catch {
            dlog("❌ Password change failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Update Email
    
    /// Update user email address
    func updateEmail(newEmail: String) async throws {
        #if DEBUG
        dlog("📧 Updating email to: \(newEmail)")
        #endif
        
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user is currently signed in"])
        }
        
        do {
            try await user.sendEmailVerification(beforeUpdatingEmail: newEmail)
            dlog("✅ Email verification sent for update in Firebase Auth")

            // P0 FIX: Mark emailVerified=false in Firestore immediately when a user
            // requests an email change. Firebase Auth will flip isEmailVerified back
            // to true only after the user clicks the verification link in the new
            // address. Marking false here prevents stale "verified" state from
            // persisting in our user doc between the request and confirmation.
            let db = Firestore.firestore()
            try? await db.collection("users").document(user.uid).setData(
                ["emailVerified": false], merge: true
            )
            dlog("📧 emailVerified set to false in Firestore pending new-address confirmation")
        } catch {
            dlog("❌ Email update failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Re-authenticate user with current password
    func reauthenticate(password: String) async throws {
        dlog("🔐 Re-authenticating user")
        
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user is currently signed in"])
        }
        
        guard let email = user.email else {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User email not found"])
        }
        
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        
        do {
            try await user.reauthenticate(with: credential)
            dlog("✅ Re-authentication successful")
        } catch {
            dlog("❌ Re-authentication failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Delete Account
    
    /// Delete account - works for both password-based and Apple/Google Sign-In users
    func deleteAccount(password: String?) async throws {
        dlog("🗑️ Deleting account")
        
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user is currently signed in"])
        }
        
        let userId = user.uid
        
        // Determine authentication provider
        let isAppleSignIn = user.providerData.contains { $0.providerID == "apple.com" }
        let isGoogleSignIn = user.providerData.contains { $0.providerID == "google.com" }
        let isEmailSignIn = user.providerData.contains { $0.providerID == "password" }
        
        do {
            // Re-authenticate based on provider.
            // Firebase requires recent authentication for destructive operations —
            // skipping reauthentication for Apple/Google will cause a requiresRecentLogin
            // error for sessions that have been open too long. The caller must handle
            // AuthErrorCode.requiresRecentLogin by presenting a fresh sign-in flow.
            if isAppleSignIn {
                // Apple: reauthentication must be driven by the view layer (present ASAuthorizationController).
                // Attempting deletion without it will produce requiresRecentLogin for older sessions.
                // We proceed here; callers should catch requiresRecentLogin and re-invoke with fresh Apple credential.
                dlog("🍎 Apple Sign-In user - proceeding with deletion (may require re-auth for old sessions)")
            } else if isGoogleSignIn {
                // Google: same pattern — caller must handle requiresRecentLogin by re-presenting Google Sign-In.
                dlog("🔍 Google Sign-In user - proceeding with deletion (may require re-auth for old sessions)")
            } else if isEmailSignIn {
                // Email/password users must re-authenticate
                guard let password = password, !password.isEmpty else {
                    throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Password is required for email users"])
                }
                
                guard let email = user.email else {
                    throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User email not found"])
                }
                
                dlog("📧 Email user - re-authenticating with password")
                let credential = EmailAuthProvider.credential(withEmail: email, password: password)
                try await user.reauthenticate(with: credential)
                dlog("✅ Re-authentication successful")
            } else {
                throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown authentication provider"])
            }
            
            // Delete user data from Firestore
            try await firebaseManager.deleteUserData(userId: userId)
            dlog("✅ User data deleted from Firestore")
            
            // Delete user account from Firebase Auth
            try await user.delete()
            dlog("✅ User account deleted")
            
            // Reset state
            await MainActor.run {
                isAuthenticated = false
                needsOnboarding = false
            }
            
        } catch {
            let nsError = error as NSError
            if nsError.code == AuthErrorCode.requiresRecentLogin.rawValue {
                // Firebase requires a fresh credential for this session.
                // The calling view must reauthenticate (present Apple/Google sign-in or password entry)
                // then retry deleteAccount().
                dlog("⚠️ Account deletion requires recent authentication — caller must reauthenticate")
                throw NSError(
                    domain: "AuthError",
                    code: AuthErrorCode.requiresRecentLogin.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: "For security, please sign in again before deleting your account."]
                )
            }
            dlog("❌ Account deletion failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Check if current user signed in with Apple/Google (passwordless)
    func isPasswordlessUser() -> Bool {
        guard let user = Auth.auth().currentUser else { return false }
        
        let isAppleSignIn = user.providerData.contains { $0.providerID == "apple.com" }
        let isGoogleSignIn = user.providerData.contains { $0.providerID == "google.com" }
        
        return isAppleSignIn || isGoogleSignIn
    }
    
    /// Get the authentication provider name for display
    func getAuthProviderName() -> String {
        guard let user = Auth.auth().currentUser else { return "Unknown" }
        
        if user.providerData.contains(where: { $0.providerID == "apple.com" }) {
            return "Apple ID"
        } else if user.providerData.contains(where: { $0.providerID == "google.com" }) {
            return "Google"
        } else if user.providerData.contains(where: { $0.providerID == "phone" }) {
            return "Phone Number"
        } else if user.providerData.contains(where: { $0.providerID == "password" }) {
            return "Email"
        }
        
        return "Unknown"
    }
    
    // MARK: - Phone Number Authentication
    
    /// Send verification code to phone number
    /// P0 FIX: Added duplicate send prevention, network error handling, and proper state management
    func sendPhoneVerificationCode(phoneNumber: String) async {
        // P0: Prevent duplicate sends
        guard !isSendingPhoneCode else {
            dlog("⚠️ Phone code send already in progress")
            return
        }
        
        guard !isAuthenticating else {
            dlog("⚠️ Authentication already in progress")
            return
        }
        
        // P0-2: Prevent rapid successive taps (3-second cooldown)
        if let lastTimestamp = lastOTPSendTimestamp,
           let lastPhone = lastOTPPhoneNumber,
           lastPhone == phoneNumber,
           Date().timeIntervalSince(lastTimestamp) < 3.0 {
            dlog("⚠️ Please wait before resending OTP (3-second cooldown)")
            await MainActor.run {
                self.errorMessage = "Please wait a moment before trying again."
                self.showError = true
            }
            return
        }
        
        // P0: Check network connectivity first
        guard await isNetworkAvailable() else {
            await MainActor.run {
                self.errorMessage = "No internet connection. Please check your network and try again."
                self.showError = true
            }
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
            return
        }
        
        // P0: Set flags to prevent duplicates
        await MainActor.run {
            self.isSendingPhoneCode = true
            self.isAuthenticating = true
            self.isVerifyingPhone = true
            self.errorMessage = nil
            self.showError = false
            self.phoneNumber = phoneNumber  // P1: Store for retry/change
        }
        
        defer {
            Task { @MainActor in
                self.isSendingPhoneCode = false
                self.isAuthenticating = false
                self.isVerifyingPhone = false
            }
        }
        
        #if DEBUG
        dlog("📱 Sending verification code to: \(phoneNumber)")
        #endif

        // P0: Enforce server-side rate limit BEFORE calling Firebase.
        // checkServerRateLimit sets errorMessage/showError itself if denied.
        guard await checkServerRateLimit(phoneNumber: phoneNumber) else {
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
            return
        }
        
        do {
            // Format phone number to E.164 format if needed
            let formattedNumber = formatPhoneNumber(phoneNumber)
            
            // Send verification code
            let verificationID = try await PhoneAuthProvider.provider()
                .verifyPhoneNumber(formattedNumber, uiDelegate: nil)
            
            await MainActor.run {
                self.phoneVerificationId = verificationID
                dlog("✅ Verification code sent successfully")
                
                // P0-2: Update timestamp to prevent rapid retries
                self.lastOTPSendTimestamp = Date()
                self.lastOTPPhoneNumber = phoneNumber
                
                // P1: Clean up old timer before starting new one
                self.resendCooldownTimer?.invalidate()
                self.resendCooldownTimer = nil
                
                // Start resend cooldown (60 seconds)
                self.resendCooldown = 60
                self.startResendCooldownTimer()
            }
            
            // Success haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
        } catch {
            dlog("❌ Failed to send verification code: \(error.localizedDescription)")
            
            // P1: Enhanced network error handling
            let errorMessage = handlePhoneAuthError(error)
            
            await MainActor.run {
                self.errorMessage = errorMessage
                self.showError = true
            }
            
            // Error haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
    }
    
    /// Verify phone number with SMS code
    /// P0 FIX: Properly handles login vs signup, network errors, and state cleanup
    func verifyPhoneCode(_ code: String, displayName: String, username: String, isSignUp: Bool) async {
        guard let verificationID = phoneVerificationId else {
            await MainActor.run {
                errorMessage = "Verification session expired. Please request a new code."
                showError = true
            }
            return
        }
        
        guard !isAuthenticating else {
            dlog("⚠️ Verification already in progress")
            return
        }
        
        // P1: Check network connectivity
        guard await isNetworkAvailable() else {
            await MainActor.run {
                self.errorMessage = "No internet connection. Please check your network and try again."
                self.showError = true
            }
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
            return
        }
        
        await MainActor.run {
            self.isAuthenticating = true
            self.isLoading = true
            self.errorMessage = nil
            self.showError = false
        }
        
        // Already on @MainActor — no Task hop needed
        defer {
            isAuthenticating = false
            isLoading = false
        }
        
        dlog("🔐 Verifying phone code... (isSignUp: \(isSignUp))")
        
        do {
            // Create credential
            let credential = PhoneAuthProvider.provider().credential(
                withVerificationID: verificationID,
                verificationCode: code
            )
            
            // Sign in with credential
            let authResult = try await Auth.auth().signIn(with: credential)
            dlog("✅ Phone verification successful")
            
            let userId = authResult.user.uid
            let phoneNumber = authResult.user.phoneNumber ?? ""
            
            // P0 FIX: Only create new user profile for sign-ups, not logins
            if isSignUp {
                dlog("📝 Creating new user profile for phone sign-up")
                
                // Create name keywords for search
                let nameKeywords = createNameKeywords(from: displayName)
                
                // Create initials
                let names = displayName.components(separatedBy: " ")
                let firstName = names.first ?? ""
                let lastName = names.count > 1 ? names.last ?? "" : ""
                let initials = "\(firstName.prefix(1))\(lastName.prefix(1))".uppercased()
                
                let userData: [String: Any] = [
                    "uid": userId,
                    "phoneNumber": phoneNumber,
                    "displayName": displayName,
                    "displayNameLowercase": displayName.lowercased(),
                    "username": username.lowercased(),
                    "usernameLowercase": username.lowercased(),
                    "initials": initials,
                    "bio": "",
                    "profileImageURL": NSNull(),
                    "nameKeywords": nameKeywords,
                    "createdAt": Timestamp(date: Date()),
                    "updatedAt": Timestamp(date: Date()),
                    "followersCount": 0,
                    "followingCount": 0,
                    "postsCount": 0,
                    "isPrivate": false,
                    "notificationsEnabled": true,
                    "pushNotificationsEnabled": true,
                    "emailNotificationsEnabled": true,
                    "notifyOnLikes": true,
                    "notifyOnComments": true,
                    "notifyOnFollows": true,
                    "notifyOnMentions": true,
                    "notifyOnPrayerRequests": true,
                    "allowMessagesFromEveryone": true,
                    "showActivityStatus": true,
                    "allowTagging": true,
                    "hasCompletedOnboarding": false,
                    "authProvider": "phone",
                    "phoneVerified": true,
                    "phoneVerifiedAt": Timestamp(date: Date())
                ]
                
                try await firebaseManager.firestore.collection("users")
                    .document(userId)
                    .setData(userData, merge: true)
                
                dlog("✅ User profile created for phone sign-up")
            } else {
                dlog("🔐 Phone login - updating existing user")
                
                // For login, just update phone verification status
                try await firebaseManager.firestore.collection("users")
                    .document(userId)
                    .setData([
                        "phoneNumber": phoneNumber,
                        "phoneVerified": true,
                        "phoneVerifiedAt": Timestamp(date: Date()),
                        "updatedAt": Timestamp(date: Date())
                    ], merge: true)
                
                dlog("✅ Phone number verified for existing user")
            }
            
            // Success haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            // Show success checkmark animation
            await MainActor.run {
                self.showAuthSuccess = true
            }
            
            // Wait for animation to finish
            try? await Task.sleep(nanoseconds: 1_700_000_000) // 1.7s animation duration
            
            // P1: Clean up state properly
            await MainActor.run {
                self.phoneVerificationId = nil
                self.showAuthSuccess = false
                self.phoneNumber = ""
                
                // P0 FIX: Phone-authenticated users never need email verification
                // Clear any stale flag left over from a prior email-signup session
                self.needsEmailVerification = false
                self.showEmailVerificationBanner = false
                
                // P1: Stop and clean up timer
                self.resendCooldownTimer?.invalidate()
                self.resendCooldownTimer = nil
                self.resendCooldown = 0
            }
            
        } catch {
            dlog("❌ Phone verification failed: \(error.localizedDescription)")

            // P0: Report failure to server for security monitoring/rate-limit tracking
            let storedPhone = await MainActor.run { self.phoneNumber }
            if !storedPhone.isEmpty {
                await reportVerificationFailure(
                    phoneNumber: storedPhone,
                    reason: (error as NSError).localizedDescription
                )
            }

            await MainActor.run {
                self.errorMessage = handlePhoneAuthError(error)
                self.showError = true
            }
            
            // Error haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
    }
    
    /// Resend verification code
    /// P1 FIX: Added cooldown check and proper error handling
    func resendVerificationCode(phoneNumber: String) async {
        guard resendCooldown == 0 else {
            dlog("⚠️ Please wait \(resendCooldown)s before resending")
            await MainActor.run {
                self.errorMessage = "Please wait \(resendCooldown) seconds before requesting a new code."
                self.showError = true
            }
            return
        }
        
        await sendPhoneVerificationCode(phoneNumber: phoneNumber)
    }
    
    /// Start cooldown timer for resend button
    /// P1 FIX: Proper timer cleanup and management
    private func startResendCooldownTimer() {
        // P1: Clean up any existing timer first
        resendCooldownTimer?.invalidate()
        
        // P1: Create and store timer reference for proper cleanup
        resendCooldownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                if self.resendCooldown > 0 {
                    self.resendCooldown -= 1
                } else {
                    self.resendCooldownTimer?.invalidate()
                    self.resendCooldownTimer = nil
                }
            }
        }
    }
    
    /// Clean up phone auth state
    /// P1 FIX: Proper state cleanup when dismissing OTP sheet
    func cleanupPhoneAuthState() {
        phoneVerificationId = nil
        phoneNumber = ""
        resendCooldownTimer?.invalidate()
        resendCooldownTimer = nil
        resendCooldown = 0
        isSendingPhoneCode = false
        isVerifyingPhone = false
        dlog("🧹 Phone auth state cleaned up")
    }
    
    /// Check network availability using NWPathMonitor (no external HTTP probe).
    /// Returns immediately based on the OS-level path status — no latency, no blocked-domain risk.
    private func isNetworkAvailable() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "com.amen.networkCheck", qos: .utility)
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied)
            }
            monitor.start(queue: queue)
        }
    }
    
    /// Check server-side rate limit before sending OTP
    /// P0: Server-side rate limiting to prevent abuse
    private func checkServerRateLimit(phoneNumber: String) async -> Bool {
        // Cloud Functions deployed - server-side rate limiting enabled
        // callable.call() must not be cancelled mid-flight (causes asyncLet_finish_after_task_completion crash).
        // We run it in a Task.detached and await its value without propagating cancellation.
        do {
            let functions = Functions.functions()
            let callable = functions.httpsCallable("checkPhoneVerificationRateLimit")
            // Extract the Sendable data dict inside the task to avoid transferring non-Sendable HTTPSCallableResult
            let callTask = Task.detached {
                let result = try await callable.call(["phoneNumber": phoneNumber, "action": "send"])
                return result.data as? [String: Any]
            }
            let data = try await callTask.value

            if let data,
               let allowed = data["allowed"] as? Bool {

                if !allowed {
                    let reason = data["reason"] as? String ?? "Rate limit exceeded"
                    _ = data["retryAfter"] as? Int ?? 60

                    await MainActor.run {
                        self.errorMessage = reason
                        self.showError = true
                    }

                    dlog("🚫 Server rate limit check failed: \(reason)")
                    return false
                }

                dlog("✅ Server rate limit check passed")
                return true
            }
        } catch {
            dlog("⚠️ Server rate limit check error: \(error.localizedDescription)")
            // P0 FIX: Fail closed on network error — do not allow OTP send if
            // server rate limit cannot be verified. Client-side cooldowns are
            // not sufficient alone; a network error could mask an attack.
            await MainActor.run {
                self.errorMessage = "Unable to verify rate limit. Please check your connection and try again."
                self.showError = true
            }
        }

        // Fail closed: deny if server check fails or returns unexpected data
        return false
    }
    
    /// Report failed verification attempt to server
    /// P0: Track failures for security monitoring
    private func reportVerificationFailure(phoneNumber: String, reason: String) async {
        // Cloud Functions deployed - failure reporting enabled
        do {
            let functions = Functions.functions()
            let callable = functions.httpsCallable("reportPhoneVerificationFailure")
            _ = try await callable.call([
                "phoneNumber": phoneNumber,
                "reason": reason
            ])
            dlog("📊 Reported verification failure to server")
        } catch {
            dlog("⚠️ Failed to report verification failure: \(error.localizedDescription)")
        }
    }
    
    /// Format phone number to E.164 format (+country_code + number)
    private func formatPhoneNumber(_ phoneNumber: String) -> String {
        // Remove all non-digit characters
        let digits = phoneNumber.filter { $0.isNumber }
        
        // If already starts with +, return as is
        if phoneNumber.hasPrefix("+") {
            return phoneNumber
        }
        
        // If starts with country code (e.g., 1 for US), add +
        if digits.count == 11 && digits.hasPrefix("1") {
            return "+\(digits)"
        }
        
        // Assume US number if 10 digits
        if digits.count == 10 {
            return "+1\(digits)"
        }
        
        // Return with + prefix
        return "+\(digits)"
    }
    
    /// Create searchable name keywords
    private func createNameKeywords(from name: String) -> [String] {
        let lowercasedName = name.lowercased()
        var keywords = Set<String>()
        
        // Add full name
        keywords.insert(lowercasedName)
        
        // Add individual words
        let words = lowercasedName.components(separatedBy: " ")
        words.forEach { keywords.insert($0) }
        
        // Add prefixes for autocomplete (min 2 chars).
        // Guard word.count >= 2 to avoid a fatal "Range requires lowerBound <= upperBound"
        // crash when a single-character word (or empty string) is encountered.
        for word in words {
            guard word.count >= 2 else { continue }
            for i in 2...word.count {
                keywords.insert(String(word.prefix(i)))
            }
        }
        
        return Array(keywords)
    }
    
    /// Handle phone auth specific errors
    private func handlePhoneAuthError(_ error: Error) -> String {
        let nsError = error as NSError
        
        switch nsError.code {
        case AuthErrorCode.invalidPhoneNumber.rawValue:
            return "Invalid phone number format. Please use international format."
        case AuthErrorCode.invalidVerificationCode.rawValue:
            return "Invalid verification code. Please check and try again."
        case AuthErrorCode.sessionExpired.rawValue:
            return "Verification session expired. Please request a new code."
        case AuthErrorCode.quotaExceeded.rawValue:
            return "SMS quota exceeded. Please try again later."
        case AuthErrorCode.tooManyRequests.rawValue:
            return "Too many requests. Please wait before trying again."
        default:
            return "Phone verification failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Complete Onboarding
    
    func completeOnboarding() {
        guard let userId = Auth.auth().currentUser?.uid else {
            dlog("⚠️ Cannot complete onboarding: No user logged in")
            return
        }
        
        // ✅ FIX: Set local state IMMEDIATELY (synchronously) to prevent race condition
        // This prevents checkOnboardingStatus() from resetting it back to true
        needsOnboarding = false
        onboardingJustCompleted = true  // Prevent checkOnboardingStatus from overwriting
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding_\(userId)")
        dlog("✅ Onboarding state set to complete locally")
        
        // Update Firestore (single source of truth) asynchronously
        Task {
            do {
                let db = Firestore.firestore()
                try await db.collection("users").document(userId).updateData([
                    "hasCompletedOnboarding": true,
                    "onboardingCompletedAt": Timestamp(date: Date())
                ])
                
                dlog("✅ Onboarding completion saved to Firestore")
                
                // Clear the flag after Firestore update succeeds
                // Wait a bit to ensure any pending checkOnboardingStatus calls complete
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
                    self?.onboardingJustCompleted = false
                }
                
            } catch {
                dlog("❌ Failed to save onboarding completion to Firestore: \(error.localizedDescription)")
                dlog("⚠️ Local state already updated - user can proceed")
                
                // Clear the flag even on error (after delay)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
                    self?.onboardingJustCompleted = false
                }
            }
        }
    }
    
    // MARK: - Complete Username Selection
    
    func completeUsernameSelection() {
        needsUsernameSelection = false
        dlog("✅ Username selection completed")
    }
    
    // MARK: - Welcome to AMEN
    
    func showWelcomeToAMENScreen() {
        showWelcomeToAMEN = true
    }
    
    func dismissWelcomeToAMEN() {
        showWelcomeToAMEN = false
        // Now goes directly to main app
    }
    
    // MARK: - App Tutorial (DISABLED)
    
    // Tutorial feature removed - users go directly to main app after onboarding
    /*
    func showAppTutorialScreen() {
        showAppTutorial = true
    }
    
    func dismissAppTutorial() {
        showAppTutorial = false
    }
    */
    
    // MARK: - Account Linking
    
    /// Get list of linked auth providers
    func getLinkedProviders() -> [String] {
        return firebaseManager.getLinkedProviders()
    }
    
    /// Check if provider is linked
    func isProviderLinked(_ provider: String) -> Bool {
        return firebaseManager.isProviderLinked(provider)
    }
    
    /// Link Google account
    func linkGoogleAccount() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await firebaseManager.linkGoogleAccount()
            dlog("✅ Google account linked")
            
            // Success haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
        } catch {
            dlog("❌ Failed to link Google account: \(error.localizedDescription)")
            errorMessage = handleAuthError(error)
            showError = true
            
            // Error haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
        
        isLoading = false
    }
    
    /// Link Apple account
    func linkAppleAccount(idToken: String, nonce: String, fullName: PersonNameComponents?) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await firebaseManager.linkAppleAccount(idToken: idToken, nonce: nonce, fullName: fullName)
            dlog("✅ Apple account linked")
            
            // Success haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
        } catch {
            dlog("❌ Failed to link Apple account: \(error.localizedDescription)")
            errorMessage = handleAuthError(error)
            showError = true
            
            // Error haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
        
        isLoading = false
    }
    
    /// P0: Link phone number to existing account
    /// Allows users who signed up with email/social to add phone verification
    func linkPhoneAccount(phoneNumber: String) async {
        isLoading = true
        errorMessage = nil
        
        dlog("📱 Linking phone number to existing account")
        
        // Send verification code
        await sendPhoneVerificationCode(phoneNumber: phoneNumber)
        
        // Store that we're in linking mode (not signup)
        self.phoneNumber = phoneNumber
        
        dlog("✅ Phone verification code sent for linking")
        
        isLoading = false
    }
    
    /// P0: Complete phone linking after OTP verification
    /// Called after user verifies the OTP code sent to their phone
    func completeLinkPhoneAccount(verificationCode: String) async -> Bool {
        guard let verificationID = phoneVerificationId else {
            await MainActor.run {
                errorMessage = "Verification session expired. Please try again."
                showError = true
            }
            return false
        }
        
        guard let currentUser = Auth.auth().currentUser else {
            await MainActor.run {
                errorMessage = "No user signed in"
                showError = true
            }
            return false
        }
        
        isLoading = true
        
        do {
            // Create phone credential
            let credential = PhoneAuthProvider.provider().credential(
                withVerificationID: verificationID,
                verificationCode: verificationCode
            )
            
            // Link credential to current user
            _ = try await currentUser.link(with: credential)
            dlog("✅ Phone number successfully linked to account")
            
            // Update Firestore with phone verification
            if let phoneNum = currentUser.phoneNumber {
                try await firebaseManager.firestore.collection("users")
                    .document(currentUser.uid)
                    .setData([
                        "phoneNumber": phoneNum,
                        "phoneVerified": true,
                        "phoneVerifiedAt": Timestamp(date: Date()),
                        "updatedAt": Timestamp(date: Date())
                    ], merge: true)
            }
            
            // Success haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            // Clean up
            await MainActor.run {
                self.phoneVerificationId = nil
                self.phoneNumber = ""
                self.isLoading = false
            }
            
            return true
            
        } catch let error as NSError {
            dlog("❌ Failed to link phone number: \(error.localizedDescription)")
            
            // P0: Enhanced error handling for provider conflicts
            let errorMsg: String
            switch error.code {
            case AuthErrorCode.providerAlreadyLinked.rawValue:
                errorMsg = "This phone number is already linked to your account."
            case AuthErrorCode.credentialAlreadyInUse.rawValue:
                errorMsg = "This phone number is already used by another account."
            case AuthErrorCode.invalidVerificationCode.rawValue:
                errorMsg = "Invalid verification code. Please try again."
            default:
                errorMsg = handlePhoneAuthError(error)
            }
            
            await MainActor.run {
                self.errorMessage = errorMsg
                self.showError = true
                self.isLoading = false
            }
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
            
            return false
        }
    }
    
    /// P0: Unlink phone number from account
    /// Requires at least one other auth provider to remain
    func unlinkPhoneAccount() async -> Bool {
        guard let currentUser = Auth.auth().currentUser else {
            await MainActor.run {
                errorMessage = "No user signed in"
                showError = true
            }
            return false
        }
        
        // Check that user has at least one other provider
        let providers = currentUser.providerData.map { $0.providerID }
        guard providers.count > 1 else {
            await MainActor.run {
                errorMessage = "Cannot remove phone number. You must have at least one sign-in method."
                showError = true
            }
            return false
        }
        
        isLoading = true
        
        do {
            _ = try await currentUser.unlink(fromProvider: "phone")
            dlog("✅ Phone number unlinked from account")
            
            // Update Firestore
            try await firebaseManager.firestore.collection("users")
                .document(currentUser.uid)
                .updateData([
                    "phoneNumber": FieldValue.delete(),
                    "phoneVerified": false,
                    "updatedAt": Timestamp(date: Date())
                ])
            
            // Success haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            await MainActor.run {
                self.isLoading = false
            }
            
            return true
            
        } catch {
            dlog("❌ Failed to unlink phone number: \(error.localizedDescription)")
            await MainActor.run {
                self.errorMessage = "Failed to remove phone number: \(error.localizedDescription)"
                self.showError = true
                self.isLoading = false
            }
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
            
            return false
        }
    }
    
    /// Unlink auth provider
    func unlinkProvider(_ providerID: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await firebaseManager.unlinkProvider(providerID)
            dlog("✅ Provider unlinked: \(providerID)")
            
            // Success haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
        } catch {
            dlog("❌ Failed to unlink provider: \(error.localizedDescription)")
            errorMessage = handleAuthError(error)
            showError = true
            
            // Error haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
        
        isLoading = false
    }
    
    // MARK: - Error Handling
    
    private func handleAuthError(_ error: Error) -> String {
        let nsError = error as NSError
        
        switch nsError.code {
        case AuthErrorCode.invalidEmail.rawValue:
            return "Please enter a valid email address"
        case AuthErrorCode.emailAlreadyInUse.rawValue:
            return "This email is already registered"
        case AuthErrorCode.weakPassword.rawValue:
            return "Password must be at least 6 characters"
        case AuthErrorCode.wrongPassword.rawValue:
            return "Incorrect password. Please try again"
        case AuthErrorCode.userNotFound.rawValue:
            return "No account found with this email"
        case AuthErrorCode.networkError.rawValue:
            return "Network error. Please check your connection"
        case AuthErrorCode.tooManyRequests.rawValue:
            return "Too many attempts. Please try again later"
        case AuthErrorCode.userDisabled.rawValue:
            return "This account has been disabled"
        case AuthErrorCode.providerAlreadyLinked.rawValue:
            return "This account is already linked"
        case AuthErrorCode.credentialAlreadyInUse.rawValue:
            return "This credential is already associated with another account"
        default:
            return error.localizedDescription
        }
    }
}

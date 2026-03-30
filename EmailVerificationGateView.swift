//
//  EmailVerificationGateView.swift
//  AMENAPP
//
//  Email verification enforcement before main app access
//

import SwiftUI
import FirebaseAuth

struct EmailVerificationGateView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @State private var isCheckingVerification = false
    @State private var resendCooldown = 0
    @State private var canResend = true
    @State private var showSuccessMessage = false
    // Holds the cooldown Task so it can be cancelled if the view disappears mid-count
    @State private var cooldownTask: Task<Void, Never>?
    
    var body: some View {
        ZStack {
            // Dark background
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // Icon
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 80))
                    .foregroundStyle(.white.opacity(0.9))
                
                // Title
                Text("Verify Your Email")
                    .font(.custom("OpenSans-Bold", size: 28))
                    .foregroundStyle(.white)
                
                // Description
                VStack(spacing: 12) {
                    Text("We're sending a verification link to:")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                    
                    if let email = Auth.auth().currentUser?.email {
                        Text(email)
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.white)
                    }
                    
                    Text("Check your email and click the verification link. It may take a few moments to arrive.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    
                    Text("Don't see it? Check your spam folder.")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.orange.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                }
                
                Spacer()
                
                // Actions
                VStack(spacing: 16) {
                    // Check verification status button
                    Button {
                        checkVerificationStatus()
                    } label: {
                        HStack(spacing: 12) {
                            if isCheckingVerification {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 18))
                            }
                            
                            Text(isCheckingVerification ? "Checking..." : "Check Verification Status")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.green.opacity(0.8))
                        )
                    }
                    .disabled(isCheckingVerification)
                    
                    // Resend email button
                    Button {
                        resendVerificationEmail()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "envelope.arrow.triangle.branch")
                                .font(.system(size: 16))
                            
                            if resendCooldown > 0 {
                                Text("Resend in \(resendCooldown)s")
                                    .font(.custom("OpenSans-Regular", size: 14))
                            } else {
                                Text("Resend Verification Email")
                                    .font(.custom("OpenSans-Regular", size: 14))
                            }
                        }
                        .foregroundStyle(.white.opacity(canResend ? 1.0 : 0.5))
                    }
                    .disabled(!canResend)
                    
                    // Success message
                    if showSuccessMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Verification email sent!")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .transition(.opacity)
                    }
                    
                    // Sign out option
                    Button {
                        authViewModel.signOut()
                    } label: {
                        Text("Sign Out")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                
                Spacer()
            }
        }
        .onAppear {
            Task {
                // Only auto-send if sign-up hasn't already sent an email in the last 60 s.
                // emailVerificationCooldownRemaining > 0 means signUp() fired recently —
                // sending again immediately would trigger Firebase abuse-detection rate limiting.
                if authViewModel.emailVerificationCooldownRemaining == 0 {
                    await authViewModel.sendEmailVerification()
                }

                // Auto-check verification status after a brief delay.
                // This allows users who clicked the link before reaching this screen to
                // pass through without any manual tap.
                try? await Task.sleep(nanoseconds: 500_000_000)
                checkVerificationStatus()
            }
        }
        .onDisappear {
            // Cancel the countdown task to prevent it running after view is gone
            cancelCooldown()
        }
    }
    
    private func checkVerificationStatus() {
        guard !isCheckingVerification else { return }
        
        isCheckingVerification = true
        
        Task {
            // Reload user to get fresh email verification status
            try? await Auth.auth().currentUser?.reload()
            
            await MainActor.run {
                if let isVerified = Auth.auth().currentUser?.isEmailVerified, isVerified {
                    // Email is verified — dismiss the gate
                    authViewModel.isEmailVerified = true
                    authViewModel.needsEmailVerification = false
                    authViewModel.showEmailVerificationBanner = false
                } else {
                    // Still not verified
                    authViewModel.errorMessage = "Email not yet verified. Please check your inbox."
                    authViewModel.showError = true
                }
                
                isCheckingVerification = false
            }
        }
    }
    
    private func resendVerificationEmail() {
        guard canResend else { return }

        canResend = false
        resendCooldown = 60
        showSuccessMessage = false

        // Cancel any in-flight cooldown before starting a new one
        cooldownTask?.cancel()

        cooldownTask = Task {
            await authViewModel.sendEmailVerification()

            guard !Task.isCancelled else { return }
            withAnimation { showSuccessMessage = true }

            // Tick the countdown using Task.sleep — auto-cancelled when view disappears
            // (no Timer leak). Each sleep is 1 s; we stop when cancelled or at 0.
            for remaining in stride(from: 60, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                resendCooldown = remaining
                try? await Task.sleep(for: .seconds(1))
            }

            guard !Task.isCancelled else { return }
            resendCooldown = 0
            canResend = true

            // Auto-hide the success banner after the cooldown
            withAnimation { showSuccessMessage = false }
        }
    }
}

// Cancels the cooldown task when the view leaves the hierarchy,
// preventing the Task from running after the view is gone.
private extension EmailVerificationGateView {
    func cancelCooldown() {
        cooldownTask?.cancel()
        cooldownTask = nil
    }
}

#Preview {
    EmailVerificationGateView()
        .environmentObject(AuthenticationViewModel())
}

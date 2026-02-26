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
                        Task {
                            await authViewModel.signOut()
                        }
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
            // Send verification email immediately when view appears
            // This ensures user gets a fresh email even if sign-up email failed/went to spam
            Task {
                await authViewModel.sendEmailVerification()
                
                // Then auto-check verification status after a brief delay
                try? await Task.sleep(nanoseconds: 500_000_000)
                checkVerificationStatus()
            }
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
                    // Email is verified!
                    authViewModel.isEmailVerified = true
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
        
        Task {
            await authViewModel.sendEmailVerification()
            
            await MainActor.run {
                showSuccessMessage = true
                
                // Start countdown
                Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                    if resendCooldown > 0 {
                        resendCooldown -= 1
                    } else {
                        canResend = true
                        timer.invalidate()
                    }
                }
                
                // Hide success message after 3 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        withAnimation {
                            showSuccessMessage = false
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    EmailVerificationGateView()
        .environmentObject(AuthenticationViewModel())
}

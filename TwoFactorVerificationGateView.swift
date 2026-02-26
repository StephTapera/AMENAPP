//
//  TwoFactorVerificationGateView.swift
//  AMENAPP
//
//  P0 SECURITY: 2FA verification gate for login
//  Blocks access until user verifies 2FA code or backup code
//

import SwiftUI
import FirebaseAuth

struct TwoFactorVerificationGateView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @StateObject private var twoFactorService = TwoFactorAuthService.shared
    
    @State private var verificationCode = ""
    @State private var isVerifying = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showBackupCodeInput = false
    @State private var backupCode = ""
    @State private var resendCooldown = 0
    @State private var canResend = true
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 32) {
                    // Icon
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.green.opacity(0.9))
                        .padding(.top, 60)
                    
                    // Title
                    VStack(spacing: 8) {
                        Text("Two-Factor Authentication")
                            .font(.custom("OpenSans-Bold", size: 28))
                            .foregroundStyle(.white)
                        
                        if let phone = twoFactorService.phoneNumber {
                            Text("Enter the code sent to \(formatPhoneForDisplay(phone))")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    
                    // Code input
                    if !showBackupCodeInput {
                        VStack(spacing: 16) {
                            TextField("", text: $verificationCode)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .font(.custom("Menlo", size: 32))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.white.opacity(0.12))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                                .padding(.horizontal, 40)
                                .onChange(of: verificationCode) { oldValue, newValue in
                                    // Auto-submit when 6 digits entered
                                    if newValue.count == 6 {
                                        Task {
                                            await verify2FACode()
                                        }
                                    }
                                }
                            
                            Text("6-digit verification code")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.horizontal)
                    } else {
                        // Backup code input
                        VStack(spacing: 16) {
                            TextField("", text: $backupCode)
                                .keyboardType(.default)
                                .textContentType(.oneTimeCode)
                                .font(.custom("Menlo", size: 20))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.white.opacity(0.12))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                                .padding(.horizontal, 40)
                            
                            Text("Format: 1234-5678")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.horizontal)
                    }
                    
                    // Verify button
                    Button {
                        Task {
                            if showBackupCodeInput {
                                await verifyBackupCode()
                            } else {
                                await verify2FACode()
                            }
                        }
                    } label: {
                        if isVerifying {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        } else {
                            Text(showBackupCodeInput ? "Verify Backup Code" : "Verify")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(canSubmit ? Color.green : Color.gray.opacity(0.3))
                    )
                    .disabled(!canSubmit || isVerifying)
                    .padding(.horizontal, 40)
                    
                    // Alternative options
                    VStack(spacing: 16) {
                        if !showBackupCodeInput {
                            // Resend code
                            Button {
                                Task {
                                    await resendCode()
                                }
                            } label: {
                                Text(resendCooldown > 0 ? "Resend code in \(resendCooldown)s" : "Resend code")
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.blue)
                            }
                            .disabled(!canResend)
                            
                            Divider()
                                .background(.white.opacity(0.2))
                                .padding(.horizontal, 40)
                            
                            // Use backup code
                            Button {
                                withAnimation {
                                    showBackupCodeInput = true
                                    verificationCode = ""
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    Text("Can't access your phone?")
                                        .font(.custom("OpenSans-Regular", size: 14))
                                        .foregroundStyle(.white.opacity(0.7))
                                    
                                    Text("Use backup code")
                                        .font(.custom("OpenSans-SemiBold", size: 14))
                                        .foregroundStyle(.orange)
                                }
                            }
                        } else {
                            // Back to SMS code
                            Button {
                                withAnimation {
                                    showBackupCodeInput = false
                                    backupCode = ""
                                }
                            } label: {
                                Text("← Back to SMS verification")
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Sign out option
                    Button {
                        authViewModel.signOut()
                    } label: {
                        Text("Sign Out")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.red)
                            .padding(.bottom, 40)
                    }
                }
            }
        }
        .alert("Verification Failed", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .onAppear {
            // Send initial 2FA code
            Task {
                await sendInitial2FACode()
            }
        }
    }
    
    private var canSubmit: Bool {
        if showBackupCodeInput {
            return backupCode.count >= 9 // Format: 1234-5678
        } else {
            return verificationCode.count == 6
        }
    }
    
    private func formatPhoneForDisplay(_ phone: String) -> String {
        // Format: +1 (720) 305-2376 → (720) 305-2376
        let digits = phone.filter { $0.isNumber }
        guard digits.count >= 10 else { return phone }
        
        let lastTen = String(digits.suffix(10))
        let areaCode = String(lastTen.prefix(3))
        let prefix = String(lastTen.dropFirst(3).prefix(3))
        let lineNumber = String(lastTen.suffix(4))
        
        return "(\(areaCode)) \(prefix)-\(lineNumber)"
    }
    
    // MARK: - Actions
    
    private func sendInitial2FACode() async {
        guard let phone = twoFactorService.phoneNumber else {
            errorMessage = "No phone number found for 2FA"
            showError = true
            return
        }
        
        do {
            _ = try await twoFactorService.send2FACode(phoneNumber: phone)
            print("✅ Initial 2FA code sent")
        } catch {
            print("❌ Failed to send initial 2FA code: \(error.localizedDescription)")
            errorMessage = "Failed to send verification code. Please try again."
            showError = true
        }
    }
    
    private func verify2FACode() async {
        guard !isVerifying else { return }
        isVerifying = true
        
        do {
            let success = try await twoFactorService.verify2FACode(verificationCode: verificationCode)
            
            if success {
                // Success - allow authentication to proceed
                await MainActor.run {
                    authViewModel.needs2FAVerification = false
                    authViewModel.showAuthSuccess = true
                    
                    // Success haptic
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } else {
                throw TwoFactorError.verificationFailed("Invalid code")
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                verificationCode = ""
                
                // Error haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
        
        isVerifying = false
    }
    
    private func verifyBackupCode() async {
        guard !isVerifying else { return }
        guard let userId = authViewModel.pending2FAUserId else {
            errorMessage = "Session expired. Please sign in again."
            showError = true
            return
        }
        
        isVerifying = true
        
        do {
            let success = try await TwoFactorAuthService.shared.verifyBackupCode(backupCode, userId: userId)
            
            if success {
                // Success - allow authentication to proceed
                await MainActor.run {
                    authViewModel.needs2FAVerification = false
                    authViewModel.showAuthSuccess = true
                    
                    // Success haptic
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } else {
                throw TwoFactorError.verificationFailed("Invalid backup code")
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                backupCode = ""
                
                // Error haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
        
        isVerifying = false
    }
    
    private func resendCode() async {
        guard canResend else { return }
        guard let phone = twoFactorService.phoneNumber else { return }
        
        canResend = false
        resendCooldown = 60
        
        // Start cooldown timer
        Task {
            while resendCooldown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    resendCooldown -= 1
                }
            }
            await MainActor.run {
                canResend = true
            }
        }
        
        do {
            _ = try await twoFactorService.send2FACode(phoneNumber: phone)
            print("✅ 2FA code resent")
            
            // Success haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        } catch {
            print("❌ Failed to resend code: \(error.localizedDescription)")
            errorMessage = "Failed to resend code. Please try again."
            showError = true
            
            // Reset cooldown on error
            await MainActor.run {
                resendCooldown = 0
                canResend = true
            }
            
            // Error haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
    }
}

#Preview {
    TwoFactorVerificationGateView()
        .environmentObject(AuthenticationViewModel())
}

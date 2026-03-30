//
//  TwoFactorGateView.swift
//  AMENAPP
//
//  2FA verification gate shown during login for users with 2FA enabled
//  P0 SECURITY: Prevents authentication bypass
//

import SwiftUI
import FirebaseAuth

struct TwoFactorGateView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @ObservedObject private var twoFactorService = TwoFactorAuthService.shared
    
    let userId: String
    let userEmail: String
    
    @State private var verificationCode = ""
    @State private var backupCode = ""
    @State private var showBackupCodeEntry = false
    @State private var isVerifying = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var resendCooldown = 0
    @State private var canResend = false
    @State private var resendTimer: Timer?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                    
                    Text("Two-Factor Authentication")
                        .font(.custom("OpenSans-Bold", size: 24))
                        .foregroundStyle(.white)
                    
                    Text("Enter the code sent to your phone")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 60)
                
                if !showBackupCodeEntry {
                    // SMS Code Entry
                    VStack(spacing: 16) {
                        TextField("6-Digit Code", text: $verificationCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .font(.system(size: 32, weight: .medium, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.white.opacity(0.1))
                            )
                            .foregroundStyle(.white)
                            .padding(.horizontal, 32)
                        
                        // Verify Button
                        Button {
                            Task { await verifyCode() }
                        } label: {
                            HStack {
                                if isVerifying {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Verify")
                                        .font(.custom("OpenSans-SemiBold", size: 16))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.blue)
                            )
                        }
                        .disabled(verificationCode.count != 6 || isVerifying)
                        .opacity(verificationCode.count != 6 || isVerifying ? 0.5 : 1.0)
                        .padding(.horizontal, 32)
                        
                        // Resend Code
                        if canResend {
                            Button {
                                Task { await resendCode() }
                            } label: {
                                Text("Resend Code")
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.blue)
                            }
                        } else if resendCooldown > 0 {
                            Text("Resend in \(resendCooldown)s")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    
                    // Switch to Backup Code
                    Button {
                        withAnimation {
                            showBackupCodeEntry = true
                        }
                    } label: {
                        Text("Use Backup Code Instead")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.top, 16)
                    
                } else {
                    // Backup Code Entry
                    VStack(spacing: 16) {
                        Text("Enter Backup Code")
                            .font(.custom("OpenSans-SemiBold", size: 18))
                            .foregroundStyle(.white)
                        
                        Text("Use one of your 8-digit backup codes")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                        
                        TextField("0000-0000", text: $backupCode)
                            .keyboardType(.numberPad)
                            .font(.system(size: 24, weight: .medium, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.white.opacity(0.1))
                            )
                            .foregroundStyle(.white)
                            .padding(.horizontal, 32)
                        
                        // Verify Backup Code Button
                        Button {
                            Task { await verifyBackupCode() }
                        } label: {
                            HStack {
                                if isVerifying {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Verify Backup Code")
                                        .font(.custom("OpenSans-SemiBold", size: 16))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.green)
                            )
                        }
                        .disabled(backupCode.count < 8 || isVerifying)
                        .opacity(backupCode.count < 8 || isVerifying ? 0.5 : 1.0)
                        .padding(.horizontal, 32)
                        
                        // Back to SMS Code
                        Button {
                            withAnimation {
                                showBackupCodeEntry = false
                                backupCode = ""
                            }
                        } label: {
                            Text("Back to SMS Code")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.blue)
                        }
                        .padding(.top, 8)
                    }
                }
                
                // Cancel
                Button {
                    // Sign out and return to login
                    try? Auth.auth().signOut()
                    authViewModel.needs2FAVerification = false
                    authViewModel.pending2FAUserId = nil
                    authViewModel.pending2FAEmail = nil
                } label: {
                    Text("Cancel")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.red.opacity(0.8))
                }
                .padding(.top, 32)
                
                Spacer()
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .onAppear {
            Task {
                await sendInitialCode()
                startResendTimer()
            }
        }
        .onDisappear {
            // Clean up timer to prevent memory leak
            resendTimer?.invalidate()
            resendTimer = nil
        }
    }
    
    // MARK: - Actions
    
    private func sendInitialCode() async {
        do {
            let phone = try await twoFactorService.get2FAPhone(userId: userId)
            _ = try await twoFactorService.send2FACode(phoneNumber: phone)
            dlog("✅ Initial 2FA code sent")
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func verifyCode() async {
        isVerifying = true
        
        do {
            // Verify the 2FA code
            let success = try await twoFactorService.verify2FACode(verificationCode: verificationCode)
            
            if success {
                // 2FA verified - user can now authenticate
                authViewModel.needs2FAVerification = false
                authViewModel.pending2FAUserId = nil
                authViewModel.pending2FAEmail = nil
                
                // Success haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
                dlog("✅ 2FA verification successful - user authenticated")
            }
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            
            // Error haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
        
        isVerifying = false
    }
    
    private func verifyBackupCode() async {
        isVerifying = true
        
        do {
            let success = try await twoFactorService.verifyBackupCode(backupCode, userId: userId)
            
            if success {
                // Backup code verified - user can now authenticate
                authViewModel.needs2FAVerification = false
                authViewModel.pending2FAUserId = nil
                authViewModel.pending2FAEmail = nil
                
                // Success haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
                dlog("✅ Backup code verified - user authenticated")
            }
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            
            // Error haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
        
        isVerifying = false
    }
    
    private func resendCode() async {
        do {
            let phone = try await twoFactorService.get2FAPhone(userId: userId)
            _ = try await twoFactorService.send2FACode(phoneNumber: phone)
            
            // Success haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            // Reset timer
            canResend = false
            resendCooldown = 60
            startResendTimer()
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func startResendTimer() {
        // Invalidate existing timer first
        resendTimer?.invalidate()
        
        resendCooldown = 60
        canResend = false
        
        // Store timer reference for cleanup
        resendTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] timer in
            if resendCooldown > 0 {
                resendCooldown -= 1
            } else {
                canResend = true
                timer.invalidate()
                resendTimer = nil
            }
        }
    }
}

//
//  TwoFactorAuthView.swift
//  AMENAPP
//
//  Two-Factor Authentication setup and management
//

import SwiftUI

struct TwoFactorAuthView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var twoFactorService = TwoFactorAuthService.shared
    
    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    @State private var showSetup = false
    @State private var showVerification = false
    @State private var showDisableConfirmation = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if twoFactorService.is2FAEnabled {
                        enabledState
                    } else {
                        disabledState
                    }
                } header: {
                    Text("TWO-FACTOR AUTHENTICATION")
                } footer: {
                    Text(twoFactorService.is2FAEnabled
                        ? "2FA is enabled. You'll need to verify your phone number when signing in from new devices."
                        : "Add an extra layer of security. You'll need both your password and phone to sign in.")
                        .font(.system(size: 13))
                }
                
                if !twoFactorService.is2FAEnabled {
                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            FeatureRow(
                                icon: "lock.shield.fill",
                                title: "Enhanced Security",
                                description: "Protects your account even if your password is compromised"
                            )
                            
                            Divider()
                            
                            FeatureRow(
                                icon: "bell.badge.fill",
                                title: "Login Alerts",
                                description: "Get notified of sign-in attempts on new devices"
                            )
                            
                            Divider()
                            
                            FeatureRow(
                                icon: "checkmark.shield.fill",
                                title: "Verified Access",
                                description: "Only you can access your account with your phone"
                            )
                        }
                        .padding(.vertical, 8)
                    } header: {
                        Text("BENEFITS")
                    }
                }
            }
            .navigationTitle("Two-Factor Auth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showSetup) {
                SetupPhoneView(
                    phoneNumber: $phoneNumber,
                    onContinue: {
                        Task {
                            await sendVerificationCode()
                        }
                    }
                )
            }
            .sheet(isPresented: $showVerification) {
                VerificationCodeView(
                    verificationCode: $verificationCode,
                    phoneNumber: phoneNumber,
                    onVerify: {
                        Task {
                            await verifyCode()
                        }
                    },
                    onResend: {
                        Task {
                            await sendVerificationCode()
                        }
                    }
                )
            }
            .alert("Disable 2FA?", isPresented: $showDisableConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Disable", role: .destructive) {
                    Task {
                        await disable2FA()
                    }
                }
            } message: {
                Text("Your account will be less secure without two-factor authentication. You can always turn it back on.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }
    
    private var enabledState: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Status")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Enabled")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                
                Spacer()
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Phone Number")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    
                    Text(twoFactorService.phoneNumber ?? "Not set")
                        .font(.system(size: 16, weight: .medium))
                }
                
                Spacer()
            }
            
            Divider()
            
            Button {
                showDisableConfirmation = true
            } label: {
                Text("Disable Two-Factor Authentication")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var disabledState: some View {
        Button {
            showSetup = true
        } label: {
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 18))
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Two-Factor Authentication")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text("Add an extra layer of security")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Actions
    
    private func sendVerificationCode() async {
        isLoading = true
        
        do {
            _ = try await twoFactorService.setupTwoFactor(phoneNumber: phoneNumber)
            
            await MainActor.run {
                showSetup = false
                showVerification = true
                
                // Success haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            }
            
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                
                // Error haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
        
        isLoading = false
    }
    
    private func verifyCode() async {
        isLoading = true
        
        do {
            try await twoFactorService.verifyAndEnable2FA(verificationCode: verificationCode)
            
            await MainActor.run {
                showVerification = false
                
                // Success haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            }
            
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                
                // Error haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
        
        isLoading = false
    }
    
    private func disable2FA() async {
        isLoading = true
        
        do {
            try await twoFactorService.disable2FA()
            
            await MainActor.run {
                // Success haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            }
            
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                
                // Error haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
        
        isLoading = false
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.blue)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Setup Phone View

struct SetupPhoneView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var phoneNumber: String
    let onContinue: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                    .padding(.top, 40)
                
                VStack(spacing: 8) {
                    Text("Enter Your Phone Number")
                        .font(.system(size: 24, weight: .bold))
                    
                    Text("We'll send you a verification code to confirm it's really you")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                TextField("Phone Number", text: $phoneNumber)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .font(.system(size: 16))
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                
                Button {
                    onContinue()
                    dismiss()
                } label: {
                    Text("Send Code")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal)
                }
                .disabled(phoneNumber.count < 10)
                .opacity(phoneNumber.count < 10 ? 0.5 : 1.0)
                
                Spacer()
            }
            .navigationTitle("Set Up 2FA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Verification Code View

struct VerificationCodeView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var verificationCode: String
    let phoneNumber: String
    let onVerify: () -> Void
    let onResend: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                    .padding(.top, 40)
                
                VStack(spacing: 8) {
                    Text("Enter Verification Code")
                        .font(.system(size: 24, weight: .bold))
                    
                    Text("We sent a code to \(phoneNumber)")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                TextField("6-Digit Code", text: $verificationCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(size: 24, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                
                Button {
                    onVerify()
                    dismiss()
                } label: {
                    Text("Verify & Enable")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal)
                }
                .disabled(verificationCode.count != 6)
                .opacity(verificationCode.count != 6 ? 0.5 : 1.0)
                
                Button {
                    onResend()
                } label: {
                    Text("Resend Code")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                }
                
                Spacer()
            }
            .navigationTitle("Verify Phone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    TwoFactorAuthView()
}

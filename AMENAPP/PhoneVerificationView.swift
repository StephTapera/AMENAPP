//
//  PhoneVerificationView.swift
//  AMENAPP
//
//  Phone verification with SMS OTP
//

import SwiftUI
import FirebaseAuth

struct PhoneVerificationView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = PhoneVerificationViewModel()
    @State private var phoneNumber = ""
    @State private var otpCode = ""
    @FocusState private var isPhoneFocused: Bool
    @FocusState private var isOTPFocused: Bool
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "phone.badge.checkmark.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                        
                        Text("Verify Phone Number")
                            .font(AMENFont.bold(22))
                        
                        Text("Add a verified phone number for account recovery and two-factor authentication")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .padding(.top, 20)
                    
                    // Phone input (if not sent)
                    if !viewModel.codeSent {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Phone Number")
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 12) {
                                // Country code
                                Text("+1")
                                    .font(AMENFont.regular(16))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 14)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                                
                                // Phone number field
                                TextField("(555) 123-4567", text: $phoneNumber)
                                    .font(AMENFont.regular(16))
                                    .keyboardType(.phonePad)
                                    .focused($isPhoneFocused)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                            }
                            
                            Text("Standard messaging rates may apply")
                                .font(AMENFont.regular(12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                        
                        // Send code button
                        Button {
                            Task {
                                await viewModel.sendVerificationCode(phoneNumber: "+1" + phoneNumber)
                            }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue)
                                    .frame(height: 50)
                                
                                if viewModel.isSending {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Send Verification Code")
                                        .font(AMENFont.semiBold(16))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .disabled(phoneNumber.isEmpty || viewModel.isSending)
                        .opacity(phoneNumber.isEmpty ? 0.5 : 1.0)
                        .padding(.horizontal, 20)
                    }
                    
                    // OTP input (if code sent)
                    if viewModel.codeSent {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Verification Code")
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(.secondary)
                            
                            Text("Enter the 6-digit code sent to +1 " + phoneNumber)
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                            
                            // OTP field
                            TextField("000000", text: $otpCode)
                                .font(AMENFont.regular(24).monospacedDigit())
                                .keyboardType(.numberPad)
                                .focused($isOTPFocused)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 16)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                                .onChange(of: otpCode) { _, newValue in
                                    // Limit to 6 digits
                                    if newValue.count > 6 {
                                        otpCode = String(newValue.prefix(6))
                                    }
                                }
                            
                            // Resend button
                            if viewModel.canResend {
                                Button {
                                    Task {
                                        await viewModel.sendVerificationCode(phoneNumber: "+1" + phoneNumber)
                                    }
                                } label: {
                                    Text("Resend Code")
                                        .font(AMENFont.medium(14))
                                        .foregroundStyle(.blue)
                                }
                            } else {
                                Text("Resend available in \(viewModel.resendCountdown)s")
                                    .font(AMENFont.regular(13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Verify button
                        Button {
                            Task {
                                let success = await viewModel.verifyCode(code: otpCode)
                                if success {
                                    dismiss()
                                }
                            }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue)
                                    .frame(height: 50)
                                
                                if viewModel.isVerifying {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Verify Phone Number")
                                        .font(AMENFont.semiBold(16))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .disabled(otpCode.count != 6 || viewModel.isVerifying)
                        .opacity(otpCode.count == 6 ? 1.0 : 0.5)
                        .padding(.horizontal, 20)
                    }
                    
                    // Error message
                    if let error = viewModel.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            
                            Text(error)
                                .font(AMENFont.regular(14))
                                .foregroundStyle(.red)
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                isPhoneFocused = true
            }
        }
    }
}

@MainActor
class PhoneVerificationViewModel: ObservableObject {
    @Published var codeSent = false
    @Published var isSending = false
    @Published var isVerifying = false
    @Published var errorMessage: String?
    @Published var canResend = false
    @Published var resendCountdown = 60
    
    private var verificationID: String?
    private var resendTimer: Timer?
    
    func sendVerificationCode(phoneNumber: String) async {
        isSending = true
        errorMessage = nil
        
        do {
            // Firebase Phone Auth
            let verificationID = try await PhoneAuthProvider.provider()
                .verifyPhoneNumber(phoneNumber, uiDelegate: nil)
            
            self.verificationID = verificationID
            self.codeSent = true
            startResendTimer()
            
        } catch {
            errorMessage = "Failed to send code: \(error.localizedDescription)"
        }
        
        isSending = false
    }
    
    func verifyCode(code: String) async -> Bool {
        guard let verificationID = verificationID else {
            errorMessage = "No verification ID found"
            return false
        }
        
        isVerifying = true
        errorMessage = nil
        
        do {
            let credential = PhoneAuthProvider.provider().credential(
                withVerificationID: verificationID,
                verificationCode: code
            )
            
            // Link phone to current user
            try await Auth.auth().currentUser?.link(with: credential)
            
            // Record security event
            await SecurityService.shared.recordSecurityEvent(type: .phoneVerified)
            
            isVerifying = false
            return true
            
        } catch {
            errorMessage = "Invalid code: \(error.localizedDescription)"
            isVerifying = false
            return false
        }
    }
    
    private func startResendTimer() {
        canResend = false
        resendCountdown = 60
        
        resendTimer?.invalidate()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            Task { @MainActor in
                self.resendCountdown -= 1
                if self.resendCountdown <= 0 {
                    self.canResend = true
                    timer.invalidate()
                }
            }
        }
    }
}

#Preview {
    PhoneVerificationView()
}

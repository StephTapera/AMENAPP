import SwiftUI

/// View for entering and verifying 2FA OTP codes during sign-in
struct TwoFactorVerificationView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var otpService = TwoFactorOTPService.shared
    @State private var code = ["", "", "", "", "", ""]
    @FocusState private var focusedField: Int?
    @State private var showError = false
    @State private var resendCooldown = 0
    @State private var timer: Timer?

    let deliveryMethod: String
    let maskedDestination: String
    let onVerified: (String) -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Header
                VStack(spacing: 16) {
                    Image(systemName: deliveryMethod == "email" ? "envelope.fill" : "message.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)

                    Text("Enter Verification Code")
                        .font(.custom("OpenSans-Bold", size: 24))
                        .foregroundStyle(.primary)

                    Text("We sent a 6-digit code to \(maskedDestination)")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                // Code input fields
                HStack(spacing: 12) {
                    ForEach(0..<6, id: \.self) { index in
                        codeDigitField(index: index)
                    }
                }
                .padding(.horizontal, 24)

                // Timer
                if let timeRemaining = otpService.timeRemaining, timeRemaining > 0 {
                    Text("Code expires in \(otpService.timeRemainingString)")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                } else if otpService.isExpired {
                    Text("Code expired. Please request a new one.")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.red)
                }

                Spacer()

                // Resend button
                VStack(spacing: 12) {
                    if resendCooldown > 0 {
                        Text("Resend code in \(resendCooldown)s")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            resendCode()
                        } label: {
                            Text("Didn't receive the code? Resend")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.green)
                        }
                        .disabled(otpService.isRequesting)
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .overlay {
            if otpService.isVerifying {
                LoadingOverlay(message: "Verifying code...")
            }
        }
        .alert("Verification Failed", isPresented: $showError) {
            Button("Try Again", role: .cancel) {
                clearCode()
            }
        } message: {
            Text(otpService.errorMessage ?? "Invalid code. Please try again.")
        }
        .onAppear {
            focusedField = 0
            startResendCooldown()
        }
        .onDisappear {
            timer?.invalidate()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.primary)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Code Digit Field

    @ViewBuilder
    private func codeDigitField(index: Int) -> some View {
        TextField("", text: $code[index])
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.custom("OpenSans-Bold", size: 28))
            .frame(width: 48, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(focusedField == index ? Color.green : Color.clear, lineWidth: 2)
            )
            .focused($focusedField, equals: index)
            .onChange(of: code[index]) { oldValue, newValue in
                handleCodeInput(index: index, oldValue: oldValue, newValue: newValue)
            }
    }

    // MARK: - Helper Methods

    private func handleCodeInput(index: Int, oldValue: String, newValue: String) {
        // Only allow single digit
        if newValue.count > 1 {
            code[index] = String(newValue.last!)
        }

        // Move to next field if digit entered
        if !newValue.isEmpty && index < 5 {
            focusedField = index + 1
        }

        // Auto-verify when all 6 digits entered
        if code.allSatisfy({ !$0.isEmpty }) {
            verifyCode()
        }
    }

    private func verifyCode() {
        let enteredCode = code.joined()

        guard enteredCode.count == 6 else { return }

        Task {
            do {
                guard let otpId = otpService.otpId else {
                    throw TwoFactorOTPError.verificationFailed
                }

                let sessionToken = try await otpService.verifyOTP(otpId: otpId, code: enteredCode)

                // Success - call completion handler
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    onVerified(sessionToken)
                }

            } catch {
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                    showError = true
                }
            }
        }
    }

    private func clearCode() {
        code = ["", "", "", "", "", ""]
        focusedField = 0
    }

    private func resendCode() {
        clearCode()

        Task {
            do {
                _ = try await otpService.requestOTP(deliveryMethod: deliveryMethod)

                await MainActor.run {
                    startResendCooldown()
                }
            } catch {
                await MainActor.run {
                    showError = true
                }
            }
        }
    }

    private func startResendCooldown() {
        resendCooldown = 60
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if resendCooldown > 0 {
                resendCooldown -= 1
            } else {
                timer?.invalidate()
            }
        }
    }
}

#Preview {
    NavigationStack {
        TwoFactorVerificationView(
            deliveryMethod: "email",
            maskedDestination: "st***@gmail.com"
        ) { _ in
            print("Verified!")
        }
    }
}

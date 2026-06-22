//
//  TwoFactorAuthView.swift
//  AMENAPP
//
//  Two-Factor Authentication setup and management
//

import SwiftUI
import FirebaseAuth

struct TwoFactorAuthView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var twoFactorService = TwoFactorAuthService.shared

    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    @State private var showSetup = false
    @State private var showVerification = false
    @State private var showDisableConfirmation = false
    @State private var showBackupCodesSheet = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {

                    // MARK: 2FA Status Section
                    Text("TWO-FACTOR AUTHENTICATION")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        if twoFactorService.is2FAEnabled {
                            enabledState
                        } else {
                            disabledState
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    // Footer
                    Text(twoFactorService.is2FAEnabled
                        ? "2FA is enabled. You'll need to verify your phone number when signing in from new devices."
                        : "Add an extra layer of security. You'll need both your password and phone to sign in.")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // MARK: Benefits Section (only when disabled)
                    if !twoFactorService.is2FAEnabled {
                        Text("BENEFITS")
                            .font(AMENFont.bold(11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            TwoFAFeatureRow(
                                icon: "lock.shield.fill",
                                title: "Enhanced Security",
                                description: "Protects your account even if your password is compromised"
                            )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            Divider().padding(.leading, 16)

                            TwoFAFeatureRow(
                                icon: "bell.badge.fill",
                                title: "Login Alerts",
                                description: "Get notified of sign-in attempts on new devices"
                            )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            Divider().padding(.leading, 16)

                            TwoFAFeatureRow(
                                icon: "checkmark.shield.fill",
                                title: "Verified Access",
                                description: "Only you can access your account with your phone"
                            )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                        .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 40)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
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
        VStack(spacing: 0) {
            // Status row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Status")
                        .font(.systemScaled(14))
                        .foregroundStyle(.secondary)

                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Enabled")
                            .font(.systemScaled(16, weight: .semibold))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().padding(.leading, 16)

            // Phone row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Phone Number")
                        .font(.systemScaled(14))
                        .foregroundStyle(.secondary)

                    Text(twoFactorService.maskedPhone ?? "Not set")
                        .font(.systemScaled(16, weight: .medium))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().padding(.leading, 16)

            // Backup codes row
            Button {
                showBackupCodesSheet = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recovery Backup Codes")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(.primary)
                        if let count = twoFactorService.backupCodesRemaining {
                            Text("\(count) of 6 codes remaining")
                                .font(.systemScaled(13))
                                .foregroundStyle(count <= 2 ? .red : .secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(PlainButtonStyle())

            // Low-stock warning banner
            if twoFactorService.isBackupCodesLow {
                Divider().padding(.leading, 16)

                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Low on backup codes")
                            .font(.systemScaled(13, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("Generate new codes before you run out.")
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Divider().padding(.leading, 16)

            // Disable row
            Button {
                showDisableConfirmation = true
            } label: {
                Text("Disable Two-Factor Authentication")
                    .font(.systemScaled(15, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .task {
            if let userId = FirebaseAuth.Auth.auth().currentUser?.uid {
                await twoFactorService.loadBackupCodeCount(userId: userId)
            }
        }
        .sheet(isPresented: $showBackupCodesSheet) {
            BackupCodesManagementView()
        }
    }

    private var disabledState: some View {
        Button {
            showSetup = true
        } label: {
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.systemScaled(18))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Two-Factor Authentication")
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("Add an extra layer of security")
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(PlainButtonStyle())
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

            // Generate backup codes and store them
            if let userId = Auth.auth().currentUser?.uid {
                _ = try? await twoFactorService.regenerateBackupCodes(userId: userId)
            }

            await MainActor.run {
                showVerification = false
                // Open backup codes sheet so user can save their codes immediately
                showBackupCodesSheet = true

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

private struct TwoFAFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(20))
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.systemScaled(15, weight: .semibold))

                Text(description)
                    .font(.systemScaled(13))
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
                    .font(.systemScaled(60))
                    .foregroundStyle(.blue)
                    .padding(.top, 40)

                VStack(spacing: 8) {
                    Text("Enter Your Phone Number")
                        .font(.systemScaled(24, weight: .bold))

                    Text("We'll send you a verification code to confirm it's really you")
                        .font(.systemScaled(15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                TextField("Phone Number", text: $phoneNumber)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .font(.systemScaled(16))
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)

                Button {
                    onContinue()
                    dismiss()
                } label: {
                    Text("Send Code")
                        .font(.systemScaled(16, weight: .semibold))
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
                    .font(.systemScaled(60))
                    .foregroundStyle(.green)
                    .padding(.top, 40)

                VStack(spacing: 8) {
                    Text("Enter Verification Code")
                        .font(.systemScaled(24, weight: .bold))

                    Text("We sent a code to \(phoneNumber)")
                        .font(.systemScaled(15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                TextField("6-Digit Code", text: $verificationCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.systemScaled(24, weight: .medium, design: .monospaced))
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
                        .font(.systemScaled(16, weight: .semibold))
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
                        .font(.systemScaled(14))
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

// MARK: - Backup Codes Management View

struct BackupCodesManagementView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var twoFactorService = TwoFactorAuthService.shared
    @State private var newCodes: [String] = []
    @State private var isRegenerating = false
    @State private var showConfirmRegenerate = false
    @State private var copiedToClipboard = false
    @State private var errorMessage: String?
    @State private var showError = false

    private var hasNewCodes: Bool { !newCodes.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Icon + heading
                    VStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .font(.systemScaled(48))
                            .foregroundStyle(.orange)
                            .padding(.top, 32)

                        Text("Recovery Backup Codes")
                            .font(.systemScaled(22, weight: .bold))

                        Text("Use a backup code to sign in if you lose access to your phone. Each code can only be used once.")
                            .font(.systemScaled(14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // Remaining count or new codes
                    if hasNewCodes {
                        VStack(spacing: 16) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("New codes generated — save these now")
                                    .font(.systemScaled(14, weight: .semibold))
                                    .foregroundStyle(.green)
                            }

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(newCodes, id: \.self) { code in
                                    Text(code)
                                        .font(.system(.body, design: .monospaced))
                                        .padding(12)
                                        .frame(maxWidth: .infinity)
                                        .background(Color(.tertiarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }

                            // Copy all button
                            Button {
                                copyNewCodes()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: copiedToClipboard ? "checkmark.circle.fill" : "doc.on.doc")
                                    Text(copiedToClipboard ? "Copied!" : "Copy All Codes")
                                        .font(.systemScaled(15, weight: .semibold))
                                }
                                .foregroundStyle(copiedToClipboard ? .green : .white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(copiedToClipboard ? Color.green : Color.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(20)
                        .background(Color.green.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    } else {
                        // Current count status
                        VStack(spacing: 12) {
                            if let count = twoFactorService.backupCodesRemaining {
                                HStack(spacing: 10) {
                                    Image(systemName: count <= 2 ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                                        .foregroundStyle(count <= 2 ? .orange : .green)
                                    Text("\(count) of 6 codes remaining")
                                        .font(.systemScaled(16, weight: .semibold))
                                        .foregroundStyle(count <= 2 ? .orange : .primary)
                                    Spacer()
                                }
                                .padding()
                                .background(Color(count <= 2 ? .systemOrange : .systemGreen).opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            Text("You cannot view existing codes — they are stored securely and never shown after creation. Generate new codes to replace them.")
                                .font(.systemScaled(13))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal)
                    }

                    // Regenerate button
                    if !hasNewCodes {
                        Button {
                            showConfirmRegenerate = true
                        } label: {
                            HStack(spacing: 8) {
                                if isRegenerating {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text(isRegenerating ? "Generating..." : "Generate New Codes")
                                    .font(.systemScaled(15, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(isRegenerating)
                        .padding(.horizontal)
                    }

                    Color.clear.frame(height: 20)
                }
            }
            .navigationTitle("Backup Codes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Replace All Backup Codes?", isPresented: $showConfirmRegenerate) {
                Button("Cancel", role: .cancel) { }
                Button("Generate New", role: .destructive) {
                    Task { await regenerateCodes() }
                }
            } message: {
                Text("Your existing backup codes will be permanently invalidated and replaced with 6 new codes.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                if let msg = errorMessage { Text(msg) }
            }
        }
    }

    private func regenerateCodes() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        isRegenerating = true
        do {
            let codes = try await twoFactorService.regenerateBackupCodes(userId: userId)
            await MainActor.run {
                newCodes = codes
                isRegenerating = false
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            }
        } catch {
            await MainActor.run {
                isRegenerating = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func copyNewCodes() {
        let text = "AMEN Backup Recovery Codes\n\n\(newCodes.joined(separator: "\n"))\n\nKeep these codes safe. Each can only be used once."
        UIPasteboard.general.string = text
        withAnimation { copiedToClipboard = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { withAnimation { copiedToClipboard = false } }
        }
    }
}

// MARK: - Preview

#Preview {
    TwoFactorAuthView()
}

//
//  AmenPhoneAuthView.swift
//  AMENAPP
//
//  Phone number authentication — two-step flow (entry + OTP verification).
//  Visual language: MinimalAuthenticationView (white/light, glass card).
//  Does NOT use AuthenticationViewModel. Calls FirebaseAuth directly.
//

import SwiftUI
import FirebaseAuth

// MARK: - Country Code Model

private struct CountryCode: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let dialCode: String
    let flag: String
}

private let countryCodes: [CountryCode] = [
    CountryCode(name: "United States",    dialCode: "+1",   flag: "🇺🇸"),
    CountryCode(name: "Canada",           dialCode: "+1",   flag: "🇨🇦"),
    CountryCode(name: "United Kingdom",   dialCode: "+44",  flag: "🇬🇧"),
    CountryCode(name: "Australia",        dialCode: "+61",  flag: "🇦🇺"),
    CountryCode(name: "Germany",          dialCode: "+49",  flag: "🇩🇪"),
    CountryCode(name: "France",           dialCode: "+33",  flag: "🇫🇷"),
    CountryCode(name: "Brazil",           dialCode: "+55",  flag: "🇧🇷"),
    CountryCode(name: "India",            dialCode: "+91",  flag: "🇮🇳"),
    CountryCode(name: "Mexico",           dialCode: "+52",  flag: "🇲🇽"),
    CountryCode(name: "Nigeria",          dialCode: "+234", flag: "🇳🇬"),
    CountryCode(name: "South Africa",     dialCode: "+27",  flag: "🇿🇦"),
    CountryCode(name: "Kenya",            dialCode: "+254", flag: "🇰🇪"),
    CountryCode(name: "Ghana",            dialCode: "+233", flag: "🇬🇭"),
]

// MARK: - Step Enum

private enum PhoneAuthStep {
    case phoneEntry
    case otpEntry
}

// MARK: - AmenPhoneAuthView

struct AmenPhoneAuthView: View {

    // MARK: State

    @State private var step: PhoneAuthStep = .phoneEntry

    // Phone entry
    @State private var selectedCountry: CountryCode = countryCodes[0]
    @State private var phoneDigits: String = ""

    // OTP entry
    @State private var otpCode: String = ""
    @State private var verificationID: String = ""

    // Resend timer
    @State private var resendCountdown: Int = 60
    @State private var resendTimer: Timer? = nil

    // UI
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var appeared: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Computed

    private var fullPhoneNumber: String {
        "\(selectedCountry.dialCode)\(phoneDigits.trimmingCharacters(in: .whitespaces))"
    }

    private var canSendCode: Bool {
        phoneDigits.filter(\.isNumber).count >= 7
    }

    private var canVerify: Bool {
        otpCode.filter(\.isNumber).count == 6
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                navBar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 28)

                        wordmark

                        Spacer().frame(height: 28)

                        mainCard
                            .padding(.horizontal, 20)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 18)
                            .animation(
                                .spring(response: 0.50, dampingFraction: 0.82).delay(0.05),
                                value: appeared
                            )

                        Spacer().frame(height: 60)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.50).delay(0.05)) {
                appeared = true
            }
        }
    }

    // MARK: - Nav Bar

    private var navBar: some View {
        HStack {
            Button {
                if step == .otpEntry {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        step = .phoneEntry
                        errorMessage = nil
                        otpCode = ""
                        stopResendTimer()
                    }
                } else {
                    dismiss()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                        .font(.systemScaled(15, weight: .regular))
                    Text("Back")
                        .font(.systemScaled(15, weight: .regular))
                }
                .foregroundStyle(Color(white: 0.30))
            }
            .accessibilityLabel(step == .otpEntry ? "Back to phone entry" : "Back")

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.systemScaled(14, weight: .regular))
                    .foregroundStyle(Color(white: 0.40))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(white: 0.92)))
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Wordmark

    private var wordmark: some View {
        Text("AMEN")
            .font(.systemScaled(20, weight: .light))
            .tracking(6)
            .foregroundStyle(Color(white: 0.62))
    }

    // MARK: - Main Glass Card

    private var mainCard: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Error banner
            if let errorMessage {
                PhoneAuthErrorBanner(message: errorMessage)
                    .padding(.bottom, 20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Step content — animated swap
            Group {
                if step == .phoneEntry {
                    phoneEntryContent
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .leading)),
                                removal: .opacity.combined(with: .move(edge: .leading))
                            )
                        )
                } else {
                    otpEntryContent
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity.combined(with: .move(edge: .trailing))
                            )
                        )
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: step)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    reduceTransparency
                        ? AnyShapeStyle(Color(.systemBackground))
                        : AnyShapeStyle(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.60), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 12)
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 3)
    }

    // MARK: - Step 1: Phone Entry

    private var phoneEntryContent: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Icon block
            phoneIconBlock(systemName: "phone.fill")

            Spacer().frame(height: 20)

            Text("Your phone\nnumber.")
                .font(.systemScaled(32, weight: .light))
                .foregroundStyle(.primary)
                .lineSpacing(2)

            Spacer().frame(height: 10)

            Text("We'll send a verification code to confirm it's you.")
                .font(.systemScaled(15, weight: .regular))
                .foregroundStyle(Color(white: 0.50))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 28)

            // Phone input row
            VStack(alignment: .leading, spacing: 6) {
                Text("PHONE NUMBER")
                    .font(.systemScaled(11, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Color(white: 0.42))

                HStack(spacing: 10) {
                    // Country code picker
                    Menu {
                        ForEach(countryCodes) { country in
                            Button {
                                selectedCountry = country
                            } label: {
                                Text("\(country.flag) \(country.name)  \(country.dialCode)")
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedCountry.flag)
                                .font(.systemScaled(18, weight: .regular))
                            Text(selectedCountry.dialCode)
                                .font(.systemScaled(15, weight: .medium))
                                .foregroundStyle(Color(white: 0.12))
                            Image(systemName: "chevron.down")
                                .font(.systemScaled(11, weight: .medium))
                                .foregroundStyle(Color(white: 0.42))
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(white: 0.86), lineWidth: 1)
                                )
                        )
                    }
                    .accessibilityLabel("Country code: \(selectedCountry.name) \(selectedCountry.dialCode)")

                    // Digits field
                    TextField("Phone number", text: $phoneDigits)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber) // B-02: number autofill
                        .font(.systemScaled(16, weight: .regular))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Phone number") // E-03
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(white: 0.86), lineWidth: 1)
                                )
                        )
                        .frame(maxWidth: .infinity)
                }
            }

            Spacer().frame(height: 28)

            // CTA button
            Button {
                handleSendCode()
            } label: {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Text("Send Code →")
                            .font(.systemScaled(15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(canSendCode ? Color.black : Color(white: 0.72))
                )
                .animation(.amenEaseQuick, value: canSendCode)
            }
            .disabled(isLoading || !canSendCode)
            .accessibilityHint(canSendCode ? "Sends a 6-digit code to your phone" : "Enter at least 7 digits to continue")
        }
    }

    // MARK: - Step 2: OTP Entry

    private var otpEntryContent: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Icon block
            phoneIconBlock(systemName: "message.badge.filled.fill")

            Spacer().frame(height: 20)

            Text("Enter the\ncode.")
                .font(.systemScaled(32, weight: .light))
                .foregroundStyle(.primary)
                .lineSpacing(2)

            Spacer().frame(height: 10)

            Text("We sent a 6-digit code to \(fullPhoneNumber)")
                .font(.systemScaled(15, weight: .regular))
                .foregroundStyle(Color(white: 0.50))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 28)

            // OTP field
            VStack(alignment: .leading, spacing: 6) {
                Text("VERIFICATION CODE")
                    .font(.systemScaled(11, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Color(white: 0.42))

                TextField("••••••", text: $otpCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode) // B-01: enables SMS code autofill
                    .font(.system(.title2, design: .monospaced).weight(.medium))
                    .multilineTextAlignment(.center)
                    .tracking(8)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("Verification code") // E-03
                    .accessibilityHint("Enter the 6-digit code sent by text message")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(white: 0.86), lineWidth: 1)
                            )
                    )
                    .onChange(of: otpCode) { _, newValue in
                        // Strip non-digits and cap at 6
                        let digits = newValue.filter(\.isNumber)
                        let capped = String(digits.prefix(6))
                        if capped != newValue { otpCode = capped }
                        // Auto-verify when 6 digits entered
                        if capped.count == 6 {
                            handleVerify()
                        }
                    }
            }

            Spacer().frame(height: 28)

            // CTA button
            Button {
                handleVerify()
            } label: {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Text("Verify & Sign In ✓")
                            .font(.systemScaled(15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(canVerify ? Color.black : Color(white: 0.72))
                )
                .animation(.amenEaseQuick, value: canVerify)
            }
            .disabled(isLoading || !canVerify)

            Spacer().frame(height: 16)

            // Resend row
            resendRow
        }
    }

    // MARK: - Resend Row

    private var resendRow: some View {
        HStack {
            Spacer()
            if resendCountdown > 0 {
                Text("Resend code in \(resendCountdown)s")
                    .font(.systemScaled(13, weight: .regular))
                    .foregroundStyle(Color(white: 0.52))
                    .monospacedDigit()
            } else {
                Button {
                    otpCode = ""
                    errorMessage = nil
                    handleSendCode()
                } label: {
                    Text("Resend code")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(Color(white: 0.12))
                        .underline()
                }
            }
            Spacer()
        }
    }

    // MARK: - Icon Block

    private func phoneIconBlock(systemName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black)
                .frame(width: 52, height: 52)
                .shadow(color: .black.opacity(0.20), radius: 8, x: 0, y: 4)

            Image(systemName: systemName)
                .font(.systemScaled(22, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Auth Handlers

    private func handleSendCode() {
        let trimmedDigits = phoneDigits.trimmingCharacters(in: .whitespaces)
        guard trimmedDigits.filter(\.isNumber).count >= 7 else { return }

        isLoading = true
        errorMessage = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        PhoneAuthProvider.provider().verifyPhoneNumber(fullPhoneNumber, uiDelegate: nil) { verificationId, error in
            DispatchQueue.main.async {
                isLoading = false

                if let error = error {
                    let message = phoneErrorMessage(for: error)
                    showError(message)
                    return
                }

                guard let verificationId else {
                    showError("Could not start verification. Please try again.")
                    return
                }

                verificationID = verificationId

                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    step = .otpEntry
                    errorMessage = nil
                }
                startResendTimer()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private func handleVerify() {
        guard canVerify, !isLoading else { return }

        isLoading = true
        errorMessage = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: otpCode
        )

        Auth.auth().signIn(with: credential) { _, error in
            DispatchQueue.main.async {
                isLoading = false

                if let error = error {
                    let message = phoneErrorMessage(for: error)
                    showError(message)
                    return
                }

                UINotificationFeedbackGenerator().notificationOccurred(.success)
                stopResendTimer()
                dismiss()
            }
        }
    }

    // MARK: - Error Mapping

    private func phoneErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        let code = nsError.code
        let description = nsError.localizedDescription

        // Map by Firebase error code
        switch code {
        case 17010:
            return "Too many attempts. Please wait and try again."
        case 17042, 17044:
            return "Invalid phone number. Check the number and try again."
        case 17045:
            return "Invalid verification code. Please check and re-enter."
        default:
            break
        }

        // Map by localizedDescription string patterns
        if description.contains("INVALID_PHONE_NUMBER") {
            return "Invalid phone number. Check the number and try again."
        }
        if description.contains("INVALID_CODE") || description.contains("INVALID_VERIFICATION_CODE") {
            return "Invalid verification code. Please check and re-enter."
        }
        if description.contains("TOO_MANY_REQUESTS") {
            return "Too many attempts. Please wait and try again."
        }
        if description.contains("SESSION_EXPIRED") || description.contains("CODE_EXPIRED") {
            return "The verification code expired. Please request a new one."
        }

        return description
    }

    private func showError(_ message: String) {
        withAnimation(.amenEaseQuick) {
            errorMessage = message
        }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    // MARK: - Resend Timer

    private func startResendTimer() {
        resendCountdown = 60
        stopResendTimer()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            DispatchQueue.main.async {
                if resendCountdown > 0 {
                    resendCountdown -= 1
                } else {
                    timer.invalidate()
                    resendTimer = nil
                }
            }
        }
    }

    private func stopResendTimer() {
        resendTimer?.invalidate()
        resendTimer = nil
    }
}

// MARK: - Phone Auth Error Banner

private struct PhoneAuthErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.systemScaled(14, weight: .regular))

            Text(message)
                .font(.systemScaled(13, weight: .regular))
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(Color(red: 0.78, green: 0.18, blue: 0.18))
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.78, green: 0.18, blue: 0.18).opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(red: 0.78, green: 0.18, blue: 0.18).opacity(0.20), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}

// MARK: - Preview

#Preview {
    AmenPhoneAuthView()
}

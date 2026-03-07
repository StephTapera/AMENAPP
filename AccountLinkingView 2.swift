//
//  AccountLinkingView.swift
//  AMENAPP
//
//  Account linking management - add or remove sign-in methods
//

import SwiftUI
import AuthenticationServices
import CryptoKit
import FirebaseAuth

struct AccountLinkingView: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var linkedProviders: [String] = []
    @State private var showUnlinkConfirmation = false
    @State private var providerToUnlink: String?
    @State private var appleNonce: String?
    @State private var appleLinkingCoordinator: AppleLinkingCoordinator?
    @State private var showPhoneLinking = false
    @State private var phoneNumber = ""
    @State private var showPhoneVerification = false
    @State private var verificationCode = ""
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Link multiple sign-in methods to your account for easier access and added security.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Linked Accounts")
                }
                
                // Email/Password
                if linkedProviders.contains("password") {
                    Section {
                        HStack {
                            Image(systemName: "envelope.fill")
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Email & Password")
                                    .font(.system(size: 16, weight: .medium))
                                
                                if let email = Auth.auth().currentUser?.email {
                                    Text(email)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Text("Linked")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        .padding(.vertical, 8)
                    }
                }

                // Phone
                Section {
                    if linkedProviders.contains("phone") {
                        HStack {
                            Image(systemName: "phone.fill")
                                .foregroundStyle(.green)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Phone Number")
                                    .font(.system(size: 16, weight: .medium))

                                if let phoneNumber = Auth.auth().currentUser?.phoneNumber {
                                    Text(phoneNumber)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Button {
                                providerToUnlink = "phone"
                                showUnlinkConfirmation = true
                            } label: {
                                Text("Unlink")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 8)
                    } else {
                        Button {
                            showPhoneLinking = true
                        } label: {
                            HStack {
                                Image(systemName: "phone.fill")
                                    .foregroundStyle(.gray)
                                    .frame(width: 24)

                                Text("Link Phone Number")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.primary)

                                Spacer()

                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                            .padding(.vertical, 8)
                        }
                        .disabled(viewModel.isLoading)
                    }
                }

                // Google
                Section {
                    if linkedProviders.contains("google.com") {
                        HStack {
                            Image(systemName: "g.circle.fill")
                                .foregroundStyle(.red)
                                .frame(width: 24)
                            
                            Text("Google")
                                .font(.system(size: 16, weight: .medium))
                            
                            Spacer()
                            
                            Button {
                                providerToUnlink = "google.com"
                                showUnlinkConfirmation = true
                            } label: {
                                Text("Unlink")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 8)
                    } else {
                        Button {
                            Task {
                                await viewModel.linkGoogleAccount()
                                refreshLinkedProviders()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "g.circle.fill")
                                    .foregroundStyle(.gray)
                                    .frame(width: 24)
                                
                                Text("Link Google Account")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                            .padding(.vertical, 8)
                        }
                        .disabled(viewModel.isLoading)
                    }
                }
                
                // Apple
                Section {
                    if linkedProviders.contains("apple.com") {
                        HStack {
                            Image(systemName: "apple.logo")
                                .foregroundStyle(.black)
                                .frame(width: 24)
                            
                            Text("Apple")
                                .font(.system(size: 16, weight: .medium))
                            
                            Spacer()
                            
                            Button {
                                providerToUnlink = "apple.com"
                                showUnlinkConfirmation = true
                            } label: {
                                Text("Unlink")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 8)
                    } else {
                        Button {
                            handleAppleLinking()
                        } label: {
                            HStack {
                                Image(systemName: "apple.logo")
                                    .foregroundStyle(.gray)
                                    .frame(width: 24)
                                
                                Text("Link Apple Account")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                            .padding(.vertical, 8)
                        }
                        .disabled(viewModel.isLoading)
                    }
                }
                
                // Info section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(.green)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enhanced Security")
                                    .font(.system(size: 14, weight: .semibold))
                                
                                Text("Multiple sign-in methods make your account more secure and accessible")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "key.fill")
                                .foregroundStyle(.blue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Flexible Access")
                                    .font(.system(size: 14, weight: .semibold))
                                
                                Text("Sign in with any linked method - email, phone, Google, or Apple")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Linked Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                refreshLinkedProviders()
            }
            .alert("Unlink Account?", isPresented: $showUnlinkConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Unlink", role: .destructive) {
                    if let provider = providerToUnlink {
                        Task {
                            await viewModel.unlinkProvider(provider)
                            refreshLinkedProviders()
                        }
                    }
                }
            } message: {
                Text("Are you sure you want to unlink this sign-in method? You can always link it again later.")
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
            .sheet(isPresented: $showPhoneLinking) {
                PhoneLinkingSheet(
                    phoneNumber: $phoneNumber,
                    showVerification: $showPhoneVerification,
                    onSendCode: {
                        Task {
                            await viewModel.linkPhoneAccount(phoneNumber: phoneNumber)
                        }
                    }
                )
                .environmentObject(viewModel)
            }
            .sheet(isPresented: $showPhoneVerification) {
                PhoneVerificationSheet(
                    verificationCode: $verificationCode,
                    phoneNumber: phoneNumber,
                    onVerify: {
                        Task {
                            let success = await viewModel.completeLinkPhoneAccount(verificationCode: verificationCode)
                            if success {
                                showPhoneVerification = false
                                showPhoneLinking = false
                                refreshLinkedProviders()
                            }
                        }
                    },
                    onResend: {
                        Task {
                            await viewModel.linkPhoneAccount(phoneNumber: phoneNumber)
                        }
                    }
                )
                .environmentObject(viewModel)
            }
        }
    }
    
    private func refreshLinkedProviders() {
        linkedProviders = viewModel.getLinkedProviders()
    }
    
    private func handleAppleLinking() {
        // Generate nonce
        let nonce = randomNonceString()
        appleNonce = nonce
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        let coordinator = AppleLinkingCoordinator(
            nonce: nonce,
            viewModel: viewModel,
            onSuccess: {
                refreshLinkedProviders()
            }
        )
        // Store coordinator in @State so it isn't immediately deallocated (delegate is weak)
        appleLinkingCoordinator = coordinator
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = coordinator
        authorizationController.performRequests()
    }
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            // Fallback: use UUID-based entropy if SecRandomCopyBytes fails (should never happen on-device)
            print("⚠️ SecRandomCopyBytes failed (\(errorCode)), using UUID fallback for nonce")
            return UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        
        return String(nonce)
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
}

// MARK: - Apple Linking Coordinator

class AppleLinkingCoordinator: NSObject, ASAuthorizationControllerDelegate {
    let nonce: String
    let viewModel: AuthenticationViewModel
    let onSuccess: () -> Void
    
    init(nonce: String, viewModel: AuthenticationViewModel, onSuccess: @escaping () -> Void) {
        self.nonce = nonce
        self.viewModel = viewModel
        self.onSuccess = onSuccess
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                print("❌ Apple Sign In failed: Unable to fetch identity token")
                return
            }
            
            await viewModel.linkAppleAccount(
                idToken: idTokenString,
                nonce: nonce,
                fullName: appleIDCredential.fullName
            )
            
            onSuccess()
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("❌ Apple linking error: \(error.localizedDescription)")
    }
}

// MARK: - Phone Linking Sheet

struct PhoneLinkingSheet: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    @Environment(\.dismiss) var dismiss
    @Binding var phoneNumber: String
    @Binding var showVerification: Bool
    let onSendCode: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "phone.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                    .padding(.top, 32)

                VStack(spacing: 8) {
                    Text("Link Phone Number")
                        .font(.title2.bold())

                    Text("We'll send you a verification code")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Phone Number")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("+1 (555) 123-4567", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                Button {
                    onSendCode()
                    showVerification = true
                } label: {
                    Text("Send Verification Code")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(phoneNumber.isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(12)
                }
                .disabled(phoneNumber.isEmpty || viewModel.isLoading)
                .padding(.horizontal)

                Spacer()
            }
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

// MARK: - Phone Verification Sheet

struct PhoneVerificationSheet: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    @Environment(\.dismiss) var dismiss
    @Binding var verificationCode: String
    let phoneNumber: String
    let onVerify: () -> Void
    let onResend: () -> Void

    @State private var resendTimer = 60
    @State private var canResend = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                    .padding(.top, 32)

                VStack(spacing: 8) {
                    Text("Verify Phone Number")
                        .font(.title2.bold())

                    Text("Enter the code sent to")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(phoneNumber)
                        .font(.subheadline.bold())
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Verification Code")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("000000", text: $verificationCode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 24, weight: .semibold))
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                Button {
                    onVerify()
                } label: {
                    Text("Verify")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(verificationCode.count == 6 ? Color.blue : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(verificationCode.count != 6 || viewModel.isLoading)
                .padding(.horizontal)

                Button {
                    if canResend {
                        onResend()
                        resendTimer = 60
                        canResend = false
                        startResendTimer()
                    }
                } label: {
                    if canResend {
                        Text("Resend Code")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    } else {
                        Text("Resend in \(resendTimer)s")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!canResend)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                startResendTimer()
            }
        }
    }

    private func startResendTimer() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if resendTimer > 0 {
                resendTimer -= 1
            } else {
                canResend = true
                timer.invalidate()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AccountLinkingView()
        .environmentObject(AuthenticationViewModel())
}

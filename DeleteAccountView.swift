//
//  DeleteAccountView.swift
//  AMENAPP
//
//  Full account deletion flow per Apple App Store Guideline 5.1.1.
//

import SwiftUI
import FirebaseAuth
import AuthenticationServices
import CryptoKit

struct DeleteAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var deletionService = AccountDeletionService.shared
    @EnvironmentObject private var authViewModel: AuthenticationViewModel

    // Confirmation text
    @State private var confirmText = ""
    var isConfirmed: Bool { confirmText == "DELETE" }

    // Re-auth state
    @State private var showReauthSheet = false
    @State private var password = ""
    @State private var reauthError: String?

    // Deletion state
    @State private var isDeleting = false
    @State private var deletionError: String?
    @State private var showError = false
    @FocusState private var confirmFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Warning icon
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.red)
                        .padding(.top, 32)

                    Text("Delete Your Account")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                }

                // What gets deleted
                VStack(alignment: .leading, spacing: 12) {
                    Text("This will permanently delete:")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 8) {
                        DeletionBullet("Your profile and posts")
                        DeletionBullet("Your prayer requests and testimonies")
                        DeletionBullet("Your messages and conversations")
                        DeletionBullet("Your mentorship relationships")
                        DeletionBullet("Your church notes and saved items")
                        DeletionBullet("All personal data from AMEN servers")
                    }

                    Text("This action is permanent and cannot be undone.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.red.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.red.opacity(0.18), lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 20)

                // Confirmation text field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Type DELETE to confirm")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextField("", text: $confirmText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .focused($confirmFieldFocused)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    confirmText.isEmpty ? Color.clear :
                                    isConfirmed ? Color.red.opacity(0.6) : Color.orange.opacity(0.4),
                                    lineWidth: 1
                                )
                        )
                }
                .padding(.horizontal, 20)

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        confirmFieldFocused = false
                        triggerDeletion()
                    } label: {
                        Group {
                            if isDeleting {
                                HStack(spacing: 8) {
                                    ProgressView().tint(.white)
                                    Text("Deleting…")
                                }
                            } else {
                                Text("Delete My Account")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isConfirmed ? Color.red : Color.red.opacity(0.3))
                        )
                    }
                    .disabled(!isConfirmed || isDeleting)
                    .padding(.horizontal, 20)

                    Button("Cancel") { dismiss() }
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 40)
            }
        }
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showReauthSheet) {
            ReauthenticationSheet(
                providerID: AccountDeletionService.shared.currentProviderID ?? "password",
                password: $password,
                error: $reauthError
            ) { success in
                if success {
                    showReauthSheet = false
                    Task { await performDeletion() }
                }
            }
        }
        .alert("Deletion Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deletionError ?? "An unexpected error occurred. Please try again.")
        }
    }

    // MARK: - Helpers

    private func triggerDeletion() {
        // Firebase requires re-auth before account deletion
        showReauthSheet = true
    }

    private func performDeletion() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isDeleting = true
        do {
            try await AccountDeletionService.shared.deleteAccount(userId: uid)
            // Sign out and return to root
            authViewModel.signOut()
        } catch {
            deletionError = error.localizedDescription
            showError = true
        }
        isDeleting = false
    }
}

// MARK: - Supporting Views

private struct DeletionBullet: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("·").foregroundStyle(.red)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ReauthenticationSheet: View {
    let providerID: String
    @Binding var password: String
    @Binding var error: String?
    let onComplete: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @FocusState private var passwordFocused: Bool

    private var isApple: Bool { providerID == "apple.com" }
    private var isGoogle: Bool { providerID == "google.com" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 40))
                        .foregroundStyle(.primary)
                        .padding(.top, 32)
                    Text("Confirm Your Identity")
                        .font(.title3.bold())
                    Text("For security, please verify your identity before deleting your account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                if isApple {
                    // Apple re-auth
                    Button {
                        Task { await reauthWithApple() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.logo")
                            Text("Continue with Apple")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black))
                    }
                    .padding(.horizontal, 24)
                } else if isGoogle {
                    Text("Please sign in with Google again to confirm.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                } else {
                    // Email/password
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter your password")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .focused($passwordFocused)
                    }
                    .padding(.horizontal, 24)

                    if let err = error {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 24)
                    }

                    Button {
                        Task { await reauthWithPassword() }
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Confirm")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(password.isEmpty ? Color.accentColor.opacity(0.4) : Color.accentColor)
                        )
                    }
                    .disabled(password.isEmpty || isLoading)
                    .padding(.horizontal, 24)
                }

                Spacer()
            }
            .navigationTitle("Verify Identity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onComplete(false)
                    }
                }
            }
            .onAppear {
                if !isApple && !isGoogle { passwordFocused = true }
            }
        }
        .presentationDetents([.medium])
    }

    private func reauthWithPassword() async {
        guard let email = Auth.auth().currentUser?.email else { return }
        isLoading = true
        error = nil
        do {
            try await AccountDeletionService.shared.reauthenticateWithPassword(
                email: email, password: password
            )
            onComplete(true)
        } catch {
            self.error = "Incorrect password. Please try again."
        }
        isLoading = false
    }

    private func reauthWithApple() async {
        isLoading = true
        error = nil
        // Generate cryptographically secure nonce
        var randomBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let rawNonce = String(randomBytes.map { charset[Int($0) % charset.count] })
        let hashedNonce = SHA256.hash(data: Data(rawNonce.utf8))
            .compactMap { String(format: "%02x", $0) }.joined()

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = []
        request.nonce = hashedNonce

        let controller = ASAuthorizationController(authorizationRequests: [request])
        let delegate = AppleReauthDelegate(rawNonce: rawNonce) { result in
            Task { @MainActor in
                switch result {
                case .success(let credential):
                    do {
                        let firebaseCredential = OAuthProvider.appleCredential(
                            withIDToken: credential.identityToken.flatMap { String(data: $0, encoding: .utf8) } ?? "",
                            rawNonce: rawNonce,
                            fullName: credential.fullName
                        )
                        try await Auth.auth().currentUser?.reauthenticate(with: firebaseCredential)
                        self.onComplete(true)
                    } catch {
                        self.error = "Apple re-authentication failed. Please try again."
                        self.onComplete(false)
                    }
                case .failure:
                    self.error = "Apple sign-in was cancelled or failed."
                    self.onComplete(false)
                }
                self.isLoading = false
            }
        }
        controller.delegate = delegate
        // Retain delegate for duration of presentation
        objc_setAssociatedObject(controller, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        controller.performRequests()
    }
}

// MARK: - Apple Re-auth Delegate

private final class AppleReauthDelegate: NSObject, ASAuthorizationControllerDelegate {
    private let rawNonce: String
    private let completion: (Result<ASAuthorizationAppleIDCredential, Error>) -> Void

    init(rawNonce: String, completion: @escaping (Result<ASAuthorizationAppleIDCredential, Error>) -> Void) {
        self.rawNonce = rawNonce
        self.completion = completion
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            completion(.success(credential))
        } else {
            completion(.failure(NSError(domain: "AppleReauth", code: -1,
                                       userInfo: [NSLocalizedDescriptionKey: "Invalid credential type"])))
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        completion(.failure(error))
    }
}

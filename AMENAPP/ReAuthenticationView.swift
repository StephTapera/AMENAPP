//
//  ReAuthenticationView.swift
//  AMENAPP
//
//  Require recent password entry before sensitive actions
//

import SwiftUI
import FirebaseAuth

struct ReAuthenticationView: View {
    @Environment(\.dismiss) var dismiss
    let action: SensitiveAction
    let onSuccess: () -> Void
    
    @State private var password = ""
    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @FocusState private var isPasswordFocused: Bool
    
    enum SensitiveAction {
        case changePassword
        case changeEmail
        case changePhone
        case disableMFA
        case deleteAccount
        case deactivateAccount
        case revokeAllSessions
        case downloadData
        
        var title: String {
            switch self {
            case .changePassword: return "Change Password"
            case .changeEmail: return "Change Email"
            case .changePhone: return "Change Phone"
            case .disableMFA: return "Disable Two-Factor Auth"
            case .deleteAccount: return "Delete Account"
            case .deactivateAccount: return "Deactivate Account"
            case .revokeAllSessions: return "Log Out All Devices"
            case .downloadData: return "Download Your Data"
            }
        }
        
        var description: String {
            switch self {
            case .changePassword, .changeEmail, .changePhone:
                return "For your security, please confirm your password to continue."
            case .disableMFA:
                return "Disabling two-factor authentication will make your account less secure. Confirm your password to continue."
            case .deleteAccount:
                return "This is a permanent action. Please confirm your password to proceed with account deletion."
            case .deactivateAccount:
                return "Confirm your password to temporarily deactivate your account."
            case .revokeAllSessions:
                return "You'll be logged out from all devices except this one. Confirm your password to continue."
            case .downloadData:
                return "Confirm your password to download your personal data."
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: "lock.shield.fill")
                            .font(.systemScaled(28))
                            .foregroundStyle(.orange)
                    }
                    
                    Text("Confirm Your Password")
                        .font(AMENFont.bold(20))
                    
                    Text(action.description)
                        .font(AMENFont.regular(15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 40)
                
                // Password field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Password")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.secondary)
                    
                    SecureField("Enter your password", text: $password)
                        .font(AMENFont.regular(16))
                        .focused($isPasswordFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .onSubmit {
                            Task {
                                await authenticate()
                            }
                        }
                }
                .padding(.horizontal, 20)
                
                // Error message
                if let error = errorMessage {
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
                
                // Confirm button
                Button {
                    Task {
                        await authenticate()
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue)
                            .frame(height: 50)
                        
                        if isAuthenticating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Confirm")
                                .font(AMENFont.semiBold(16))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .disabled(password.isEmpty || isAuthenticating)
                .opacity(password.isEmpty ? 0.5 : 1.0)
                .padding(.horizontal, 20)
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                isPasswordFocused = true
            }
        }
    }
    
    private func authenticate() async {
        guard let user = Auth.auth().currentUser,
              let email = user.email else {
            errorMessage = "Unable to verify user"
            return
        }
        
        isAuthenticating = true
        errorMessage = nil
        
        do {
            let credential = EmailAuthProvider.credential(withEmail: email, password: password)
            try await user.reauthenticate(with: credential)
            
            // Success - call the callback
            onSuccess()
            dismiss()
            
        } catch {
            errorMessage = "Incorrect password. Please try again."
            isAuthenticating = false
        }
    }
}

#Preview {
    ReAuthenticationView(action: .changePassword) {
        print("Authenticated successfully")
    }
}

//
//  SelahAppLockGateView.swift
//  AMENAPP
//
//  Phase 3b — Reflections & Privacy
//  Full-screen App Lock gate that uses Face ID / Touch ID / passcode via
//  LocalAuthentication. The journal is never visible until the user
//  successfully authenticates.
//

import SwiftUI
import LocalAuthentication

struct SelahAppLockGateView: View {

    let onUnlocked: () -> Void
    @State private var authError: String?
    @State private var isAuthenticating: Bool = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // MARK: Lock icon
            Image(systemName: "lock.fill")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, isActive: isAuthenticating)

            // MARK: Title + subtitle
            VStack(spacing: 8) {
                Text("Your reflections are private")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Authenticate to open your journal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // MARK: Unlock button
            Button {
                authenticateWithBiometrics()
            } label: {
                Label("Unlock Journal", systemImage: biometricSystemImage)
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.tint)
            }
            .disabled(isAuthenticating)
            .padding(.horizontal, 40)
            .accessibilityIdentifier("appLock.unlockButton")

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        // MARK: Error alert
        .alert("Authentication Failed", isPresented: Binding(
            get: { authError != nil },
            set: { if !$0 { authError = nil } }
        )) {
            Button("Try Again") {
                authError = nil
                authenticateWithBiometrics()
            }
            .accessibilityIdentifier("appLock.tryAgainButton")

            Button("Cancel", role: .cancel) {
                authError = nil
            }
        } message: {
            if let error = authError {
                Text(error)
            }
        }
        .onAppear {
            authenticateWithBiometrics()
        }
    }

    // MARK: - Biometric auth

    private func authenticateWithBiometrics() {
        let context = LAContext()
        var policyError: NSError?

        isAuthenticating = true

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            isAuthenticating = false
            authError = policyError?.localizedDescription
                ?? "Biometric authentication is not available on this device."
            return
        }

        let reason = "Authenticate to access your private reflections."
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success {
                    onUnlocked()
                } else {
                    let laError = error as? LAError
                    // User-cancelled errors are silent — no alert needed.
                    if laError?.code == .userCancel || laError?.code == .appCancel {
                        return
                    }
                    authError = error?.localizedDescription
                        ?? "Authentication failed. Please try again."
                }
            }
        }
    }

    // MARK: - Biometric icon

    private var biometricSystemImage: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return "lock.open"
        }
        switch context.biometryType {
        case .faceID:    return "faceid"
        case .touchID:   return "touchid"
        case .opticID:   return "opticid"
        default:         return "lock.open"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    SelahAppLockGateView(onUnlocked: {})
}
#endif

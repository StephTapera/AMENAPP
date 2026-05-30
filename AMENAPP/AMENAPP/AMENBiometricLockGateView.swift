// AMENBiometricLockGateView.swift
// AMENAPP
//
// Fullscreen lock gate shown when BiometricAppLockManager.isAppLocked == true.
// Triggers biometric prompt automatically on appear and exposes a manual Unlock
// button for retry. Uses AMEN color tokens (amenGold / amenBlack).

import SwiftUI

struct AMENBiometricLockGateView: View {

    @ObservedObject private var lockManager = BiometricAppLockManager.shared
    private let biometricService = BiometricAuthService.shared

    // Icon for the biometric type currently enrolled
    private var biometricIcon: String {
        switch biometricService.biometricType {
        case .faceID:   return "faceid"
        case .touchID:  return "touchid"
        case .opticID:  return "opticid"
        case .none:     return "lock.fill"
        }
    }

    private var biometricLabel: String {
        switch biometricService.biometricType {
        case .faceID:   return "Unlock with Face ID"
        case .touchID:  return "Unlock with Touch ID"
        case .opticID:  return "Unlock with Optic ID"
        case .none:     return "Unlock AMEN"
        }
    }

    var body: some View {
        ZStack {
            // ── Background ────────────────────────────────────────────────
            AmenTheme.Colors.amenBlack
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── App wordmark / lock icon ──────────────────────────────
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(AmenTheme.Colors.amenGold.opacity(0.12))
                            .frame(width: 120, height: 120)

                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 88, height: 88)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                AmenTheme.Colors.amenGold.opacity(0.5),
                                                AmenTheme.Colors.amenGold.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )

                        Image(systemName: biometricIcon)
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        AmenTheme.Colors.amenGold,
                                        AmenTheme.Colors.amenGold.opacity(0.7)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    Text("AMEN")
                        .font(.system(size: 32, weight: .semibold, design: .default))
                        .tracking(4)
                        .foregroundStyle(Color.white)

                    Text("Your session is locked")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.5))
                }

                Spacer()

                // ── Unlock button ─────────────────────────────────────────
                Button {
                    Task {
                        await BiometricAppLockManager.shared.unlockWithBiometrics()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: biometricIcon)
                            .font(.system(size: 16, weight: .medium))
                        Text(biometricLabel)
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(AmenTheme.Colors.amenBlack)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AmenTheme.Colors.amenGold)
                    )
                    .padding(.horizontal, 32)
                }
                .buttonStyle(.plain)

                Spacer()
                    .frame(height: 48)
            }
        }
        // Auto-trigger biometric prompt as soon as the gate appears
        .onAppear {
            Task {
                await BiometricAppLockManager.shared.unlockWithBiometrics()
            }
        }
    }
}

#Preview {
    AMENBiometricLockGateView()
}

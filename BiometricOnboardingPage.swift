//
//  BiometricOnboardingPage.swift
//  AMENAPP
//
//  Biometric authentication setup during onboarding
//

import SwiftUI
import LocalAuthentication

struct BiometricOnboardingPage: View {
    @Binding var enableBiometric: Bool
    @ObservedObject private var biometricService = BiometricAuthService.shared
    @State private var showingSetupSuccess = false
    @State private var setupFailed = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 32) {
            // Icon - Dynamic based on device capability
            Image(systemName: biometricService.biometricType.icon)
                .font(.system(size: 80))
                .foregroundStyle(.blue.opacity(0.9))
                .symbolEffect(.pulse, options: .repeating, value: enableBiometric)
            
            // Title
            Text("Quick & Secure Sign-In")
                .font(.custom("OpenSans-Bold", size: 28))
                .foregroundStyle(.primary)
            
            // Description
            VStack(spacing: 12) {
                if biometricService.isBiometricAvailable {
                    Text("Use \(biometricService.biometricType.displayName) for instant access")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.secondary)
                    
                    Text("Sign in with just a glance or touch. Your biometric data stays securely on your device and is never shared.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                } else {
                    Text("Biometric authentication not available")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.secondary)
                    
                    Text("Your device doesn't support Face ID or Touch ID, or it hasn't been set up in Settings.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            
            Spacer()
            
            // Biometric Toggle (only if available)
            if biometricService.isBiometricAvailable {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable \(biometricService.biometricType.displayName)")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                                .foregroundStyle(.primary)
                            
                            Text("Recommended for convenience")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $enableBiometric)
                            .labelsHidden()
                            .tint(.blue)
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemBackground))
                    )
                    
                    // Benefits section (shown when enabled)
                    if enableBiometric {
                        VStack(spacing: 16) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundStyle(.green)
                                Text("Security Benefits")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.primary)
                            }
                            
                            VStack(alignment: .leading, spacing: 12) {
                                BenefitRow(
                                    icon: "bolt.fill",
                                    text: "Instant sign-in - no typing required",
                                    color: .orange
                                )
                                
                                BenefitRow(
                                    icon: "lock.shield.fill",
                                    text: "More secure than passwords alone",
                                    color: .green
                                )
                                
                                BenefitRow(
                                    icon: "iphone.gen3",
                                    text: "Data never leaves your device",
                                    color: .blue
                                )
                                
                                BenefitRow(
                                    icon: "key.fill",
                                    text: "You can always use password as backup",
                                    color: .purple
                                )
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.green.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.green.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .transition(.opacity.combined(with: .scale))
                    }
                    
                    // Success feedback
                    if showingSetupSuccess {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Biometric sign-in enabled!")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.green)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.green.opacity(0.1))
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    
                    // Error feedback
                    if setupFailed {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(errorMessage)
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.orange)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.orange.opacity(0.1))
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 24)
            }
            
            Spacer()
        }
        .onChange(of: enableBiometric) { _, newValue in
            if newValue {
                Task {
                    await setupBiometric()
                }
            } else {
                biometricService.disableBiometric()
                showingSetupSuccess = false
                setupFailed = false
            }
        }
    }
    
    private func setupBiometric() async {
        // Test biometric authentication
        let success = await biometricService.authenticateWithPasscodeFallback(
            reason: "Enable biometric sign-in for AMEN"
        )
        
        await MainActor.run {
            if success {
                biometricService.enableBiometric()
                withAnimation {
                    showingSetupSuccess = true
                    setupFailed = false
                }
                
                // Hide success message after 3 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        withAnimation {
                            showingSetupSuccess = false
                        }
                    }
                }
            } else {
                enableBiometric = false
                withAnimation {
                    setupFailed = true
                    errorMessage = "Setup cancelled or failed. You can enable this later in Settings."
                    showingSetupSuccess = false
                }
                
                // Hide error after 5 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    await MainActor.run {
                        withAnimation {
                            setupFailed = false
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        BiometricOnboardingPage(enableBiometric: .constant(false))
    }
}

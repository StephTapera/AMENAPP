//
//  TwoFactorOnboardingView.swift
//  AMENAPP
//
//  2FA setup during onboarding with backup codes
//

import SwiftUI

struct TwoFactorOnboardingView: View {
    @Binding var enable2FA: Bool
    @Binding var backupCodes: [String]
    @State private var showBackupCodes = false
    @State private var copiedToClipboard = false
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                // Icon
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green.opacity(0.9))
                    .padding(.top, 40)
                
                // Title
                Text("Secure Your Account")
                    .font(.custom("OpenSans-Bold", size: 28))
                    .foregroundStyle(.primary)
                
                // Description
                VStack(spacing: 12) {
                    Text("Add an extra layer of security")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.secondary)
                    
                    Text("Two-factor authentication (2FA) protects your account even if someone gets your password.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                // 2FA Toggle
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Two-Factor Authentication")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                                .foregroundStyle(.primary)
                            
                            Text("Recommended for account security")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $enable2FA)
                            .labelsHidden()
                            .tint(.green)
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemBackground))
                    )
                    
                    // Backup codes section (shown when 2FA enabled)
                    if enable2FA {
                        VStack(spacing: 16) {
                            HStack(spacing: 8) {
                                Image(systemName: "key.fill")
                                    .foregroundStyle(.orange)
                                Text("Backup Recovery Codes")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.primary)
                            }
                            
                            Text("Save these codes in a safe place. You'll need them if you lose access to your device.")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            
                            // Backup codes grid
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(backupCodes, id: \.self) { code in
                                    Text(code)
                                        .font(.custom("Menlo", size: 14))
                                        .foregroundStyle(.primary)
                                        .padding(12)
                                        .frame(maxWidth: .infinity)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(.tertiarySystemBackground))
                                        )
                                }
                            }
                            
                            // Copy button
                            Button {
                                copyBackupCodes()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: copiedToClipboard ? "checkmark.circle.fill" : "doc.on.doc")
                                    Text(copiedToClipboard ? "Copied!" : "Copy All Codes")
                                        .font(.custom("OpenSans-SemiBold", size: 14))
                                }
                                .foregroundStyle(copiedToClipboard ? .green : .primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(copiedToClipboard ? Color.green : Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.orange.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.orange.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95)).combined(with: .move(edge: .top)))
                        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: enable2FA)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .onChange(of: enable2FA) { _, newValue in
            // Haptic feedback
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
            
            if newValue && backupCodes.isEmpty {
                // Generate backup codes when 2FA is enabled
                backupCodes = generateBackupCodes()
            } else if !newValue {
                // Clear backup codes when 2FA is disabled
                backupCodes = []
            }
        }
    }
    
    private func generateBackupCodes() -> [String] {
        var codes: [String] = []
        for _ in 0..<6 {
            let code = String(format: "%04d-%04d", Int.random(in: 1000...9999), Int.random(in: 1000...9999))
            codes.append(code)
        }
        return codes
    }
    
    private func copyBackupCodes() {
        let codesText = backupCodes.joined(separator: "\n")
        UIPasteboard.general.string = "AMEN Backup Recovery Codes\n\n\(codesText)\n\nKeep these codes safe. You'll need them if you lose access to your device."
        
        withAnimation {
            copiedToClipboard = true
        }
        
        // Reset after 2 seconds
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation {
                    copiedToClipboard = false
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        TwoFactorOnboardingView(
            enable2FA: .constant(true),
            backupCodes: .constant(["1234-5678", "2345-6789", "3456-7890", "4567-8901", "5678-9012", "6789-0123"])
        )
    }
}

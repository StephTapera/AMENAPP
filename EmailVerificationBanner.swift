//
//  EmailVerificationBanner.swift
//  AMENAPP
//
//  Email verification banner for unverified accounts
//

import SwiftUI
import Combine

struct EmailVerificationBanner: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    @State private var isResending = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Warning icon
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.yellow)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Verify Your Email")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text("Check your inbox for the verification link")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Resend button
                Button {
                    resendVerificationEmail()
                } label: {
                    if isResending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Resend")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.blue)
                    }
                }
                .disabled(isResending)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [
                        Color.yellow.opacity(0.12),
                        Color.orange.opacity(0.08)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(
                Rectangle()
                    .fill(Color.yellow.opacity(0.3))
                    .frame(height: 1),
                alignment: .bottom
            )
        }
    }
    
    private func resendVerificationEmail() {
        isResending = true
        
        Task {
            await viewModel.sendEmailVerification()
            
            // Wait a moment before allowing another resend
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            await MainActor.run {
                isResending = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    EmailVerificationBanner()
        .environmentObject(AuthenticationViewModel())
}

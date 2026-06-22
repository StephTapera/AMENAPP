// BlessAndCloseSheet.swift
// AMENAPP — SabbathMode
//
// Bottom sheet confirming the user's intent to step out of Sabbath.
// Uses COPY OPTION A (the live option — awaiting human sign-off).
// Tone: invitational, never punitive. No shame language.
// requiresConfirm: true (SabbathConfig.ts stepOutPolicy).
// Calls service.enterStepOut() on confirm. Shows alert on error.
//
// BANNED tokens: gold, purple, dark gradients, serif fonts.

import SwiftUI

struct BlessAndCloseSheet: View {
    @ObservedObject var service: SabbathModeService
    @Binding var isPresented: Bool

    @State private var isLoading = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            Capsule()
                .fill(Color(.separator))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .accessibilityHidden(true)

            // COPY OPTION A — "Step out of Sabbath?"
            VStack(alignment: .leading, spacing: 12) {
                Text("Step out of Sabbath?")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("You can return to the full app for the rest of today. Sabbath will resume next week.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            Spacer().frame(height: 28)

            // Buttons
            VStack(spacing: 10) {
                // Primary: Step out
                Button {
                    Task { await handleStepOut() }
                } label: {
                    Group {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Step out")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.primary, in: Capsule())
                    .foregroundStyle(Color(uiColor: .systemBackground))
                }
                .disabled(isLoading)
                .accessibilityLabel("Step out of Sabbath and return to the full app")

                // Secondary: Stay in Sabbath
                Button {
                    isPresented = false
                } label: {
                    Text("Stay in Sabbath")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            Capsule()
                                .strokeBorder(Color(.separator), lineWidth: 1)
                        )
                        .foregroundStyle(.primary)
                }
                .disabled(isLoading)
            }
            .padding(.horizontal, 24)

            // Safe area bottom padding
            Spacer().frame(height: 24)
        }
        .background(Color(.systemBackground))
        .alert("Cannot step out", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func handleStepOut() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await service.enterStepOut()
            isPresented = false
        } catch SabbathStepOutError.alreadySteppedOut {
            errorMessage = "You have already stepped out of Sabbath for today."
            showErrorAlert = true
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }
}

#Preview {
    BlessAndCloseSheet(
        service: SabbathModeService.shared,
        isPresented: .constant(true)
    )
    .presentationDetents([.medium])
}

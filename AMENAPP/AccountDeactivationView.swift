// AccountDeactivationView.swift
// AMEN App
//
// Two-screen deactivation flow:
//   1. AccountDeactivationView  — choose reason, review consequences, confirm
//   2. ReactivationPromptView   — shown when a deactivated user signs back in
//
// Visual language: Threads/Instagram style — white background, black text,
// card-based layout, minimal chrome. Matches the rest of AMEN settings UI.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Deactivation Flow

struct AccountDeactivationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authViewModel: AuthenticationViewModel

    @State private var selectedReason: AccountDeactivationService.DeactivationReason = .takingABreak
    @State private var step: Step = .reason
    @State private var isDeactivating = false
    @State private var showError = false
    @State private var errorMessage = ""

    private enum Step { case reason, confirm }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer().frame(height: 24)

                        switch step {
                        case .reason:  reasonStep
                        case .confirm: confirmStep
                        }

                        Spacer().frame(height: 48)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .navigationTitle("Deactivate Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(AMENFont.semiBold(16))
                }
            }
            .alert("Something went wrong", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Step 1: Reason

    private var reasonStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Why are you deactivating?")
                    .font(AMENFont.bold(22))
                    .foregroundStyle(.primary)
                Text("This helps us improve AMEN. Your answer is private.")
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }

            // Reason picker
            VStack(spacing: 0) {
                ForEach(Array(AccountDeactivationService.DeactivationReason.allCases.enumerated()),
                        id: \.element.id) { idx, reason in
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.75))) {
                            selectedReason = reason
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: reason.icon)
                                .font(.systemScaled(16, weight: .medium))
                                .foregroundStyle(selectedReason == reason ? .white : .secondary)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle().fill(selectedReason == reason
                                        ? Color.primary
                                        : Color(.tertiarySystemBackground))
                                )

                            Text(reason.displayTitle)
                                .font(AMENFont.semiBold(15))
                                .foregroundStyle(.primary)

                            Spacer()

                            if selectedReason == reason {
                                Image(systemName: "checkmark")
                                    .font(.systemScaled(13, weight: .bold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)

                    if idx < AccountDeactivationService.DeactivationReason.allCases.count - 1 {
                        Divider().padding(.leading, 62)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)

            // CTA
            Button {
                withAnimation { step = .confirm }
            } label: {
                Text("Continue")
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(ScaleButtonStyle())
        }
    }

    // MARK: - Step 2: Confirm

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("What happens when\nyou deactivate")
                    .font(AMENFont.bold(22))
                    .foregroundStyle(.primary)
                    .lineSpacing(2)
            }

            // Consequences cards
            VStack(spacing: 0) {
                consequenceRow(
                    icon: "eye.slash",
                    color: Color(red: 0.35, green: 0.50, blue: 0.95),
                    title: "Profile & content hidden",
                    body: "Your profile, posts, prayers, and testimonies won't be visible to anyone."
                )
                Divider().padding(.leading, 56)
                consequenceRow(
                    icon: "person.2.slash",
                    color: Color(red: 0.20, green: 0.62, blue: 0.45),
                    title: "Follows preserved",
                    body: "Your follow relationships are kept. They'll be restored when you come back."
                )
                Divider().padding(.leading, 56)
                consequenceRow(
                    icon: "arrow.clockwise",
                    color: Color(red: 0.55, green: 0.30, blue: 0.90),
                    title: "30-day reactivation window",
                    body: "Sign back in any time within 30 days to instantly restore everything. After 30 days your account is permanently deleted."
                )
                Divider().padding(.leading, 56)
                consequenceRow(
                    icon: "icloud.slash",
                    color: Color(red: 0.90, green: 0.45, blue: 0.15),
                    title: "You'll be signed out",
                    body: "After deactivation you'll be signed out of this device."
                )
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)

            // Deactivate button
            Button {
                Task { await performDeactivation() }
            } label: {
                Group {
                    if isDeactivating {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Deactivating…")
                        }
                    } else {
                        Text("Deactivate Account")
                    }
                }
                .font(AMENFont.semiBold(16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(isDeactivating)

            // Back link
            Button {
                withAnimation { step = .reason }
            } label: {
                Text("Go back")
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(isDeactivating)
        }
    }

    private func consequenceRow(icon: String, color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.systemScaled(15, weight: .medium))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.primary)
                Text(body)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Deactivation Logic

    private func performDeactivation() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isDeactivating = true
        do {
            try await AccountDeactivationService.shared.deactivateAccount(
                userId: uid,
                reason: selectedReason
            )
            // Sign out — auth listener will route to landing screen
            try Auth.auth().signOut()
            authViewModel.signOut()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isDeactivating = false
        }
    }
}

// MARK: - Reactivation Prompt

/// Shown inside ContentView when an authenticated user's account is deactivated.
/// The user is already signed in to Firebase but `authViewModel.isDeactivated = true`.
struct ReactivationPromptView: View {
    @EnvironmentObject private var authViewModel: AuthenticationViewModel

    let status: AccountDeactivationService.DeactivationStatus

    @State private var isReactivating = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo
                VStack(spacing: 14) {
                    Image("amen-logo")
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 52, height: 56)

                    Text("AMEN")
                        .font(.systemScaled(22, weight: .black))
                        .tracking(7)
                        .foregroundStyle(.black)
                }

                Spacer().frame(height: 48)

                // Status card
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.12))
                                .frame(width: 44, height: 44)
                            Image(systemName: "pause.circle.fill")
                                .font(.systemScaled(22))
                                .foregroundStyle(.orange)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Account deactivated")
                                .font(AMENFont.bold(16))
                                .foregroundStyle(.primary)
                            if let days = status.daysRemaining {
                                Text("\(days) day\(days == 1 ? "" : "s") until permanent deletion")
                                    .font(AMENFont.regular(13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    Text("Your profile and content are hidden while your account is deactivated. Tap **Reactivate** to restore everything and continue using AMEN.")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)

                    if let expiresAt = status.expiresAt {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.systemScaled(12))
                                .foregroundStyle(.orange)
                            Text("Auto-deletes \(expiresAt.formatted(.relative(presentation: .named)))")
                                .font(AMENFont.semiBold(13))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1))
                .shadow(color: .black.opacity(0.05), radius: 16, y: 6)

                Spacer().frame(height: 28)

                // Reactivate CTA
                Button {
                    Task { await reactivate() }
                } label: {
                    Group {
                        if isReactivating {
                            HStack(spacing: 10) {
                                ProgressView().tint(.white)
                                Text("Reactivating…")
                            }
                        } else {
                            Text("Reactivate My Account")
                        }
                    }
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(isReactivating)

                Spacer().frame(height: 14)

                // Sign out (different account)
                Button {
                    authViewModel.signOut()
                } label: {
                    Text("Sign out")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isReactivating)

                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .alert("Reactivation failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func reactivate() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isReactivating = true
        do {
            try await AccountDeactivationService.shared.reactivateAccount(userId: uid)
            // Clear the deactivated state — auth listener will route to main content
            await authViewModel.clearDeactivationState()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isReactivating = false
        }
    }
}

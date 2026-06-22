// GuardianLinkInvitationView.swift
// AMENAPP — Child Safety / Guardian Link (finding #44)
//
// Two surfaces:
//   GuardianLinkInvitationView   — minor enters a guardian's email to send an invite.
//   GuardianLinkVerificationView — guardian enters the 6-digit OTP to complete the link.
//
// Gate: AMENFeatureFlags.shared.guardianLinkEnabled (default OFF). Both views render
//        EmptyView when the flag is off.
//
// Design: native glass via amenGlassEffect (iOS 26) with thinMaterial fallback;
//         Motion.adaptive on all animation; Dynamic Type; ≥44pt targets.

import SwiftUI

// MARK: - Invitation (minor-initiated)

struct GuardianLinkInvitationView: View {

    @StateObject private var service = GuardianLinkService.shared
    @ObservedObject private var flags = AMENFeatureFlags.shared
    @Environment(\.dismiss) private var dismiss

    @State private var guardianEmail: String = ""
    @State private var isSubmitting = false
    @State private var sentRequestId: String?
    @State private var errorMessage: String?

    var body: some View {
        if !flags.guardianLinkEnabled {
            EmptyView()
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard

                    if sentRequestId == nil {
                        emailEntryCard
                    } else {
                        confirmationCard
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(.footnote))
                            .foregroundStyle(.red.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Error: \(errorMessage)")
                    }
                }
                .padding(20)
            }
            .navigationTitle("Add a Guardian")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "person.2.badge.gearshape")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Link a parent or guardian")
                .font(.system(.title3, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text("We'll email your guardian a 6-digit code. Once they confirm, they can approve who you message.")
                .font(.system(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
        )
    }

    private var emailEntryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Guardian's email")
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("name@example.com", text: $guardianEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .font(.system(.body))
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .accessibilityLabel("Guardian email address")

            Button(action: submit) {
                HStack {
                    if isSubmitting { ProgressView().tint(.white) }
                    Text(isSubmitting ? "Sending…" : "Send invite")
                        .font(.system(.body, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting || guardianEmail.isEmpty)
            .accessibilityLabel("Send guardian invite")
        }
        .padding(18)
        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
        )
    }

    private var confirmationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Invite sent", systemImage: "checkmark.circle.fill")
                .font(.system(.headline))
                .foregroundStyle(.green)
            Text("We emailed a verification code to your guardian. Ask them to open AMEN and enter it to finish linking.")
                .font(.system(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
        )
    }

    private func submit() {
        guard !isSubmitting else { return }
        errorMessage = nil
        isSubmitting = true
        Task {
            do {
                let id = try await service.requestGuardianLink(guardianEmail: guardianEmail)
                withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.85))) {
                    sentRequestId = id
                }
            } catch {
                errorMessage = (error as? GuardianLinkService.GuardianLinkError)?.errorDescription
                    ?? "Something went wrong. Please try again."
            }
            isSubmitting = false
        }
    }
}

// MARK: - Verification (guardian-initiated)

struct GuardianLinkVerificationView: View {

    let requestId: String

    @StateObject private var service = GuardianLinkService.shared
    @ObservedObject private var flags = AMENFeatureFlags.shared
    @Environment(\.dismiss) private var dismiss

    @State private var code: String = ""
    @State private var isVerifying = false
    @State private var didApprove = false
    @State private var errorMessage: String?

    var body: some View {
        if !flags.guardianLinkEnabled {
            EmptyView()
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard
                    if didApprove {
                        approvedCard
                    } else {
                        codeEntryCard
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(.footnote))
                            .foregroundStyle(.red.opacity(0.85))
                            .accessibilityLabel("Error: \(errorMessage)")
                    }
                }
                .padding(20)
            }
            .navigationTitle("Confirm Guardian Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Enter the code we emailed you")
                .font(.system(.title3, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text("This confirms you're the guardian for this account.")
                .font(.system(.subheadline))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
        )
    }

    private var codeEntryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("000000", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(.title2, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .onChange(of: code) { _, newValue in
                    // Keep only digits, cap at 6.
                    let digits = String(newValue.filter(\.isNumber).prefix(6))
                    if digits != newValue { code = digits }
                }
                .accessibilityLabel("6-digit verification code")

            Button(action: verify) {
                HStack {
                    if isVerifying { ProgressView().tint(.white) }
                    Text(isVerifying ? "Verifying…" : "Confirm link")
                        .font(.system(.body, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isVerifying || code.count != 6)
            .accessibilityLabel("Confirm guardian link")
        }
        .padding(18)
        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
        )
    }

    private var approvedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Guardian link confirmed", systemImage: "checkmark.seal.fill")
                .font(.system(.headline))
                .foregroundStyle(.green)
            Text("You're now linked. You can approve who this account messages from your settings.")
                .font(.system(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
        )
    }

    private func verify() {
        guard !isVerifying else { return }
        errorMessage = nil
        isVerifying = true
        Task {
            do {
                try await service.verifyGuardianLink(requestId: requestId, otp: code)
                withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.85))) {
                    didApprove = true
                }
            } catch {
                errorMessage = (error as? GuardianLinkService.GuardianLinkError)?.errorDescription
                    ?? "Verification failed. Please try again."
            }
            isVerifying = false
        }
    }
}

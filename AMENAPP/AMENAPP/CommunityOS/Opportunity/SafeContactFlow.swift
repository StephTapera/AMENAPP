// SafeContactFlow.swift
// AMEN Community OS — Opportunity OS (A10)
//
// The apply flow that routes through the Amen inbox.
// NEVER shows raw contact info (email, phone, external link).
// All applicant-org contact is mediated through the Amen DM system.
//
// Flow:
//   Step 1 — Confirm: user sees opportunity title + org name, chooses to apply
//   Step 2 — Compose: user writes a brief intro message
//   Step 3 — Sent: confirmation screen
//
// Design rules (C3): system colors only, Color.accentColor for interactive.

import SwiftUI
import FirebaseFunctions
import FirebaseAuth

// MARK: - SafeContactFlow

struct SafeContactFlow: View {

    let opportunityId: String
    let opportunityTitle: String
    let orgName: String

    @Binding var isPresented: Bool

    // MARK: State

    private enum FlowStep {
        case confirm
        case compose
        case sent
        case error(String)
    }

    @State private var step: FlowStep = .confirm
    @State private var introMessage = ""
    @State private var isSending = false

    private let functions = Functions.functions()
    private var currentUserId: String { Auth.auth().currentUser?.uid ?? "" }

    // MARK: Char limit

    private let messageCharLimit = 500

    private var isMessageValid: Bool {
        let trimmed = introMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= messageCharLimit
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch step {
                case .confirm:
                    confirmStep
                case .compose:
                    composeStep
                case .sent:
                    sentStep
                case .error(let message):
                    errorStep(message)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Apply via Amen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .accessibilityLabel("Cancel application")
                }
            }
        }
    }

    // MARK: Step 1 — Confirm

    private var confirmStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Privacy assurance banner
                privacyBanner

                // Opportunity summary
                VStack(alignment: .leading, spacing: 16) {
                    opportunitySummaryCard

                    // What happens next
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What happens when you apply")
                            .font(.headline)
                            .foregroundStyle(Color(uiColor: .label))

                        stepBullet(
                            icon: "envelope.fill",
                            text: "A message is sent through your Amen inbox — no email or phone number is shared."
                        )
                        stepBullet(
                            icon: "person.fill.checkmark",
                            text: "The organization sees your Amen profile name only."
                        )
                        stepBullet(
                            icon: "lock.shield.fill",
                            text: "All follow-up communication stays within Amen."
                        )
                    }
                }
                .padding(.horizontal, 20)

                // Confirm button
                Button {
                    withAnimation(.spring(response: 0.3)) { step = .compose }
                } label: {
                    Text("Continue to Compose Message")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .accessibilityLabel("Continue to compose your application message")
            }
            .padding(.vertical, 24)
        }
    }

    // MARK: Step 2 — Compose

    private var composeStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Reminder banner
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .font(.body)
                    Text("Your message goes through Amen Inbox. Do not include your email, phone, or other personal contact details.")
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .multilineTextAlignment(.leading)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal, 20)

                // Compose area
                VStack(alignment: .leading, spacing: 8) {
                    Text("Introduce yourself")
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: .label))

                    Text("Tell \(orgName) why you're interested in "\(opportunityTitle)".")
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))

                    ZStack(alignment: .topLeading) {
                        if introMessage.isEmpty {
                            Text("Write a brief introduction (e.g. your background, why you're interested)…")
                                .font(.body)
                                .foregroundStyle(Color(uiColor: .placeholderText))
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        TextEditor(text: $introMessage)
                            .font(.body)
                            .frame(minHeight: 140)
                            .scrollContentBackground(.hidden)
                            .onChange(of: introMessage) { _, newVal in
                                if newVal.count > messageCharLimit {
                                    introMessage = String(newVal.prefix(messageCharLimit))
                                }
                            }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )

                    HStack {
                        Spacer()
                        Text("\(introMessage.count)/\(messageCharLimit)")
                            .font(.caption)
                            .foregroundStyle(
                                introMessage.count > messageCharLimit - 50
                                ? Color.orange
                                : Color(uiColor: .secondaryLabel)
                            )
                    }
                }
                .padding(.horizontal, 20)

                // Send button
                Button {
                    Task { await sendApplication() }
                } label: {
                    Group {
                        if isSending {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Send Application via Amen")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isMessageValid && !isSending
                                  ? Color.accentColor
                                  : Color(uiColor: .secondarySystemFill))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isMessageValid || isSending)
                .padding(.horizontal, 20)
                .accessibilityLabel("Send application via Amen Inbox")
                .accessibilityHint("This will send your message through the Amen inbox only.")
            }
            .padding(.vertical, 24)
        }
    }

    // MARK: Step 3 — Sent

    private var sentStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("Application Sent")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color(uiColor: .label))

                Text("Your message was sent to \(orgName) through your Amen inbox. They'll respond through Amen — your personal contact info was never shared.")
                    .font(.body)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button {
                isPresented = false
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .accessibilityLabel("Dismiss")
        }
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Application sent to \(orgName). No personal contact info was shared.")
    }

    // MARK: Error Step

    private func errorStep(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(Color.orange)
                .accessibilityHidden(true)
            Text("Something went wrong")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                step = .compose
            } label: {
                Text("Try Again")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule(style: .continuous).fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }

    // MARK: Supporting Views

    private var privacyBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Safe, private application")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .label))
                Text("Your phone number and email are never shared. All contact goes through Amen Inbox.")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.20), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Safe private application. Phone and email are never shared.")
    }

    private var opportunitySummaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Applying to")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            Text(opportunityTitle)
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
            Text(orgName)
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 3)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Applying to \(opportunityTitle) at \(orgName)")
    }

    private func stepBullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .multilineTextAlignment(.leading)
        }
    }

    // MARK: Send Action

    private func sendApplication() async {
        guard isMessageValid else { return }
        isSending = true
        defer { isSending = false }

        do {
            try await functions.httpsCallable("applyViaInbox").call([
                "opportunityId": opportunityId,
                "applicantId": currentUserId,
                "introMessage": introMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
            await MainActor.run {
                withAnimation(.spring(response: 0.4)) {
                    step = .sent
                }
            }
        } catch {
            await MainActor.run {
                step = .error(error.localizedDescription)
            }
        }
    }
}

// MARK: - Preview

#Preview("Safe Contact Flow") {
    SafeContactFlow(
        opportunityId: "opp_preview_01",
        opportunityTitle: "Youth Group Volunteer Leader",
        orgName: "Grace Community Church",
        isPresented: .constant(true)
    )
}

// BereanDMConsentSheet.swift
// AMENAPP
//
// Shown once before AI safety scanning begins in DMs.
// User must explicitly accept before AI processes their messages.
// H-16 fix: DM content AI consent disclosure UX

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct BereanDMConsentSheet: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // MARK: — Icon + Title
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.12))
                                    .frame(width: 72, height: 72)
                                Image(systemName: "shield.lefthalf.filled")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .accessibilityHidden(true)

                            Text("AI Safety Scanning")
                                .font(.title2)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)

                            Text("To protect our community, AMEN uses AI to scan messages for mental health crisis signals. Here's exactly what that means for your privacy.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        Spacer()
                    }

                    Divider()

                    // MARK: — What We Do
                    VStack(alignment: .leading, spacing: 16) {
                        Label {
                            Text("What AI does in your DMs")
                                .font(.headline)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }

                        bulletRow(
                            icon: "heart.text.square",
                            iconColor: .pink,
                            title: "Crisis signal detection",
                            detail: "Message content is scanned for signs of self-harm, suicidal ideation, or severe distress so we can offer you immediate support resources."
                        )

                        bulletRow(
                            icon: "lock.shield",
                            iconColor: .blue,
                            title: "On-device where possible",
                            detail: "Initial screening runs on your device. Content is only sent to our safety gateway when a potential signal is detected."
                        )

                        bulletRow(
                            icon: "bell.badge",
                            iconColor: .orange,
                            title: "Wellness resources",
                            detail: "If the AI detects a crisis signal, it surfaces crisis hotlines and pastoral care resources — it does not alert anyone without your knowledge."
                        )
                    }

                    Divider()

                    // MARK: — What We Don't Do
                    VStack(alignment: .leading, spacing: 16) {
                        Label {
                            Text("What we never do")
                                .font(.headline)
                        } icon: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }

                        doNotRow(
                            icon: "externaldrive.badge.xmark",
                            text: "Store your DM content for AI training or analysis beyond the safety scan."
                        )

                        doNotRow(
                            icon: "person.2.slash",
                            text: "Share your message content with third parties, advertisers, or other users."
                        )

                        doNotRow(
                            icon: "brain",
                            text: "Use your DM content to train AI models, build profiles, or generate recommendations."
                        )

                        doNotRow(
                            icon: "megaphone.fill",
                            text: "Alert other users, moderators, or your contacts based solely on AI signal detection — only wellness resources are surfaced to you."
                        )
                    }

                    Divider()

                    // MARK: — Privacy Note
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Privacy & Safety Policy")
                                .font(.footnote)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            Text("You can update this preference at any time in Settings → Privacy → AI Safety Scanning. Declining does not restrict your DM access — it simply disables the AI safety layer.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )

                    // MARK: — Action Buttons
                    VStack(spacing: 12) {
                        Button {
                            saveConsent(true)
                            onAccept()
                        } label: {
                            Text("I understand, continue")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .accessibilityLabel("Accept AI safety scanning and continue to DMs")
                        .accessibilityHint("AI will scan your messages for crisis signals. You can change this in Settings later.")

                        Button {
                            saveConsent(false)
                            onDecline()
                        } label: {
                            Text("Not now")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(.secondarySystemBackground))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .accessibilityLabel("Decline AI safety scanning")
                        .accessibilityHint("AI safety scanning will be disabled. You can still send and receive messages normally.")

                        Text("Choosing \"Not now\" disables AI crisis detection in your conversations.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: — Helpers

    @ViewBuilder
    private func bulletRow(icon: String, iconColor: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func doNotRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.red.opacity(0.8))
                .frame(width: 28)
                .accessibilityHidden(true)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: — Persistence

    private func saveConsent(_ accepted: Bool) {
        // UserDefaults for fast in-process access
        UserDefaults.standard.set(accepted, forKey: "consentDMProcessing")

        // Firestore for cross-device persistence and audit trail
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("users").document(uid)
            .setData(
                [
                    "consentDMProcessing": accepted,
                    "consentDMProcessingDate": Timestamp()
                ],
                merge: true
            )
    }
}

#if DEBUG
#Preview {
    BereanDMConsentSheet(onAccept: {}, onDecline: {})
}
#endif

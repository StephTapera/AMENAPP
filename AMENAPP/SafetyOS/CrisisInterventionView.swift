// CrisisInterventionView.swift
// AMENAPP — SafetyOS
// Shown when crisisLanguage flag is detected. Provides immediate resources.
// Never auto-publishes the content — always requires explicit user action after review.

import SwiftUI

struct CrisisInterventionView: View {
    let onContinuePosting: () -> Void
    let onGetHelp: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.systemScaled(48))
                    // PURGED: Color.amenGold → Color.accentColor per C3 design contract
                    .foregroundStyle(Color.accentColor)

                Text("We care about you")
                    .font(.title2.weight(.bold))

                Text("It looks like you may be going through something difficult. You don't have to face this alone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Resources
            VStack(spacing: 12) {
                CrisisInterventionResourceRow(
                    icon: "phone.fill",
                    title: "988 Suicide & Crisis Lifeline",
                    detail: "Call or text 988 — available 24/7",
                    action: { openCrisisLine("988") }
                )
                CrisisInterventionResourceRow(
                    icon: "message.fill",
                    title: "Crisis Text Line",
                    detail: "Text HOME to 741741",
                    action: {
                        // Open SMS to Crisis Text Line (741741)
                        if let url = URL(string: "sms:741741&body=HOME") {
                            UIApplication.shared.open(url)
                        }
                    }
                )
                CrisisInterventionResourceRow(
                    icon: "hands.sparkles.fill",
                    title: "Talk to Your Pastor or Mentor",
                    detail: "Reach out to someone in your community",
                    action: onGetHelp
                )
            }
            .padding(.horizontal)

            // Options
            VStack(spacing: 10) {
                Button {
                    onGetHelp()
                } label: {
                    Text("Reach Out to Someone Now")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        // PURGED: Color.amenGold → Color.accentColor per C3 design contract
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    onContinuePosting()
                } label: {
                    Text("I'm OK — Continue Posting")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 32)
        .background(Color(.systemBackground))
    }

    private func openCrisisLine(_ number: String) {
        guard let url = URL(string: "tel://\(number)") else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Resource Row

private struct CrisisInterventionResourceRow: View {
    let icon: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.systemScaled(20))
                    // PURGED: Color.amenGold → Color.accentColor per C3 design contract
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}

// MARK: - Preview

#Preview {
    CrisisInterventionView(
        onContinuePosting: {},
        onGetHelp: {},
        onDismiss: {}
    )
}

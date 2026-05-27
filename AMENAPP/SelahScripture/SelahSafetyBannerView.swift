//
//  SelahSafetyBannerView.swift
//  AMENAPP
//
//  Phase 3b — Reflections & Privacy
//  Care-moment banner displayed when safety classification returns a
//  blocking theme. This is not an error state — it is a pastoral moment.
//  Wording and structure are intentionally warm and non-alarming.
//

import SwiftUI

struct SelahSafetyBannerView: View {

    let payload: SelahSupportPayload
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: Header
                VStack(alignment: .leading, spacing: 6) {
                    Text(payload.groundingTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("You are not alone in this moment.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // MARK: Grounding Steps
                if !payload.groundingSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(payload.groundingSteps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1).")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 20, alignment: .trailing)

                                Text(step)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                // MARK: Trusted Human Prompt
                Text(payload.trustedHumanPrompt)
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // MARK: Resource Links
                if !payload.resourceLinks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Resources")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        ForEach(payload.resourceLinks) { link in
                            Link(link.title, destination: link.url)
                                .font(.subheadline)
                                .foregroundStyle(.teal)
                                .accessibilityIdentifier("safetyBanner.resource.\(link.id)")
                        }
                    }
                }

                // MARK: Dismiss
                Button(action: onDismiss) {
                    Text("I have what I need")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.teal.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.teal)
                }
                .accessibilityIdentifier("safetyBanner.dismissButton")
            }
            .padding(20)
        }
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.teal.opacity(0.12), lineWidth: 1.5)
                }
        }
        .padding()
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    SelahSafetyBannerView(
        payload: SelahSupportPayload(
            groundingTitle: "We hear you. You matter.",
            groundingSteps: [
                "Take a slow breath in through your nose, and out through your mouth.",
                "Name one thing you can see right now.",
                "You don't have to carry this alone."
            ],
            trustedHumanPrompt: "Is there someone you trust — a friend, pastor, or counselor — you could reach out to today?",
            resourceLinks: [
                SelahResourceLink(
                    id: "988",
                    title: "988 Suicide & Crisis Lifeline (US)",
                    url: URL(string: "tel:988")!,
                    region: "US"
                ),
                SelahResourceLink(
                    id: "samaritans",
                    title: "Samaritans (UK & Ireland)",
                    url: URL(string: "tel:116123")!,
                    region: "UK"
                )
            ]
        ),
        onDismiss: {}
    )
}
#endif

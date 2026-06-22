// DiscussionFollowUpPrompt.swift
// AMEN App — Community OS / Discussion OS (A6)
//
// A gentle, opt-in follow-up card shown when a discussion thread goes quiet.
// NEVER auto-shown — only presented when the user has explicitly opted into
// follow-up notifications. See Design Rules for non-manipulative spec.
//
// Design contract (C3):
//   - White card, soft shadow (AmenShadow.card spec)
//   - Two buttons: "Yes, continue" (accentColor) and "Dismiss" (secondaryLabel)
//   - 28pt continuous corner radius
//   - No engagement-maximising language

import SwiftUI

// MARK: - DiscussionFollowUpPrompt

/// A gentle, non-manipulative card prompting the user to re-engage with a quiet discussion.
///
/// IMPORTANT: This component must never be displayed automatically or without explicit
/// user consent. Always gate on follow-up notification opt-in preference.
///
/// Usage:
/// ```swift
/// if followUpOptInEnabled {
///     DiscussionFollowUpPrompt(
///         prompt: "The conversation on "What does faith mean in action?" is still going.",
///         onAccept: { navigateToDiscussion() },
///         onDismiss: { hidePrompt() }
///     )
/// }
/// ```
struct DiscussionFollowUpPrompt: View {

    /// The contextual prompt text shown to the user.
    /// Should be neutral and informational — not manipulative or urgency-inducing.
    let prompt: String

    /// Called when the user taps "Yes, continue".
    let onAccept: () -> Void

    /// Called when the user taps "Dismiss".
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header row
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.systemScaled(14, weight: .regular))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .accessibilityHidden(true)

                Text("Conversation Update")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(uiColor: .label))
            }

            // Prompt body
            Text(prompt)
                .font(.callout)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            // Action buttons
            HStack(spacing: 12) {
                // Accept
                Button {
                    onAccept()
                } label: {
                    Text("Yes, continue")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Yes, continue this discussion")

                // Dismiss
                Button {
                    onDismiss()
                } label: {
                    Text("Dismiss")
                        .font(.callout)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemFill))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss this follow-up prompt")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)
                .shadow(
                    color: .black.opacity(0.07),
                    radius: 24,
                    x: 0,
                    y: 5
                )
        )
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(spacing: 20) {
        DiscussionFollowUpPrompt(
            prompt: "The conversation on \"What does faith mean in action?\" is still going — 3 new replies since you last visited.",
            onAccept: { },
            onDismiss: { }
        )
        .padding(.horizontal, 20)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(uiColor: .systemGroupedBackground))
}
#endif

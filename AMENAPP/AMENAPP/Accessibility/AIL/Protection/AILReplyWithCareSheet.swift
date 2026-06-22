// AILReplyWithCareSheet.swift
// AMENAPP — Accessibility Intelligence Layer (AIL) · Protection Surface (A6)
//
// "Reply with Care" — a PRE-SEND, fully DISMISSIBLE nudge. Given the user's draft,
// it routes the text through AILTransformService.transform(.replyCareCheck, …). If
// that returns a non-empty suggestion (and the transform did NOT fail open), a
// gentle sheet offers a thought before sending. Otherwise the send proceeds with
// no interruption at all.
//
// IRON RULES (encoded here, in code AND behavior):
//   • Protection SUGGESTS; moderation DECIDES. This view shares ZERO code path with
//     NeMo / Guardian / ModerationGatewayService. It calls only the fail-open
//     AILTransformService and can NEVER block a send — "Send anyway" always proceeds.
//   • FAIL OPEN everywhere: on failOpen or an empty suggestion, the sheet does
//     nothing and the caller's send goes through untouched.
//   • NO tier checks — accessibility is free at every tier.
//   • Reduce Motion → no presentation animation.
//
// Usage:
//   AILReplyWithCareSheet(draft: draft, onSend: { send() }, onEdit: { focusEditor() })
// The host presents this only after gating on `shouldShow` (see makeIfNeeded).

import SwiftUI

/// A dismissible "a thought before you send" sheet. NEVER blocks: both paths proceed.
struct AILReplyWithCareSheet: View {

    /// The user's current draft (already composed, awaiting send).
    let draft: String
    /// Proceed with the send exactly as the user intended ("Send anyway").
    let onSend: () -> Void
    /// Return the user to the editor to revise ("Edit"). Does NOT send.
    let onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Pre-resolved suggestion text. The host computes this via `careSuggestion`
    /// and only presents the sheet when it is non-empty + not fail-open.
    let suggestion: String

    init(
        draft: String,
        suggestion: String,
        onSend: @escaping () -> Void,
        onEdit: @escaping () -> Void
    ) {
        self.draft = draft
        self.suggestion = suggestion
        self.onSend = onSend
        self.onEdit = onEdit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            Text(suggestion)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text("Suggestion: \(suggestion)"))

            Spacer(minLength: 0)

            buttons
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)   // always dismissible by swipe
        .transaction { txn in
            if reduceMotion { txn.disablesAnimations = true }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.text.square")
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("A thought before you send…")
                .font(.headline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Buttons (both proceed; never blocks)

    private var buttons: some View {
        VStack(spacing: 12) {
            // "Send anyway" ALWAYS proceeds — this is the non-blocking guarantee.
            Button {
                dismiss()
                onSend()
            } label: {
                Text("Send anyway")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint(Text("Sends your message as written."))

            Button {
                dismiss()
                onEdit()
            } label: {
                Text("Edit")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .accessibilityHint(Text("Returns to the editor so you can revise before sending."))
        }
    }
}

// MARK: - Gating helper

extension AILReplyWithCareSheet {

    /// Resolve a care suggestion for a draft. Returns `nil` when there is nothing
    /// to suggest (fail-open, empty draft, or empty suggestion) — in which case the
    /// host should NOT present the sheet and should let the send proceed.
    ///
    /// This isolates the single AIL call so the view itself stays presentation-only,
    /// and keeps the non-blocking contract obvious at the call site.
    static func careSuggestion(
        for draft: String,
        originalRef: String,
        isDirectMessage: Bool = false
    ) async -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let result = await AILTransformService.shared.transform(
            task: .replyCareCheck,
            input: draft,
            originalRef: originalRef,
            isDirectMessage: isDirectMessage
        )

        // FAIL OPEN — no nudge, send proceeds untouched.
        guard !result.failOpen else { return nil }

        guard let suggestion = result.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !suggestion.isEmpty else { return nil }

        return suggestion
    }
}

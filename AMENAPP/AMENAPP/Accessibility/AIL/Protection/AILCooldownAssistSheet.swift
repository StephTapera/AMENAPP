// AILCooldownAssistSheet.swift
// AMENAPP — Accessibility Intelligence Layer (AIL) · Protection Surface (A6)
//
// "Cooldown Assist" — given a heated draft, this routes the text through
// AILTransformService.transform(.cooldownRewrite, …) and offers a calmer rewrite.
// The user chooses "Use this" (adopt the rewrite) or "Keep mine" (send as written).
// BOTH paths proceed; neither blocks the send.
//
// IRON RULES (encoded here, in code AND behavior):
//   • Protection SUGGESTS; moderation DECIDES. Shares ZERO code path with NeMo /
//     Guardian / ModerationGatewayService — only the fail-open AILTransformService.
//   • FAIL OPEN: if the transform fails open (or yields no rewrite) we silently keep
//     the user's draft and the host proceeds — the sheet is never even shown.
//   • Never blocks: "Keep mine" always sends the original; "Use this" sends the calmer
//     version. The user is in control either way.
//   • NO tier checks — accessibility is free at every tier.
//   • Reduce Motion → no presentation animation.
//
// Usage:
//   AILCooldownAssistSheet(original: draft, rewrite: rewrite,
//                          onUseRewrite: { send($0) }, onKeepMine: { send(draft) })

import SwiftUI

/// A dismissible calmer-rewrite offer. NEVER blocks: both choices proceed.
struct AILCooldownAssistSheet: View {

    /// The user's original (heated) draft.
    let original: String
    /// The suggested calmer rewrite (pre-resolved, non-empty, not fail-open).
    let rewrite: String
    /// Adopt the calmer rewrite — passes the rewrite text to the host to send.
    let onUseRewrite: (String) -> Void
    /// Keep the original draft and send it unchanged.
    let onKeepMine: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    rewriteBlock
                    originalBlock
                }
            }

            buttons
        }
        .padding(24)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)   // always dismissible
        .transaction { txn in
            if reduceMotion { txn.disablesAnimations = true }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "wind")
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Want to send this a little calmer?")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Text blocks

    private var rewriteBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Suggested")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(rewrite)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text("Suggested rewrite: \(rewrite)"))
        }
    }

    private var originalBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Yours")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(original)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text("Your original: \(original)"))
        }
    }

    // MARK: - Buttons (both proceed; never blocks)

    private var buttons: some View {
        VStack(spacing: 12) {
            Button {
                dismiss()
                onUseRewrite(rewrite)
            } label: {
                Text("Use this")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint(Text("Sends the calmer rewrite instead of your draft."))

            // "Keep mine" ALWAYS sends the original — the non-blocking guarantee.
            Button {
                dismiss()
                onKeepMine()
            } label: {
                Text("Keep mine")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .accessibilityHint(Text("Sends your message exactly as you wrote it."))
        }
    }
}

// MARK: - Gating helper

extension AILCooldownAssistSheet {

    /// Resolve a calmer rewrite for a heated draft. Returns `nil` when there is no
    /// rewrite to offer (fail-open, empty draft, empty rewrite, or a rewrite identical
    /// to the original) — in which case the host should NOT present the sheet and
    /// should send the user's draft unchanged.
    static func cooldownRewrite(
        for draft: String,
        originalRef: String,
        isDirectMessage: Bool = false
    ) async -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let result = await AILTransformService.shared.transform(
            task: .cooldownRewrite,
            input: draft,
            originalRef: originalRef,
            isDirectMessage: isDirectMessage
        )

        // FAIL OPEN — silently keep the user's draft.
        guard !result.failOpen else { return nil }

        guard let rewrite = result.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rewrite.isEmpty,
              rewrite != trimmed else { return nil }

        return rewrite
    }
}

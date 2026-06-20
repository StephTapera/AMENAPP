//
//  InboundBlockWarningBanner.swift
//  AMENAPP
//
//  Trust & Safety Remediation (item 21 follow-on) — a quiet, non-blocking caution
//  shown before opening a DM with an account that several people have blocked.
//  Advisory only — it never prevents messaging.
//
//  Use the `.inboundBlockWarning(for:)` modifier to attach it to any DM surface;
//  it fetches the coarse signal and renders the banner as a top safe-area inset
//  only when warranted. When the feature flag is off, it renders nothing and
//  performs no network call (zero regression).
//

import SwiftUI

struct InboundBlockWarningBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Proceed with care")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Several people have blocked this account. Be cautious about sharing personal information.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Proceed with care. Several people have blocked this account. Be cautious about sharing personal information."
        )
    }
}

// MARK: - Attach modifier

private struct InboundBlockWarningModifier: ViewModifier {
    let userId: String
    @State private var signal: InboundBlockSignalService.Signal = .none

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if signal.shouldWarn {
                    InboundBlockWarningBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            // Re-fetch whenever the conversation partner changes.
            .task(id: userId) {
                let result = await InboundBlockSignalService.shared.warning(for: userId)
                withAnimation(.easeInOut(duration: 0.2)) {
                    signal = result
                }
            }
    }
}

extension View {
    /// Surfaces an advisory "blocked by several people" caution above this view
    /// for the given DM partner. No-op (and no network call) when the
    /// `inbound_block_warning_enabled` flag is off or `userId` is empty.
    func inboundBlockWarning(for userId: String?) -> some View {
        modifier(InboundBlockWarningModifier(userId: userId ?? ""))
    }
}

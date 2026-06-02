// ONEEarnedPermanenceView.swift
// ONE — "Remember this" overlay control. Cancels scheduled decay on tap.
// P2-G | Overlays on any displayed moment. Wired to ONEDecaySchedulerService.cancel().

import SwiftUI

struct ONEEarnedPermanenceView: View {
    let momentID: String
    var isRemembered: Bool
    var onRemember: () async -> Void

    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            guard !isRemembered else { return }
            Task { await onRemember() }
        } label: {
            HStack(spacing: ONE.Spacing.xs) {
                Image(systemName: isRemembered ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .medium))
                    .scaleEffect(isPulsing ? 1.25 : 1.0)
                Text(isRemembered ? "Remembered" : "Remember")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isRemembered ? ONE.Colors.ephemeralRed : Color.secondary)
            .padding(.horizontal, ONE.Spacing.md)
            .padding(.vertical, ONE.Spacing.sm)
            .background(
                Capsule(style: .continuous)
                    .fill(isRemembered
                        ? ONE.Colors.ephemeralRed.opacity(0.12)
                        : Color.primary.opacity(0.08))
                    .stroke(
                        isRemembered ? ONE.Colors.ephemeralRed.opacity(0.30) : Color.clear,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isRemembered)
        .onChange(of: isRemembered) { _, newValue in
            if newValue && !reduceMotion {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { isPulsing = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { isPulsing = false }
                }
            }
        }
        .accessibilityLabel(
            isRemembered
                ? "This moment is remembered and will not fade"
                : "Remember this moment to prevent it from expiring"
        )
        .accessibilityHint(isRemembered ? "" : "Tap to save this moment permanently")
        .accessibilityAddTraits(isRemembered ? [.isStaticText] : [.isButton])
    }
}

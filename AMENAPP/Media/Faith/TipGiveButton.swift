// TipGiveButton.swift
// AMENAPP — Agent 7: Faith Layer
//
// Glass pill "Give" button. Callers handle the actual Stripe Connect payment
// sheet — this component is purely the button surface with spring feedback.

import SwiftUI

@MainActor
struct TipGiveButton: View {
    var creatorId: String
    var postId: String
    var onTap: () -> Void

    @State private var isExpanding: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            handleTap()
        } label: {
            GlassPill {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.amenGold)
                    Text("Give")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.amenGold)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isExpanding ? 1.05 : 1.0)
        .animation(
            reduceMotion
                ? .easeOut(duration: LiquidGlassTokens.motionFast)
                : .spring(response: 0.28, dampingFraction: 0.60),
            value: isExpanding
        )
        .accessibilityLabel("Give to creator")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Tap handler

    private func handleTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        guard !reduceMotion else {
            onTap()
            return
        }

        isExpanding = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            isExpanding = false
            onTap()
        }
    }
}

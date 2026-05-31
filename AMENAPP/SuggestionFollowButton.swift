// SuggestionFollowButton.swift
// AMENAPP
//
// Follow / Requested / Following button state machine for suggestion cards.
// Extracted from SuggestedForYouModule.swift.

import SwiftUI

struct SuggestionFollowButton: View {
    let state: FollowStateManager.FollowState
    let isLoading: Bool
    let onFollow: () -> Void
    let onCancelRequest: () -> Void
    let onUnfollow: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            switch state {
            case .notFollowing, .followsYou:
                onFollow()
            case .requested:
                onCancelRequest()
            case .following, .mutualFollow:
                onUnfollow()
            }
        } label: {
            HStack(spacing: 4) {
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(state == .notFollowing || state == .followsYou ? .white : .primary)
                } else {
                    Text(state.buttonTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(buttonForeground)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background { buttonBackground }
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.8)), value: isPressed)
            .animation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.8)), value: state)
        }
        .buttonStyle(.plain)
        ._onButtonGesture(pressing: { isPressed = $0 }, perform: {})
        .disabled(isLoading)
        .accessibilityLabel(state.buttonTitle)
    }

    private var buttonForeground: Color {
        switch state {
        case .notFollowing, .followsYou:
            return .white
        case .requested:
            return .primary
        case .following, .mutualFollow:
            return .primary
        }
    }

    @ViewBuilder
    private var buttonBackground: some View {
        switch state {
        case .notFollowing, .followsYou:
            // Strong emphasis — solid black
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(isPressed ? 0.78 : 1.0))
        case .requested:
            // Subdued — outlined glass
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.75)
                )
        case .following, .mutualFollow:
            // Neutral — light glass
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.75)
                )
        }
    }
}

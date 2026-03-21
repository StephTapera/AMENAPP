//
//  MediaModerationView.swift
//  AMENAPP
//
//  Wraps any media display with the AI moderation state machine:
//
//    .unchecked / .checking  → ProgressView shimmer
//    .approved / .failedOpen → passes through to content
//    .warningRequired        → content + dismissable warning banner
//    .blurred                → frosted overlay + "Under Review" label
//    .hidden                 → solid overlay + "Pending Review" message
//    .rejected               → solid overlay + rejection copy, no reveal option
//

import SwiftUI

// MARK: - Main Wrapper

struct MediaModerationView<Content: View>: View {
    let state: MediaModerationState
    @ViewBuilder let content: () -> Content

    @State private var warningDismissed = false

    var body: some View {
        switch state {
        case .unchecked, .checking:
            moderationLoadingShimmer

        case .approved, .failedOpen:
            content()

        case .warningRequired(let message, _):
            content()
                .overlay(alignment: .top) {
                    if !warningDismissed {
                        ModerationWarningBanner(message: message) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                warningDismissed = true
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

        case .blurred(let result):
            BlurredMediaView(content: content, result: result)

        case .hidden(let result):
            HiddenMediaView(result: result)

        case .rejected(let reason):
            RejectedMediaView(reason: reason)
        }
    }

    // Shimmer placeholder while moderation runs
    private var moderationLoadingShimmer: some View {
        RoundedRectangle(cornerRadius: 0)
            .fill(Color(.secondarySystemBackground))
            .overlay(
                ZStack {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.secondary)
                    Text("Checking content…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .offset(y: 28)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Blurred Media View

private struct BlurredMediaView<Content: View>: View {
    @ViewBuilder let content: () -> Content
    let result: MediaModerationResult

    @State private var revealed = false

    var body: some View {
        ZStack {
            if revealed {
                content()
                    .overlay(alignment: .top) {
                        ModerationWarningBanner(
                            message: "This content is under review. Exercise your own discernment.",
                            onDismiss: nil
                        )
                    }
            } else {
                content()
                    .blur(radius: 24)
                    .overlay(BlurOverlayLabel(onReveal: { revealed = true }))
            }
        }
    }
}

private struct BlurOverlayLabel: View {
    let onReveal: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
            VStack(spacing: 12) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Under Review")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Our team is reviewing this content.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                Button {
                    HapticManager.impact(style: .light)
                    onReveal()
                } label: {
                    Text("Show Anyway")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(.white.opacity(0.15)))
                }
            }
            .padding()
        }
    }
}

// MARK: - Hidden Media View

private struct HiddenMediaView: View {
    let result: MediaModerationResult

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            VStack(spacing: 10) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.orange)
                Text("Pending Review")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("This media has been flagged and is hidden\nuntil reviewed by our moderation team.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                if !result.flagCategories.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(result.flagCategories.prefix(2), id: \.self) { cat in
                            Text(cat)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(.orange.opacity(0.12)))
                        }
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Rejected Media View

private struct RejectedMediaView: View {
    let reason: String

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            VStack(spacing: 10) {
                Image(systemName: "xmark.shield.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.red)
                Text("Content Removed")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("This media was removed for violating\nAMEN's community standards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Warning Banner

struct ModerationWarningBanner: View {
    let message: String
    let onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.yellow)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let dismiss = onDismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.black.opacity(0.72))
                .overlay(
                    Rectangle()
                        .fill(Color.yellow.opacity(0.4))
                        .frame(height: 2),
                    alignment: .bottom
                )
        )
    }
}

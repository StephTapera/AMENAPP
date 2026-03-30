//
//  EmptyStateView.swift
//  AMENAPP
//
//  Reusable empty state component shown when a feed has no content.
//  Shows only when isLoading == false AND items are empty.
//

import SwiftUI

struct EmptyStateView: View {
    let icon: String
    var emoji: String? = nil
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 16) {
            if let emoji {
                Text(emoji)
                    .font(.system(size: 52))
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: appeared)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 44))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: appeared)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: appeared)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .tint(.indigo)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.18), value: appeared)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                appeared = true
            }
        }
    }
}

// MARK: - Skeleton Loading Card

struct SkeletonCard: View {
    var height: CGFloat = 120
    var cornerRadius: CGFloat = 16
    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.secondary.opacity(shimmer ? 0.10 : 0.05))
            .frame(height: height)
            .animation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: shimmer
            )
            .onAppear { shimmer = true }
    }
}

struct SkeletonFeed: View {
    var count = 3
    var cardHeight: CGFloat = 120
    var spacing: CGFloat = 12

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { _ in
                SkeletonCard(height: cardHeight)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Empty — with action") {
    EmptyStateView(
        icon: "bell",
        title: "No notifications yet",
        subtitle: "When someone prays for you or replies, it'll show up here."
    )
}
#Preview("Empty — with emoji + action") {
    EmptyStateView(
        icon: "bell",
        emoji: "🙏",
        title: "No prayer requests yet",
        subtitle: "Share a prayer request or intercede for someone today.",
        actionTitle: "Post a Prayer",
        action: {}
    )
}
#Preview("Skeleton") {
    SkeletonFeed()
}
#endif

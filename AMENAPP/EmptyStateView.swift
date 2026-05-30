//
//  EmptyStateView.swift
//  AMENAPP
//
//  Reusable empty state component shown when a feed has no content.
//  Shows only when isLoading == false AND items are empty.
//

import SwiftUI

// MARK: - AmenGlass3DIcon

struct AmenGlass3DIcon: View {
    let systemName: String
    var tint: Color = AmenTheme.Colors.amenPurple
    var size: CGFloat = 80

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Ambient glow beneath
            Circle()
                .fill(tint.opacity(colorScheme == .dark ? 0.14 : 0.09))
                .frame(width: size * 1.55, height: size * 1.55)
                .blur(radius: size * 0.28)

            // Glass sphere
            ZStack {
                // Base material
                Circle()
                    .fill(
                        reduceTransparency
                            ? AnyShapeStyle(Color(.systemBackground))
                            : AnyShapeStyle(.ultraThinMaterial)
                    )

                // Color tint coat
                Circle()
                    .fill(tint.opacity(colorScheme == .dark ? 0.18 : 0.10))

                // Specular highlight (top-left)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(colorScheme == .dark ? 0.30 : 0.55), Color.clear],
                            center: UnitPoint(x: 0.33, y: 0.22),
                            startRadius: 0,
                            endRadius: size * 0.48
                        )
                    )

                // Outer rim — light
                Circle()
                    .strokeBorder(Color.white.opacity(0.42), lineWidth: 0.7)

                // Outer rim — dark (definition)
                Circle()
                    .strokeBorder(Color.black.opacity(colorScheme == .dark ? 0.20 : 0.08), lineWidth: 0.6)

                // SF Symbol
                Image(systemName: systemName)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
            }
            .frame(width: size, height: size)
            // Layered shadows: colored lift + neutral depth
            .shadow(color: tint.opacity(colorScheme == .dark ? 0.28 : 0.20), radius: size * 0.30, x: 0, y: size * 0.18)
            .shadow(color: Color.black.opacity(0.10), radius: size * 0.12, x: 0, y: size * 0.06)
        }
    }
}

// MARK: - EmptyStateView

struct EmptyStateView: View {
    let icon: String
    var emoji: String? = nil
    let title: String
    let subtitle: String
    var iconTint: Color = AmenTheme.Colors.amenPurple
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 20) {
            if let emoji {
                Text(emoji)
                    .font(.systemScaled(52))
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)
                    .animation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.7), value: appeared)
            } else {
                AmenGlass3DIcon(systemName: icon, tint: iconTint, size: 80)
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)
                    .animation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.7), value: appeared)
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
            .animation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: appeared)

            if let actionTitle, let action {
                AmenLiquidGlassPillButton(
                    title: actionTitle,
                    systemImage: "plus",
                    isLoading: false,
                    isDisabled: false,
                    action: action
                )
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.8).delay(0.18), value: appeared)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.secondary.opacity(shimmer ? 0.10 : 0.05))
            .frame(height: height)
            .animation(
                reduceMotion ? .none : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
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
#Preview("Empty — notifications") {
    EmptyStateView(
        icon: "bell",
        title: "No notifications yet",
        subtitle: "When someone prays for you or replies, it'll show up here.",
        iconTint: AmenTheme.Colors.amenPurple
    )
}
#Preview("Empty — prayer") {
    EmptyStateView(
        icon: "hands.sparkles",
        title: "No prayer requests yet",
        subtitle: "Share a prayer request or intercede for someone today.",
        iconTint: AmenTheme.Colors.amenGold,
        actionTitle: "Post a Prayer",
        action: {}
    )
}
#Preview("Empty — with emoji") {
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
#Preview("3D Glass Icon — gold") {
    VStack(spacing: 24) {
        AmenGlass3DIcon(systemName: "hands.sparkles", tint: AmenTheme.Colors.amenGold, size: 80)
        AmenGlass3DIcon(systemName: "bell.fill", tint: AmenTheme.Colors.amenPurple, size: 80)
        AmenGlass3DIcon(systemName: "sparkles.rectangle.stack", tint: AmenTheme.Colors.amenBlue, size: 80)
        AmenGlass3DIcon(systemName: "checkmark.seal.fill", tint: AmenTheme.Colors.amenGold, size: 80)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
}
#endif

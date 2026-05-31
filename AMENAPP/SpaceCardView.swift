// SpaceCardView.swift — AMEN App
// White Amen Flow card representing a single Community/Space in discovery.

import SwiftUI

struct SpaceCardView: View {
    let space: AMENSpace
    let isJoined: Bool
    let onJoin: () -> Void
    let onTap: () -> Void

    @State private var joinPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let accent = Color(red: 0.70, green: 0.12, blue: 0.30)

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accent.opacity(0.10))
                        Image(systemName: "person.3.fill")
                            .font(.systemScaled(18, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(space.name)
                            .font(AMENFont.bold(17))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(space.description)
                            .font(AMENFont.regular(14))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                if !space.aiDetectedTopics.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(space.aiDetectedTopics.prefix(3)), id: \.self) { topic in
                                Text(topic)
                                    .font(AMENFont.semiBold(11))
                                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(AmenTheme.Colors.surfaceChip, in: Capsule())
                            }
                        }
                    }
                    .accessibilityLabel("Spiritual topics")
                }

                statsBlock

                HStack(spacing: 10) {
                    if !space.recentPosterPhotoURLs.isEmpty {
                        avatarStack
                    } else {
                        Label("Community conversation", systemImage: "bubble.left.and.bubble.right")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }

                    Spacer(minLength: 0)
                    joinButton
                }
            }
            .padding(16)
            .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.055), radius: 14, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(joinPressed && !reduceMotion ? 0.992 : 1.0)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.82), value: joinPressed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(space.name). \(space.memberCount) members. \(isJoined ? "Joined" : "Join")")
    }

    private var joinButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.72))) {
                joinPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.72))) {
                    joinPressed = false
                }
            }
            onJoin()
        } label: {
            Text(isJoined ? "Joined" : "Join")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(isJoined ? accent : .white)
                .padding(.horizontal, isJoined ? 14 : 18)
                .padding(.vertical, 8)
                .background(joinButtonBackground, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(isJoined ? accent.opacity(0.35) : Color.clear, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isJoined ? "Joined" : "Join space")
    }

    private var joinButtonBackground: some ShapeStyle {
        isJoined ? AnyShapeStyle(accent.opacity(0.10)) : AnyShapeStyle(accent)
    }

    @ViewBuilder
    private var statsBlock: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                statItem(icon: "person.fill", value: space.memberCount.compactFormatted, label: "members")
                statItem(icon: "doc.fill", value: space.postCount.compactFormatted, label: "posts")
                statItem(icon: "shield.checkered", value: "Safe", label: "moderated")
            }
        } else {
            HStack(spacing: 12) {
                statItem(icon: "person.fill", value: space.memberCount.compactFormatted, label: "members")
                statItem(icon: "doc.fill", value: space.postCount.compactFormatted, label: "posts")
                statItem(icon: "shield.checkered", value: "Safe", label: "moderated")
                Spacer(minLength: 0)
            }
        }
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.systemScaled(10, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.textTertiary)

            Text("\(value) \(label)")
                .font(AMENFont.regular(12))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }

    private var avatarStack: some View {
        HStack(spacing: 6) {
            ZStack {
                ForEach(Array(space.recentPosterPhotoURLs.prefix(3).enumerated()), id: \.offset) { index, urlString in
                    CachedAsyncImage(url: URL(string: urlString)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(accent.opacity(0.16))
                    }
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                    .offset(x: CGFloat(index) * -6)
                    .zIndex(Double(3 - index))
                }
            }
            .frame(height: 22)
            .padding(.leading, CGFloat(min(space.recentPosterPhotoURLs.count, 3) - 1) * 3)

            Text("Recent activity")
                .font(AMENFont.regular(12))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
        }
    }
}

// Int.compactFormatted is defined app-wide in FollowerAvatarStack.swift

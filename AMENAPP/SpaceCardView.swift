// SpaceCardView.swift — AMEN App
// Glass card representing a single Community/Space in the discovery list

import SwiftUI

struct SpaceCardView: View {
    let space: AMENSpace
    let isJoined: Bool
    let onJoin: () -> Void
    let onTap: () -> Void

    @State private var joinPressed = false

    private let accentPurple   = Color(red: 0.6,  green: 0.35, blue: 1.0)
    private let accentPurpleDim = Color(red: 0.45, green: 0.2,  blue: 0.85)

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {

                // ── Top Row: name + join button ──────────────────────────
                HStack(alignment: .center, spacing: 10) {
                    Text(space.name)
                        .font(AMENFont.bold(17))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()

                    joinButton
                }

                // ── AI Topic Pills ───────────────────────────────────────
                if !space.aiDetectedTopics.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(space.aiDetectedTopics.prefix(3)), id: \.self) { topic in
                            Text(topic)
                                .font(AMENFont.semiBold(11))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(accentPurple.opacity(0.15))
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(accentPurple.opacity(0.25), lineWidth: 0.75)
                                        )
                                )
                        }
                        Spacer()
                    }
                }

                // ── Description ──────────────────────────────────────────
                Text(space.description)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // ── Stats Row ────────────────────────────────────────────
                HStack(spacing: 14) {
                    statItem(icon: "person.fill",
                             value: space.memberCount.compactFormatted,
                             label: "members")

                    statItem(icon: "doc.fill",
                             value: space.postCount.compactFormatted,
                             label: "posts")

                    statItem(icon: "flame.fill",
                             value: space.weeklyActiveUsers.compactFormatted,
                             label: "this week")

                    Spacer()
                }

                // ── Recent Poster Avatar Stack ───────────────────────────
                if !space.recentPosterPhotoURLs.isEmpty {
                    avatarStack
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Join Button

    private var joinButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                joinPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                    joinPressed = false
                }
            }
            onJoin()
        } label: {
            Group {
                if isJoined {
                    Text("Joined")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(accentPurple)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(accentPurple.opacity(0.12))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(accentPurple.opacity(0.5), lineWidth: 1)
                                )
                        )
                } else {
                    Text("Join")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [accentPurple, accentPurpleDim],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: accentPurple.opacity(0.4), radius: 6, y: 2)
                        )
                }
            }
            .scaleEffect(joinPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: joinPressed)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stat Item

    private func statItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.systemScaled(10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))

            Text("\(value) \(label)")
                .font(AMENFont.regular(12))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Avatar Stack

    private var avatarStack: some View {
        HStack(spacing: 6) {
            ZStack {
                ForEach(Array(space.recentPosterPhotoURLs.prefix(3).enumerated()), id: \.offset) { index, urlString in
                    AsyncImage(url: URL(string: urlString)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(accentPurple.opacity(0.25))
                    }
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1.5))
                    .offset(x: CGFloat(index) * -6)
                    .zIndex(Double(3 - index))
                }
            }
            .frame(height: 22)
            .padding(.leading, CGFloat(min(space.recentPosterPhotoURLs.count, 3) - 1) * 3)

            Text("Recent activity")
                .font(AMENFont.regular(12))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

// Int.compactFormatted is defined app-wide in FollowerAvatarStack.swift

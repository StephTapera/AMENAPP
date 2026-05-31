// DiscussionHeroHeader.swift
// AMENAPP — Discussions
//
// Apple Music–style album header for a group/discussion.
// Layout (top → bottom):
//   1. Full-bleed hero background (group photo or gradient art)
//   2. Centered group art square (220 pt) with drop shadow
//   3. Group name  (bold, 22pt)
//   4. GroupMetadataStrip  ("Bible Study · 234 members · Public")
//   5. GroupActionRow       (Open / Notify / Join)
//
// Collapses as the user scrolls, transitioning to a nav-bar inline title.
// All animations use Motion.liquidSpring / Motion.adaptive.

import SwiftUI

// MARK: - GroupMetadataStrip

/// "Category · member count · privacy" — mirrors "Gospel · 2026 · Dolby Atmos"
struct GroupMetadataStrip: View {
    let category: String
    let memberCount: Int
    let isPrivate: Bool

    private var privacyLabel: String { isPrivate ? "Private" : "Public" }

    var body: some View {
        HStack(spacing: 0) {
            Text(category)
            separator
            Text("\(memberCount.formatted()) members")
            separator
            HStack(spacing: 3) {
                Image(systemName: isPrivate ? "lock.fill" : "globe")
                    .font(.system(size: 10, weight: .semibold))
                Text(privacyLabel)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private var separator: some View {
        Text(" · ")
            .foregroundStyle(.tertiary)
    }
}

// MARK: - GroupActionRow

/// Three glass-capsule action buttons: Open / Notify / Join (or Leave).
struct GroupActionRow: View {
    let isMember: Bool
    let notificationsOn: Bool
    var onOpen: () -> Void
    var onNotify: () -> Void
    var onJoinOrLeave: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            // Secondary: Notify (bell)
            actionButton(
                icon: notificationsOn ? "bell.fill" : "bell",
                label: "Notify",
                style: .secondary,
                action: onNotify
            )
            .accessibilityLabel(notificationsOn ? "Disable notifications" : "Enable notifications")

            // Primary: Open
            actionButton(
                icon: "arrow.right.circle.fill",
                label: "Open",
                style: .primary,
                action: onOpen
            )
            .accessibilityLabel("Open group")

            // Secondary: Join or Leave
            actionButton(
                icon: isMember ? "checkmark.circle.fill" : "plus.circle.fill",
                label: isMember ? "Leave" : "Join",
                style: isMember ? .joined : .secondary,
                action: onJoinOrLeave
            )
            .accessibilityLabel(isMember ? "Leave group" : "Join group")
        }
    }

    // MARK: - Button style variants

    enum ActionStyle { case primary, secondary, joined }

    @ViewBuilder
    private func actionButton(
        icon: String,
        label: String,
        style: ActionStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Capsule()
                        .fill(style == .primary
                              ? AnyShapeStyle(Color(red: 0.06, green: 0.06, blue: 0.07))
                              : AnyShapeStyle(.ultraThinMaterial))
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    style == .primary
                                        ? Color.clear
                                        : Color.white.opacity(0.30),
                                    lineWidth: 0.6
                                )
                        )
                        .frame(width: 76, height: 38)
                        .shadow(color: .black.opacity(style == .primary ? 0.22 : 0.08),
                                radius: 6, x: 0, y: 3)

                    HStack(spacing: 5) {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(
                                style == .primary
                                    ? Color.white
                                    : style == .joined
                                        ? Color(red: 0.44, green: 0.26, blue: 0.80) // amenPurple
                                        : Color.primary
                            )
                        Text(label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(
                                style == .primary ? Color.white : Color.primary
                            )
                    }
                }
            }
        }
        .buttonStyle(AmenPressStyle(scale: 0.94))
    }
}

// MARK: - DiscussionHeroHeader

struct DiscussionHeroHeader: View {
    let groupId: String
    let groupName: String
    let category: String
    let memberCount: Int
    let isPrivate: Bool
    let coverImageURL: String?
    let isMember: Bool
    let notificationsOn: Bool

    var onOpen: () -> Void = {}
    var onNotify: () -> Void = {}
    var onJoinOrLeave: () -> Void = {}

    // Scroll progress 0→1: 0 = fully expanded, 1 = fully collapsed
    var collapseProgress: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            heroBackground
                .frame(height: 200)
                .overlay(alignment: .bottom) {
                    heroArt
                        .offset(y: 50) // bleeds below the hero band
                }
                .clipped()

            // Spacer for the art overhang
            Color.clear.frame(height: 60)

            VStack(spacing: 8) {
                Text(groupName)
                    .font(.system(size: 22, weight: .bold))
                    .multilineTextAlignment(.center)
                    .opacity(1 - collapseProgress * 2)

                GroupMetadataStrip(
                    category: category,
                    memberCount: memberCount,
                    isPrivate: isPrivate
                )
                .opacity(1 - collapseProgress * 2)

                GroupActionRow(
                    isMember: isMember,
                    notificationsOn: notificationsOn,
                    onOpen: onOpen,
                    onNotify: onNotify,
                    onJoinOrLeave: onJoinOrLeave
                )
                .padding(.top, 6)
                .opacity(1 - collapseProgress * 2.5)
                .scaleEffect(1 - collapseProgress * 0.05,
                             anchor: .top)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .animation(Motion.adaptive(Motion.liquidSpring), value: collapseProgress)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var heroBackground: some View {
        let accentTint = groupAccentTint(for: groupId)
        if let url = coverImageURL, !url.isEmpty {
            CachedAsyncImage(url: URL(string: url)) { img in
                img.resizable().scaledToFill()
                    .overlay(
                        LinearGradient(
                            colors: [.clear, Color(.systemBackground).opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } placeholder: {
                gradientBackground(tint: accentTint)
            }
        } else {
            gradientBackground(tint: accentTint)
        }
    }

    private func gradientBackground(tint: Color) -> some View {
        ZStack {
            tint.opacity(0.15)
            LinearGradient(
                colors: [tint.opacity(0.35), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private var heroArt: some View {
        if let url = coverImageURL, !url.isEmpty {
            CachedAsyncImage(url: URL(string: url)) { img in
                img.resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 6)
            } placeholder: {
                GroupGradientArtView(groupId: groupId, groupName: groupName, size: 120)
            }
        } else {
            GroupGradientArtView(groupId: groupId, groupName: groupName, size: 120)
        }
    }
}

// MARK: - Preview

#Preview("Hero Header") {
    ScrollView {
        DiscussionHeroHeader(
            groupId: "group_bible_study_001",
            groupName: "Morning Scripture Circle",
            category: "Bible Study",
            memberCount: 234,
            isPrivate: false,
            coverImageURL: nil,
            isMember: false,
            notificationsOn: false
        )
    }
    .background(Color(.systemBackground))
}

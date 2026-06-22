// CreatorSpotlightHeroView.swift
// AMENAPP — Creator Spotlight / Wave 1
//
// Hero header for the Creator Spotlight page.
// Shows avatar, name, mission statement, role verification badges,
// a glass Follow pill, and a descriptive presence line.
//
// CONSTITUTION LOCK:
//   - NO star rating, NO numeric score, NO chart
//   - Presence shown as descriptive text only (not a vanity achievement)
//   - trustScore never referenced

import SwiftUI

struct CreatorSpotlightHeroView: View {

    let creatorId: String
    let spotlight: CreatorSpotlight?

    /// Display name sourced from the caller — not from trustScore or subscriber rank.
    let displayName: String
    /// Optional descriptive presence count in raw Int (e.g. 2400 → "2.4K people").
    /// Pass nil to hide the presence line entirely.
    let presenceCount: Int?

    @State private var appeared = false
    @State private var isFollowing = false
    @State private var followLoading = false

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
    private var reduceTransparency: Bool { UIAccessibility.isReduceTransparencyEnabled }

    var body: some View {
        VStack(spacing: 0) {
            avatarSection
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.92)

            missionSection
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

            badgesSection
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)

            followRow
                .opacity(appeared ? 1 : 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .background(Color(.systemBackground))
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.05)) {
                    appeared = true
                }
            }
        }
    }

    // MARK: - Avatar

    private var avatarSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 80, height: 80)
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Text(displayName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            if let count = presenceCount {
                Text("Joined by \(formatPresence(count)) people")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Mission

    @ViewBuilder
    private var missionSection: some View {
        if let mission = spotlight?.missionStatement, !mission.isEmpty {
            Text(mission)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 12)
        }
    }

    // MARK: - Verification Badges

    @ViewBuilder
    private var badgesSection: some View {
        let badges = spotlight?.verificationBadges ?? []
        if !badges.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(badges, id: \.kind) { badge in
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                            Text(badge.displayLabel)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Follow Row

    private var followRow: some View {
        Button {
            guard !followLoading else { return }
            followLoading = true
            // TODO: wire to CreatorStore follow/unfollow
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isFollowing.toggle()
                followLoading = false
            }
        } label: {
            Group {
                if followLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 80)
                } else {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isFollowing ? Color.accentColor : .white)
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 32)
            .background {
                if isFollowing {
                    if reduceTransparency {
                        Capsule().fill(Color(.secondarySystemBackground))
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                    }
                } else {
                    Capsule().fill(Color.accentColor)
                }
            }
            .overlay {
                if isFollowing {
                    Capsule().stroke(Color.accentColor, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: isFollowing)
    }

    // MARK: - Helpers

    private func formatPresence(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }
}

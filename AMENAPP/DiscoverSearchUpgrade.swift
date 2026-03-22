// DiscoverSearchUpgrade.swift
// AMENAPP
//
// Smart Search upgrades layered on top of AMENDiscoveryView / UniversalSearchResultsView:
//   PART 1 — SearchScope + SearchScopeTabBar
//   PART 3 — SearchTopProfileCard (Instagram-style top match)
//   PART 4 — BereanSearchAnswerCard (AI answer for question queries)

import SwiftUI

// MARK: - PART 1: Search Scope

enum SearchScope: String, CaseIterable {
    case forYou  = "For You"
    case people  = "People"
    case posts   = "Posts"
    case videos  = "Videos"
    case photos  = "Photos"
    case tags    = "Tags"
}

/// Horizontally scrollable filter tab row — insert directly below search bar.
struct SearchScopeTabBar: View {
    @Binding var selected: SearchScope
    @Namespace private var ns

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(SearchScope.allCases, id: \.self) { scope in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                            selected = scope
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(scope.rawValue)
                            .font(.system(size: 14, weight: selected == scope ? .semibold : .regular))
                            .foregroundStyle(selected == scope ? Color(.label) : Color(.secondaryLabel))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Group {
                                    if selected == scope {
                                        Capsule()
                                            .fill(Color(.label).opacity(0.08))
                                            .matchedGeometryEffect(id: "scope_bg", in: ns)
                                    }
                                }
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.3, dampingFraction: 0.72), value: selected)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }
}

// MARK: - PART 3: Top Profile Card

/// Instagram-style top match card with avatar, follow button, and 3-image media strip.
/// Shown above results when `searchScope == .forYou || .people` and results.people is non-empty.
struct SearchTopProfileCard: View {
    let person: DiscoveryPerson
    let previewPosts: [DiscoveryPost]
    let onFollow: () -> Void
    let onTapProfile: () -> Void
    @State private var isFollowing: Bool
    @State private var appeared = false

    init(person: DiscoveryPerson, previewPosts: [DiscoveryPost], onFollow: @escaping () -> Void, onTapProfile: @escaping () -> Void) {
        self.person = person
        self.previewPosts = previewPosts
        self.onFollow = onFollow
        self.onTapProfile = onTapProfile
        _isFollowing = State(initialValue: person.isFollowing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Profile info row
            Button(action: onTapProfile) {
                HStack(spacing: 12) {
                    // Avatar
                    Group {
                        if let urlStr = person.avatarURL, let url = URL(string: urlStr) {
                            CachedAsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Circle().fill(Color(.systemGray5))
                            }
                        } else {
                            Circle().fill(Color(.systemGray5))
                                .overlay(Text(String(person.displayName.prefix(1))).font(.system(size: 18, weight: .semibold)).foregroundStyle(.secondary))
                        }
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())

                    // Name + stats
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(person.username)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(.label))
                            if person.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.blue)
                            }
                        }
                        Text(person.displayName + " · " + formatFollowers(person.followerCount))
                            .font(.system(size: 13))
                            .foregroundStyle(Color(.secondaryLabel))
                    }

                    Spacer()

                    // Follow button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                            isFollowing.toggle()
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onFollow()
                    } label: {
                        Text(isFollowing ? "Following" : "Follow")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isFollowing ? Color(.label) : .white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(
                                isFollowing ? Color(.systemGray5) : Color(.label),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            // 3-column media preview strip — only when previewPosts have images
            let imagePosts = previewPosts.filter { $0.imageURL != nil }.prefix(3)
            if !imagePosts.isEmpty {
                HStack(spacing: 1.5) {
                    ForEach(Array(imagePosts)) { post in
                        if let urlStr = post.imageURL, let url = URL(string: urlStr) {
                            CachedAsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle().fill(Color(.systemGray6))
                            }
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                        }
                    }
                }
                .frame(height: 110)
            }

            Divider().padding(.top, 2)
        }
        .background(Color(.systemBackground))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78).delay(0.05)) {
                appeared = true
            }
        }
    }

    private func formatFollowers(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM followers", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK followers", Double(n) / 1_000) }
        return "\(n) followers"
    }
}

// MARK: - PART 4: Berean Search Answer Card

/// Shows a concise Berean AI answer when the query looks like a question.
/// Automatically triggers for queries containing '?' or starting with question words.
struct BereanSearchAnswerCard: View {
    let query: String
    let answer: String
    let isLoading: Bool
    let onAskMore: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(.label))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(.systemBackground))
                    )
                Text("Berean AI")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(.label))
                Spacer()
                Image(systemName: "ellipsis")
                    .foregroundStyle(Color(.tertiaryLabel))
                    .font(.system(size: 14))
            }

            if isLoading {
                // Typing dots
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color(.tertiaryLabel))
                            .frame(width: 6, height: 6)
                            .scaleEffect(isLoading ? 1.0 : 0.6)
                            .animation(
                                .easeInOut(duration: 0.5)
                                    .repeatForever()
                                    .delay(Double(i) * 0.15),
                                value: isLoading
                            )
                    }
                }
                .padding(.vertical, 4)
            } else if !answer.isEmpty {
                Text(answer)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineSpacing(3)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onAskMore) {
                    HStack(spacing: 5) {
                        Text("Ask Berean more about this")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Color(.label))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(0.1)) {
                appeared = true
            }
        }
    }
}

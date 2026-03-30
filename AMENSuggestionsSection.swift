//
//  AMENSuggestionsSection.swift
//  AMENAPP
//
//  Premium "Suggested for you" multi-category section.
//  Covers people, bible studies, and communities with
//  iOS Liquid Glass visual language.
//

import SwiftUI

// MARK: - Suggestion Category

enum AMENSuggestionCategory: String, CaseIterable {
    case people      = "People"
    case studies     = "Bible Studies"
    case communities = "Communities"
    case topics      = "Topics"
}

// MARK: - Suggestion Item (unified suggestion model)

struct AMENSuggestion: Identifiable {
    let id: String
    let category: AMENSuggestionCategory

    // Person fields
    var person: DiscoveryPerson?

    // Study fields (bible studies / groups)
    var studyTitle: String?
    var studySubtitle: String?    // e.g. "Romans · 6 weeks"
    var studyIcon: String?        // SF Symbol
    var studyIconColor: Color?

    // Community / topic fields
    var topic: DiscoveryTopic?

    // Shared
    var reason: String?           // "Based on your interests"
    var memberCount: Int?
    var isJoined: Bool = false
    var isFollowing: Bool = false
}

// MARK: - AMENSuggestionsSection

/// Full multi-category "Suggested for you" section.
/// Drop-in replacement for `followSuggestionsSection` inside AMENDiscoveryView.
struct AMENSuggestionsSection: View {

    // Data
    let peopleSuggestions: [FollowSuggestion]
    var isLoadingPeople: Bool = false

    // Callbacks
    var onFollowPerson: (String) -> Void = { _ in }
    var onUnfollowPerson: (String) -> Void = { _ in }
    var onStudyTap: (AMENSuggestion) -> Void = { _ in }
    var onCommunityTap: (DiscoveryTopic) -> Void = { _ in }

    @State private var selectedCategory: AMENSuggestionCategory = .people
    @Namespace private var categoryNamespace

    // Curated bible study suggestions (static, will be data-driven later)
    private let studySuggestions: [AMENSuggestion] = AMENSuggestionsSection.defaultStudies
    private let communitySuggestions: [DiscoveryTopic] = Array(DiscoveryTopic.catalog.prefix(6))

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // ── Section header ──────────────────────────────────────────
            HStack {
                Text("Suggested for you")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)

            // ── Category pill tabs ───────────────────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AMENSuggestionCategory.allCases, id: \.self) { cat in
                        AMENSuggestionCategoryPill(
                            label: cat.rawValue,
                            isSelected: selectedCategory == cat,
                            namespace: categoryNamespace
                        ) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                selectedCategory = cat
                            }
                            HapticManager.selection()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }

            // ── Cards row ───────────────────────────────────────────────
            Group {
                switch selectedCategory {
                case .people:
                    peopleCardsRow
                case .studies:
                    studyCardsRow
                case .communities:
                    communityCardsRow
                case .topics:
                    topicCardsRow
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(x: 10)),
                removal: .opacity.combined(with: .offset(x: -10))
            ))
            .id(selectedCategory) // forces transition on category change
        }
    }

    // MARK: - People Row

    @ViewBuilder
    private var peopleCardsRow: some View {
        if isLoadingPeople {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        AMENPersonSuggestionCardSkeleton()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
            }
        } else if peopleSuggestions.isEmpty {
            AMENSuggestionsEmptyCard(
                icon: "person.2",
                message: "We'll suggest people as you explore AMEN."
            )
            .padding(.horizontal, 20)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(peopleSuggestions) { suggestion in
                        AMENPersonSuggestionCard(suggestion: suggestion) {
                            if suggestion.isFollowing {
                                onUnfollowPerson(suggestion.id)
                            } else {
                                onFollowPerson(suggestion.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
            }
        }
    }

    // MARK: - Study Row

    private var studyCardsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(studySuggestions) { study in
                    AMENStudySuggestionCard(study: study) {
                        onStudyTap(study)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Community Row

    private var communityCardsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(communitySuggestions) { topic in
                    AMENCommunitySuggestionCard(topic: topic) {
                        onCommunityTap(topic)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Topic Row (reuses communities)

    private var topicCardsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(DiscoveryTopic.catalog) { topic in
                    AMENTopicPillCard(topic: topic) {
                        onCommunityTap(topic)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Static Study Data

    static let defaultStudies: [AMENSuggestion] = [
        AMENSuggestion(id: "romans", category: .studies,
                       studyTitle: "Romans",
                       studySubtitle: "The righteousness of God · 16 chapters",
                       studyIcon: "book.closed.fill", studyIconColor: .indigo,
                       reason: "Popular in your community",
                       memberCount: 1240),
        AMENSuggestion(id: "proverbs", category: .studies,
                       studyTitle: "Proverbs",
                       studySubtitle: "Wisdom for daily life · 31 chapters",
                       studyIcon: "lightbulb.fill", studyIconColor: .orange,
                       reason: "Trending this week",
                       memberCount: 980),
        AMENSuggestion(id: "sermon-on-mount", category: .studies,
                       studyTitle: "Sermon on the Mount",
                       studySubtitle: "Matthew 5–7 · 6 week study",
                       studyIcon: "mountain.2.fill", studyIconColor: .teal,
                       reason: "Recommended for you",
                       memberCount: 764),
        AMENSuggestion(id: "psalms", category: .studies,
                       studyTitle: "Psalms",
                       studySubtitle: "Praise, lament, and trust · 150 psalms",
                       studyIcon: "music.note", studyIconColor: .purple,
                       reason: "Based on your interests",
                       memberCount: 2100),
        AMENSuggestion(id: "john", category: .studies,
                       studyTitle: "Gospel of John",
                       studySubtitle: "I am the way · 21 chapters",
                       studyIcon: "cross.fill", studyIconColor: Color(red: 0.88, green: 0.38, blue: 0.28),
                       reason: "Most studied on AMEN",
                       memberCount: 3400),
        AMENSuggestion(id: "ephesians", category: .studies,
                       studyTitle: "Ephesians",
                       studySubtitle: "The armor of God · 6 chapters",
                       studyIcon: "shield.fill", studyIconColor: .blue,
                       reason: "Recommended for you",
                       memberCount: 620),
    ]
}

// MARK: - Category Pill

struct AMENSuggestionCategoryPill: View {
    let label: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                        .matchedGeometryEffect(id: "pill", in: namespace)
                }
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.78), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Person Suggestion Card (Liquid Glass)

struct AMENPersonSuggestionCard: View {
    let suggestion: FollowSuggestion
    var onFollowTap: () -> Void

    @State private var isFollowInFlight = false
    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .center, spacing: 0) {

            // ── Dismiss button ──────────────────────────────────────────
            HStack {
                Spacer()
                Button {
                    // Dismiss this suggestion (no-op for now, extend via DiscoveryService)
                    HapticManager.impact(style: .light)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // ── Avatar ──────────────────────────────────────────────────
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let urlStr = suggestion.person.avatarURL,
                       !urlStr.isEmpty,
                       let url = URL(string: urlStr) {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            avatarInitial
                        }
                    } else {
                        avatarInitial
                    }
                }
                .frame(width: 62, height: 62)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )

                // Verified badge
                if suggestion.person.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                        .background(Circle().fill(Color(.systemBackground)).frame(width: 14, height: 14))
                        .offset(x: 2, y: 2)
                }
            }
            .padding(.bottom, 10)

            // ── Name + handle ───────────────────────────────────────────
            VStack(spacing: 2) {
                Text(suggestion.person.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: 120)

                Text("@\(suggestion.person.username)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 120)
            }

            // ── Follow reason ───────────────────────────────────────────
            if !suggestion.reason.isEmpty {
                Text(suggestion.reason)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 120)
                    .padding(.top, 6)
            }

            Spacer(minLength: 10)

            // ── Follow button ───────────────────────────────────────────
            Button {
                guard !isFollowInFlight else { return }
                isFollowInFlight = true
                HapticManager.impact(style: .light)
                onFollowTap()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    isFollowInFlight = false
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(suggestion.isFollowing
                              ? Color.primary.opacity(0.07)
                              : Color.primary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )

                    if isFollowInFlight {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(suggestion.isFollowing ? .primary : Color(.systemBackground))
                    } else {
                        Text(suggestion.isFollowing ? "Following" : "Follow")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(suggestion.isFollowing
                                             ? .primary
                                             : Color(.systemBackground))
                    }
                }
                .frame(height: 36)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(isFollowInFlight)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            .padding(.top, 8)
        }
        .frame(width: 152, height: 232)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 4)
        )
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    private var avatarInitial: some View {
        ZStack {
            Circle()
                .fill(Color.primary.opacity(0.07))
            Text(String(suggestion.person.displayName.prefix(1)).uppercased())
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Study Suggestion Card (Liquid Glass)

struct AMENStudySuggestionCard: View {
    let study: AMENSuggestion
    var onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {

                // ── Icon hero ───────────────────────────────────────────
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill((study.studyIconColor ?? .indigo).opacity(0.10))
                        .frame(width: 48, height: 48)
                    Image(systemName: study.studyIcon ?? "book.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(study.studyIconColor ?? .indigo)
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)

                Spacer(minLength: 10)

                // ── Title + subtitle ────────────────────────────────────
                VStack(alignment: .leading, spacing: 3) {
                    Text(study.studyTitle ?? "")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(study.studySubtitle ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 8)

                // ── Member count + reason ───────────────────────────────
                if let count = study.memberCount {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text("\(count.formatted()) studying")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
            }
            .frame(width: 170, height: 176)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 3)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Community Suggestion Card (Liquid Glass)

struct AMENCommunitySuggestionCard: View {
    let topic: DiscoveryTopic
    var onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {

                // ── Icon + trending badge ───────────────────────────────
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(topic.iconColor.opacity(0.12))
                            .frame(width: 42, height: 42)
                        Image(systemName: topic.icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(topic.iconColor)
                    }

                    Spacer()

                    if topic.isTrending {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                            Text("Trending")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.10))
                                .overlay(Capsule().strokeBorder(Color.orange.opacity(0.20), lineWidth: 0.5))
                        )
                    }
                }
                .padding(.top, 14)
                .padding(.horizontal, 14)

                Spacer(minLength: 8)

                // ── Title ───────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 3) {
                    Text(topic.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let scripture = topic.relatedScripture {
                        Text(scripture)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 14)

                Spacer(minLength: 6)

                // ── Description ─────────────────────────────────────────
                Text(topic.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
            .frame(width: 186, height: 176)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(topic.iconColor.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 3)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Topic Pill Card (compact horizontal chip)

struct AMENTopicPillCard: View {
    let topic: DiscoveryTopic
    var onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(topic.iconColor.opacity(0.10))
                        .frame(width: 30, height: 30)
                    Image(systemName: topic.icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(topic.iconColor)
                }
                Text(topic.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Skeleton Card

struct AMENPersonSuggestionCardSkeleton: View {
    @State private var shimmer = false

    var body: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 62, height: 62)
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 80, height: 12)
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.04))
                .frame(width: 60, height: 10)
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.primary.opacity(0.06))
                .frame(height: 36)
                .padding(.horizontal, 14)
        }
        .frame(width: 152, height: 232)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
        .opacity(shimmer ? 0.5 : 1.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
    }
}

// MARK: - Empty State Card

struct AMENSuggestionsEmptyCard: View {
    let icon: String
    let message: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Suggestions Section") {
    ScrollView {
        AMENSuggestionsSection(
            peopleSuggestions: [],
            isLoadingPeople: false
        )
        .padding(.vertical, 20)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Person Card") {
    HStack {
        AMENPersonSuggestionCard(
            suggestion: FollowSuggestion(
                id: "abc",
                person: DiscoveryPerson(
                    id: "abc", displayName: "Sarah Johnson",
                    username: "sarahjohnson", bio: "Pastor & author",
                    avatarURL: nil, followerCount: 1240,
                    isVerified: true, isFollowing: false,
                    mutualFollowersCount: 4,
                    followReason: "Popular in Prayer",
                    topicAffinities: ["prayer"], qualityScore: 85
                ),
                reason: "Popular in Prayer",
                isFollowing: false
            ),
            onFollowTap: {}
        )
        AMENPersonSuggestionCard(
            suggestion: FollowSuggestion(
                id: "xyz",
                person: DiscoveryPerson(
                    id: "xyz", displayName: "Marcus Webb",
                    username: "marcuswebb", bio: "Faith & Entrepreneur",
                    avatarURL: nil, followerCount: 560,
                    isVerified: false, isFollowing: false,
                    mutualFollowersCount: 1,
                    followReason: "Faith & Work",
                    topicAffinities: ["faith-work"], qualityScore: 72
                ),
                reason: "Faith & Work",
                isFollowing: false
            ),
            onFollowTap: {}
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Study Card") {
    HStack {
        ForEach(AMENSuggestionsSection.defaultStudies.prefix(2)) { study in
            AMENStudySuggestionCard(study: study, onTap: {})
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Community Card") {
    HStack {
        ForEach(DiscoveryTopic.catalog.prefix(2)) { topic in
            AMENCommunitySuggestionCard(topic: topic, onTap: {})
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
#endif

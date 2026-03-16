// DiscoverySearchResultsView.swift
// AMEN App — Discovery & Search System
//
// Full search results screen with tabbed navigation.
// Tabs: Top | People | Posts | Topics | Churches | Notes

import SwiftUI
import FirebaseAuth

struct DiscoverySearchResultsView: View {
    let query: String

    @ObservedObject private var service = DiscoveryService.shared
    @State private var selectedTab: DiscoverySearchTab = .top

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            resultTabBar

            Divider()

            // Results content — use Group + switch to avoid TabView generic inference issues
            Group {
                switch selectedTab {
                case .top:      topResultsTab
                case .people:   peopleTab
                case .posts:    postsTab
                case .topics:   topicsTab
                case .churches: churchesTab
                case .notes:    notesTab
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedTab)
        }
    }

    // MARK: - Tab Bar

    private var resultTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(DiscoverySearchTab.allCases) { tab in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Text(tab.rawValue)
                                .font(.custom(
                                    selectedTab == tab ? "OpenSans-SemiBold" : "OpenSans-Regular",
                                    size: 14
                                ))
                                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)

                            // Active indicator
                            Rectangle()
                                .fill(selectedTab == tab ? Color.primary : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Top Results Tab

    private var topResultsTab: some View {
        Group {
            if service.isSearching {
                searchingState
            } else if service.topResults.isEmpty {
                emptyState(for: .top)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(service.topResults) { result in
                            topResultRow(result)
                            Divider().padding(.leading, 16)
                        }
                        Spacer().frame(height: 100)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func topResultRow(_ result: DiscoveryResult) -> some View {
        switch result.type {
        case .person(let person):
            SearchPersonRow(person: person) {
                Task {
                    if person.isFollowing {
                        await service.unfollowUser(userId: person.id)
                    } else {
                        await service.followUser(userId: person.id)
                    }
                }
            }
        case .topic(let topic):
            NavigationLink(destination: DiscoveryTopicPageView(topic: topic)) {
                DiscoveryTopicRow(topic: topic)
            }
            .buttonStyle(.plain)
        case .post(let post):
            SearchPostRow(post: post)
        case .church(let church):
            SearchChurchRow(church: church)
        case .note(let note):
            DiscoveryNoteRow(note: note)
        case .resource(let resource):
            DiscoveryResourceRow(resource: resource)
        case .job(let job):
            NavigationLink(destination: JobDetailView(jobId: job.id)) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "briefcase.fill")
                                .foregroundStyle(Color.accentColor)
                                .font(.subheadline)
                        }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.title)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        Text(job.employerName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - People Tab

    private var peopleTab: some View {
        Group {
            if service.isSearching {
                searchingState
            } else if service.peopleResults.isEmpty {
                emptyState(for: .people)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(service.peopleResults) { person in
                            SearchPersonRow(person: person) {
                                Task {
                                    if person.isFollowing {
                                        await service.unfollowUser(userId: person.id)
                                    } else {
                                        await service.followUser(userId: person.id)
                                    }
                                }
                            }
                            Divider().padding(.leading, 64)
                        }
                        if service.hasMorePeople {
                            loadMoreButton { /* pagination */ }
                        }
                        Spacer().frame(height: 100)
                    }
                }
            }
        }
    }

    // MARK: - Posts Tab

    private var postsTab: some View {
        Group {
            if service.isSearching {
                searchingState
            } else if service.postResults.isEmpty {
                emptyState(for: .posts)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(service.postResults) { post in
                            SearchPostRow(post: post)
                            Divider().padding(.leading, 16)
                        }
                        Spacer().frame(height: 100)
                    }
                }
            }
        }
    }

    // MARK: - Topics Tab

    private var topicsTab: some View {
        Group {
            if service.isSearching {
                searchingState
            } else if service.topicResults.isEmpty {
                emptyState(for: .topics)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(service.topicResults) { topic in
                            NavigationLink(destination: DiscoveryTopicPageView(topic: topic)) {
                                DiscoveryTopicRow(topic: topic)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 16)
                        }
                        Spacer().frame(height: 100)
                    }
                }
            }
        }
    }

    // MARK: - Churches Tab

    private var churchesTab: some View {
        Group {
            if service.isSearching {
                searchingState
            } else if service.churchResults.isEmpty {
                emptyState(for: .churches)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(service.churchResults) { church in
                            SearchChurchRow(church: church)
                            Divider().padding(.leading, 16)
                        }
                        Spacer().frame(height: 100)
                    }
                }
            }
        }
    }

    // MARK: - Notes Tab

    private var notesTab: some View {
        Group {
            if service.isSearching {
                searchingState
            } else if service.noteResults.isEmpty {
                emptyState(for: .notes)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(service.noteResults) { note in
                            DiscoveryNoteRow(note: note)
                            Divider().padding(.leading, 16)
                        }
                        Spacer().frame(height: 100)
                    }
                }
            }
        }
    }

    // MARK: - Common States

    private var searchingState: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Searching…")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func emptyState(for tab: DiscoverySearchTab) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No \(tab.rawValue.lowercased()) found for \"\(query)\"")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(32)
    }

    private func loadMoreButton(action: @escaping () -> Void) -> some View {
        Button("Load more", action: action)
            .font(.custom("OpenSans-Regular", size: 14))
            .foregroundStyle(.secondary)
            .padding()
    }
}

// MARK: - Result Row Components

struct SearchPersonRow: View {
    let person: DiscoveryPerson
    let onFollowTap: () -> Void

    @State private var isFollowInFlight = false
    @State private var showProfile = false

    var body: some View {
        // Use ZStack so the row body navigates on tap while the Follow button
        // sits on top with its own tap target — avoids the classic
        // Button-inside-NavigationLink gesture conflict where the button swallows all taps.
        ZStack(alignment: .trailing) {
            // Row content — tapping anywhere except the Follow button opens profile
            Button {
                showProfile = true
            } label: {
                HStack(spacing: 12) {
                    // Avatar — CachedAsyncImage for reliable display + scroll performance
                    ZStack {
                        Circle()
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .frame(width: 44, height: 44)
                        if let urlStr = person.avatarURL, !urlStr.isEmpty, let url = URL(string: urlStr) {
                            CachedAsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())
                            } placeholder: {
                                Text(String(person.displayName.prefix(1)).uppercased())
                                    .font(.custom("OpenSans-Bold", size: 16))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text(String(person.displayName.prefix(1)).uppercased())
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(person.displayName)
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.primary)
                            if person.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.blue)
                            }
                        }
                        Text("@\(person.username)")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                        if !person.bio.isEmpty {
                            Text(person.bio)
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    // Spacer with right-padding to leave room for the Follow button overlay
                    Spacer()
                    Color.clear.frame(width: person.id == Auth.auth().currentUser?.uid ? 0 : 90)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .navigationDestination(isPresented: $showProfile) {
                UserProfileView(userId: person.id)
            }

            // Follow button — overlaid on the right so it gets its own tap target
            if Auth.auth().currentUser?.uid != person.id {
                Button {
                    guard !isFollowInFlight else { return }
                    isFollowInFlight = true
                    onFollowTap()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isFollowInFlight = false
                    }
                } label: {
                    Text(person.isFollowing ? "Following" : "Follow")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(person.isFollowing ? .secondary : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(person.isFollowing ? Color.clear : Color.primary.opacity(0.08))
                                .overlay(Capsule().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
                .disabled(isFollowInFlight)
                .padding(.trailing, 16)
            }
        }
    }
}

struct SearchPostRow: View {
    let post: DiscoveryPost

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Author avatar
            ZStack {
                Circle()
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 36, height: 36)
                if let urlStr = post.authorAvatarURL, !urlStr.isEmpty, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                    } placeholder: {
                        Text(String(post.authorName.prefix(1)).uppercased())
                            .font(.custom("OpenSans-Bold", size: 13))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(String(post.authorName.prefix(1)).uppercased())
                        .font(.custom("OpenSans-Bold", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(post.authorName)
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.primary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(RelativeDateTimeFormatter().localizedString(for: post.createdAt, relativeTo: Date()))
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }

                Text(post.excerpt)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                HStack(spacing: 12) {
                    if let tag = post.topicTag {
                        Text(tag)
                            .font(.custom("OpenSans-SemiBold", size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                    Label("\(post.amenCount)", systemImage: "hands.sparkles")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                    Label("\(post.commentCount)", systemImage: "bubble.left")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func categoryColor(_ category: String) -> Color {
        switch category.lowercased() {
        case "prayer": return .purple
        case "testimonies": return .orange
        case "opentable": return .blue
        case "tip": return .green
        default: return .gray.opacity(0.4)
        }
    }
}

struct DiscoveryTopicRow: View {
    let topic: DiscoveryTopic

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: topic.icon)
                .font(.system(size: 18))
                .foregroundStyle(topic.iconColor)
                .frame(width: 44, height: 44)
                .background(topic.backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(topic.title)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.primary)
                    if topic.isTrending {
                        Text("Trending")
                            .font(.custom("OpenSans-SemiBold", size: 10))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.1)))
                    }
                }
                Text(topic.description)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if topic.postCount > 0 {
                    Text("\(topic.postCount) posts")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct SearchChurchRow: View {
    let church: DiscoveryChurch

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let url = church.imageURL, !url.isEmpty {
                    CachedAsyncImage(url: URL(string: url)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.1))
                            .overlay(Image(systemName: "building.columns.fill")
                                .foregroundStyle(.blue))
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 44, height: 44)
                        .overlay(Image(systemName: "building.columns.fill")
                            .foregroundStyle(.blue))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(church.name)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.primary)
                    if church.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.blue)
                    }
                }
                Text("\(church.city), \(church.state)")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                if let den = church.denomination {
                    Text(den)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let dist = church.distanceMiles {
                Text(String(format: "%.1f mi", dist))
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct DiscoveryNoteRow: View {
    let note: DiscoveryNote

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.indigo.opacity(0.1))
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "doc.text.fill")
                    .foregroundStyle(.indigo))

            VStack(alignment: .leading, spacing: 3) {
                Text(note.title)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let speaker = note.speakerName {
                    Text(speaker)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                if let scripture = note.scriptureReference {
                    Text(scripture)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct DiscoveryResourceRow: View {
    let resource: DiscoveryResource

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.teal.opacity(0.1))
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "bookmark.fill")
                    .foregroundStyle(.teal))

            VStack(alignment: .leading, spacing: 3) {
                Text(resource.title)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(resource.type.capitalized)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

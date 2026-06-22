// FollowKnowledgeView.swift
// AMEN Catalog — Follow Topics + Knowledge Feed
//
// Privacy contract:
//   - Following is ALWAYS explicit user action (opt-in only, never forced)
//   - No engagement scores, leaderboards, or popularity ranks shown
//   - Catalog update notifications are in-app only by default
//
// Layout:
//   FollowKnowledgeView   — Your Topics + Discover Topics
//   TopicFeedView         — Recent works across followed topics
//
// Liquid Glass: glass capsules, secondary backgrounds, SF Pro type, no gold/purple surfaces.

import SwiftUI
import FirebaseFunctions

// MARK: - Models

struct FollowedTopic: Identifiable {
    let id: String          // topicId
    let topicName: String
    let recentWorkCount: Int
    let followedAt: Date?
}

struct DiscoverableTopic: Identifiable {
    let id: String          // topicId
    let topicName: String
    var isFollowed: Bool
}

// MARK: - Hardcoded starter topic list (matches CF predefined list)

private let starterTopics: [DiscoverableTopic] = [
    "Leadership", "Prayer", "Marriage", "AI", "Startups", "Faith", "Finance", "Health",
    "Relationships", "Creativity", "Scripture", "Justice", "Worship", "Education",
    "Business", "Parenting", "Mental Health", "Community", "Social Justice", "Technology",
    "Discipleship", "Evangelism", "Church", "Family", "Serving", "Missions",
    "Theology", "Apologetics", "Counseling", "Devotional",
].map { name in
    DiscoverableTopic(
        id: name.lowercased().replacingOccurrences(of: " ", with: "-"),
        topicName: name,
        isFollowed: false
    )
}

// MARK: - ViewModel

@MainActor
final class FollowKnowledgeViewModel: ObservableObject {

    @Published var followedTopics: [FollowedTopic] = []
    @Published var discoverTopics: [DiscoverableTopic] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // Optimistic pending set — topic IDs being followed/unfollowed
    @Published var pendingFollowIds: Set<String> = []

    private let functions = Functions.functions()

    // MARK: - Load

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await functions.httpsCallable("getFollowedTopics").call([:])
            guard let data = result.data as? [String: Any] else {
                isLoading = false
                return
            }

            let rawTopics = data["topics"] as? [[String: Any]] ?? []
            let loaded: [FollowedTopic] = rawTopics.compactMap { d in
                guard let id = d["topicId"] as? String else { return nil }
                var followedAt: Date?
                if let ms = d["followedAt"] as? Double {
                    followedAt = Date(timeIntervalSince1970: ms / 1000)
                }
                return FollowedTopic(
                    id: id,
                    topicName: d["topicName"] as? String ?? id,
                    recentWorkCount: d["recentWorkCount"] as? Int ?? 0,
                    followedAt: followedAt
                )
            }
            followedTopics = loaded

            let followedIds = Set(loaded.map(\.id))
            discoverTopics = starterTopics.map { topic in
                var t = topic
                t.isFollowed = followedIds.contains(topic.id)
                return t
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Follow (optimistic)

    func follow(topic: DiscoverableTopic) {
        guard !pendingFollowIds.contains(topic.id) else { return }
        guard !followedTopics.contains(where: { $0.id == topic.id }) else { return }

        // Optimistic update
        pendingFollowIds.insert(topic.id)
        updateFollowState(topicId: topic.id, isFollowed: true)

        Task {
            do {
                _ = try await functions.httpsCallable("followTopic").call([
                    "topicId": topic.id,
                    "topicName": topic.topicName,
                ])
                // Refresh to sync server state
                await load()
            } catch {
                // Rollback on failure
                updateFollowState(topicId: topic.id, isFollowed: false)
                errorMessage = "Could not follow topic. Please try again."
            }
            pendingFollowIds.remove(topic.id)
        }
    }

    // MARK: - Unfollow (optimistic)

    func unfollow(topicId: String) {
        guard !pendingFollowIds.contains(topicId) else { return }

        // Optimistic update
        pendingFollowIds.insert(topicId)
        followedTopics.removeAll { $0.id == topicId }
        updateFollowState(topicId: topicId, isFollowed: false)

        Task {
            do {
                _ = try await functions.httpsCallable("unfollowTopic").call([
                    "topicId": topicId,
                ])
                await load()
            } catch {
                // Rollback — reload to recover true state
                await load()
                errorMessage = "Could not unfollow topic. Please try again."
            }
            pendingFollowIds.remove(topicId)
        }
    }

    private func updateFollowState(topicId: String, isFollowed: Bool) {
        if let idx = discoverTopics.firstIndex(where: { $0.id == topicId }) {
            discoverTopics[idx].isFollowed = isFollowed
        }
    }
}

// MARK: - FollowKnowledgeView

struct FollowKnowledgeView: View {

    @StateObject private var vm = FollowKnowledgeViewModel()
    @State private var showTopicFeed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.followedTopics.isEmpty {
                    loadingView
                } else {
                    scrollContent
                }
            }
            .navigationTitle("Topics")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showTopicFeed = true
                    } label: {
                        Label("Topic Feed", systemImage: "list.bullet.below.rectangle")
                    }
                    .disabled(vm.followedTopics.isEmpty)
                    .accessibilityLabel("View topic feed")
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .navigationDestination(isPresented: $showTopicFeed) {
                FollowTopicFeedView()
            }
            .alert("Error", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                yourTopicsSection
                discoverTopicsSection
            }
            .padding(.vertical, 20)
        }
    }

    // MARK: - Your Topics

    private var yourTopicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            KnowledgeSectionHeader(title:"Your Topics", subtitle: "Topics you're following")

            if vm.followedTopics.isEmpty {
                emptyFollowedState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(vm.followedTopics) { topic in
                            FollowedTopicChip(
                                topic: topic,
                                isPending: vm.pendingFollowIds.contains(topic.id)
                            ) {
                                vm.unfollow(topicId: topic.id)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var emptyFollowedState: some View {
        HStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.systemScaled(20))
                .foregroundStyle(.secondary)
            Text("Follow topics to see relevant works")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .accessibilityLabel("No followed topics. Follow topics below to see relevant works.")
    }

    // MARK: - Discover Topics

    private var discoverTopicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            KnowledgeSectionHeader(title:"Discover Topics", subtitle: "Tap to follow")

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 120), spacing: 10),
                ],
                spacing: 10
            ) {
                ForEach($vm.discoverTopics) { $topic in
                    DiscoverTopicCell(
                        topic: topic,
                        isPending: vm.pendingFollowIds.contains(topic.id)
                    ) {
                        if topic.isFollowed {
                            vm.unfollow(topicId: topic.id)
                        } else {
                            vm.follow(topic: topic)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Loading topics...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .accessibilityLabel("Loading topics")
    }
}

// MARK: - Followed Topic Chip

private struct FollowedTopicChip: View {
    let topic: FollowedTopic
    let isPending: Bool
    let onUnfollow: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.topicName)
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(.primary)
                if topic.recentWorkCount > 0 {
                    Text("\(topic.recentWorkCount) new")
                        .font(.systemScaled(11))
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                onUnfollow()
            } label: {
                if isPending {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "xmark")
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Unfollow \(topic.topicName)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .opacity(isPending ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isPending)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(topic.topicName), followed. Double-tap the X to unfollow.")
    }
}

// MARK: - Discover Topic Cell

private struct DiscoverTopicCell: View {
    let topic: DiscoverableTopic
    let isPending: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(topic.topicName)
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(topic.isFollowed ? Color(uiColor: .label) : .primary)
                    .lineLimit(1)
                Spacer()
                Group {
                    if isPending {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 14, height: 14)
                    } else if topic.isFollowed {
                        Image(systemName: "checkmark")
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(.blue)
                    } else {
                        Image(systemName: "plus")
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                topic.isFollowed
                    ? Color.blue.opacity(0.08)
                    : Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(topic.isFollowed ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .disabled(isPending)
        .opacity(isPending ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: topic.isFollowed)
        .accessibilityLabel(topic.isFollowed ? "Following \(topic.topicName). Tap to unfollow." : "Follow \(topic.topicName)")
    }
}

// MARK: - Section Header

private struct KnowledgeSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.systemScaled(20, weight: .bold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - TopicFeedUIState (local, avoids importing CatalogUIState's DocumentSnapshot dependency)

private enum TopicFeedUIState {
    case loading
    case empty
    case populated
    case error(String)
}

// MARK: - TopicFeedView

struct FollowTopicFeedView: View {

    @State private var works: [TopicFeedWork] = []
    @State private var feedState: TopicFeedUIState = .loading
    @State private var followedTopicNames: [String] = []

    private let functions = Functions.functions()

    var body: some View {
        Group {
            switch feedState {
            case .loading:
                feedLoadingView
            case .empty:
                feedEmptyView
            case .populated:
                feedList
            case .error(let msg):
                feedErrorView(msg)
            }
        }
        .navigationTitle("Topic Feed")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadFeed() }
        .refreshable { await loadFeed() }
    }

    // MARK: - Feed List

    private var feedList: some View {
        List {
            if !followedTopicNames.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(followedTopicNames, id: \.self) { name in
                                Text(name)
                                    .font(.systemScaled(13, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Your topics")
                }
            }

            Section {
                ForEach(works) { work in
                    TopicFeedWorkRow(work: work)
                }
            } header: {
                Text("Latest works")
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - States

    private var feedLoadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Loading your topic feed...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .accessibilityLabel("Loading topic feed")
    }

    private var feedEmptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bookmark.slash")
                .font(.systemScaled(44))
                .foregroundStyle(.secondary)
            Text("Follow topics to see their latest works here")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Go back and follow topics you care about.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    private func feedErrorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(44))
                .foregroundStyle(.secondary)
            Text("Could not load feed")
                .font(.headline)
            Button("Try Again") { Task { await loadFeed() } }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
    }

    // MARK: - Load

    private func loadFeed() async {
        feedState = .loading
        do {
            let result = try await functions.httpsCallable("getTopicFeed").call([:])
            guard let data = result.data as? [String: Any] else {
                feedState = .empty
                return
            }

            let rawWorks = data["works"] as? [[String: Any]] ?? []
            let loaded: [TopicFeedWork] = rawWorks.compactMap { d in
                guard let id = d["id"] as? String else { return nil }
                var publishedAt: Date?
                if let ms = d["publishedAt"] as? Double {
                    publishedAt = Date(timeIntervalSince1970: ms / 1000)
                }
                return TopicFeedWork(
                    id: id,
                    title: d["title"] as? String ?? "",
                    type: d["type"] as? String ?? "article",
                    creatorName: d["creatorName"] as? String ?? "",
                    creatorAvatar: d["creatorAvatar"] as? String,
                    coverUrl: d["coverUrl"] as? String,
                    topics: d["topics"] as? [String] ?? [],
                    publishedAt: publishedAt
                )
            }

            followedTopicNames = data["topics"] as? [String] ?? []
            works = loaded
            feedState = loaded.isEmpty ? .empty : .populated
        } catch {
            feedState = .error(error.localizedDescription)
        }
    }
}

// MARK: - TopicFeedWork (local model, avoids dependency on CatalogWork DocumentSnapshot)

struct TopicFeedWork: Identifiable {
    let id: String
    let title: String
    let type: String
    let creatorName: String
    let creatorAvatar: String?
    let coverUrl: String?
    let topics: [String]
    let publishedAt: Date?
}

// MARK: - Topic Feed Work Row

private struct TopicFeedWorkRow: View {
    let work: TopicFeedWork

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            // Cover
            Group {
                if let url = work.coverUrl, let imgURL = URL(string: url) {
                    AsyncImage(url: imgURL) { img in img.resizable().scaledToFill() }
                    placeholder: { coverPlaceholder }
                } else {
                    coverPlaceholder
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(work.title)
                    .font(.systemScaled(15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(work.type.capitalized)
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())

                    Text(work.creatorName)
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !work.topics.isEmpty {
                    Text(work.topics.prefix(2).joined(separator: " · "))
                        .font(.systemScaled(12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let date = work.publishedAt {
                Text(Self.dateFormatter.string(from: date))
                    .font(.systemScaled(11))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(work.title), \(work.type), by \(work.creatorName)")
    }

    private var coverPlaceholder: some View {
        Image(systemName: "doc.text")
            .font(.systemScaled(22))
            .foregroundStyle(.secondary)
            .frame(width: 52, height: 52)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}


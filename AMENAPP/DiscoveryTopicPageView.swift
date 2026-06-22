// DiscoveryTopicPageView.swift
// AMEN App — Discovery & Search System
//
// Dedicated topic landing page.
// Shows: topic header, AI summary, top posts, related topics, related scripture.

import SwiftUI
import FirebaseFirestore

struct DiscoveryTopicPageView: View {
    let topic: DiscoveryTopic

    @State private var topPosts: [DiscoveryPost] = []
    @State private var latestPosts: [DiscoveryPost] = []
    @State private var relatedTopics: [DiscoveryTopic] = []
    @State private var isLoadingPosts = true
    @State private var isFollowingTopic = false
    @State private var selectedSegment: Segment = .top

    enum Segment: String, CaseIterable { case top = "Top", latest = "Latest" }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Topic header
                topicHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 20)

                Divider()

                // Segment picker
                segmentPicker
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)

                Divider()

                // Posts
                if isLoadingPosts {
                    VStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { _ in
                            DiscoveryTrendSkeletonCard()
                        }
                    }
                    .padding(16)
                } else {
                    let posts = selectedSegment == .top ? topPosts : latestPosts
                    if posts.isEmpty {
                        VStack(spacing: 12) {
                            Spacer(minLength: 40)
                            Image(systemName: topic.icon)
                                .font(.systemScaled(32))
                                .foregroundStyle(topic.iconColor.opacity(0.5))
                            Text("No posts in \(topic.title) yet")
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 40)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(posts) { post in
                            SearchPostRow(post: post)
                            Divider().padding(.leading, 16)
                        }
                    }
                }

                // Related topics
                if !relatedTopics.isEmpty {
                    relatedTopicsSection
                        .padding(.top, 24)
                }

                // Scripture reference
                if let scripture = topic.relatedScripture {
                    scriptureReference(scripture)
                        .padding(16)
                }

                Spacer().frame(height: 100)
            }
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                        isFollowingTopic.toggle()
                    }
                } label: {
                    Text(isFollowingTopic ? "Following" : "Follow")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(isFollowingTopic ? .secondary : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isFollowingTopic ? Color.clear : Color.primary.opacity(0.08))
                                .overlay(Capsule().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .task { await loadPosts() }
    }

    // MARK: - Topic Header

    private var topicHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: topic.icon)
                    .font(.systemScaled(28, weight: .medium))
                    .foregroundStyle(topic.iconColor)
                    .frame(width: 60, height: 60)
                    .background(topic.backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text(topic.title)
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(.primary)
                    if !topic.description.isEmpty {
                        Text(topic.description)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Text(topic.description)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Segment Picker

    private var segmentPicker: some View {
        HStack(spacing: 0) {
            ForEach(Segment.allCases, id: \.self) { seg in
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.85))) {
                        selectedSegment = seg
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(seg.rawValue)
                            .font(.custom(
                                selectedSegment == seg ? "OpenSans-SemiBold" : "OpenSans-Regular",
                                size: 14
                            ))
                            .foregroundStyle(selectedSegment == seg ? .primary : .secondary)
                        Rectangle()
                            .fill(selectedSegment == seg ? Color.primary : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Related Topics

    private var relatedTopicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Related topics")
                .font(.custom("OpenSans-SemiBold", size: 15))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(relatedTopics) { related in
                        NavigationLink(destination: DiscoveryTopicPageView(topic: related)) {
                            TopicChipButton(topic: related) {}
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Scripture Reference

    private func scriptureReference(_ ref: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "book.fill")
                .font(.systemScaled(14))
                .foregroundStyle(.indigo)
            Text(ref)
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(.indigo)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.systemScaled(11))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.indigo.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.indigo.opacity(0.12), lineWidth: 0.5))
        )
    }

    // MARK: - Data Load

    private func loadPosts() async {
        isLoadingPosts = true
        defer { isLoadingPosts = false }

        // Load top posts — ordered by recency (no engagement ranking)
        do {
            let topSnapshot = try await Firestore.firestore().collection("posts")
                .whereField("topicTag", isEqualTo: topic.canonicalSlug)
                .whereField("visibility", isEqualTo: "everyone")
                .order(by: "createdAt", descending: true)
                .limit(to: 10)
                .getDocuments()

            topPosts = topSnapshot.documents.compactMap { makePost(from: $0) }

            // Load latest posts by date
            let latestSnapshot = try await Firestore.firestore().collection("posts")
                .whereField("topicTag", isEqualTo: topic.canonicalSlug)
                .whereField("visibility", isEqualTo: "everyone")
                .order(by: "createdAt", descending: true)
                .limit(to: 20)
                .getDocuments()

            latestPosts = latestSnapshot.documents.compactMap { makePost(from: $0) }

        } catch {
            // Non-fatal — empty state shown
        }

        // Build related topics from catalog (topics in same category cluster)
        relatedTopics = DiscoveryTopic.catalog
            .filter { $0.id != topic.id }
            .prefix(6)
            .map { $0 }
    }

    private func makePost(from doc: QueryDocumentSnapshot) -> DiscoveryPost? {
        let d = doc.data()
        guard let content = d["content"] as? String else { return nil }
        return DiscoveryPost(
            id: doc.documentID,
            authorId: d["authorId"] as? String ?? "",
            authorName: d["authorDisplayName"] as? String ?? "",
            authorHandle: d["authorUsername"] as? String ?? "",
            authorAvatarURL: d["authorProfileImageURL"] as? String,
            excerpt: String(content.prefix(180)),
            fullContent: content,
            category: d["category"] as? String ?? "",
            topicTag: d["topicTag"] as? String,
            createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            amenCount: d["amenCount"] as? Int ?? 0,
            commentCount: d["commentCount"] as? Int ?? 0,
            imageURL: (d["imageURLs"] as? [String])?.first,
            highlightedExcerpt: nil
        )
    }
}

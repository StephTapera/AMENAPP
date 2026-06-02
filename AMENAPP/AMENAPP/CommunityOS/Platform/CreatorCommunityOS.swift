// CreatorCommunityOS.swift
// AMEN App — Community Around Content OS / Platform Layer
//
// Private analytics dashboard for creators.
// Shows meaningful engagement only — no likes, no follower counts, no vanity metrics.
//
// Feature flag: CommunityOSFlag.creatorCommunityOS

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - CreatorEngagementSummary

/// A private summary of how a creator's content is generating meaningful spiritual activity.
/// Deliberately excludes likes, views, follower counts, and any vanity metrics.
struct CreatorEngagementSummary: Codable {
    /// Number of prayers inspired by the creator's content.
    var prayersGeneratedCount: Int
    /// Number of study sessions started because of the creator's content.
    var studiesStartedCount: Int
    /// Number of testimonies shared in communities around the creator's content.
    var testimonyCount: Int
    /// Number of community nodes auto-created around the creator's content.
    var communitiesCreatedCount: Int
    /// Number of church libraries that have included the creator's content.
    var churchesUsingContent: Int
    /// Most common spiritual themes across the creator's content.
    var topThemes: [String]

    init(
        prayersGeneratedCount: Int = 0,
        studiesStartedCount: Int = 0,
        testimonyCount: Int = 0,
        communitiesCreatedCount: Int = 0,
        churchesUsingContent: Int = 0,
        topThemes: [String] = []
    ) {
        self.prayersGeneratedCount = prayersGeneratedCount
        self.studiesStartedCount = studiesStartedCount
        self.testimonyCount = testimonyCount
        self.communitiesCreatedCount = communitiesCreatedCount
        self.churchesUsingContent = churchesUsingContent
        self.topThemes = topThemes
    }
}

// MARK: - CreatorCommunityOS

@MainActor
final class CreatorCommunityOS: ObservableObject {

    // MARK: Published state

    /// The creator's shared content objects, fetched from Firestore.
    @Published var contentObjects: [ContentObject] = []
    /// Auto-created community nodes around the creator's content.
    @Published var communityNodes: [CommunityNode] = []
    /// Aggregated meaningful engagement summary.
    @Published var engagementSummary: CreatorEngagementSummary?
    @Published var isLoading = false

    // MARK: Private

    private let db = Firestore.firestore()

    // MARK: - loadDashboard

    /// Fetches content objects authored by `creatorId`, associated community nodes,
    /// and computes a meaningful engagement summary.
    func loadDashboard(creatorId: String) async {
        guard CommunityOSFlagService.shared.isEnabled(.creatorCommunityOS) else {
            dlog("[CreatorCommunityOS] Flag creatorCommunityOS is off — skipping dashboard load")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Fetch content objects authored by this creator
            let contentSnapshot = try await db
                .collection("contentObjects")
                .whereField("authorId", isEqualTo: creatorId)
                .order(by: "createdAt", descending: true)
                .limit(to: 50)
                .getDocuments()

            let fetchedContent = contentSnapshot.documents.compactMap { doc -> ContentObject? in
                ContentObject(from: doc.data())
            }
            contentObjects = fetchedContent

            // Fetch community nodes associated with the creator's content
            let contentIds = fetchedContent.map { $0.id }
            guard !contentIds.isEmpty else {
                communityNodes = []
                engagementSummary = CreatorEngagementSummary()
                dlog("[CreatorCommunityOS] No content found for creator \(creatorId)")
                return
            }

            // Firestore array-contains-any is limited to 30 items per query
            let chunkedIds = stride(from: 0, to: contentIds.count, by: 30).map {
                Array(contentIds[$0..<min($0 + 30, contentIds.count)])
            }

            var allNodes: [CommunityNode] = []
            for chunk in chunkedIds {
                let nodeSnapshot = try await db
                    .collection("communityNodes")
                    .whereField("contentObjectId", in: chunk)
                    .getDocuments()
                let nodes = nodeSnapshot.documents.compactMap { doc -> CommunityNode? in
                    CommunityNode(from: doc.data())
                }
                allNodes.append(contentsOf: nodes)
            }
            communityNodes = allNodes

            // Compute meaningful summary
            engagementSummary = buildSummary(content: fetchedContent, nodes: allNodes)
            dlog("[CreatorCommunityOS] Dashboard loaded for creator \(creatorId): \(fetchedContent.count) items, \(allNodes.count) nodes")
        } catch {
            dlog("[CreatorCommunityOS] Error loading dashboard: \(error)")
        }
    }

    // MARK: - Queries

    /// Returns the creator's content object that has generated the most prayers.
    func getContentWithMostPrayer() -> ContentObject? {
        contentObjects.max(by: { $0.prayerCount < $1.prayerCount })
    }

    /// Returns the creator's content object that has generated the most testimonies.
    func getContentWithMostTestimonies() -> ContentObject? {
        contentObjects.max(by: { $0.testimonyCount < $1.testimonyCount })
    }

    /// Returns the community node with the highest health score.
    var topCommunity: CommunityNode? {
        communityNodes.max(by: { $0.healthScore < $1.healthScore })
    }

    // MARK: - Private helpers

    private func buildSummary(content: [ContentObject], nodes: [CommunityNode]) -> CreatorEngagementSummary {
        let prayers = content.reduce(0) { $0 + $1.prayerCount }
        let studies = content.reduce(0) { $0 + $1.discussionCount }   // proxy: discussions often include studies
        let testimonies = content.reduce(0) { $0 + $1.testimonyCount }
        let communities = nodes.count
        let churches = nodes.reduce(0) { $0 + $1.churchCount }

        // Collect themes, ranked by frequency
        var themeFrequency: [String: Int] = [:]
        for item in content {
            for theme in item.themes {
                themeFrequency[theme, default: 0] += 1
            }
        }
        let topThemes = themeFrequency
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }

        return CreatorEngagementSummary(
            prayersGeneratedCount: prayers,
            studiesStartedCount: studies,
            testimonyCount: testimonies,
            communitiesCreatedCount: communities,
            churchesUsingContent: churches,
            topThemes: Array(topThemes)
        )
    }
}

// MARK: - CreatorCommunityDashboardView

/// Private analytics dashboard for a creator.
/// Surfaces only meaningful spiritual impact — never vanity metrics.
struct CreatorCommunityDashboardView: View {

    @StateObject private var vm = CreatorCommunityOS()
    let creatorId: String

    var body: some View {
        Group {
            if CommunityOSFlagService.shared.isEnabled(.creatorCommunityOS) {
                dashboardContent
            } else {
                Color(.systemBackground)
            }
        }
        .task {
            await vm.loadDashboard(creatorId: creatorId)
        }
    }

    // MARK: Dashboard content

    @ViewBuilder
    private var dashboardContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                if vm.isLoading {
                    loadingState
                } else if vm.contentObjects.isEmpty {
                    emptyState
                } else {
                    // Stats grid
                    if let summary = vm.engagementSummary {
                        statsGrid(summary: summary)
                    }

                    // Top content section
                    topContentSection

                    // Communities list
                    communitiesSection
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .navigationTitle("Your Community Impact")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your Community Impact")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(Color(.label))
            Text("Private · Only visible to you")
                .font(.caption)
                .foregroundColor(Color(.secondaryLabel))
        }
    }

    // MARK: Stats grid

    private func statsGrid(summary: CreatorEngagementSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Community Activity")
                .font(.headline)
                .foregroundColor(Color(.label))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statCard(
                    value: summary.prayersGeneratedCount,
                    label: "Prayers Inspired",
                    icon: "hands.sparkles.fill",
                    color: Color(hex: "#6B48FF")
                )
                statCard(
                    value: summary.studiesStartedCount,
                    label: "Studies Started",
                    icon: "text.book.closed.fill",
                    color: Color(hex: "#1A7BD4")
                )
                statCard(
                    value: summary.testimonyCount,
                    label: "Testimonies Shared",
                    icon: "star.bubble.fill",
                    color: Color(hex: "#D4A017")
                )
                statCard(
                    value: summary.communitiesCreatedCount,
                    label: "Communities Built",
                    icon: "person.3.fill",
                    color: Color(hex: "#2DAA6B")
                )
            }

            if summary.churchesUsingContent > 0 {
                statCard(
                    value: summary.churchesUsingContent,
                    label: "Churches Using Your Content",
                    icon: "building.columns.fill",
                    color: Color(.systemTeal),
                    wide: true
                )
            }
        }
    }

    @ViewBuilder
    private func statCard(value: Int, label: String, icon: String, color: Color, wide: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Color(.label))
                Text(label)
                    .font(.caption)
                    .foregroundColor(Color(.secondaryLabel))
                    .lineLimit(2)
            }
            if wide { Spacer() }
        }
        .padding(12)
        .frame(maxWidth: wide ? .infinity : nil, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Top content

    @ViewBuilder
    private var topContentSection: some View {
        let prayerContent = vm.getContentWithMostPrayer()
        let testimonyContent = vm.getContentWithMostTestimonies()

        if prayerContent != nil || testimonyContent != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Impact")
                    .font(.headline)
                    .foregroundColor(Color(.label))

                if let item = prayerContent {
                    topContentCard(
                        content: item,
                        label: "Most Prayers",
                        valueLabel: "\(item.prayerCount) prayers",
                        icon: "hands.sparkles.fill",
                        color: Color(hex: "#6B48FF")
                    )
                }
                if let item = testimonyContent {
                    topContentCard(
                        content: item,
                        label: "Most Testimonies",
                        valueLabel: "\(item.testimonyCount) testimonies",
                        icon: "star.bubble.fill",
                        color: Color(hex: "#D4A017")
                    )
                }
            }
        }
    }

    private func topContentCard(
        content: ContentObject,
        label: String,
        valueLabel: String,
        icon: String,
        color: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: content.kind.systemImage)
                .font(.title3)
                .foregroundColor(Color(.secondaryLabel))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                Text(content.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color(.label))
                    .lineLimit(1)
                Text(valueLabel)
                    .font(.caption)
                    .foregroundColor(Color(.secondaryLabel))
            }
            Spacer()

            Image(systemName: icon)
                .foregroundColor(color)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Communities section

    @ViewBuilder
    private var communitiesSection: some View {
        if !vm.communityNodes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Communities")
                    .font(.headline)
                    .foregroundColor(Color(.label))

                ForEach(vm.communityNodes.sorted(by: { $0.healthScore > $1.healthScore })) { node in
                    communityRow(node: node)
                }
            }
        }
    }

    private func communityRow(node: CommunityNode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: node.contentKind.systemImage)
                .font(.body)
                .foregroundColor(Color(.secondaryLabel))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(node.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color(.label))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(node.memberCount) members")
                        .font(.caption)
                        .foregroundColor(Color(.secondaryLabel))

                    CommunityHealthTierBadgeView(
                        tier: CommunityHealthService.shared.computeHealthTierSync(
                            score: node.healthScore
                        )
                    )
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 44))
                .foregroundColor(Color(.secondaryLabel))
            Text("Share content to start building community around your work")
                .font(.body)
                .foregroundColor(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: Loading state

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading your community impact...")
                .font(.caption)
                .foregroundColor(Color(.secondaryLabel))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - CommunityHealthService sync helper

/// Synchronous tier computation exposed for view-layer use without crossing actor boundaries.
extension CommunityHealthService {
    nonisolated func computeHealthTierSync(score: Double) -> CommunityHealthTier {
        switch score {
        case 0.80...:     return .thriving
        case 0.65..<0.80: return .healthy
        case 0.45..<0.65: return .growing
        case 0.25..<0.45: return .dormant
        default:          return .atrisk
        }
    }
}

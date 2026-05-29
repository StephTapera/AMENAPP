// DiscussionDiscoveryHomeView.swift
// AMENAPP — Discussions
//
// "Home / Browse" surface for group discovery.
// Mirrors Apple Music Home:
//   - "Top Picks for You" hero carousel (paged, auto-advances)
//   - "Recently Visited" shelf (groups the user has opened)
//   - "Browse by Topic" category grid
//   - Tap any card → DiscussionGroupDetailView (album page)
//
// Wired from AmenDiscoverView when discussionDiscoveryHomeEnabled is true.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class DiscussionDiscoveryViewModel: ObservableObject {
    @Published private(set) var topPicks: [CommunityGroup] = []
    @Published private(set) var recentlyVisited: [CommunityGroup] = []
    @Published private(set) var isLoading = true

    private var db: Firestore { Firestore.firestore() }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadTopPicks() }
            group.addTask { await self.loadRecentlyVisited() }
        }
    }

    private func loadTopPicks() async {
        do {
            let snapshot = try await db.collection("communityGroups")
                .whereField("isPrivate", isEqualTo: false)
                .order(by: "memberCount", descending: true)
                .limit(to: 10)
                .getDocuments()
            topPicks = snapshot.documents.compactMap { try? $0.data(as: CommunityGroup.self) }
        } catch {
            topPicks = []
        }
    }

    private func loadRecentlyVisited() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let snapshot = try await db.collection("userGroupLibrary")
                .document(uid)
                .collection("addedGroups")
                .order(by: "addedAt", descending: true)
                .limit(to: 8)
                .getDocuments()
            recentlyVisited = snapshot.documents.compactMap { doc -> CommunityGroup? in
                let data = doc.data()
                return CommunityGroup(
                    id: doc.documentID,
                    name: data["groupName"] as? String ?? "",
                    description: "",
                    category: CommunityGroup.GroupCategory(
                        rawValue: data["groupCategory"] as? String ?? "General"
                    ) ?? .general,
                    creatorId: "",
                    memberCount: data["memberCount"] as? Int ?? 0,
                    coverImageURL: data["coverImageURL"] as? String,
                    isPrivate: data["isPrivate"] as? Bool ?? false,
                    createdAt: Date(),
                    rules: []
                )
            }
        } catch {
            recentlyVisited = []
        }
    }
}

// MARK: - View

struct DiscussionDiscoveryHomeView: View {
    @StateObject private var viewModel = DiscussionDiscoveryViewModel()
    @State private var selectedGroup: CommunityGroup?
    @State private var heroPage = 0
    @State private var heroTimer: Timer?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    topPicksSection
                    if !viewModel.recentlyVisited.isEmpty {
                        recentlyVisitedSection
                    }
                    browseByCategorySection
                    Spacer().frame(height: 40)
                }
                .padding(.top, 8)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SmartCommunitySearchView()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .accessibilityLabel("Search groups")
                    }
                }
            }
            .task { await viewModel.load() }
            .navigationDestination(item: $selectedGroup) { group in
                GroupView(groupId: group.id)
            }
        }
    }

    // MARK: - Top Picks carousel

    private var topPicksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Top Picks for You")

            if viewModel.isLoading {
                topPicksSkeleton
            } else if viewModel.topPicks.isEmpty {
                emptyTopPicks
            } else {
                TabView(selection: $heroPage) {
                    ForEach(Array(viewModel.topPicks.enumerated()), id: \.element.id) { idx, group in
                        DiscussionTopPicksCard(
                            group: group,
                            width: UIScreen.main.bounds.width - 32,
                            height: 200,
                            onTap: { selectedGroup = $0 }
                        )
                        .padding(.horizontal, 16)
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(height: 220)
                .onAppear { startHeroTimer() }
                .onDisappear { stopHeroTimer() }
            }
        }
    }

    private var topPicksSkeleton: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color(.systemFill))
            .frame(height: 200)
            .padding(.horizontal, 16)
            .redacted(reason: .placeholder)
    }

    private var emptyTopPicks: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "person.3")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("No groups found yet")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(height: 160)
    }

    // MARK: - Recently Visited shelf

    private var recentlyVisitedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recently Visited")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(viewModel.recentlyVisited) { group in
                        Button { selectedGroup = group } label: {
                            recentCard(group)
                        }
                        .buttonStyle(AmenPressStyle(scale: 0.965))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    private func recentCard(_ group: CommunityGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupGradientArtView(groupId: group.id, groupName: group.name, size: 100)
                .shadow(color: .black.opacity(0.10), radius: 6, y: 3)

            Text(group.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)
                .foregroundStyle(.primary)

            Text(group.category.rawValue)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
        }
    }

    // MARK: - Browse by category grid

    private var browseByCategorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Browse by Topic")

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(CommunityGroup.GroupCategory.allCases, id: \.self) { cat in
                    NavigationLink {
                        DiscussionCategoryBrowseView(category: cat)
                    } label: {
                        categoryTile(cat)
                    }
                    .buttonStyle(AmenPressStyle(scale: 0.965))
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func categoryTile(_ category: CommunityGroup.GroupCategory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(category.color)
                )

            Text(category.rawValue)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Section header helper

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .padding(.horizontal, 16)
    }

    // MARK: - Auto-advance timer

    private func startHeroTimer() {
        heroTimer?.invalidate()
        heroTimer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: true) { _ in
            Task { @MainActor in
                let count = viewModel.topPicks.count
                guard count > 1 else { return }
                withAnimation(Motion.adaptive(Motion.liquidSpring)) {
                    heroPage = (heroPage + 1) % count
                }
            }
        }
    }

    private func stopHeroTimer() {
        heroTimer?.invalidate()
        heroTimer = nil
    }
}

// MARK: - Category browse view (simple list by category)

struct DiscussionCategoryBrowseView: View {
    let category: CommunityGroup.GroupCategory
    @State private var groups: [CommunityGroup] = []
    @State private var isLoading = true
    @State private var selectedGroup: CommunityGroup?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                ContentUnavailableView(
                    "No groups yet",
                    systemImage: category.icon,
                    description: Text("Check back soon — groups in \(category.rawValue) will appear here.")
                )
            } else {
                List(groups) { group in
                    NavigationLink {
                        GroupView(groupId: group.id)
                    } label: {
                        HStack(spacing: 12) {
                            GroupGradientArtView(groupId: group.id, groupName: group.name, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.name).font(.system(size: 15, weight: .semibold))
                                Text("\(group.memberCount.formatted()) members")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(category.rawValue)
        .navigationBarTitleDisplayMode(.large)
        .task { await loadGroups() }
        .navigationDestination(item: $selectedGroup) { group in
            GroupView(groupId: group.id)
        }
    }

    private func loadGroups() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snapshot = try await Firestore.firestore()
                .collection("communityGroups")
                .whereField("category", isEqualTo: category.rawValue)
                .whereField("isPrivate", isEqualTo: false)
                .order(by: "memberCount", descending: true)
                .limit(to: 30)
                .getDocuments()
            groups = snapshot.documents.compactMap { try? $0.data(as: CommunityGroup.self) }
        } catch {
            groups = []
        }
    }
}

// MARK: - Preview

#Preview("Discovery Home") {
    DiscussionDiscoveryHomeView()
}

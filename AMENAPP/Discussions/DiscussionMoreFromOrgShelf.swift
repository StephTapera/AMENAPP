// DiscussionMoreFromOrgShelf.swift
// AMENAPP — Discussions
//
// "More By PJ Morton" equivalent: a horizontal glass shelf of related groups.
// Query priority:
//   1. Same organizationId (if present)
//   2. Same category (fallback)
// Shelf is omitted entirely when fewer than 2 results are found.

import SwiftUI
import FirebaseFirestore

struct DiscussionMoreFromOrgShelf: View {
    let currentGroupId: String
    let organizationId: String?
    let category: String

    @State private var groups: [CommunityGroup] = []
    @State private var isLoading = true

    private var shelfTitle: String {
        if organizationId != nil {
            return "More from this Organization"
        }
        return "More in \(category)"
    }

    var body: some View {
        // Omit entirely when < 2 results
        if !isLoading && groups.count < 2 {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(shelfTitle)
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                    NavigationLink {
                        DiscussionDiscoveryHomeView()
                    } label: {
                        HStack(spacing: 2) {
                            Text("See All")
                                .font(.system(size: 14, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)

                if isLoading {
                    shelfSkeleton
                } else {
                    scrollContent
                }
            }
            .task { await loadRelatedGroups() }
        }
    }

    // MARK: - Scroll shelf

    private var scrollContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(groups) { group in
                    NavigationLink {
                        GroupView(groupId: group.id)
                    } label: {
                        shelfCard(for: group)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func shelfCard(for group: CommunityGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Art
            ZStack {
                if let url = group.coverImageURL, !url.isEmpty {
                    CachedAsyncImage(url: URL(string: url)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        GroupGradientArtView(groupId: group.id,
                                            groupName: group.name,
                                            size: 140)
                    }
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    GroupGradientArtView(groupId: group.id, groupName: group.name, size: 140)
                }
            }
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)

            // Labels
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text("\(group.memberCount.formatted()) members")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 140, alignment: .leading)
        }
        .buttonStyle(AmenPressStyle(scale: 0.965))
    }

    // MARK: - Skeleton

    private var shelfSkeleton: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.systemFill))
                            .frame(width: 140, height: 140)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemFill))
                            .frame(width: 100, height: 13)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemFill))
                            .frame(width: 70, height: 11)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .redacted(reason: .placeholder)
    }

    // MARK: - Query

    private func loadRelatedGroups() async {
        isLoading = true
        defer { isLoading = false }

        let db = Firestore.firestore()
        var query: Query

        if let orgId = organizationId, !orgId.isEmpty {
            query = db.collection("communityGroups")
                .whereField("organizationId", isEqualTo: orgId)
                .limit(to: 8)
        } else {
            query = db.collection("communityGroups")
                .whereField("category", isEqualTo: category)
                .whereField("isPrivate", isEqualTo: false)
                .limit(to: 8)
        }

        do {
            let snapshot = try await query.getDocuments()
            groups = snapshot.documents
                .compactMap { try? $0.data(as: CommunityGroup.self) }
                .filter { $0.id != currentGroupId }
        } catch {
            groups = []
        }
    }
}

// MARK: - Preview

#Preview("More From Org Shelf") {
    NavigationStack {
        DiscussionMoreFromOrgShelf(
            currentGroupId: "preview_current",
            organizationId: nil,
            category: "Bible Study"
        )
        .padding(.vertical)
    }
}

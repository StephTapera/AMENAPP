// SmartFollowersListView.swift
// AMENAPP
//
// Followers, Following, and Mutuals list screens powered by the Smart Activity Layer.
// Single view accepts SocialGraphListType to render any of the three lists.

import SwiftUI

struct SmartFollowersListView: View {
    let listType: SocialGraphListType
    var onUserTap: ((String) -> Void)? = nil

    @StateObject private var viewModel: SocialGraphListViewModel
    @State private var selectedUserId: String? = nil
    @Environment(\.dismiss) private var dismiss

    init(listType: SocialGraphListType, onUserTap: ((String) -> Void)? = nil) {
        self.listType = listType
        self.onUserTap = onUserTap
        _viewModel = StateObject(wrappedValue: SocialGraphListViewModel(listType: listType))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SmartSearchBar(text: $viewModel.searchQuery)
                    .padding(.vertical, 8)

                SmartActivityFilterBar(
                    activeFilter: $viewModel.activeFilter,
                    sortMode: $viewModel.sortMode
                )

                Divider()

                contentView
            }
            .navigationTitle(listType.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task { await viewModel.load() }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.loadState {
        case .loading:
            skeletonList
        case .empty:
            emptyState
        case .error(let msg):
            errorState(message: msg)
        case .loaded, .idle:
            loadedList
        }
    }

    // MARK: - Loaded List

    private var loadedList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                SmartActivityDigestView(rows: viewModel.rows)

                ForEach(viewModel.filteredRows) { row in
                    SmartUserRow(
                        viewModel: row,
                        onTap: {
                            onUserTap?(row.id)
                            selectedUserId = row.id
                        },
                        onFollow: {
                            handleFollow(userId: row.id)
                        },
                        onMarkSeen: {
                            viewModel.markSeen(userId: row.id)
                        }
                    )

                    FeedPostDivider(leadingInset: 74)
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .padding()
                }

                if viewModel.hasMore {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task { await viewModel.loadMore() }
                        }
                }
            }
        }
        .refreshable { await viewModel.refresh() }
    }

    // MARK: - Skeleton

    private var skeletonList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<10, id: \.self) { _ in
                    SmartUserRowSkeleton()
                    FeedPostDivider(leadingInset: 74)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: emptyStateIcon)
                .font(.systemScaled(44))
                .foregroundStyle(.secondary)
            Text(emptyStateMessage)
                .font(.systemScaled(16, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateIcon: String {
        switch listType {
        case .followers: return "person.crop.circle.badge.minus"
        case .following: return "person.crop.circle.badge.plus"
        case .mutuals: return "arrow.triangle.2.circlepath"
        }
    }

    private var emptyStateMessage: String {
        switch listType {
        case .followers: return "No followers yet"
        case .following: return "Not following anyone yet"
        case .mutuals: return "No mutual followers yet"
        }
    }

    // MARK: - Error State

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(44))
                .foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.systemScaled(16, weight: .medium))
            Text(message)
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.bordered)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Follow Action

    private func handleFollow(userId: String) {
        Task {
            // Delegate to FollowService — same pattern used elsewhere in app
            let isCurrentlyFollowing = viewModel.filteredRows.first(where: { $0.id == userId })?.isFollowing ?? false
            if isCurrentlyFollowing {
                try? await FollowService.shared.unfollowUser(userId: userId)
            } else {
                try? await FollowService.shared.followUser(userId: userId)
            }
            await viewModel.refresh()
        }
    }
}

// MARK: - Convenience Entry Points

extension SmartFollowersListView {
    static func followers(for userId: String, onUserTap: ((String) -> Void)? = nil) -> SmartFollowersListView {
        SmartFollowersListView(listType: .followers(userId: userId), onUserTap: onUserTap)
    }

    static func following(for userId: String, onUserTap: ((String) -> Void)? = nil) -> SmartFollowersListView {
        SmartFollowersListView(listType: .following(userId: userId), onUserTap: onUserTap)
    }

    static func mutuals(for userId: String, onUserTap: ((String) -> Void)? = nil) -> SmartFollowersListView {
        SmartFollowersListView(listType: .mutuals(userId: userId), onUserTap: onUserTap)
    }
}

// TopicFeedView.swift
// AMENAPP
//
// Full-screen topic feed: header with topic name, sort picker,
// filtered PostCard list, empty/loading/error states.

import SwiftUI

struct TopicFeedView: View {
    let topicKey: String
    let displayName: String

    @StateObject private var viewModel: TopicFeedViewModel

    init(topicKey: String, displayName: String? = nil) {
        self.topicKey = topicKey
        let name = displayName ?? TopicNormalizationService.shared.displayName(for: topicKey)
        self.displayName = name
        _viewModel = StateObject(wrappedValue: TopicFeedViewModel(topicKey: topicKey, displayName: name))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Sort / filter bar
                sortBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                if viewModel.isLoading && viewModel.posts.isEmpty {
                    loadingState
                } else if let error = viewModel.error, viewModel.posts.isEmpty {
                    errorState(error)
                } else if viewModel.posts.isEmpty {
                    emptyState
                } else {
                    postsContent
                }
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.large)
        .task {
            if viewModel.posts.isEmpty {
                await viewModel.loadInitial()
            }
        }
    }

    // MARK: - Sort / Filter Bar

    private var sortBar: some View {
        HStack(spacing: 8) {
            // Category filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(TopicFeedFilter.allCases) { filter in
                        Button {
                            Task { await viewModel.applyFilter(filter) }
                        } label: {
                            Text(filter.displayName)
                                .font(AMENFont.semiBold(12))
                                .foregroundColor(viewModel.activeFilter == filter ? .white : .black.opacity(0.6))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(viewModel.activeFilter == filter ? Color.black.opacity(0.8) : Color.white.opacity(0.82))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()

            // Sort picker
            Menu {
                ForEach(TopicFeedSort.allCases) { sort in
                    Button {
                        Task { await viewModel.applySort(sort) }
                    } label: {
                        Label(sort.displayName, systemImage: sort.icon)
                    }
                }
            } label: {
                Image(systemName: viewModel.activeSort.icon)
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundColor(.black.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.82))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5)
                    )
            }
        }
    }

    // MARK: - Posts Content

    private var postsContent: some View {
        Group {
            ForEach(viewModel.posts, id: \.id) { post in
                PostCard(post: post)
                    .onAppear {
                        // Trigger pagination when nearing the end
                        if post.id == viewModel.posts.last?.id {
                            Task { await viewModel.loadMore() }
                        }
                    }
            }

            if viewModel.isLoadingMore {
                ProgressView()
                    .padding(.vertical, 16)
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading posts...")
                .font(AMENFont.regular(14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(32))
                .foregroundColor(.orange)
            Text("Something went wrong")
                .font(AMENFont.semiBold(16))
            Text(message)
                .font(AMENFont.regular(13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await viewModel.loadInitial() }
            }
            .font(AMENFont.semiBold(14))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 32)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.systemScaled(32))
                .foregroundColor(.secondary)
            Text("No posts yet")
                .font(AMENFont.semiBold(16))
            Text("Be the first to post about \(displayName)")
                .font(AMENFont.regular(13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 32)
    }
}

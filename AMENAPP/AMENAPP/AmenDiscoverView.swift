import SwiftUI

struct AmenDiscoverView: View {
    @StateObject private var viewModel = AmenDiscoverViewModel()
    @StateObject private var trendingService = TrendingTopicService.shared
    @Namespace private var tileNamespace
    @State private var showReasonSheet = false
    @State private var showFeedbackSheet = false
    @State private var scrollOffset: CGFloat = 0
    @State private var showDiscussionDiscovery = false
    @State private var trendingExpanded = false

    // Disambiguation routing state
    @State private var showBereanSheet = false
    @State private var bereanInitialQuery: String = ""
    @State private var showScriptureSearch = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            ScrollView {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: DiscoverOffsetKey.self, value: proxy.frame(in: .named("amen_discover")).minY)
                }
                .frame(height: 0)

                VStack(spacing: 12) {
                    AmenDiscoverSearchCapsule(
                        searchQuery: $viewModel.searchQuery,
                        compactProgress: min(max(-scrollOffset / 160, 0), 1),
                        onBereanAI: { query in
                            bereanInitialQuery = query
                            showBereanSheet = true
                        },
                        onFindScripture: {
                            showScriptureSearch = true
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    AmenDiscoverTopicRail(filters: viewModel.filters, selected: viewModel.selectedFilter) { filter in
                        Task { await viewModel.applyFilter(filter) }
                    }

                    if viewModel.isLoading {
                        AmenDiscoverSkeletonGrid()
                    } else if viewModel.errorMessage != nil {
                        AmenDiscoverEmptyState {
                            Task { await viewModel.loadInitial() }
                        }
                    } else if viewModel.items.isEmpty {
                        AmenDiscoverEmptyState {
                            Task { await viewModel.loadInitial() }
                        }
                    } else {
                        AmenDiscoverGridView(
                            items: viewModel.items,
                            onTap: { item in
                                viewModel.logTap(item)
                                viewModel.openDetail(item)
                            },
                            onAppear: { item in
                                Task { await viewModel.loadMoreIfNeeded(current: item) }
                            },
                            namespace: tileNamespace
                        )
                    }

                    // Discussions Discovery entry point (album-style groups browse)
                    if AMENFeatureFlags.shared.discussionDiscoveryHomeEnabled {
                        Button {
                            showDiscussionDiscovery = true
                        } label: {
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.44, green: 0.26, blue: 0.80))
                                Text("Browse Groups")
                                    .font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(AmenPressStyle(scale: 0.985))
                        .accessibilityLabel("Browse Groups")
                        .accessibilityHint("Opens the groups discovery page")
                    }

                    // Organization Experiences section
                    if AMENFeatureFlags.shared.organizationExperiencesEnabled {
                        OrganizationExperienceDiscoverySection()
                    }

                    // Trending Topics — Berean AI summaries
                    TrendingTopicSectionView(
                        service: trendingService,
                        expanded: $trendingExpanded
                    )
                }
                .padding(.bottom, 90)
            }
            .coordinateSpace(name: "amen_discover")
            .onPreferenceChange(DiscoverOffsetKey.self) { scrollOffset = $0 }

            // AmenDiscoverGlassTabBar retired — AmenDiscoverTopicRail at top is the canonical filter.
            // AmenDiscoverGlassTabBar(selected: $viewModel.selectedFilter, tabs: ["For You", "Churches", "Sermons", "Selah"])
            //     .padding(.bottom, 12)
            //     .opacity(max(0.72, min(1, 1 - (-scrollOffset / 900))))
        }
        .task {
            AMENAnalyticsService.shared.track(.discoverView)
            await viewModel.loadInitial()
            await trendingService.loadTrendingTopics()
        }
        .sheet(isPresented: $showBereanSheet) {
            if bereanInitialQuery.isEmpty {
                BereanChatView()
            } else {
                BereanChatView(initialQuery: bereanInitialQuery)
                    .onAppear { bereanInitialQuery = "" }
            }
        }
        .sheet(isPresented: $showScriptureSearch) {
            BereanScriptureSearchSheet { _ in
                showScriptureSearch = false
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $viewModel.selectedItem) { item in
            AmenDiscoverDetailView(
                item: item,
                namespace: tileNamespace,
                onWhyThis: {
                    Task {
                        await viewModel.loadWhyThis(for: item)
                        showReasonSheet = true
                    }
                },
                onFeedback: {
                    showFeedbackSheet = true
                }
            )
            .sheet(isPresented: $showReasonSheet) {
                AmenDiscoverReasonSheet(reason: viewModel.reasonText)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showFeedbackSheet) {
                AmenDiscoverSafetyFeedbackSheet { feedback in
                    Task { await viewModel.submitFeedback(item, feedback: feedback) }
                }
            }
        }
        // "Near Me" filter chip → NearbyPeopleView (privacy-gated)
        .sheet(isPresented: $viewModel.showNearbyPeopleSheet) {
            NearbyPeopleView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDiscussionDiscovery) {
            DiscussionDiscoveryHomeView()
                .presentationDragIndicator(.visible)
        }
    }
}

private struct DiscoverOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct AmenDiscoverErrorState: View {
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.secondary)

            VStack(spacing: 6) {
                Text("Couldn't load your feed")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Check your connection and try again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: onRetry) {
                Text("Retry")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Feed failed to load. Tap Retry to try again.")
    }
}

private struct AmenDiscoverEmptyState: View {
    var onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)
            AmenGlass3DIcon(systemName: "sparkles", tint: AmenTheme.Colors.amenGold, size: 72)

            VStack(spacing: 6) {
                Text("Your AMEN Flow is warming up")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("We're curating faith content just for you.\nCheck back shortly.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: onRefresh) {
                Text("Refresh")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Feed is empty. Tap Refresh to check for new content.")
    }
}

private struct AmenDiscoverSkeletonGrid: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(0..<8, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 170)
                    .redacted(reason: .placeholder)
            }
        }
        .padding(.horizontal, 16)
    }
}

private struct OrganizationExperienceDiscoverySection: View {
    @State private var showOrgSearch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Organizations")
                    .font(AMENFont.bold(17))
                    .foregroundStyle(.primary)
                Spacer()
                Button("Browse") {
                    HapticManager.impact(style: .light)
                    showOrgSearch = true
                }
                .font(AMENFont.semiBold(14))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Browse all organizations")
            }
            .padding(.horizontal, 16)

            Text("Churches, schools, and ministries active on Amen")
                .font(AMENFont.regular(13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
        }
        .padding(.top, 16)
        .sheet(isPresented: $showOrgSearch) {
            NavigationStack {
                ChurchSearchView()
                    .navigationTitle("Find Organizations")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

// MARK: - TrendingTopicSectionView

/// "Trending now — summarized by Berean" collapsible section.
/// Shows up to 5 cards collapsed; "Show more" reveals all 20.
private struct TrendingTopicSectionView: View {
    @ObservedObject var service: TrendingTopicService
    @Binding var expanded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visibleTopics: [DiscoverTopic] {
        expanded ? service.topics : Array(service.topics.prefix(5))
    }

    var body: some View {
        // Only render section when there is something (or something is loading).
        if service.topics.isEmpty && !service.isLoading { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                // Section header
                HStack(spacing: 6) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.amenBlue)

                    Text("Trending now — summarized by Berean")
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 10)

                // Cards
                if service.isLoading && service.topics.isEmpty {
                    // Skeleton state — show 3 placeholder cards while loading
                    VStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { _ in
                            TrendingTopicShimmerCard()
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    VStack(spacing: 10) {
                        ForEach(visibleTopics) { topic in
                            TrendingTopicSummaryCard(topic: topic, service: service)
                                .onAppear {
                                    // Lazy AI summary fetch triggered when card becomes visible
                                    Task { await service.fetchAISummary(for: topic.id) }
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .animation(
                        Motion.adaptive(.spring(response: 0.36, dampingFraction: 0.78)),
                        value: expanded
                    )
                }

                // Show more / Show less button
                if service.topics.count > 5 {
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.36, dampingFraction: 0.78))) {
                            expanded.toggle()
                        }
                        HapticManager.impact(style: .light)
                    } label: {
                        HStack(spacing: 4) {
                            Text(expanded ? "Show less" : "Show more")
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(AmenTheme.Colors.amenBlue)
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AmenTheme.Colors.amenBlue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(AmenPressStyle(scale: 0.97))
                    .padding(.horizontal, 16)
                    .accessibilityLabel(expanded ? "Show fewer trending topics" : "Show all trending topics")
                }
            }
        )
    }
}

// MARK: - TrendingTopicSummaryCard

private struct TrendingTopicSummaryCard: View {
    let topic: DiscoverTopic
    @ObservedObject var service: TrendingTopicService

    private var postCountLabel: String {
        let n = topic.postCount
        if n >= 1_000 { return "\(n / 1_000)k posts" }
        return "\(n) posts"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left: topic info
            VStack(alignment: .leading, spacing: 4) {
                Text(topic.displayName)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)

                Text(postCountLabel)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)

                if let summary = topic.aiSummary {
                    Text(summary)
                        .font(AMENFont.regular(13).italic())
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                } else {
                    // Loading shimmer while summary is being fetched
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(AmenTheme.Colors.shimmerBase)
                        .frame(maxWidth: .infinity)
                        .frame(height: 13)
                        .amenSkeleton()
                        .padding(.top, 2)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(AmenTheme.Colors.shimmerBase)
                        .frame(width: 140, height: 13)
                        .amenSkeleton()
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            // Right: Follow / Following toggle button
            FollowTopicButton(topic: topic, service: service)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.card, style: .continuous)
                .fill(AmenTheme.Colors.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.card, style: .continuous)
                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
        )
        .amenShadow(radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(topic.displayName), \(postCountLabel)\(topic.aiSummary.map { ". \($0)" } ?? "")")
    }
}

// MARK: - FollowTopicButton

private struct FollowTopicButton: View {
    let topic: DiscoverTopic
    @ObservedObject var service: TrendingTopicService
    @State private var isProcessing = false

    private var isFollowing: Bool {
        service.topics.first(where: { $0.id == topic.id })?.isFollowing ?? false
    }

    var body: some View {
        Button {
            guard !isProcessing else { return }
            isProcessing = true
            HapticManager.impact(style: .light)
            Task {
                if isFollowing {
                    await service.unfollowTopic(topic.id)
                } else {
                    await service.followTopic(topic.id)
                }
                isProcessing = false
            }
        } label: {
            Text(isFollowing ? "Following" : "Follow")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(isFollowing ? AmenTheme.Colors.textSecondary : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isFollowing
                              ? AmenTheme.Colors.surfaceChip
                              : AmenTheme.Colors.amenBlue)
                )
        }
        .buttonStyle(AmenPressStyle(scale: 0.95))
        .disabled(isProcessing)
        .accessibilityLabel(isFollowing ? "Unfollow \(topic.displayName)" : "Follow \(topic.displayName)")
        .animation(Motion.adaptive(Motion.popToggle), value: isFollowing)
    }
}

// MARK: - TrendingTopicShimmerCard

private struct TrendingTopicShimmerCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(AmenTheme.Colors.shimmerBase)
                    .frame(width: 120, height: 15)
                    .amenSkeleton()
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(AmenTheme.Colors.shimmerBase)
                    .frame(width: 60, height: 12)
                    .amenSkeleton()
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(AmenTheme.Colors.shimmerBase)
                    .frame(maxWidth: .infinity)
                    .frame(height: 12)
                    .amenSkeleton()
                    .padding(.top, 2)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AmenTheme.Colors.shimmerBase)
                .frame(width: 70, height: 30)
                .amenSkeleton()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.card, style: .continuous)
                .fill(AmenTheme.Colors.surfaceCard)
        )
    }
}

#Preview {
    AmenDiscoverView()
}

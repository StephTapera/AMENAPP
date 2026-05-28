//
//  MediaOnlyFeedView.swift
//  AMENAPP
//
//  Full-featured media-only feed experience for Photos & Videos mode.
//  Renders enriched tiles in a 3-column grid with metadata overlays,
//  optional filter pills, and proper loading/empty/error/privacy states.
//  Opens MediaDetailView on tile tap.
//  Liquid Glass design system.
//

import SwiftUI
import FirebaseAuth

struct MediaOnlyFeedView: View {
    @ObservedObject var viewModel: MediaFeedViewModel
    var onViewFullPost: ((String) -> Void)? = nil
    var onViewProfile: ((String) -> Void)? = nil
    var isCurrentUserProfile: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedItem: EnrichedMediaGridItem?
    @State private var showDetail = false

    // Long-press menu state
    @State private var longPressedItem: EnrichedMediaGridItem? = nil
    @State private var showLongPressMenu = false
    @State private var showReportSheet = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                loadingSkeleton
            case .loaded:
                if viewModel.uniquePostItems.isEmpty {
                    emptyState(
                        icon: "photo.on.rectangle.angled",
                        title: "No photos or videos yet",
                        message: "When visual posts are shared, they'll appear here"
                    )
                } else {
                    mediaGrid
                }
            case .empty:
                emptyState(
                    icon: "photo.on.rectangle.angled",
                    title: "No photos or videos yet",
                    message: "When visual posts are shared, they'll appear here"
                )
            case .error(let message):
                emptyState(
                    icon: "exclamationmark.triangle",
                    title: "Something went wrong",
                    message: message
                )
            case .privacyRestricted:
                emptyState(
                    icon: "lock.fill",
                    title: "This profile's media is private",
                    message: "Follow this person to see their photos and videos"
                )
            }
        }
        .fullScreenCover(isPresented: $showDetail) {
            if let item = selectedItem {
                MediaDetailView(item: item, onViewFullPost: onViewFullPost)
            }
        }
        .sheet(isPresented: $showReportSheet) {
            if let item = longPressedItem {
                ReportContentSheet(
                    targetType: .post,
                    targetId: item.postId,
                    onSubmitted: { _ in showReportSheet = false },
                    onDismiss: { showReportSheet = false }
                )
            }
        }
        .mediaLongPressMenu(
            isPresented: $showLongPressMenu,
            isOwnPost: isCurrentUserProfile,
            postPreviewImageURL: longPressedItem.flatMap { URL(string: $0.imageURL) },
            postAuthorName: longPressedItem?.authorName ?? "",
            onLike: {
                guard let item = longPressedItem else { return }
                Task { try? await PostInteractionsService.shared.toggleAmen(postId: item.postId) }
            },
            onRepost: {
                guard let item = longPressedItem else { return }
                Task { _ = try? await PostInteractionsService.shared.toggleRepost(postId: item.postId) }
            },
            onShare: {
                guard let item = longPressedItem else { return }
                let shareURL = URL(string: "https://amenapp.com/post/\(item.postId)")
                let activityVC = UIActivityViewController(
                    activityItems: [shareURL as Any].compactMap { $0 },
                    applicationActivities: nil
                )
                if let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }),
                   let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                    root.present(activityVC, animated: true)
                }
            },
            onViewProfile: {
                if let authorId = longPressedItem?.authorId, !authorId.isEmpty {
                    onViewProfile?(authorId)
                }
            },
            onNotInterested: {
                guard let item = longPressedItem else { return }
                Task { await HeyFeedPreferencesService.shared.hidePost(item.postId) }
            },
            onReport: {
                showReportSheet = true
            },
            onDelete: {
                guard let item = longPressedItem else { return }
                Task { try? await FirebasePostService.shared.deletePost(postId: item.postId) }
            },
            onEdit: {},   // Grid thumbnails do not edit inline
            onPin: {
                guard let item = longPressedItem else { return }
                Task { try? await PinnedPostService.shared.togglePin(postId: item.postId) }
            }
        )
    }

    // MARK: - Filter Pills

    @ViewBuilder
    var filterPills: some View {
        if AMENFeatureFlags.shared.mediaFilterPillsEnabled {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MediaFeedFilter.allCases) { filter in
                        filterPill(filter)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private func filterPill(_ filter: MediaFeedFilter) -> some View {
        let isActive = viewModel.activeFilter == filter
        Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.25, dampingFraction: 0.8)) {
                viewModel.activeFilter = filter
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: filter.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(filter.rawValue)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))
            }
            .foregroundColor(isActive ? AmenTheme.Colors.iconPrimary : AmenTheme.Colors.iconSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(pillBackground(isActive: isActive))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.rawValue)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    @ViewBuilder
    private func pillBackground(isActive: Bool) -> some View {
        if isActive {
            Capsule()
                .fill(AmenTheme.Colors.surfaceCard.opacity(colorScheme == .dark ? 0.92 : 0.84))
                .overlay(
                    Capsule()
                        .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
                )
                .shadow(color: AmenTheme.Colors.shadowCard, radius: 4, y: 1)
        } else {
            Capsule()
                .fill(AmenTheme.Colors.surfaceChip)
                .overlay(
                    Capsule()
                        .strokeBorder(AmenTheme.Colors.borderSoft.opacity(0.8), lineWidth: 0.5)
                )
        }
    }

    // MARK: - Media Grid

    private var mediaGrid: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(viewModel.uniquePostItems) { item in
                MediaTileView(item: item) {
                    selectedItem = item
                    showDetail = true
                    AMENAnalyticsService.shared.track(.mediaGridTileOpened(postId: item.postId))
                } onLongPress: {
                    longPressedItem = item
                    showLongPressMenu = true
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
        .padding(.bottom, 20)
    }

    // MARK: - Loading Skeleton

    private var loadingSkeleton: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<9, id: \.self) { _ in
                Rectangle()
                    .fill(AmenTheme.Colors.shimmerBase)
                    .frame(minHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .shimmering()
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
        .accessibilityLabel("Loading media")
    }

    // MARK: - Empty / Error / Privacy States

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AmenTheme.Colors.surfaceCard)
                    .overlay(
                        Circle()
                            .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
                    )
                    .shadow(color: AmenTheme.Colors.shadowCard, radius: 10, y: 4)
                    .frame(width: 72, height: 72)

                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(AmenTheme.Colors.iconSecondary)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)

                Text(message)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Shimmer Modifier

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        AmenTheme.Colors.shimmerHighlight.opacity(0.55),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .clipped()
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = UIScreen.main.bounds.width
                }
            }
    }
}

private extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

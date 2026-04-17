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

struct MediaOnlyFeedView: View {
    @ObservedObject var viewModel: MediaFeedViewModel
    var onViewFullPost: ((String) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedItem: EnrichedMediaGridItem?
    @State private var showDetail = false

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
            .foregroundColor(isActive ? Color(white: 0.10) : Color(white: 0.50))
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
                .fill(Color.white.opacity(0.82))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 1)
        } else {
            Capsule()
                .fill(Color.white.opacity(0.50))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.black.opacity(0.04), lineWidth: 0.5)
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
                    AMENAnalyticsService.shared.logEvent(.mediaGridTileOpened(postId: item.postId))
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
                    .fill(Color.black.opacity(0.04))
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
                    .fill(Color.white.opacity(0.72))
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
                    .frame(width: 72, height: 72)

                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(Color(white: 0.55))
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(white: 0.10))

                Text(message)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(white: 0.55))
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
                        Color.white.opacity(0.15),
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

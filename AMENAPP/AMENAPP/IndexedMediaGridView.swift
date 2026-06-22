//
//  IndexedMediaGridView.swift
//  AMENAPP
//
//  Profile "Photos & Videos" tab backed by the server-maintained
//  users/{userId}/mediaPosts denormalized index.
//
//  Replaces direct posts-collection scans with cheap paginated reads.
//  Drop-in over MediaGridView — internally converts MediaPostIndexDoc
//  to MediaGridItem and delegates rendering to MediaGridView.
//
//  Usage:
//      IndexedMediaGridView(userId: uid, viewerOwns: true)
//      IndexedMediaGridView(userId: targetUid, viewerOwns: false)
//

import SwiftUI

struct IndexedMediaGridView: View {

    let userId: String
    let viewerOwns: Bool
    var sourceContext: MediaSourceContext = .profile

    @StateObject private var service: MediaPostIndexService

    init(userId: String, viewerOwns: Bool, sourceContext: MediaSourceContext = .profile) {
        self.userId = userId
        self.viewerOwns = viewerOwns
        self.sourceContext = sourceContext
        _service = StateObject(wrappedValue: MediaPostIndexService(
            userId: userId,
            viewerOwns: viewerOwns
        ))
    }

    // Flatten all docs to MediaGridItem for each individual media frame
    private var gridItems: [MediaGridItem] {
        service.filtered.flatMap { $0.toGridItems() }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter strip
            if !service.docs.isEmpty {
                filterStrip
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            // Grid
            if service.isLoading && service.docs.isEmpty {
                ProgressView()
                    .tint(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
            } else if let error = service.errorMessage, service.docs.isEmpty {
                errorState(message: error)
            } else {
                MediaGridView(items: gridItems, sourceContext: sourceContext)
                    .onAppear {
                        // Trigger pagination when near the end
                    }
            }

            // Load-more trigger at the bottom of the list
            if service.hasMore && !service.docs.isEmpty {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        Task { await service.loadNextPageIfNeeded(trigger: service.filtered.last ?? service.docs[0]) }
                    }
            }
        }
        .task {
            if service.docs.isEmpty {
                await service.loadFirstPage()
            }
        }
        .refreshable {
            await service.loadFirstPage()
        }
    }

    // MARK: - Filter Strip

    private var filterStrip: some View {
        HStack(spacing: 8) {
            ForEach(MediaPostIndexFilter.allCases) { filter in
                filterChip(filter)
            }
            Spacer()
        }
    }

    private func filterChip(_ filter: MediaPostIndexFilter) -> some View {
        let selected = service.activeFilter == filter
        return Button {
            service.activeFilter = filter
        } label: {
            HStack(spacing: 4) {
                Image(systemName: filter.icon)
                    .font(.systemScaled(11, weight: .medium))
                Text(filter.rawValue)
                    .font(AMENFont.medium(13))
            }
            .foregroundStyle(selected ? Color.white : Color(white: 0.3))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(selected ? Color.black : Color(white: 0.93))
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: service.activeFilter)
    }

    // MARK: - Error State

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(28, weight: .semibold))
                .foregroundStyle(Color(white: 0.6))
            Text(message)
                .font(AMENFont.regular(14))
                .foregroundStyle(Color(white: 0.5))
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await service.loadFirstPage() }
            }
            .font(AMENFont.semiBold(14))
            .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

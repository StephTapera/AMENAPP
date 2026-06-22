// ResourceCenterModule.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3 UI
//
// Resource center for a creator. Skeleton-first; CalmCap-bounded list with an explicit
// "Load more" affordance (NO infinite scroll). Paginates via CreatorHubService.pageResources.
//
// Exact initializer (mandated): ResourceCenterModule(creatorId: String, resources: [CreatorHubResource]).
//
// Conventions: white bg / black text; translucent ResourceCards on a plain background (no
// glass-on-glass); AmenTheme.Colors.* tokens; Dynamic Type; VoiceOver labels; reduce-motion safe.

import SwiftUI

struct ResourceCenterModule: View {
    let creatorId: String

    @State private var resources: [CreatorHubResource]
    @State private var nextCursor: String?
    @State private var isLoadingMore = false
    @State private var didInitialLoad = false
    @State private var loadError: String?

    /// Opens a resolved resource URL (host wires SafariView / external open).
    var onOpenResource: (URL) -> Void = { _ in }

    init(creatorId: String, resources: [CreatorHubResource]) {
        self.creatorId = creatorId
        _resources = State(initialValue: resources)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !didInitialLoad && resources.isEmpty {
                skeletonList
            } else if resources.isEmpty {
                emptyState
            } else {
                ForEach(resources) { resource in
                    CreatorHubResourceCard(resource: resource, onOpen: onOpenResource)
                }
                footer
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            // First page may already be seeded; mark loaded so we don't show skeletons forever.
            if !didInitialLoad {
                didInitialLoad = true
                if resources.isEmpty { await loadMore() }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        Text("Resources")
            .font(.title3.weight(.semibold))
            .foregroundStyle(AmenTheme.Colors.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Footer (Load more / terminus)

    @ViewBuilder
    private var footer: some View {
        if let loadError {
            errorRow(loadError)
        } else if nextCursor != nil {
            Button {
                Task { await loadMore() }
            } label: {
                HStack {
                    Spacer()
                    if isLoadingMore {
                        ProgressView()
                    } else {
                        Text("Load more")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AmenTheme.Colors.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceChip)
            )
            .disabled(isLoadingMore)
            .accessibilityLabel("Load more resources")
        } else {
            Text("That's everything for now.")
                .font(.footnote)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
                .accessibilityLabel("That's everything for now.")
        }
    }

    // MARK: States

    private var skeletonList: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonCardRow()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical")
                .font(.largeTitle)
                .foregroundStyle(AmenTheme.Colors.iconSecondary)
            Text("No resources yet")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No resources yet")
    }

    private func errorRow(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(AmenTheme.Colors.statusError)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await loadMore() } }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: Paging

    private func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        loadError = nil
        defer { isLoadingMore = false }
        do {
            let (items, cursor) = try await CreatorHubService.shared.pageResources(
                creatorId: creatorId, cursor: nextCursor
            )
            resources.append(contentsOf: items)
            nextCursor = cursor
        } catch {
            loadError = "Couldn't load resources. Please try again."
        }
    }
}

#if DEBUG
#Preview("ResourceCenterModule") {
    ScrollView {
        ResourceCenterModule(creatorId: "demo", resources: [
            CreatorHubResource(id: "1", creatorId: "demo", kind: .devotional,
                               title: "Morning Light Devotional",
                               fileRef: nil, externalUrl: "https://example.com",
                               topics: ["Hope", "Mornings"])
        ])
    }
    .background(AmenTheme.Colors.backgroundPrimary)
}
#endif

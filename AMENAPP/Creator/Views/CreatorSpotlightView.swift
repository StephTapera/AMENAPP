// CreatorSpotlightView.swift
// AMENAPP — Creator Spotlight / Wave 1
//
// Main public page for a creator.
// Fail-closed: renders EmptyView when feature flag is off.
// Layout: hero → metadata strip → capability badges → preview → more by.

import SwiftUI

struct CreatorSpotlightView: View {

    let creatorId: String

    @StateObject private var viewModel: CreatorSpotlightViewModel

    init(creatorId: String) {
        self.creatorId = creatorId
        _viewModel = StateObject(wrappedValue: CreatorSpotlightViewModel(creatorId: creatorId))
    }

    var body: some View {
        if !AMENFeatureFlags.shared.creatorSpotlightEnabled {
            EmptyView()
        } else {
            content
                .task { await viewModel.load() }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                CreatorSpotlightHeroView(
                    creatorId: creatorId,
                    spotlight: viewModel.spotlight,
                    displayName: displayName,
                    presenceCount: nil          // TODO: wire from profile once loaded
                )

                Divider().padding(.horizontal, 20)

                CreatorOrientingMetadataStripView(
                    metadata: featuredContent?.orientingMetadata
                )

                if let capabilities = featuredContent?.capabilities, !capabilities.isEmpty {
                    Divider().padding(.horizontal, 20)
                    CreatorContentCapabilityBadgesView(capabilities: capabilities)
                }

                Divider().padding(.horizontal, 20)

                CreatorPreviewBeforeCommitView(
                    previewUrl: featuredContent?.previewUrl,
                    format: featuredContent?.format ?? .video
                )

                let moreIds = moreContentIds
                if !moreIds.isEmpty {
                    Divider().padding(.horizontal, 20)
                    CreatorMoreByView(contentIds: moreIds)
                }

                Spacer(minLength: 40)
            }
        }
        .background(Color(.systemBackground))
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .overlay {
            if let errorMessage = viewModel.error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
            }
        }
    }

    // MARK: - Derived Data (real, from the loaded CreatorHubService payload)

    /// Display name from the loaded creator profile.
    private var displayName: String {
        viewModel.displayName
    }

    /// The featured content item, resolved against the loaded, approved content.
    private var featuredContent: CreatorContent? {
        guard let id = viewModel.spotlight?.featuredContentId else { return viewModel.contents.first }
        return viewModel.contents.first { $0.id == id }
    }

    /// Approved content IDs for the "More by" rail, excluding the featured item.
    private var moreContentIds: [String] {
        let featuredId = featuredContent?.id
        return viewModel.contents
            .filter { $0.moderationStatus == .approved && $0.id != featuredId }
            .map { $0.id }
    }
}

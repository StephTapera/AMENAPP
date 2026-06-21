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

    // MARK: - Derived Data

    /// Placeholder display name until a profile model is loaded.
    private var displayName: String {
        "Creator"
    }

    /// The featured content item, if spotlight and Firestore are loaded.
    private var featuredContent: CreatorContent? {
        // TODO: resolve spotlight.featuredContentId against loaded content collection
        nil
    }

    /// Content IDs for the "More by" rail, excluding the featured item.
    private var moreContentIds: [String] {
        // TODO: populate from loaded content collection
        []
    }
}

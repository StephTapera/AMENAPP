import SwiftUI

struct CreatorDailyPortionFeedView: View {
    @State private var assets: [CreatorRenderableMediaAsset] = []
    @State private var isLoading = false
    @State private var exhausted = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                CreatorSpaceHeader(
                    title: "Daily Portion",
                    subtitle: "A bounded media session built for completion, not endless refresh."
                )

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else if let errorMessage {
                    CreatorStatusPanel(title: "Feed unavailable", message: errorMessage, systemImage: "exclamationmark.triangle")
                } else if assets.isEmpty {
                    CreatorStatusPanel(title: "You're caught up", message: "No more Creator Spaces media is queued for this portion.", systemImage: "checkmark.circle")
                } else {
                    ForEach(assets) { asset in
                        CreatorRenderableMediaCard(asset: asset)
                    }
                    if exhausted {
                        CreatorStatusPanel(title: "End of portion", message: "This session has reached its explicit end state.", systemImage: "checkmark.circle")
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Daily Portion")
        .task { await load() }
    }

    private func load() async {
        guard CreatorSpacesFeatureFlags.shared.creatorSpacesEnabled else {
            exhausted = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await CreatorSpacesService.shared.getDailyPortion()
            assets = try await CreatorSpacesService.shared.fetchRenderableMediaAssets(ids: response.items)
            exhausted = response.exhausted
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CreatorRenderableMediaCard: View {
    let asset: CreatorRenderableMediaAsset

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Captured in AMEN", systemImage: "checkmark.seal")
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(.green)
                Spacer()
                Text(asset.moderationStatus.capitalized)
                    .font(AMENFont.medium(11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)

            PostMediaContainerView(media: asset.media)
        }
        .padding(.vertical, 14)
        .amenGlassSurface(shape: .rounded(22), background: .balanced, placement: .inline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Creator Spaces media \(asset.assetId), moderation status \(asset.moderationStatus)")
    }
}

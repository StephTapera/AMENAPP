import SwiftUI

struct CreatorSpacesHomeView: View {
    @ObservedObject private var flags = CreatorSpacesFeatureFlags.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        CreatorSpaceHeader(
                            title: "Creator Spaces",
                            subtitle: "Trusted media, collaboration, provenance, and creator commerce for communities and organizations."
                        )

                        if !flags.creatorSpacesEnabled {
                            CreatorStatusPanel(
                                title: "Creator Spaces is off",
                                message: "The production kill switch is disabled. Enable creator_spaces_enabled in Remote Config to expose live workflows.",
                                systemImage: "lock.shield"
                            )
                        }

                        topSystems
                        trustSection
                        commerceSection
                    }
                    .padding(20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Creator Spaces")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            CreatorSpacesAnalytics.track(.creatorSpaceJoined, parameters: ["surface": "resources_home"])
        }
    }

    private var topSystems: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Systems")
                .font(AMENFont.semiBold(16))
                .foregroundStyle(.secondary)

            NavigationLink(destination: CreatorDailyPortionFeedView()) {
                CreatorSpaceBanner(
                    title: "Daily Portion Feed",
                    subtitle: "Finite media sessions with a real caught-up state.",
                    systemImage: "rectangle.stack"
                )
            }
            .buttonStyle(.plain)
            .disabled(!flags.creatorSpacesEnabled)

            CreatorSpaceBanner(
                title: "Presence Posts",
                subtitle: flags.presencePostsEnabled ? "Dual-camera capture is ready for the capture workstream." : "Gated by presence_posts_enabled.",
                systemImage: "camera.aperture"
            )

            CreatorSpaceBanner(
                title: "Smart Church Clips",
                subtitle: flags.smartChurchClipsEnabled ? "Church Notes can share timestamped clips into spaces." : "Gated by smart_church_clips_enabled.",
                systemImage: "text.badge.checkmark"
            )

            EventMemoryTimeline(moments: [
                "Event photos, notes, and reflections",
                "Server-owned provenance label",
                "GUARDIAN moderation before distribution"
            ])
        }
    }

    private var trustSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trust")
                .font(AMENFont.semiBold(16))
                .foregroundStyle(.secondary)

            ProvenanceNutritionLabelView(label: previewLabel)
        }
    }

    private var commerceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Commerce")
                .font(AMENFont.semiBold(16))
                .foregroundStyle(.secondary)

            NavigationLink(destination: CreatorCommerceOverviewView()) {
                CreatorSubscriptionCard(
                    title: "Paid Creator Spaces",
                    subtitle: "Subscriptions, event passes, classes, studies, and media packs use entitlement checks.",
                    isEnabled: flags.creatorSubscriptionsEnabled
                )
            }
            .buttonStyle(.plain)
            .disabled(!flags.creatorSpacesEnabled)
        }
    }

    private var previewLabel: CreatorProvenanceLabel {
        CreatorProvenanceLabel(
            labelId: "local-preview",
            assetId: "local-preview",
            capturedOnDevice: true,
            sourceCamera: "AMEN capture chain",
            timestampChain: [CreatorProvenanceEvent(event: "capture", ts: Date())],
            editHistory: [],
            editedWithAI: false,
            aiAssistedPercent: nil,
            syntheticElementsPresent: nil,
            authenticityConfidence: nil,
            signature: "local-preview"
        )
    }
}

#Preview {
    CreatorSpacesHomeView()
}

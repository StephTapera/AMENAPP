// SafetyTrustLayer.swift
// AMENAPP
//
// Phase 3 — System 35 Trust Spine.
// Compact, composable trust strip that any media surface can adopt. Renders
// SERVER-DERIVED authenticity confidence + the AI labels the backend assigned.
// Never invents labels, never sets confidence from the client.
//
// Surface contract:
//   - Pass postId + mediaId; the view fetches provenance + AI disclosures
//     from `TrustSpineService` and renders nothing if both are absent.
//   - Tap "View provenance" → presents the existing `ProvenanceTrustPanel`
//     sheet (data fetched server-side then mapped into MediaProvenance for
//     the display layer).
//   - Tap "Report" → presents `ReportContentSheet`.
//
// Liquid Glass:
//   - .ultraThinMaterial capsule, Reduce Transparency falls back to
//     Color(.secondarySystemBackground)
//   - No glass-on-glass — host the strip directly on the media background

import SwiftUI

// MARK: - SafetyTrustLayer

struct SafetyTrustLayer: View {

    // MARK: Inputs

    let postId: String
    let mediaId: String

    /// Optional pre-fetched provenance (skip the network call if already loaded).
    var preloadedProvenance: MediaProvenance? = nil

    /// Optional pre-fetched disclosures (skip the network call if already loaded).
    var preloadedDisclosures: [AIDisclosureRecord]? = nil

    /// Optional override for the target type when reporting. Defaults to `.media`.
    var reportTargetType: TrustSpineService.ReportTargetType = .media

    // MARK: Environment / state

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var model = SafetyTrustLayerModel()
    @State private var showingProvenanceSheet = false
    @State private var showingReportSheet = false

    // MARK: Body

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                loadingCapsule
            case .loaded:
                if model.hasAnyTrustSignal {
                    loadedContent
                } else {
                    EmptyView()
                }
            case .empty:
                EmptyView()
            case .failed:
                EmptyView()
            }
        }
        .task(id: identityKey) {
            await model.load(
                postId: postId,
                mediaId: mediaId,
                preloadedProvenance: preloadedProvenance,
                preloadedDisclosures: preloadedDisclosures
            )
        }
        .provenanceTrustSheet(
            isPresented: $showingProvenanceSheet,
            provenance: model.provenance,
            aiDisclosures: model.disclosures
        )
        .reportContentSheet(
            isPresented: $showingReportSheet,
            targetType: reportTargetType,
            targetId: mediaId
        )
    }

    // MARK: Loaded content

    private var loadedContent: some View {
        HStack(spacing: 10) {
            confidenceBadge
            if !model.disclosures.isEmpty {
                aiLabelStrip
            }
            Spacer(minLength: 0)
            menuButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(layerBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.black.opacity(0.08), lineWidth: 0.6)
        )
        .accessibilityElement(children: .contain)
    }

    private var confidenceBadge: some View {
        let confidence = model.provenance?.authenticityConfidence ?? 0
        let icon = confidenceIcon(confidence)
        let label = confidenceLabel(confidence)
        let tint = confidenceTint(confidence)
        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .accessibilityLabel("Authenticity: \(label)")
    }

    private var aiLabelStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.disclosures) { disclosure in
                    AILabelPill(disclosure: disclosure)
                }
            }
        }
        .frame(maxHeight: 28)
    }

    private var menuButton: some View {
        Menu {
            Button {
                showingProvenanceSheet = true
            } label: {
                Label("View provenance", systemImage: "shield.lefthalf.filled")
            }
            if !model.disclosures.isEmpty {
                Button {
                    showingProvenanceSheet = true
                } label: {
                    Label("View AI disclosures", systemImage: "sparkles")
                }
            }
            Divider()
            Button(role: .destructive) {
                showingReportSheet = true
            } label: {
                Label("Report", systemImage: "flag")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(6)
                .background(Circle().fill(Color(.tertiarySystemFill)))
        }
        .accessibilityLabel("Trust and safety options")
    }

    private var loadingCapsule: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.mini)
            Text("Checking media trust…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(layerBackground)
        .clipShape(Capsule())
    }

    private var layerBackground: some View {
        Group {
            if reduceTransparency {
                Color(.secondarySystemBackground)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }

    // MARK: Helpers

    private var identityKey: String { "\(postId)|\(mediaId)" }

    private func confidenceIcon(_ confidence: Double) -> String {
        if confidence >= 0.8 { return "checkmark.seal.fill" }
        if confidence >= 0.5 { return "exclamationmark.shield" }
        return "exclamationmark.triangle.fill"
    }

    private func confidenceLabel(_ confidence: Double) -> String {
        if confidence >= 0.8 { return "Verified origin" }
        if confidence >= 0.5 { return "Partial origin" }
        return "Low origin trust"
    }

    private func confidenceTint(_ confidence: Double) -> Color {
        if confidence >= 0.8 { return .green }
        if confidence >= 0.5 { return .orange }
        return .red
    }
}

// MARK: - SafetyTrustLayerModel

@MainActor
final class SafetyTrustLayerModel: ObservableObject {

    enum LoadState { case loading, loaded, empty, failed }

    @Published private(set) var state: LoadState = .loading
    @Published private(set) var provenance: MediaProvenance? = nil
    @Published private(set) var disclosures: [AIDisclosureRecord] = []

    var hasAnyTrustSignal: Bool {
        provenance != nil || !disclosures.isEmpty
    }

    func load(
        postId: String,
        mediaId: String,
        preloadedProvenance: MediaProvenance? = nil,
        preloadedDisclosures: [AIDisclosureRecord]? = nil
    ) async {
        if let preloadedProvenance {
            self.provenance = preloadedProvenance
        }
        if let preloadedDisclosures {
            self.disclosures = preloadedDisclosures
        }
        if preloadedProvenance != nil && preloadedDisclosures != nil {
            self.state = .loaded
            return
        }

        state = .loading

        async let provTask: MediaProvenance? = fetchProvenance(postId: postId, mediaId: mediaId)
        async let discTask: [AIDisclosureRecord] = fetchDisclosures(postId: postId, mediaId: mediaId)

        let prov = await provTask
        let disc = await discTask

        if prov != nil {
            self.provenance = prov
        }
        self.disclosures = disc

        self.state = (prov == nil && disc.isEmpty) ? .empty : .loaded
        if self.state == .loaded {
            TrustSpineAnalytics.track(.safetyTrustLayerShown, params: [
                "post_id": postId,
                "media_id": mediaId,
                "disclosure_count": disc.count,
            ])
        }
    }

    private func fetchProvenance(postId: String, mediaId: String) async -> MediaProvenance? {
        do {
            let summary = try await TrustSpineService.shared.getPostProvenance(
                postId: postId,
                mediaId: mediaId
            )
            return Self.toMediaProvenance(summary: summary)
        } catch {
            return nil
        }
    }

    private func fetchDisclosures(postId: String, mediaId: String) async -> [AIDisclosureRecord] {
        do {
            return try await TrustSpineService.shared.getAIDisclosureDetails(
                postId: postId,
                mediaId: mediaId
            )
        } catch {
            return []
        }
    }

    // MARK: - Bridge: ProvenanceSummary → MediaProvenance (display only)

    private static func toMediaProvenance(
        summary: TrustSpineService.ProvenanceSummary
    ) -> MediaProvenance? {
        guard let provId = summary.provenanceId,
              let postId = summary.postId,
              let mediaId = summary.mediaId,
              let ownerUid = summary.ownerUid else {
            return nil
        }
        let sourceType = MediaProvenance.MediaSourceType(
            rawValue: summary.sourceType ?? "unknown"
        ) ?? .unknown
        let credentials = MediaProvenance.ContentCredentialsStatus(
            rawValue: summary.contentCredentialsStatus ?? "not_applicable"
        ) ?? .notApplicable
        let synthetic = MediaProvenance.SyntheticMediaStatus(
            rawValue: summary.syntheticMediaStatus ?? "clean"
        ) ?? .clean
        return MediaProvenance(
            id: provId,
            postId: postId,
            mediaId: mediaId,
            ownerUid: ownerUid,
            capturedOnDevice: summary.capturedOnDevice ?? false,
            sourceType: sourceType,
            editEvents: [],
            aiEvents: [],
            authenticityConfidence: summary.authenticityConfidence ?? 0,
            contentCredentialsStatus: credentials,
            syntheticMediaStatus: synthetic,
            disclosureRequired: summary.disclosureRequired ?? false,
            disclosureSatisfied: summary.disclosureSatisfied ?? false,
            moderationStatus: summary.moderationStatus ?? "unknown"
        )
    }
}

#if DEBUG
#Preview("SafetyTrustLayer — Loaded") {
    ZStack {
        Color.black
        SafetyTrustLayer(postId: "demo_post", mediaId: "demo_media")
            .padding()
    }
}
#endif

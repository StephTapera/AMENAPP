// AmenKnowledgeGraphSpacesLinkView.swift
// AMEN Connect + Spaces — Liquid Intelligence Seam (Agent 9)
//
// Cross-link panel: shows which Connect teachings are linked to open Spaces
// decisions/tasks for a given space.
//
// Frozen contracts: ConnectSpacesPhase0Contracts.swift — do not modify.
// Callable proxy: AmenConnectSpacesPhase0BindingService.swift

import SwiftUI

// MARK: - Color helpers (file-local, matching frozen design tokens)
// NOTE: init(hex:) is declared once in this file to avoid redeclaration.

// MARK: - Row model

struct AmenLinkedTeachingRow: Identifiable {
    let id: String        // videoId
    var resolvedTitle: String?
}

// MARK: - ViewModel

@MainActor
final class AmenKnowledgeGraphSpacesLinkViewModel: ObservableObject {

    @Published var rows: [AmenLinkedTeachingRow] = []
    @Published var isLoading: Bool = false

    private let spaceId: String
    private let userId: String
    private let seam = AmenIntelligenceSeamService.shared

    init(spaceId: String, userId: String) {
        self.spaceId = spaceId
        self.userId  = userId
    }

    func load() async {
        isLoading = true
        let videoIds = await seam.graphItemsForSpace(spaceId: spaceId, userId: userId)
        rows = videoIds.map { AmenLinkedTeachingRow(id: $0, resolvedTitle: nil) }
        isLoading = false
    }

    func resolveTitle(for videoId: String) async -> String {
        await seam.resolveVideoTitle(videoId: videoId)
    }
}

// MARK: - Main view

struct AmenKnowledgeGraphSpacesLinkView: View {

    let spaceId: String
    let userId: String
    let graph: AmenConnectSpacesKnowledgeGraph

    @StateObject private var vm: AmenKnowledgeGraphSpacesLinkViewModel

    init(spaceId: String, userId: String, graph: AmenConnectSpacesKnowledgeGraph) {
        self.spaceId = spaceId
        self.userId  = userId
        self.graph   = graph
        _vm = StateObject(wrappedValue: AmenKnowledgeGraphSpacesLinkViewModel(
            spaceId: spaceId,
            userId: userId
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            glassHeader
            Divider()
                .opacity(0.2)

            if vm.isLoading {
                loadingView
            } else if vm.rows.isEmpty {
                emptyState
            } else {
                linkedList
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.amenPurple.opacity(0.22), lineWidth: 0.75)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task {
            await vm.load()
        }
    }

    // MARK: - Glass header (amenPurple tint)

    private var glassHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "link.circle.fill")
                .foregroundStyle(Color.amenPurple)
                .font(.body)
                .accessibilityHidden(true)
            Text("Teachings linked to this space")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.amenPurple)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            Color(.systemBackground)
                .opacity(0.0)
                .amenGlassEffect(in: .rect(cornerRadius: 0))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Teachings linked to this space")
    }

    // MARK: - Loading

    private var loadingView: some View {
        HStack {
            ProgressView()
                .tint(Color.amenPurple)
            Text("Loading linked teachings…")
                .font(.subheadline)
                .foregroundStyle(Color.amenBlack.opacity(0.55))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
    }

    // MARK: - Empty state (matte)

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "book.closed")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor.opacity(0.5))
                    .accessibilityHidden(true)
                Text("No teachings linked yet. Study content will appear here as your team learns together.")
                    .font(.subheadline)
                    .foregroundStyle(Color.amenBlack.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No teachings linked yet. Study content will appear here as your team learns together.")
    }

    // MARK: - Linked teachings list

    private var linkedList: some View {
        VStack(spacing: 0) {
            ForEach(Array(vm.rows.enumerated()), id: \.element.id) { index, row in
                AmenLinkedTeachingRowView(
                    videoId: row.id,
                    resolveTitle: { await self.vm.resolveTitle(for: row.id) }
                )
                if index < vm.rows.count - 1 {
                    Divider()
                        .padding(.leading, 42)
                        .opacity(0.15)
                }
            }
        }
    }
}

// MARK: - Per-row view (resolves title asynchronously)

/// Displays a single linked teaching row. Title resolves async via .task(id: videoId).
/// Raw video ID is shown as fallback while loading.
private struct AmenLinkedTeachingRowView: View {

    let videoId: String
    let resolveTitle: () async -> String

    @State private var title: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.rectangle")
                .font(.body)
                .foregroundStyle(Color.amenBlue.opacity(0.6))
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title ?? "Teaching: \(videoId.prefix(8))")
                    .font(.subheadline)
                    .foregroundStyle(Color.amenBlack)
                    .lineLimit(2)
                    .animation(.easeInOut(duration: 0.15), value: title)
                if title == nil {
                    Text(videoId)
                        .font(.caption2)
                        .foregroundStyle(Color.amenBlack.opacity(0.35))
                        .lineLimit(1)
                }
            }

            Spacer()

            NavigationLink {
                AmenConnectPlayerView(video: fallbackVideo)
            } label: {
                Text("Open in Connect")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.amenBlue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open teaching in Connect")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .task(id: videoId) {
            title = await resolveTitle()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title ?? videoId). Open in Connect.")
    }

    private var fallbackVideo: AmenConnectSpacesConnectVideo {
        AmenConnectSpacesConnectVideo(
            id: videoId,
            provenance: AmenConnectSpacesVideoProvenance(
                humanRecorded: true,
                aiEdited: false,
                aiGenerated: false,
                synthVoice: false,
                synthFace: false,
                deepfakeRisk: 0,
                verifiedOriginal: false
            ),
            teacherId: "unknown",
            transcriptRef: "connect/videos/\(videoId)/transcript",
            claims: [],
            scriptureRefs: [],
            sponsored: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// AmenIntelligenceSeamService.swift
// AMEN Connect + Spaces — Liquid Intelligence Seam (Agent 9)
//
// Shared service that cross-links Connect knowledge graph data into Spaces context.
// All CF calls are graceful — errors produce friendly fallback strings, never crashes.
//
// Frozen contracts: ConnectSpacesPhase0Contracts.swift — do not modify.
// Callable proxy: AmenConnectSpacesPhase0BindingService.swift

import Foundation

@MainActor
final class AmenIntelligenceSeamService: ObservableObject {

    static let shared = AmenIntelligenceSeamService()

    private let proxy = AmenConnectSpacesCallableProxy.shared

    private init() {}

    // MARK: - Video Title Resolution

    /// Returns a human-readable title for the given video ID.
    /// Production: wire a Cloud Function that resolves the title from the video catalog.
    // TODO: wire real title-resolution CF
    func resolveVideoTitle(videoId: String) async -> String {
        "Teaching: \(videoId.prefix(8))"
    }

    // MARK: - Study Plan

    /// Records a knowledge graph event for study-plan requests and returns the canonical plan steps.
    func studyPlanItems(for videoId: String, userId: String) async -> [String] {
        // Record the event non-fatally; plan always returns.
        _ = try? await proxy.recordKnowledgeGraphEvent(
            userId: userId,
            event: "studyPlanRequested",
            itemRef: videoId
        )
        return [
            "Watch the full message",
            "Read the cited scriptures",
            "Write 3 reflection notes",
            "Share with your Accountability space",
            "Mark as understood when ready"
        ]
    }

    // MARK: - Summarize Video

    /// Calls `fetchConnectVideoContext` and extracts a summary string, with a graceful fallback.
    func summarizeVideo(videoId: String) async -> String {
        if let response = try? await proxy.fetchConnectVideoContext(videoId: videoId),
           let summary = response["summary"] as? String, !summary.isEmpty {
            return summary
        }
        return "This message explores the themes of faith and formation."
    }

    // MARK: - Cross-Source Compare

    /// Stub: cross-source compare requires full ministry library indexing.
    // TODO: wire Algolia/Pinecone cross-source CF
    func compareToSource(videoId: String, sourceRef: String) async -> String {
        "Cross-source comparison requires the ministry library to be fully indexed. Check back soon."
    }

    // MARK: - Ask a Question

    /// Calls `fetchConnectVideoContext` to anchor the question, then returns a stub answer.
    // TODO: wire Berean question CF
    func askQuestion(question: String, videoId: String, userId: String) async -> String {
        _ = try? await proxy.fetchConnectVideoContext(videoId: videoId)
        return "Question received. Berean is reviewing the teaching context."
    }

    // MARK: - Graph Items for Space

    /// Records a knowledge graph event for this space context request, then returns linked video IDs.
    // TODO: wire Pinecone namespace cross-link
    func graphItemsForSpace(spaceId: String, userId: String) async -> [String] {
        _ = try? await proxy.recordKnowledgeGraphEvent(
            userId: userId,
            event: "spacesContextRequested",
            itemRef: spaceId
        )
        return []
    }
}

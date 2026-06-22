// AmenIntelligenceSeamService.swift
// AMEN Connect + Spaces — Liquid Intelligence Seam (Agent 9)
//
// Shared service that cross-links Connect knowledge graph data into Spaces context.
// All CF calls are graceful — errors produce friendly fallback strings, never crashes.
//
// Frozen contracts: ConnectSpacesPhase0Contracts.swift — do not modify.
// Callable proxy: AmenConnectSpacesPhase0BindingService.swift

import Foundation
import FirebaseFunctions

@MainActor
final class AmenIntelligenceSeamService: ObservableObject {

    static let shared = AmenIntelligenceSeamService()

    private let proxy = AmenConnectSpacesCallableProxy.shared
    private let functions = Functions.functions()

    private init() {}

    // MARK: - Video Title Resolution

    /// Returns a human-readable title for the given video ID.
    /// Calls `resolveSpaceTitle` CF; falls back to a truncated ID on error.
    func resolveVideoTitle(videoId: String) async -> String {
        do {
            let callable = functions.httpsCallable("resolveSpaceTitle")
            let result = try await callable.call(["videoId": videoId])
            if let data = result.data as? [String: Any],
               let title = data["title"] as? String, !title.isEmpty {
                return title
            }
        } catch {
            // Non-fatal — fall through to default
        }
        return "Teaching: \(videoId.prefix(8))"
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

    /// Calls `searchCrossSources` CF (Algolia/Pinecone) to compare video to a source ref.
    /// Falls back to a friendly message on error or empty result.
    func compareToSource(videoId: String, sourceRef: String) async -> String {
        do {
            let callable = functions.httpsCallable("searchCrossSources")
            let result = try await callable.call(["videoId": videoId, "sourceRef": sourceRef])
            if let data = result.data as? [String: Any],
               let comparison = data["comparison"] as? String, !comparison.isEmpty {
                return comparison
            }
        } catch {
            // Non-fatal — fall through to default
        }
        return "Cross-source comparison requires the ministry library to be fully indexed. Check back soon."
    }

    // MARK: - Ask a Question

    /// Calls `bereanQuestion` CF with the question and video context; falls back gracefully.
    func askQuestion(question: String, videoId: String, userId: String) async -> String {
        // Anchor the question to video context first (non-fatal)
        _ = try? await proxy.fetchConnectVideoContext(videoId: videoId)
        do {
            let callable = functions.httpsCallable("bereanQuestion")
            let result = try await callable.call([
                "question": question,
                "videoId": videoId,
                "userId": userId
            ])
            if let data = result.data as? [String: Any],
               let answer = data["answer"] as? String, !answer.isEmpty {
                return answer
            }
        } catch {
            // Non-fatal — fall through to default
        }
        return "Question received. Berean is reviewing the teaching context."
    }

    // MARK: - Graph Items for Space

    /// Records a knowledge graph event and calls `searchKnowledgeGraph` CF (Pinecone namespace).
    /// Returns linked video IDs, or an empty array on error.
    func graphItemsForSpace(spaceId: String, userId: String) async -> [String] {
        _ = try? await proxy.recordKnowledgeGraphEvent(
            userId: userId,
            event: "spacesContextRequested",
            itemRef: spaceId
        )
        do {
            let callable = functions.httpsCallable("searchKnowledgeGraph")
            let result = try await callable.call(["spaceId": spaceId, "userId": userId])
            if let data = result.data as? [String: Any],
               let videoIds = data["videoIds"] as? [String] {
                return videoIds
            }
        } catch {
            // Non-fatal — return empty array
        }
        return []
    }
}

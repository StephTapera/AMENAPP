// TopicEnrichmentService.swift
// AMENAPP
//
// Derives `normalizedTopicKeys`, `topicScoreMap`, and `primaryTopicKey`
// from post content at creation time using SemanticTopicService.
//
// Fully on-device, synchronous — no network calls.
// A server-side Cloud Function mirrors this logic as a belt-and-suspenders
// for posts that miss client-side enrichment.

import Foundation

@MainActor
final class TopicEnrichmentService {

    static let shared = TopicEnrichmentService()

    private let topicService = SemanticTopicService.shared
    private let normalization = TopicNormalizationService.shared

    private init() {}

    // MARK: - Enrichment Result

    struct EnrichmentResult {
        /// Canonical topic keys for Firestore array-contains queries.
        let normalizedTopicKeys: [String]

        /// Per-key confidence scores (0–1.0).
        let topicScoreMap: TopicScoreMap

        /// The highest-confidence canonical key (used for primary badge/label).
        let primaryTopicKey: String?
    }

    // MARK: - Public API

    /// Enrich a post's content text with topic metadata.
    /// Call this at post creation time before writing to Firestore.
    func enrich(content: String) -> EnrichmentResult {
        guard !content.isEmpty else {
            return EnrichmentResult(
                normalizedTopicKeys: [],
                topicScoreMap: [:],
                primaryTopicKey: nil
            )
        }

        // Classify via existing SemanticTopicService
        let tags = topicService.classifyText(content)

        guard !tags.isEmpty else {
            return EnrichmentResult(
                normalizedTopicKeys: ["general"],
                topicScoreMap: ["general": 0.10],
                primaryTopicKey: "general"
            )
        }

        var scoreMap: TopicScoreMap = [:]
        var keys: [String] = []

        for tag in tags {
            let canonicalKey = normalization.canonicalKey(for: tag.cluster)
            if (scoreMap[canonicalKey] ?? 0) < tag.confidence {
                scoreMap[canonicalKey] = tag.confidence
            }
            if !keys.contains(canonicalKey) {
                keys.append(canonicalKey)
            }
        }

        // Sort keys by confidence descending
        keys.sort { (scoreMap[$0] ?? 0) > (scoreMap[$1] ?? 0) }

        let primaryKey = keys.first

        return EnrichmentResult(
            normalizedTopicKeys: keys,
            topicScoreMap: scoreMap,
            primaryTopicKey: primaryKey
        )
    }

    /// Enrich with additional user-supplied topic tags (from profile topics or manual tags).
    /// Merges machine-classified topics with user-supplied ones.
    func enrich(content: String, userTopics: [String]) -> EnrichmentResult {
        let baseResult = enrich(content: content)

        guard !userTopics.isEmpty else { return baseResult }

        var mergedKeys = baseResult.normalizedTopicKeys
        var mergedScores = baseResult.topicScoreMap

        for raw in userTopics {
            let key = normalization.normalize(raw)
            if !mergedKeys.contains(key) {
                mergedKeys.append(key)
                mergedScores[key] = 0.50 // User-supplied topics get a moderate confidence
            }
        }

        return EnrichmentResult(
            normalizedTopicKeys: mergedKeys,
            topicScoreMap: mergedScores,
            primaryTopicKey: baseResult.primaryTopicKey
        )
    }

    /// Build Firestore-ready dictionary fields from an enrichment result.
    /// Intended to be merged into the post data dict before `addDocument`.
    func firestoreFields(from result: EnrichmentResult) -> [String: Any] {
        var fields: [String: Any] = [:]
        fields["normalizedTopicKeys"] = result.normalizedTopicKeys
        fields["topicScoreMap"] = result.topicScoreMap
        if let primary = result.primaryTopicKey {
            fields["primaryTopicKey"] = primary
        }
        return fields
    }
}

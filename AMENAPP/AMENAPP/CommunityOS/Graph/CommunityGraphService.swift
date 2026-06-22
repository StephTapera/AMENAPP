// CommunityGraphService.swift
// AMEN App — Community Around Content OS / Graph
//
// Actor that manages the Community Graph (meaning graph) in Firestore.
// Tracks edges between users and content/topics/spaces.
// NOT a social follow graph — this is a spiritual-meaning graph.
//
// Firestore structure:
//   communityGraph/{userId}/edges/{edgeId}
//   communityGraph/{userId}/profile

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - GraphEdge (internal Firestore model)

/// A single edge in the community meaning graph.
private struct GraphEdge: Codable {
    var userId: String
    var targetId: String
    var targetType: String
    var strength: Double
    var lastInteractedAt: Date
    var signals: [String]

    // Firestore field names
    enum CodingKeys: String, CodingKey {
        case userId
        case targetId
        case targetType
        case strength
        case lastInteractedAt
        case signals
    }
}

// MARK: - CommunityGraphService

actor CommunityGraphService {

    static let shared = CommunityGraphService()
    private init() {}

    // MARK: Private state

    private lazy var db = Firestore.firestore()

    /// Minimum strength delta that triggers a DNA recalculation.
    private let dnaRecalcThreshold: Double = 0.15

    // MARK: - Collection helpers

    private func edgesCollection(for userId: String) -> CollectionReference {
        db.collection("communityGraph").document(userId).collection("edges")
    }

    private func profileDocument(for userId: String) -> DocumentReference {
        db.collection("communityGraph").document(userId).collection("profile").document("dna")
    }

    // MARK: - recordEngagement

    /// Upserts/strengthens the edge for a user–content interaction.
    /// Triggers DNA recalculation when the strength delta crosses `dnaRecalcThreshold`.
    func recordEngagement(
        userId: String,
        event: ContentEngagementEvent,
        contentObject: ContentObject
    ) async {
        guard await CommunityOSFlagService.shared.isEnabled(.meaningGraph) else {
            dlog("[CommunityGraphService] meaningGraph flag off — skipping recordEngagement")
            return
        }

        let delta = strengthFor(eventType: event.eventType)
        guard delta > 0 else { return }

        let edgeId = "\(userId)_\(contentObject.id)"
        let edgeRef = edgesCollection(for: userId).document(edgeId)

        do {
            let snapshot = try await edgeRef.getDocument()

            var newStrength: Double
            var existingSignals: [String]

            if snapshot.exists, let data = snapshot.data() {
                let existingStrength = data["strength"] as? Double ?? 0.0
                existingSignals = data["signals"] as? [String] ?? []
                newStrength = min(existingStrength + delta, 1.0)
            } else {
                existingSignals = []
                newStrength = min(delta, 1.0)
            }

            let signalKey = "\(event.eventType.rawValue)_\(contentObject.kind.rawValue)"
            if !existingSignals.contains(signalKey) {
                existingSignals.append(signalKey)
            }

            let payload: [String: Any] = [
                "userId": userId,
                "targetId": contentObject.id,
                "targetType": contentObject.kind.rawValue,
                "strength": newStrength,
                "lastInteractedAt": Timestamp(date: Date()),
                "signals": existingSignals
            ]

            try await edgeRef.setData(payload, merge: true)
            dlog("[CommunityGraphService] Edge upserted — userId:\(userId) target:\(contentObject.id) strength:\(newStrength)")

            // Trigger DNA recalculation if the strength delta is significant.
            if delta >= dnaRecalcThreshold {
                dlog("[CommunityGraphService] Strength delta \(delta) >= threshold; scheduling DNA refresh for \(userId)")
                try await CommunityDNAService.shared.refreshDNA(for: userId)
            }

        } catch {
            dlog("[CommunityGraphService] recordEngagement failed: \(error)")
        }
    }

    // MARK: - getAffinityScores

    /// Reads all edges for a user and returns aggregated affinity scores by topic.
    func getAffinityScores(for userId: String) async throws -> [CommunityAffinityScore] {
        guard await CommunityOSFlagService.shared.isEnabled(.meaningGraph) else {
            dlog("[CommunityGraphService] meaningGraph flag off — returning empty affinity scores")
            return []
        }

        let snapshot = try await edgesCollection(for: userId).getDocuments()

        // Accumulate strength per topic
        var topicAccumulators: [CommunityAffinityTopic: (total: Double, signals: Set<String>)] = [:]

        for document in snapshot.documents {
            let data = document.data()
            guard
                let targetType = data["targetType"] as? String,
                let strength = data["strength"] as? Double
            else { continue }

            let signals = data["signals"] as? [String] ?? []
            let topics = topicsForTargetType(targetType)

            for topic in topics {
                var current = topicAccumulators[topic] ?? (total: 0.0, signals: [])
                current.total += strength
                for signal in signals { current.signals.insert(signal) }
                topicAccumulators[topic] = current
            }
        }

        // Normalize per topic and build CommunityAffinityScore array
        let scores: [CommunityAffinityScore] = topicAccumulators.map { topic, accumulator in
            let normalized = min(accumulator.total, 1.0)
            return CommunityAffinityScore(
                userId: userId,
                topic: topic,
                score: normalized,
                signals: Array(accumulator.signals),
                updatedAt: Date()
            )
        }

        dlog("[CommunityGraphService] getAffinityScores — \(scores.count) topic scores for \(userId)")
        return scores.sorted { $0.score > $1.score }
    }

    // MARK: - getDNAProfile

    /// Fetches the stored DNA profile from Firestore.
    func getDNAProfile(for userId: String) async throws -> CommunityDNAProfile? {
        guard await CommunityOSFlagService.shared.isEnabled(.meaningGraph) else {
            dlog("[CommunityGraphService] meaningGraph flag off — skipping getDNAProfile")
            return nil
        }

        let snapshot = try await profileDocument(for: userId).getDocument()
        guard snapshot.exists, let data = snapshot.data() else {
            dlog("[CommunityGraphService] No DNA profile found for \(userId)")
            return nil
        }

        return dnaProfile(from: data, userId: userId)
    }

    // MARK: - saveDNAProfile

    /// Persists a DNA profile to Firestore.
    func saveDNAProfile(_ profile: CommunityDNAProfile) async throws {
        guard await CommunityOSFlagService.shared.isEnabled(.meaningGraph) else {
            dlog("[CommunityGraphService] meaningGraph flag off — skipping saveDNAProfile")
            return
        }

        let topAffinitiesData: [[String: Any]] = profile.topAffinities.map { score in
            [
                "userId": score.userId,
                "topic": score.topic.rawValue,
                "score": score.score,
                "signals": score.signals,
                "updatedAt": Timestamp(date: score.updatedAt)
            ]
        }

        let payload: [String: Any] = [
            "userId": profile.userId,
            "worshipAffinity": profile.worshipAffinity,
            "bibleAffinity": profile.bibleAffinity,
            "prayerAffinity": profile.prayerAffinity,
            "teachingAffinity": profile.teachingAffinity,
            "recoveryAffinity": profile.recoveryAffinity,
            "leadershipAffinity": profile.leadershipAffinity,
            "topAffinities": topAffinitiesData,
            "updatedAt": Timestamp(date: profile.updatedAt)
        ]

        try await profileDocument(for: profile.userId).setData(payload, merge: false)
        dlog("[CommunityGraphService] DNA profile saved for \(profile.userId)")
    }

    // MARK: - getTopicsSharedWith

    /// Returns affinity topics that both users share (score > 0 on both sides).
    func getTopicsSharedWith(
        userId: String,
        otherUserId: String
    ) async throws -> [CommunityAffinityTopic] {
        guard await CommunityOSFlagService.shared.isEnabled(.meaningGraph) else {
            dlog("[CommunityGraphService] meaningGraph flag off — returning empty shared topics")
            return []
        }

        async let myScores = getAffinityScores(for: userId)
        async let theirScores = getAffinityScores(for: otherUserId)

        let (mine, theirs) = try await (myScores, theirScores)

        let myTopics = Set(mine.filter { $0.score > 0 }.map { $0.topic })
        let theirTopics = Set(theirs.filter { $0.score > 0 }.map { $0.topic })
        let shared = myTopics.intersection(theirTopics)

        // Return shared topics sorted by the lower of the two scores (conservative overlap)
        let myScoreMap = Dictionary(uniqueKeysWithValues: mine.map { ($0.topic, $0.score) })
        let theirScoreMap = Dictionary(uniqueKeysWithValues: theirs.map { ($0.topic, $0.score) })

        let result = shared.sorted { a, b in
            let scoreA = min(myScoreMap[a] ?? 0, theirScoreMap[a] ?? 0)
            let scoreB = min(myScoreMap[b] ?? 0, theirScoreMap[b] ?? 0)
            return scoreA > scoreB
        }

        dlog("[CommunityGraphService] Shared topics between \(userId) and \(otherUserId): \(result.map { $0.rawValue })")
        return result
    }

    // MARK: - Private: strengthFor

    /// Maps an engagement event type to a strength delta (0.0–1.0).
    private func strengthFor(eventType: ContentEngagementEventType) -> Double {
        switch eventType {
        case .viewed:          return 0.05
        case .saved:           return 0.20
        case .shared:          return 0.15
        case .discussed:       return 0.30
        case .prayed:          return 0.40
        case .testified:       return 0.50
        case .studyStarted:    return 0.10
        case .studyCompleted:  return 0.45
        case .spaceJoined:     return 0.35
        case .spaceCreated:    return 0.40
        case .eventAttended:   return 0.35
        }
    }

    // MARK: - Private: topicsForTargetType

    /// Maps a target content type string to the CommunityAffinityTopics it contributes to.
    private func topicsForTargetType(_ targetType: String) -> [CommunityAffinityTopic] {
        guard let kind = ContentObjectKind(rawValue: targetType) else { return [] }
        switch kind {
        case .song:
            return [.worship]
        case .sermon, .podcast, .video, .course, .article:
            return [.theology, .discipleship]
        case .bibleVerse:
            return [.discipleship]
        case .prayerRequest:
            return [.prayer]
        case .book:
            return [.theology, .apologetics]
        case .event:
            return [.missions, .leadership]
        case .testimony:
            return [.discipleship, .recovery]
        case .userPost:
            return []
        }
    }

    // MARK: - Private: dnaProfile(from:userId:)

    private func dnaProfile(from data: [String: Any], userId: String) -> CommunityDNAProfile {
        let topAffinitiesData = data["topAffinities"] as? [[String: Any]] ?? []
        let topAffinities: [CommunityAffinityScore] = topAffinitiesData.compactMap { item in
            guard
                let topicRaw = item["topic"] as? String,
                let topic = CommunityAffinityTopic(rawValue: topicRaw),
                let score = item["score"] as? Double
            else { return nil }
            let signals = item["signals"] as? [String] ?? []
            let updatedAt = (item["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
            return CommunityAffinityScore(
                userId: userId,
                topic: topic,
                score: score,
                signals: signals,
                updatedAt: updatedAt
            )
        }

        return CommunityDNAProfile(
            userId: userId,
            worshipAffinity: data["worshipAffinity"] as? Double ?? 0.0,
            bibleAffinity: data["bibleAffinity"] as? Double ?? 0.0,
            prayerAffinity: data["prayerAffinity"] as? Double ?? 0.0,
            teachingAffinity: data["teachingAffinity"] as? Double ?? 0.0,
            recoveryAffinity: data["recoveryAffinity"] as? Double ?? 0.0,
            leadershipAffinity: data["leadershipAffinity"] as? Double ?? 0.0,
            topAffinities: topAffinities,
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }
}

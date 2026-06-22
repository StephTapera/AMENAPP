import Foundation
import FirebaseFirestore

@MainActor
final class TrustScoringEngine {

    static let shared = TrustScoringEngine()
    private let db = Firestore.firestore()
    private let algorithmVersion = "1.0.0"
    private let eventWindowDays = 90
    private var lastComputationTime: [String: Date] = [:]
    private let recomputeThrottle: TimeInterval = 3600

    private init() {}

    func computeScores(userId: String) async -> TrustScoreSnapshot? {
        guard AMENFeatureFlags.shared.trustSignalsEnabled else { return nil }
        if let lastTime = lastComputationTime[userId], Date().timeIntervalSince(lastTime) < recomputeThrottle {
            return nil
        }
        lastComputationTime[userId] = Date()

        let now = Date()
        let windowStart = Calendar.current.date(byAdding: .day, value: -eventWindowDays, to: now) ?? now
        let events = await fetchEvents(userId: userId, since: windowStart)
        let humanScore = computeHumanScore(userId: userId, events: events, now: now)
        let careScore = computeCareScore(userId: userId, events: events, now: now)
        let snapshot = TrustScoreSnapshot(
            id: UUID().uuidString,
            userId: userId,
            humanScore: humanScore,
            careScore: careScore,
            computedAt: now,
            algorithmVersion: algorithmVersion,
            eventWindowStart: windowStart,
            eventWindowEnd: now,
            eventCount: events.count,
            previousSnapshotId: nil
        )
        await persist(snapshot: snapshot, userId: userId)
        return snapshot
    }

    private func computeHumanScore(userId: String, events: [TrustEvent], now: Date) -> ProofOfHumanScore {
        var factors: [HumanSignalFactor] = []
        let integrityEvents = events.filter { $0.eventType == .composerIntegrity }
        if !integrityEvents.isEmpty {
            let avgRatio = integrityEvents.map(\.value).reduce(0, +) / Double(integrityEvents.count)
            factors.append(.init(factorType: .typedVsPastedRatio, value: avgRatio, weight: 0.25, direction: .positive, source: "ComposerIntegrityTracker", measuredAt: now))
        }
        let postEvents = events.filter { $0.eventType == .postCreated }
        let categories = Set(postEvents.compactMap { $0.metadata?["category"] })
        factors.append(.init(factorType: .contentVariety, value: min(1.0, Double(categories.count) / 4.0), weight: 0.1, direction: .positive, source: "post_activity", measuredAt: now))
        factors.append(.init(factorType: .socialGraphDepth, value: min(1.0, Double(events.filter { $0.eventType == .meaningfulReply }.count) / 20.0), weight: 0.15, direction: .positive, source: "interaction_history", measuredAt: now))
        if !events.filter({ $0.eventType == .contentFlagged }).isEmpty {
            factors.append(.init(factorType: .moderationHits, value: min(1.0, Double(events.filter { $0.eventType == .contentFlagged }.count) / 5.0), weight: 0.2, direction: .negative, source: "moderation_history", measuredAt: now))
        }
        let (score, confidence) = computeWeightedScore(factors: factors, eventCount: events.count)
        return .init(userId: userId, score: score, confidence: confidence, factors: factors, computedAt: now, snapshotId: UUID().uuidString, version: algorithmVersion)
    }

    private func computeCareScore(userId: String, events: [TrustEvent], now: Date) -> ProofOfCareScore {
        var factors: [CareSignalFactor] = []
        let prayerCommits = events.filter { $0.eventType == .prayerCommitment }
        let prayerFollowUps = events.filter { $0.eventType == .prayerFollowUp }
        if !prayerCommits.isEmpty {
            let followRate = Double(prayerFollowUps.count) / Double(prayerCommits.count)
            factors.append(.init(factorType: .prayerFollowThrough, value: min(1.0, followRate), weight: 0.25, direction: .positive, source: "PrayerFollowThroughService", measuredAt: now))
        }
        factors.append(.init(factorType: .meaningfulReplies, value: min(1.0, Double(events.filter { $0.eventType == .meaningfulReply }.count) / 15.0), weight: 0.2, direction: .positive, source: "CommentService", measuredAt: now))
        let (score, confidence) = computeWeightedScore(factors: factors, eventCount: events.count)
        return .init(userId: userId, score: score, confidence: confidence, factors: factors, computedAt: now, snapshotId: UUID().uuidString, version: algorithmVersion)
    }

    private func computeWeightedScore<F>(factors: [F], eventCount: Int) -> (Double, Double) where F: TrustWeightedFactor {
        guard !factors.isEmpty else { return (0.5, 0.1) }
        let totalWeight = factors.reduce(0) { $0 + $1.factorWeight }
        let totalContribution = factors.reduce(0) { $0 + $1.weightedContribution }
        let rawScore = totalWeight > 0 ? totalContribution / totalWeight : 0
        let score = max(0.0, min(1.0, (rawScore + 1.0) / 2.0))
        let confidence = min(1.0, Double(eventCount) / 50.0) * 0.6 + min(1.0, Double(factors.count) / 6.0) * 0.4
        return (score, confidence)
    }

    private func fetchEvents(userId: String, since: Date) async -> [TrustEvent] {
        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("trust").document("events")
                .collection("items")
                .whereField("timestamp", isGreaterThan: Timestamp(date: since))
                .order(by: "timestamp", descending: false)
                .limit(to: 500)
                .getDocuments()
            return snapshot.documents.compactMap { try? $0.data(as: TrustEvent.self) }
        } catch {
            dlog("[TrustScoringEngine] fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    private func persist(snapshot: TrustScoreSnapshot, userId: String) async {
        do {
            try db.collection("users").document(userId)
                .collection("trust").document("proofSnapshots")
                .collection("items").document(snapshot.id)
                .setData(from: snapshot)
            try db.collection("users").document(userId)
                .collection("trust").document("humanScore")
                .setData(from: snapshot.humanScore)
            try db.collection("users").document(userId)
                .collection("trust").document("careScore")
                .setData(from: snapshot.careScore)
        } catch {
            dlog("[TrustScoringEngine] persist failed: \(error.localizedDescription)")
        }
    }
}

private protocol TrustWeightedFactor {
    var factorWeight: Double { get }
    var weightedContribution: Double { get }
}

extension HumanSignalFactor: TrustWeightedFactor {
    var factorWeight: Double { weight }
    var weightedContribution: Double { contribution }
}

extension CareSignalFactor: TrustWeightedFactor {
    var factorWeight: Double { weight }
    var weightedContribution: Double { contribution }
}

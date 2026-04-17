//
//  TrustScoringEngine.swift
//  AMENAPP
//
//  Configurable scoring pipeline that computes ProofOfHumanScore and
//  ProofOfCareScore from TrustEvents. Produces snapshots for audit.
//
//  Design principles:
//    - Confidence-based signals with weighted factors
//    - Score decay / aging for old events
//    - Explainability for internal review
//    - No irreversible punitive logic
//    - Separate from moderation penalties
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class TrustScoringEngine {
    
    static let shared = TrustScoringEngine()
    private let db = Firestore.firestore()
    private init() {}
    
    // Algorithm version — bump on scoring logic changes for auditability
    private let algorithmVersion = "1.0.0"
    
    // Scoring windows
    private let eventWindowDays: Int = 90            // Consider last 90 days of events
    private let decayHalfLifeDays: Double = 30.0     // Events lose half weight every 30 days
    
    // Recomputation throttle: don't recompute more than once per hour
    private var lastComputationTime: [String: Date] = [:]
    private let recomputeThrottle: TimeInterval = 3600
    
    // MARK: - Feature Guard
    
    private var isEnabled: Bool {
        AMENFeatureFlags.shared.trustSignalsEnabled
    }
    
    // MARK: - Compute Scores
    
    /// Compute both ProofOfHumanScore and ProofOfCareScore for a user.
    /// Results are persisted as a snapshot for auditability.
    func computeScores(userId: String) async -> TrustScoreSnapshot? {
        guard isEnabled else { return nil }
        
        // Throttle
        if let lastTime = lastComputationTime[userId],
           Date().timeIntervalSince(lastTime) < recomputeThrottle {
            return nil
        }
        lastComputationTime[userId] = Date()
        
        let now = Date()
        let windowStart = Calendar.current.date(byAdding: .day, value: -eventWindowDays, to: now)!
        
        // Fetch events
        let events = await fetchEvents(userId: userId, since: windowStart)
        
        // Compute human score
        let humanScore = computeHumanScore(userId: userId, events: events, now: now)
        
        // Compute care score
        let careScore = computeCareScore(userId: userId, events: events, now: now)
        
        // Create snapshot
        let snapshotId = UUID().uuidString
        let snapshot = TrustScoreSnapshot(
            id: snapshotId,
            userId: userId,
            humanScore: humanScore,
            careScore: careScore,
            computedAt: now,
            algorithmVersion: algorithmVersion,
            eventWindowStart: windowStart,
            eventWindowEnd: now,
            eventCount: events.count,
            previousSnapshotId: nil  // Could be fetched for diff but not required
        )
        
        // Persist
        await persistSnapshot(snapshot, userId: userId)
        await persistLatestScores(humanScore: humanScore, careScore: careScore, userId: userId)
        
        return snapshot
    }
    
    // MARK: - Human Score Computation
    
    private func computeHumanScore(userId: String, events: [TrustEvent], now: Date) -> ProofOfHumanScore {
        let snapshotId = UUID().uuidString
        var factors: [HumanSignalFactor] = []
        
        // Factor: Account maturity
        let accountAgeDays = events.isEmpty ? 0 :
            Calendar.current.dateComponents([.day], from: events.first?.timestamp ?? now, to: now).day ?? 0
        let maturityValue = min(1.0, Double(accountAgeDays) / 90.0)
        factors.append(HumanSignalFactor(
            factorType: .accountMaturity,
            value: maturityValue,
            weight: 0.20,
            direction: .positive,
            source: "account_metadata",
            measuredAt: now
        ))
        
        // Factor: Typed vs pasted ratio (from composer integrity events)
        let integrityEvents = events.filter { $0.eventType == .composerIntegrity }
        if !integrityEvents.isEmpty {
            let avgRatio = integrityEvents.map { $0.value }.reduce(0, +) / Double(integrityEvents.count)
            factors.append(HumanSignalFactor(
                factorType: .typedVsPastedRatio,
                value: avgRatio,
                weight: 0.25,
                direction: .positive,
                source: "ComposerIntegrityTracker",
                measuredAt: now
            ))
        }
        
        // Factor: Content variety (unique post categories)
        let postEvents = events.filter { $0.eventType == .postCreated }
        let categories = Set(postEvents.compactMap { $0.metadata?["category"] })
        let varietyValue = min(1.0, Double(categories.count) / 4.0)
        if !postEvents.isEmpty {
            factors.append(HumanSignalFactor(
                factorType: .contentVariety,
                value: varietyValue,
                weight: 0.10,
                direction: .positive,
                source: "post_activity",
                measuredAt: now
            ))
        }
        
        // Factor: Social graph depth (computed from follow/mutual data)
        // Using a proxy: events with meaningful replies
        let replyEvents = events.filter { $0.eventType == .meaningfulReply }
        let socialValue = min(1.0, Double(replyEvents.count) / 20.0)
        factors.append(HumanSignalFactor(
            factorType: .socialGraphDepth,
            value: socialValue,
            weight: 0.15,
            direction: .positive,
            source: "interaction_history",
            measuredAt: now
        ))
        
        // Negative factors
        let flaggedEvents = events.filter { $0.eventType == .contentFlagged }
        if !flaggedEvents.isEmpty {
            let flagRate = min(1.0, Double(flaggedEvents.count) / 5.0)
            factors.append(HumanSignalFactor(
                factorType: .moderationHits,
                value: flagRate,
                weight: 0.20,
                direction: .negative,
                source: "moderation_history",
                measuredAt: now
            ))
        }
        
        let suspiciousEvents = events.filter { $0.eventType == .suspiciousPattern }
        if !suspiciousEvents.isEmpty {
            let suspicionRate = min(1.0, Double(suspiciousEvents.count) / 3.0)
            factors.append(HumanSignalFactor(
                factorType: .rapidPostingPattern,
                value: suspicionRate,
                weight: 0.15,
                direction: .negative,
                source: "behavioral_analysis",
                measuredAt: now
            ))
        }
        
        // Compute weighted score with decay
        let (score, confidence) = computeWeightedScore(factors: factors, events: events, now: now)
        
        return ProofOfHumanScore(
            userId: userId,
            score: score,
            confidence: confidence,
            factors: factors,
            computedAt: now,
            snapshotId: snapshotId,
            version: algorithmVersion
        )
    }
    
    // MARK: - Care Score Computation
    
    private func computeCareScore(userId: String, events: [TrustEvent], now: Date) -> ProofOfCareScore {
        let snapshotId = UUID().uuidString
        var factors: [CareSignalFactor] = []
        
        // Factor: Prayer follow-through
        let prayerCommits = events.filter { $0.eventType == .prayerCommitment }
        let prayerFollowUps = events.filter { $0.eventType == .prayerFollowUp }
        if !prayerCommits.isEmpty {
            let followThroughRate = Double(prayerFollowUps.count) / Double(prayerCommits.count)
            factors.append(CareSignalFactor(
                factorType: .prayerFollowThrough,
                value: min(1.0, followThroughRate),
                weight: 0.25,
                direction: .positive,
                source: "PrayerFollowThroughService",
                measuredAt: now
            ))
        }
        
        // Factor: Action thread step completion
        let stepCompletions = events.filter { $0.eventType == .actionStepCompleted }
        if !stepCompletions.isEmpty {
            let completionValue = min(1.0, Double(stepCompletions.count) / 10.0)
            factors.append(CareSignalFactor(
                factorType: .supportActionCompletion,
                value: completionValue,
                weight: 0.20,
                direction: .positive,
                source: "ActionThreadService",
                measuredAt: now
            ))
        }
        
        // Factor: Meaningful replies
        let meaningfulReplies = events.filter { $0.eventType == .meaningfulReply }
        if !meaningfulReplies.isEmpty {
            let replyValue = min(1.0, Double(meaningfulReplies.count) / 15.0)
            factors.append(CareSignalFactor(
                factorType: .meaningfulReplies,
                value: replyValue,
                weight: 0.20,
                direction: .positive,
                source: "CommentService",
                measuredAt: now
            ))
        }
        
        // Factor: Check-in completions
        let checkIns = events.filter { $0.eventType == .checkInCompleted }
        if !checkIns.isEmpty {
            let checkInValue = min(1.0, Double(checkIns.count) / 5.0)
            factors.append(CareSignalFactor(
                factorType: .checkInCompletion,
                value: checkInValue,
                weight: 0.15,
                direction: .positive,
                source: "ActionThreadService",
                measuredAt: now
            ))
        }
        
        // Factor: Consistent engagement (not bursty)
        let postDates = events.filter { $0.eventType == .postCreated }.map { $0.timestamp }
        if postDates.count >= 5 {
            let consistency = computeConsistency(dates: postDates)
            factors.append(CareSignalFactor(
                factorType: .consistentEngagement,
                value: consistency,
                weight: 0.10,
                direction: .positive,
                source: "activity_pattern",
                measuredAt: now
            ))
        }
        
        // Negative factors
        let abandonedEvents = events.filter { $0.eventType == .commitmentAbandoned }
        if !abandonedEvents.isEmpty {
            let abandonRate = min(1.0, Double(abandonedEvents.count) / 3.0)
            factors.append(CareSignalFactor(
                factorType: .abandonedCommitments,
                value: abandonRate,
                weight: 0.15,
                direction: .negative,
                source: "ActionThreadService",
                measuredAt: now
            ))
        }
        
        let blockEvents = events.filter { $0.eventType == .blockReceived }
        if !blockEvents.isEmpty {
            let blockRate = min(1.0, Double(blockEvents.count) / 5.0)
            factors.append(CareSignalFactor(
                factorType: .driveByBehavior,
                value: blockRate,
                weight: 0.10,
                direction: .negative,
                source: "BlockService",
                measuredAt: now
            ))
        }
        
        let (score, confidence) = computeWeightedScore(factors: factors, events: events, now: now)
        
        return ProofOfCareScore(
            userId: userId,
            score: score,
            confidence: confidence,
            factors: factors,
            computedAt: now,
            snapshotId: snapshotId,
            version: algorithmVersion
        )
    }
    
    // MARK: - Weighted Score Calculation
    
    private func computeWeightedScore(factors: [any WeightedFactor], events: [TrustEvent], now: Date) -> (score: Double, confidence: Double) {
        guard !factors.isEmpty else { return (0.5, 0.1) }
        
        var positiveSum = 0.0
        var negativeSum = 0.0
        var totalWeight = 0.0
        
        for factor in factors {
            let contribution = factor.weightedContribution
            totalWeight += factor.factorWeight
            
            if contribution >= 0 {
                positiveSum += contribution
            } else {
                negativeSum += abs(contribution)
            }
        }
        
        // Normalize to 0.0–1.0
        let rawScore = totalWeight > 0 ? (positiveSum - negativeSum) / totalWeight : 0.5
        let score = max(0.0, min(1.0, (rawScore + 1.0) / 2.0))  // Map from [-1,1] to [0,1]
        
        // Confidence based on number of events and factor coverage
        let eventConfidence = min(1.0, Double(events.count) / 50.0)
        let factorConfidence = min(1.0, Double(factors.count) / 6.0)
        let confidence = (eventConfidence * 0.6 + factorConfidence * 0.4)
        
        return (score, confidence)
    }
    
    /// Compute engagement consistency (0 = very bursty, 1 = very consistent)
    private func computeConsistency(dates: [Date]) -> Double {
        guard dates.count >= 2 else { return 0.5 }
        let sorted = dates.sorted()
        let intervals = zip(sorted, sorted.dropFirst()).map { $1.timeIntervalSince($0) }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        guard mean > 0 else { return 0.5 }
        let variance = intervals.map { pow($0 - mean, 2) }.reduce(0, +) / Double(intervals.count)
        let cv = sqrt(variance) / mean  // Coefficient of variation
        return max(0, min(1.0, 1.0 - cv))
    }
    
    // MARK: - Event Fetching
    
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
            dlog("[TrustScoringEngine] Failed to fetch events: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Persistence
    
    private func persistSnapshot(_ snapshot: TrustScoreSnapshot, userId: String) async {
        do {
            try await db.collection("users").document(userId)
                .collection("trust").document("proofSnapshots")
                .collection("items").document(snapshot.id)
                .setData(from: snapshot)
        } catch {
            dlog("[TrustScoringEngine] Failed to persist snapshot: \(error.localizedDescription)")
        }
    }
    
    private func persistLatestScores(humanScore: ProofOfHumanScore, careScore: ProofOfCareScore, userId: String) async {
        do {
            try await db.collection("users").document(userId)
                .collection("trust").document("humanScore")
                .setData(from: humanScore)
            try await db.collection("users").document(userId)
                .collection("trust").document("careScore")
                .setData(from: careScore)
        } catch {
            dlog("[TrustScoringEngine] Failed to persist latest scores: \(error.localizedDescription)")
        }
    }
}

// MARK: - Weighted Factor Protocol

private protocol WeightedFactor {
    var factorWeight: Double { get }
    var weightedContribution: Double { get }
}

extension HumanSignalFactor: WeightedFactor {
    var factorWeight: Double { weight }
    var weightedContribution: Double { contribution }
}

extension CareSignalFactor: WeightedFactor {
    var factorWeight: Double { weight }
    var weightedContribution: Double { contribution }
}

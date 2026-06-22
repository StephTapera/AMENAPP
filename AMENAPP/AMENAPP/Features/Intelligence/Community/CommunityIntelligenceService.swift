// CommunityIntelligenceService.swift — Features/Intelligence/Community
// Tracks community health signals for church-tier accounts.
// Aggregates group join, event RSVP, and volunteer match signals into a health score.
//
// Invariants:
//  • Church tier required (SystemCapability.communityHealth)
//  • Flag: ctx_community_health_enabled — default false (currently not in ContextIntelligenceFlags;
//    routed via ctx_group_formation_analytics_enabled until a dedicated flag is promoted)
//  • Data is aggregated at community level — individual signals are never surfaced to other users

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - CommunityHealthSnapshot

struct CommunityHealthSnapshot: Sendable {
    let communityID: String
    let weeklyNewMembers: Int
    let activeGroupCount: Int
    let eventEngagementRate: Double    // 0.0–1.0
    let volunteerFillRate: Double      // 0.0–1.0
    let computedAt: Date
}

// MARK: - CommunityIntelligenceService

final class CommunityIntelligenceService: ObservableObject, @unchecked Sendable {
    static let shared = CommunityIntelligenceService()

    @Published private(set) var snapshot: CommunityHealthSnapshot? = nil

    private var subscriptionTask: Task<Void, Never>? = nil

    private init() {}

    // MARK: - Public API

    func startObserving(communityID: String) {
        guard ContextIntelligenceFlags.groupFormation else { return }

        Task {
            let gate = await EntitlementGate.shared.canAccess(.communityHealth)
            guard gate.allowed else { return }

            subscriptionTask = Task {
                let communityTypes: [SignalType] = [
                    .groupJoined, .eventRSVPed, .volunteerMatched
                ]
                let stream = await ContextBus.shared.subscribe(to: communityTypes)
                for await _ in stream {
                    guard !Task.isCancelled else { break }
                    await self.refreshSnapshot(communityID: communityID)
                }
            }

            await refreshSnapshot(communityID: communityID)
        }
    }

    func stopObserving() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }

    // MARK: - Snapshot refresh

    private func refreshSnapshot(communityID: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let db = Firestore.firestore()
        let weekAgo = Timestamp(date: Date(timeIntervalSinceNow: -7 * 86_400))

        async let memberCount = countDocuments(
            db.collection("communityMembers")
              .whereField("communityID", isEqualTo: communityID)
              .whereField("joinedAt", isGreaterThan: weekAgo)
        )

        async let groupCount = countDocuments(
            db.collection("groups")
              .whereField("communityID", isEqualTo: communityID)
              .whereField("memberCount", isGreaterThan: 0)
        )

        async let eventStats = fetchEventStats(communityID: communityID, db: db)
        async let volunteerStats = fetchVolunteerStats(communityID: communityID, db: db)

        let (members, groups, (evtRate, volRate)) = await (memberCount, groupCount, (eventStats, volunteerStats))

        let s = CommunityHealthSnapshot(
            communityID: communityID,
            weeklyNewMembers: members,
            activeGroupCount: groups,
            eventEngagementRate: evtRate,
            volunteerFillRate: volRate,
            computedAt: Date()
        )

        // Satisfy compiler re: uid
        _ = uid

        await MainActor.run { self.snapshot = s }
    }

    private func countDocuments(_ query: Query) async -> Int {
        (try? await query.count.getAggregation(source: .server).count.intValue) ?? 0
    }

    private func fetchEventStats(communityID: String, db: Firestore) async -> Double {
        let weekAgo = Timestamp(date: Date(timeIntervalSinceNow: -7 * 86_400))
        let total = await countDocuments(
            db.collection("events")
              .whereField("communityID", isEqualTo: communityID)
              .whereField("startsAt", isGreaterThan: weekAgo)
        )
        guard total > 0 else { return 0 }
        let rsvpd = await countDocuments(
            db.collection("eventRSVPs")
              .whereField("communityID", isEqualTo: communityID)
              .whereField("rsvpdAt", isGreaterThan: weekAgo)
        )
        return Double(rsvpd) / Double(max(total, 1))
    }

    private func fetchVolunteerStats(communityID: String, db: Firestore) async -> Double {
        let total = await countDocuments(
            db.collection("volunteerNeeds")
              .whereField("communityID", isEqualTo: communityID)
              .whereField("isOpen", isEqualTo: true)
        )
        guard total > 0 else { return 1.0 }
        let filled = await countDocuments(
            db.collection("volunteerMatches")
              .whereField("communityID", isEqualTo: communityID)
              .whereField("status", isEqualTo: "confirmed")
        )
        return Double(filled) / Double(max(total, 1))
    }
}

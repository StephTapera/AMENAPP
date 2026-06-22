// AmenSpacesDashboardViewModel.swift
// AMEN Spiritual OS — Spaces Dashboard
// Real Firestore data, parallel async/let loads, @Observable pattern.
// Updated 2026-06-03 — migrated from ObservableObject to @Observable.

import Foundation
import Observation
import FirebaseFirestore
import SwiftUI

// MARK: - Support types

struct MemberPreview: Identifiable {
    let id: String
    let photoURL: URL?
    let displayName: String
}

struct SpaceDashboardEvent: Identifiable {
    let id: String
    let title: String
    let startTime: Date
    let location: String?
}

struct StudySeries {
    let seriesTitle: String
    let currentWeek: Int
    let totalWeeks: Int
    let suggestedReading: String?
}

struct ActivityItem: Identifiable {
    let id: String
    let actorName: String
    let actorPhotoURL: URL?
    let actionType: String
    let summary: String
    let timestamp: Date
}

// MARK: - AmenSpacesDashboardViewModel

@Observable
@MainActor
final class AmenSpacesDashboardViewModel {

    // MARK: - Exposed state

    var memberPreviews: [MemberPreview] = []
    var totalMemberCount: Int = 0
    var activePrayerCount: Int = 0
    var nextEvent: SpaceDashboardEvent? = nil
    var currentStudySeries: StudySeries? = nil
    var recentActivity: [ActivityItem] = []
    var isLoading: Bool = false

    // Per-space hero card gate (read from the space document)
    var heroCardEnabled: Bool = false

    // MARK: - Private

    private let spaceId: String
    @ObservationIgnored private let db = Firestore.firestore()

    // MARK: - Init

    init(spaceId: String) {
        self.spaceId = spaceId
    }

    // MARK: - Load (parallel)

    func load() async {
        guard !spaceId.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        let spaceRef = db.collection("spaces").document(spaceId)

        // Feature gate lives in the space document — load first (sequential)
        await loadSpaceGate(spaceRef: spaceRef)

        // Remaining subcollections load in parallel
        async let membersResult  = loadMembers(spaceRef: spaceRef)
        async let prayerResult   = loadActivePrayerCount(spaceRef: spaceRef)
        async let eventResult    = loadNextEvent(spaceRef: spaceRef)
        async let seriesResult   = loadCurrentStudySeries(spaceRef: spaceRef)
        async let activityResult = loadRecentActivity(spaceRef: spaceRef)

        let (members, prayerCount, event, series, activity) =
            await (membersResult, prayerResult, eventResult, seriesResult, activityResult)

        memberPreviews    = members.previews
        totalMemberCount  = members.totalCount
        activePrayerCount = prayerCount
        nextEvent         = event
        currentStudySeries = series
        recentActivity    = activity
    }

    // MARK: - Private helpers

    private func loadSpaceGate(spaceRef: DocumentReference) async {
        do {
            let doc = try await spaceRef.getDocument()
            heroCardEnabled = doc.data()?["heroCardEnabled"] as? Bool ?? false
        } catch {
            heroCardEnabled = false
        }
    }

    /// spaces/{spaceId}/members — orderBy joinedAt desc limit 5 + aggregate count
    private func loadMembers(spaceRef: DocumentReference) async
        -> (previews: [MemberPreview], totalCount: Int)
    {
        do {
            let col = spaceRef.collection("members")

            let countSnap = try await col.count.getAggregation(source: .server)
            let total = countSnap.count.intValue

            let snap = try await col
                .order(by: "joinedAt", descending: true)
                .limit(to: 5)
                .getDocuments()

            let previews: [MemberPreview] = snap.documents.map { doc in
                let d = doc.data()
                return MemberPreview(
                    id: doc.documentID,
                    photoURL: (d["photoURL"] as? String).flatMap(URL.init),
                    displayName: d["displayName"] as? String ?? ""
                )
            }
            return (previews, total)
        } catch {
            return ([], 0)
        }
    }

    /// spaces/{spaceId}/prayerRequests where status == "active" — count()
    private func loadActivePrayerCount(spaceRef: DocumentReference) async -> Int {
        do {
            let snap = try await spaceRef
                .collection("prayerRequests")
                .whereField("status", isEqualTo: "active")
                .count
                .getAggregation(source: .server)
            return snap.count.intValue
        } catch {
            return 0
        }
    }

    /// spaces/{spaceId}/events where startTime >= now orderBy startTime asc limit 1
    private func loadNextEvent(spaceRef: DocumentReference) async -> SpaceDashboardEvent? {
        do {
            let snap = try await spaceRef
                .collection("events")
                .whereField("startTime", isGreaterThanOrEqualTo: Timestamp(date: Date()))
                .order(by: "startTime", descending: false)
                .limit(to: 1)
                .getDocuments()

            guard let doc = snap.documents.first else { return nil }
            let d = doc.data()
            let title = d["title"] as? String ?? ""
            guard !title.isEmpty else { return nil }
            let startTime = (d["startTime"] as? Timestamp)?.dateValue() ?? Date()
            return SpaceDashboardEvent(
                id: doc.documentID,
                title: title,
                startTime: startTime,
                location: d["location"] as? String
            )
        } catch {
            return nil
        }
    }

    /// spaces/{spaceId}/studySeries where isCurrent == true limit 1
    private func loadCurrentStudySeries(spaceRef: DocumentReference) async -> StudySeries? {
        do {
            let snap = try await spaceRef
                .collection("studySeries")
                .whereField("isCurrent", isEqualTo: true)
                .limit(to: 1)
                .getDocuments()

            guard let doc = snap.documents.first else { return nil }
            let d = doc.data()
            let title = d["seriesTitle"] as? String ?? ""
            guard !title.isEmpty else { return nil }
            return StudySeries(
                seriesTitle: title,
                currentWeek: d["currentWeek"] as? Int ?? 1,
                totalWeeks: d["totalWeeks"] as? Int ?? 1,
                suggestedReading: d["suggestedReading"] as? String
            )
        } catch {
            return nil
        }
    }

    /// spaces/{spaceId}/activity orderBy timestamp desc limit 5
    private func loadRecentActivity(spaceRef: DocumentReference) async -> [ActivityItem] {
        do {
            let snap = try await spaceRef
                .collection("activity")
                .order(by: "timestamp", descending: true)
                .limit(to: 5)
                .getDocuments()

            return snap.documents.compactMap { doc -> ActivityItem? in
                let d = doc.data()
                let actorName = d["actorName"] as? String ?? ""
                let summary   = d["summary"]   as? String ?? ""
                let ts = (d["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                return ActivityItem(
                    id: doc.documentID,
                    actorName: actorName,
                    actorPhotoURL: (d["actorPhotoURL"] as? String).flatMap(URL.init),
                    actionType: d["actionType"] as? String ?? "post",
                    summary: summary,
                    timestamp: ts
                )
            }
        } catch {
            return []
        }
    }
}

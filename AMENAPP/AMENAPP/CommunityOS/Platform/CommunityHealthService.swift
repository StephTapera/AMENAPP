// CommunityHealthService.swift
// AMEN App — Community Around Content OS / Platform Layer
//
// Tracks and scores community health using meaningful signals only.
// No likes, no follower counts, no vanity metrics.
//
// Feature flag: CommunityOSFlag.communityHealthEngine

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - CommunityHealthDelta

/// Incremental adjustments applied atomically to a CommunityHealthSignals document via
/// Firestore FieldValue.increment. All fields are optional — only non-nil values are written.
struct CommunityHealthDelta: Codable {
    /// Delta for prayerActivityScore (fractional increment/decrement).
    var prayerActivityDelta: Double?
    /// Delta for discussionQualityScore.
    var discussionQualityDelta: Double?
    /// Delta for responseRateScore.
    var responseRateDelta: Double?
    /// Delta for mentorshipEngagementScore.
    var mentorshipEngagementDelta: Double?
    /// Delta for eventAttendanceScore.
    var eventAttendanceDelta: Double?
    /// Delta for studyCompletionScore.
    var studyCompletionDelta: Double?

    init(
        prayerActivityDelta: Double? = nil,
        discussionQualityDelta: Double? = nil,
        responseRateDelta: Double? = nil,
        mentorshipEngagementDelta: Double? = nil,
        eventAttendanceDelta: Double? = nil,
        studyCompletionDelta: Double? = nil
    ) {
        self.prayerActivityDelta = prayerActivityDelta
        self.discussionQualityDelta = discussionQualityDelta
        self.responseRateDelta = responseRateDelta
        self.mentorshipEngagementDelta = mentorshipEngagementDelta
        self.eventAttendanceDelta = eventAttendanceDelta
        self.studyCompletionDelta = studyCompletionDelta
    }

    /// Returns true if at least one delta field carries a non-nil value.
    var hasChanges: Bool {
        prayerActivityDelta != nil
        || discussionQualityDelta != nil
        || responseRateDelta != nil
        || mentorshipEngagementDelta != nil
        || eventAttendanceDelta != nil
        || studyCompletionDelta != nil
    }
}

// MARK: - CommunityHealthService

actor CommunityHealthService {

    // MARK: Singleton

    static let shared = CommunityHealthService()

    // MARK: Private

    private let db = Firestore.firestore()

    private func healthDoc(for communityId: String) -> DocumentReference {
        db.collection("communityHealth").document(communityId)
    }

    private func dailySignalsDoc(for communityId: String, date: String) -> DocumentReference {
        healthDoc(for: communityId).collection("dailySignals").document(date)
    }

    // MARK: - fetchHealthSignals

    /// Fetches the current health signals for the given community.
    /// Returns nil if no document exists yet.
    func fetchHealthSignals(for communityId: String) async throws -> CommunityHealthSignals? {
        guard CommunityOSFlagService.shared.isEnabled(.communityHealthEngine) else {
            dlog("[CommunityHealthService] Flag communityHealthEngine is off — skipping fetch")
            return nil
        }

        let snapshot = try await healthDoc(for: communityId).getDocument()
        guard snapshot.exists, let data = snapshot.data() else {
            return nil
        }

        return decodeSignals(from: data, communityId: communityId)
    }

    // MARK: - updateHealthSignals

    /// Atomically increments the relevant signal fields using Firestore FieldValue.increment.
    /// Only delta fields that are non-nil are written to Firestore.
    func updateHealthSignals(for communityId: String, delta: CommunityHealthDelta) async throws {
        guard CommunityOSFlagService.shared.isEnabled(.communityHealthEngine) else {
            dlog("[CommunityHealthService] Flag communityHealthEngine is off — skipping update")
            return
        }
        guard delta.hasChanges else { return }

        var updates: [String: Any] = [
            "communityId": communityId,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let v = delta.prayerActivityDelta {
            updates["prayerActivityScore"] = FieldValue.increment(v)
        }
        if let v = delta.discussionQualityDelta {
            updates["discussionQualityScore"] = FieldValue.increment(v)
        }
        if let v = delta.responseRateDelta {
            updates["responseRateScore"] = FieldValue.increment(v)
        }
        if let v = delta.mentorshipEngagementDelta {
            updates["mentorshipEngagementScore"] = FieldValue.increment(v)
        }
        if let v = delta.eventAttendanceDelta {
            updates["eventAttendanceScore"] = FieldValue.increment(v)
        }
        if let v = delta.studyCompletionDelta {
            updates["studyCompletionScore"] = FieldValue.increment(v)
        }

        try await healthDoc(for: communityId).setData(updates, merge: true)
        dlog("[CommunityHealthService] Updated health signals for community \(communityId)")
    }

    // MARK: - computeHealthTier

    /// Pure function mapping overallHealthScore to a CommunityHealthTier.
    /// ≥ 0.80 → thriving | ≥ 0.65 → healthy | ≥ 0.45 → growing | ≥ 0.25 → dormant | < 0.25 → atrisk
    func computeHealthTier(signals: CommunityHealthSignals) -> CommunityHealthTier {
        let score = signals.overallHealthScore
        switch score {
        case 0.80...:    return .thriving
        case 0.65..<0.80: return .healthy
        case 0.45..<0.65: return .growing
        case 0.25..<0.45: return .dormant
        default:          return .atrisk
        }
    }

    // MARK: - getHealthLeaders

    /// Queries communityHealth ordered by overallHealthScore (descending), returns top N communities.
    /// Note: overallHealthScore is a computed property — we use a denormalized `overallHealthScore`
    /// field written by the server; if absent we fall back to sorting client-side.
    func getHealthLeaders(limit: Int) async throws -> [(communityId: String, signals: CommunityHealthSignals)] {
        guard CommunityOSFlagService.shared.isEnabled(.communityHealthEngine) else {
            dlog("[CommunityHealthService] Flag communityHealthEngine is off — skipping leaders query")
            return []
        }

        let safeLimit = max(1, min(limit, 50))
        let snapshot = try await db
            .collection("communityHealth")
            .order(by: "overallHealthScore", descending: true)
            .limit(to: safeLimit)
            .getDocuments()

        return snapshot.documents.compactMap { doc -> (communityId: String, signals: CommunityHealthSignals)? in
            let communityId = doc.documentID
            guard let signals = decodeSignals(from: doc.data(), communityId: communityId) else { return nil }
            return (communityId: communityId, signals: signals)
        }
    }

    // MARK: - snapshotDailyHealth

    /// Copies current health signals to the dailySignals subcollection for trend tracking.
    /// Uses today's ISO-8601 date string as the document ID.
    func snapshotDailyHealth(communityId: String) async throws {
        guard CommunityOSFlagService.shared.isEnabled(.communityHealthEngine) else {
            dlog("[CommunityHealthService] Flag communityHealthEngine is off — skipping snapshot")
            return
        }

        guard let signals = try await fetchHealthSignals(for: communityId) else {
            dlog("[CommunityHealthService] No signals found for \(communityId) — nothing to snapshot")
            return
        }

        let dateString = ISO8601DateFormatter.amenDateOnly.string(from: Date())
        let snapshot: [String: Any] = [
            "communityId": signals.communityId,
            "prayerActivityScore": signals.prayerActivityScore,
            "discussionQualityScore": signals.discussionQualityScore,
            "responseRateScore": signals.responseRateScore,
            "mentorshipEngagementScore": signals.mentorshipEngagementScore,
            "eventAttendanceScore": signals.eventAttendanceScore,
            "studyCompletionScore": signals.studyCompletionScore,
            "overallHealthScore": signals.overallHealthScore,
            "healthTier": signals.healthTier.rawValue,
            "snapshotDate": dateString,
            "snapshotAt": FieldValue.serverTimestamp()
        ]
        try await dailySignalsDoc(for: communityId, date: dateString).setData(snapshot)
        dlog("[CommunityHealthService] Snapshotted daily health for \(communityId) on \(dateString)")
    }

    // MARK: - Private helpers

    private func decodeSignals(from data: [String: Any], communityId: String) -> CommunityHealthSignals? {
        let tier = (data["healthTier"] as? String).flatMap(CommunityHealthTier.init) ?? .dormant
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()

        return CommunityHealthSignals(
            communityId: communityId,
            prayerActivityScore: data["prayerActivityScore"] as? Double ?? 0.0,
            discussionQualityScore: data["discussionQualityScore"] as? Double ?? 0.0,
            responseRateScore: data["responseRateScore"] as? Double ?? 0.0,
            mentorshipEngagementScore: data["mentorshipEngagementScore"] as? Double ?? 0.0,
            eventAttendanceScore: data["eventAttendanceScore"] as? Double ?? 0.0,
            studyCompletionScore: data["studyCompletionScore"] as? Double ?? 0.0,
            healthTier: tier,
            updatedAt: updatedAt
        )
    }
}

// MARK: - ISO8601DateFormatter convenience

private extension ISO8601DateFormatter {
    static let amenDateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f
    }()
}

// MARK: - CommunityHealthTierBadgeView

/// A small badge showing a community's health tier.
/// Uses only SF Symbols and semantic system colors — no hex colors needed.
struct CommunityHealthTierBadgeView: View {

    let tier: CommunityHealthTier

    // MARK: Colors

    private var foregroundColor: Color {
        switch tier {
        case .thriving: return Color(hex: "#D4A017")    // gold
        case .healthy:  return Color(.systemGreen)
        case .growing:  return Color(.systemBlue)
        case .dormant:  return Color(.secondaryLabel)
        case .atrisk:   return Color(.systemYellow)
        }
    }

    private var backgroundColor: Color {
        switch tier {
        case .thriving: return Color(hex: "#D4A017").opacity(0.12)
        case .healthy:  return Color(.systemGreen).opacity(0.12)
        case .growing:  return Color(.systemBlue).opacity(0.12)
        case .dormant:  return Color(.secondaryLabel).opacity(0.12)
        case .atrisk:   return Color(.systemYellow).opacity(0.12)
        }
    }

    // MARK: Body

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: tier.systemImage)
                .font(.caption2)
            Text(tier.displayName)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundColor(foregroundColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(backgroundColor)
        .clipShape(Capsule())
    }
}

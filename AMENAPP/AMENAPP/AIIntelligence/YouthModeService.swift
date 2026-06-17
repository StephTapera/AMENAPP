// YouthModeService.swift
// AMEN — Youth Mode Service
//
// Activates and enforces youth mode for under-18 accounts.
// Enforces at the function layer; Firestore rules also enforce independently.
//
// DESIGN INVARIANTS:
//   - Guardian summary: categories only, NEVER message content or note text.
//   - DM block is silent from sender's perspective — sender sees nothing unusual.
//   - Feed pacing: breathing room card every 3-5 items (mild randomization).
//
// Flag gate: AMENFeatureFlags.shared.youthMode

import SwiftUI
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

// MARK: - Guardian Summary

struct GuardianSummary: Codable {
    /// High-level category names only — e.g. ["Scripture study", "Prayer", "Community"].
    /// NEVER contains message content, prayer request text, or note content.
    var categories: [String]
    /// Aggregate weekly session count only — no content details.
    var weeklySessionCount: Int
}

// MARK: - Youth Mode Service

@MainActor
final class YouthModeService: ObservableObject {

    static let shared = YouthModeService()

    @Published private(set) var isActive: Bool = false
    @Published private(set) var profile: YouthModeProfile?

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    private var breathingRoomInterval: Int = Int.random(in: 3...5)

    private init() {}

    // MARK: - Activate

    func activate(for uid: String, birthYear: Int) async throws {
        guard AMENFeatureFlags.shared.youthMode else { return }

        let profile = YouthModeProfile(
            uid: uid,
            feedPacing: .slow,
            dmPolicy: .verifiedAdultsBlocked,
            bereanToneKey: "gentle",
            guardianVisibility: .categoriesOnly
        )

        let data: [String: Any] = [
            "uid": profile.uid,
            "feedPacing": profile.feedPacing.rawValue,
            "dmPolicy": profile.dmPolicy.rawValue,
            "bereanToneKey": profile.bereanToneKey,
            "guardianVisibility": profile.guardianVisibility.rawValue,
            "activatedAt": FieldValue.serverTimestamp()
        ]

        try await db
            .collection("youthModeProfiles")
            .document(uid)
            .setData(data, merge: true)

        self.profile = profile
        self.isActive = true
    }

    // MARK: - Feed Pacing

    func shouldInsertBreathingRoom(afterItemIndex: Int) -> Bool {
        guard AMENFeatureFlags.shared.youthMode, isActive else { return false }

        let oneBased = afterItemIndex + 1
        if oneBased % breathingRoomInterval == 0 {
            breathingRoomInterval = Int.random(in: 3...5)
            return true
        }
        return false
    }

    // MARK: - DM Policy

    func dmAllowed(senderUid: String, recipientUid: String) async -> Bool {
        guard AMENFeatureFlags.shared.youthMode else { return true }

        do {
            let doc = try await db
                .collection("youthModeProfiles")
                .document(recipientUid)
                .getDocument()

            guard doc.exists else { return false }

            let policyRaw = doc.data()?["dmPolicy"] as? String ?? ""
            guard policyRaw == DMPolicy.verifiedAdultsBlocked.rawValue else { return true }

            let senderDoc = try await db
                .collection("users")
                .document(senderUid)
                .getDocument()

            let senderAgeVerified = senderDoc.data()?["ageVerified"] as? Bool ?? false
            if !senderAgeVerified {
                return false
            }

            return true
        } catch {
            dlog("[YouthModeService] dmAllowed check failed: \(error) — defaulting to allow")
            return true
        }
    }

    // MARK: - Guardian Summary

    func guardianSummary(for uid: String) async throws -> GuardianSummary {
        guard AMENFeatureFlags.shared.youthMode else {
            return GuardianSummary(categories: [], weeklySessionCount: 0)
        }

        let callable = functions.httpsCallable("getYouthGuardianSummary")
        let result = try await callable.call(["uid": uid])

        guard let data = result.data as? [String: Any] else {
            return GuardianSummary(categories: [], weeklySessionCount: 0)
        }

        let categories = data["categories"] as? [String] ?? []
        let weeklySessionCount = data["weeklySessionCount"] as? Int ?? 0

        return GuardianSummary(
            categories: categories,
            weeklySessionCount: weeklySessionCount
        )
    }
}

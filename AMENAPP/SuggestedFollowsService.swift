//
//  SuggestedFollowsService.swift
//  AMENAPP
//
//  Smart multi-signal ranking for "Find People to Follow".
//
//  Score formula:
//    (churchMatch   × 40) +
//    (mutualFollows × 30) +   (≤ 30 pts; 10 pts per mutual, capped at 3)
//    (sameCity      × 15) +
//    (translationMatch × 10) +
//    (recentlyJoined   × 5)
//
//  Architecture:
//    - Single async entry point: `fetchSuggestions()`
//    - Parallel TaskGroup fetches church, city, translation, and recency candidates
//    - Mutual-follow counts computed from current user's following list (in-memory)
//    - Results filtered (self / already-following / blocked / restricted)
//    - Returns [SuggestedUser] capped at 20, sorted desc by score
//    - Cache TTL: 30 min; reads from Firestore cache first (default SDK behaviour)
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Score Weights (file-private, nonisolated constant namespace)

private enum SuggestedFollowsWeight {
    static let church: Int       = 40
    static let mutualPerHit: Int = 10  // 10 per mutual, max 3 → max 30
    static let city: Int         = 15
    static let translation: Int  = 10
    static let recentlyJoined: Int = 5
}

// MARK: - SuggestedUser

/// A ranked suggestion surfaced in the "Find People to Follow" sheet.
struct SuggestedUser: Identifiable {
    let id: String          // userId
    let displayName: String
    let username: String
    let profileImageURL: String?
    let score: Int          // 0-100
    let reason: String      // Human-readable primary reason
    let secondaryReasons: [String]  // Up to 2 additional pills
    let mutualCount: Int
    /// true when the target account requires a follow request
    var isPrivate: Bool = false
}

// MARK: - SuggestedFollowsService

@MainActor
final class SuggestedFollowsService {

    static let shared = SuggestedFollowsService()
    private init() {}

    private lazy var db = Firestore.firestore()

    // Cache
    private var cachedResults: [SuggestedUser] = []
    private var lastFetchDate: Date?
    private let cacheTTL: TimeInterval = 30 * 60  // 30 minutes

    // MARK: - Public API

    /// Fetch ranked suggestions. Returns cached results if within TTL.
    func fetchSuggestions(forceRefresh: Bool = false) async -> [SuggestedUser] {
        if !forceRefresh,
           let last = lastFetchDate,
           Date().timeIntervalSince(last) < cacheTTL,
           !cachedResults.isEmpty {
            return cachedResults
        }

        guard let uid = Auth.auth().currentUser?.uid else { return [] }

        let results = await buildCandidates(currentUID: uid)
        cachedResults = results
        lastFetchDate = Date()
        return results
    }

    /// Invalidate cache (e.g. after follow/dismiss).
    func invalidateCache() {
        cachedResults = []
        lastFetchDate = nil
    }

    // MARK: - Build candidates

    private func buildCandidates(currentUID: String) async -> [SuggestedUser] {
        // Load exclusion sets up-front (all in-memory already)
        let alreadyFollowing = FollowService.shared.following
        let blocked          = BlockService.shared.blockedUsers
        let restricted       = RestrictService.shared.restrictedUserIds

        func isExcluded(_ uid: String) -> Bool {
            uid == currentUID ||
            alreadyFollowing.contains(uid) ||
            blocked.contains(uid) ||
            restricted.contains(uid)
        }

        // --- Fetch current user profile ---
        guard let currentProfile = await fetchCurrentUserProfile(uid: currentUID) else {
            return []
        }

        // Capture Firestore reference and recency cutoff before entering task groups
        // (both are @MainActor-isolated; capturing as a local constant makes them
        //  safe to use inside nonisolated addTask closures via sendable reference).
        let firestoreDB = self.db
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()

        // --- Fetch current user's following list for mutual computation ---
        let followingIDs: Set<String>
        do {
            let snap = try await firestoreDB.collection("users").document(currentUID)
                .collection("following")
                .getDocuments(source: .default)
            followingIDs = Set(snap.documents.map { $0.documentID })
        } catch {
            dlog("SuggestedFollowsService: following fetch failed: \(error.localizedDescription)")
            followingIDs = alreadyFollowing  // fall back to in-memory set
        }

        // --- Parallel candidate gathering ---
        // We aggregate raw candidates (uid → partial score) from each signal source,
        // then resolve profiles and compute final scores in a second pass.

        var rawMap: [String: (churchPts: Int, cityPts: Int, translationPts: Int, recentPts: Int)] = [:]

        func merge(_ uid: String, churchPts: Int = 0, cityPts: Int = 0,
                   translationPts: Int = 0, recentPts: Int = 0) {
            var e = rawMap[uid] ?? (0, 0, 0, 0)
            e.churchPts      = max(e.churchPts, churchPts)
            e.cityPts        = max(e.cityPts, cityPts)
            e.translationPts = max(e.translationPts, translationPts)
            e.recentPts      = max(e.recentPts, recentPts)
            rawMap[uid] = e
        }

        // Capture weight constants as local lets so they're plain value-type captures
        // (avoids referencing the nonisolated enum from an isolated context warning).
        let wChurch      = SuggestedFollowsWeight.church
        let wCity        = SuggestedFollowsWeight.city
        let wTranslation = SuggestedFollowsWeight.translation
        let wRecent      = SuggestedFollowsWeight.recentlyJoined

        await withTaskGroup(of: [(String, Int, Int, Int, Int)].self) { group in

            // Signal 1: Church match (40 pts)
            if let churchId = currentProfile.churchId, !churchId.isEmpty {
                group.addTask {
                    do {
                        let snap = try await firestoreDB.collection("users")
                            .whereField("churchId", isEqualTo: churchId)
                            .limit(to: 60)
                            .getDocuments(source: .default)
                        return snap.documents.map { ($0.documentID, wChurch, 0, 0, 0) }
                    } catch {
                        dlog("SuggestedFollowsService: church query failed: \(error.localizedDescription)")
                        return []
                    }
                }
            }

            // Signal 3: City match (15 pts)
            if let city = currentProfile.city, !city.isEmpty {
                group.addTask {
                    do {
                        let snap = try await firestoreDB.collection("users")
                            .whereField("city", isEqualTo: city)
                            .limit(to: 60)
                            .getDocuments(source: .default)
                        return snap.documents.map { ($0.documentID, 0, wCity, 0, 0) }
                    } catch {
                        dlog("SuggestedFollowsService: city query failed: \(error.localizedDescription)")
                        return []
                    }
                }
            }

            // Signal 4: Scripture translation match (10 pts)
            if let translation = currentProfile.preferredTranslation, !translation.isEmpty {
                group.addTask {
                    do {
                        let snap = try await firestoreDB.collection("users")
                            .whereField("preferredTranslation", isEqualTo: translation)
                            .limit(to: 60)
                            .getDocuments(source: .default)
                        return snap.documents.map { ($0.documentID, 0, 0, wTranslation, 0) }
                    } catch {
                        dlog("SuggestedFollowsService: translation query failed: \(error.localizedDescription)")
                        return []
                    }
                }
            }

            // Signal 5: Recently joined (5 pts)
            group.addTask {
                do {
                    let snap = try await firestoreDB.collection("users")
                        .whereField("createdAt", isGreaterThanOrEqualTo: Timestamp(date: recentCutoff))
                        .order(by: "createdAt", descending: true)
                        .limit(to: 60)
                        .getDocuments(source: .default)
                    return snap.documents.map { ($0.documentID, 0, 0, 0, wRecent) }
                } catch {
                    dlog("SuggestedFollowsService: recency query failed: \(error.localizedDescription)")
                    return []
                }
            }

            for await batch in group {
                for (uid, church, city, translation, recent) in batch {
                    guard !isExcluded(uid) else { continue }
                    merge(uid, churchPts: church, cityPts: city,
                          translationPts: translation, recentPts: recent)
                }
            }
        }

        // --- Signal 2: Mutual follows (up to 30 pts) ---
        // For each candidate already discovered, count how many of the current
        // user's following list also follows them.
        var mutualCounts: [String: Int] = [:]
        await withTaskGroup(of: (String, Int).self) { group in
            for candidateUID in rawMap.keys.prefix(80) {
                group.addTask {
                    var count = 0
                    for followerID in followingIDs.prefix(30) {
                        let docRef = firestoreDB.collection("users")
                            .document(followerID)
                            .collection("following")
                            .document(candidateUID)
                        if let snap = try? await docRef.getDocument(source: .default), snap.exists {
                            count += 1
                        }
                    }
                    return (candidateUID, count)
                }
            }
            for await (uid, count) in group {
                if count > 0 { mutualCounts[uid] = count }
            }
        }

        // --- Build final scored list ---
        let wMutualPerHit = SuggestedFollowsWeight.mutualPerHit

        var scoredCandidates: [(uid: String, score: Int,
                                churchPts: Int, cityPts: Int,
                                translationPts: Int, recentPts: Int,
                                mutualCount: Int)] = []

        for (uid, raw) in rawMap {
            let mutuals = mutualCounts[uid] ?? 0
            let mutualPts = min(mutuals, 3) * wMutualPerHit   // cap at 30
            let total = raw.churchPts + mutualPts + raw.cityPts + raw.translationPts + raw.recentPts
            scoredCandidates.append((uid, total, raw.churchPts, raw.cityPts,
                                     raw.translationPts, raw.recentPts, mutuals))
        }

        scoredCandidates.sort { $0.score > $1.score }

        // --- Resolve profiles for top 30 candidates ---
        var results: [SuggestedUser] = []

        for entry in scoredCandidates.prefix(30) {
            guard !isExcluded(entry.uid) else { continue }

            do {
                let doc = try await firestoreDB.collection("users")
                    .document(entry.uid)
                    .getDocument(source: .default)
                guard doc.exists, let data = doc.data() else { continue }

                let displayName = data["displayName"] as? String
                    ?? data["username"] as? String
                    ?? "AMEN Member"
                let username = data["username"] as? String ?? ""
                let photo = data["profileImageURL"] as? String
                    ?? data["photoURL"] as? String
                let isPrivate = data["isPrivate"] as? Bool ?? false

                let (primaryReason, secondaryReasons) = buildReasons(
                    churchPts:      entry.churchPts,
                    mutualCount:    entry.mutualCount,
                    cityPts:        entry.cityPts,
                    translationPts: entry.translationPts,
                    recentPts:      entry.recentPts,
                    currentProfile: currentProfile
                )

                results.append(SuggestedUser(
                    id: entry.uid,
                    displayName: displayName,
                    username: username,
                    profileImageURL: photo,
                    score: min(entry.score, 100),
                    reason: primaryReason,
                    secondaryReasons: secondaryReasons,
                    mutualCount: entry.mutualCount,
                    isPrivate: isPrivate
                ))

                if results.count >= 20 { break }
            } catch {
                continue
            }
        }

        return results
    }

    // MARK: - Reason Generation

    private func buildReasons(
        churchPts: Int,
        mutualCount: Int,
        cityPts: Int,
        translationPts: Int,
        recentPts: Int,
        currentProfile: CurrentUserProfile
    ) -> (primary: String, secondary: [String]) {

        var reasons: [(pts: Int, text: String)] = []

        if churchPts > 0 {
            reasons.append((pts: churchPts, text: "Goes to your church"))
        }
        if mutualCount > 0 {
            let label = mutualCount == 1
                ? "Followed by 1 person you follow"
                : "Followed by \(mutualCount) people you follow"
            reasons.append((pts: min(mutualCount, 3) * SuggestedFollowsWeight.mutualPerHit, text: label))
        }
        if cityPts > 0, let city = currentProfile.city, !city.isEmpty {
            reasons.append((pts: cityPts, text: "Also in \(city)"))
        }
        if translationPts > 0, let t = currentProfile.preferredTranslation {
            reasons.append((pts: translationPts, text: "Reads the \(t) like you"))
        }
        if recentPts > 0 {
            reasons.append((pts: recentPts, text: "New to AMEN"))
        }

        // Sort by strength descending
        reasons.sort { $0.pts > $1.pts }

        let primary = reasons.first?.text ?? "Suggested for you"
        let secondary = reasons.dropFirst().prefix(2).map { $0.text }

        return (primary, Array(secondary))
    }

    // MARK: - Current User Profile

    private struct CurrentUserProfile {
        let uid: String
        let churchId: String?
        let city: String?
        let preferredTranslation: String?
    }

    private func fetchCurrentUserProfile(uid: String) async -> CurrentUserProfile? {
        do {
            // Load user doc and bereanPreferences in parallel
            async let userDocTask = db.collection("users").document(uid)
                .getDocument(source: .default)
            async let bereanDocTask = db.collection("bereanPreferences").document(uid)
                .getDocument(source: .default)

            let (userDoc, bereanDoc) = try await (userDocTask, bereanDocTask)

            guard userDoc.exists else { return nil }

            let userData = userDoc.data() ?? [:]
            let bereanData = bereanDoc.data() ?? [:]

            // preferredTranslation: check user doc first, then bereanPreferences
            let translation = userData["preferredTranslation"] as? String
                ?? bereanData["preferredTranslation"] as? String

            return CurrentUserProfile(
                uid: uid,
                churchId: userData["churchId"] as? String,
                city: userData["city"] as? String,
                preferredTranslation: translation
            )
        } catch {
            dlog("SuggestedFollowsService: current user profile fetch failed: \(error.localizedDescription)")
            return nil
        }
    }
}

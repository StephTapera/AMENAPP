// SuggestedRailService.swift
// AMENAPP
//
// Recommendation pipeline for the Suggested Accounts rail.
// Refactored from SuggestionsService in SuggestedForYouModule.swift.
// Adds surface parameter, Cloud Function call path, local fallback,
// and per-surface cache with 15-minute TTL.

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class SuggestedRailService {
    static let shared = SuggestedRailService()
    private lazy var db = Firestore.firestore()
    private lazy var functions = Functions.functions()

    // Per-surface cache: surface → (items, fetchDate)
    private var cache: [SuggestionSurface: (items: [SuggestionItem], date: Date)] = [:]
    private let cacheTTL: TimeInterval = 15 * 60 // 15 minutes

    // Current user's profile data for reason matching
    private var currentUserInterests: [String] = []
    private var currentUserPrayerTopics: [String] = []
    private var currentUserProfileFetched: Bool = false

    // MARK: - Public API

    /// Fetch suggestions for a given surface. Tries server ranking first,
    /// falls back to the local 3-phase pipeline on failure.
    func fetchSuggestions(surface: SuggestionSurface, limit: Int = 15) async -> [SuggestionItem] {
        // Check cache
        if let cached = cache[surface],
           Date().timeIntervalSince(cached.date) < cacheTTL {
            return cached.items
        }

        // Try server-side ranking if feature flag enabled
        if AMENFeatureFlags.shared.suggestedRailServerRankingEnabled {
            if let serverItems = await fetchFromServer(surface: surface, limit: limit) {
                cache[surface] = (serverItems, Date())
                return serverItems
            }
        }

        // Fallback to local pipeline
        let localItems = await fetchLocal(surface: surface, limit: limit)
        cache[surface] = (localItems, Date())
        return localItems
    }

    /// Invalidate cache for a specific surface (e.g. after a hide/dismiss).
    func invalidateCache(for surface: SuggestionSurface) {
        cache.removeValue(forKey: surface)
    }

    /// Invalidate all caches.
    func invalidateAllCaches() {
        cache.removeAll()
        currentUserProfileFetched = false
    }

    // MARK: - Server-Side Fetch

    private func fetchFromServer(surface: SuggestionSurface, limit: Int) async -> [SuggestionItem]? {
        guard Auth.auth().currentUser != nil else { return nil }

        do {
            let result = try await functions.httpsCallable("getSuggestedAccountsRail").call([
                "surface": surface.rawValue,
                "limit": limit
            ])

            guard let data = result.data as? [[String: Any]] else { return nil }

            return data.compactMap { dict -> SuggestionItem? in
                guard let id = dict["id"] as? String,
                      let displayName = dict["displayName"] as? String,
                      let handle = dict["handle"] as? String else { return nil }

                return SuggestionItem(
                    id: id,
                    displayName: displayName,
                    handle: handle,
                    avatarURL: dict["avatarURL"] as? String,
                    isVerified: dict["isVerified"] as? Bool ?? false,
                    isPrivate: dict["isPrivate"] as? Bool ?? false,
                    accountType: SuggestionAccountType(rawValue: dict["accountType"] as? String ?? "personal") ?? .personal,
                    reasonType: SuggestionReasonType(rawValue: dict["reasonType"] as? String ?? "generic") ?? .generic,
                    reasonText: dict["reasonText"] as? String ?? "Suggested for you",
                    mutualCount: dict["mutualCount"] as? Int ?? 0,
                    mutualNames: dict["mutualNames"] as? [String] ?? [],
                    mutualAvatarURLs: dict["mutualAvatarURLs"] as? [String] ?? [],
                    score: dict["score"] as? Double ?? 0,
                    contextLine: dict["contextLine"] as? String,
                    bio: dict["bio"] as? String,
                    prayerThemes: dict["prayerThemes"] as? [String] ?? [],
                    recentTestimonyExcerpt: dict["recentTestimonyExcerpt"] as? String,
                    followerCount: dict["followerCount"] as? Int ?? 0,
                    postCount: dict["postCount"] as? Int ?? 0,
                    sharedTopics: dict["sharedTopics"] as? [String] ?? []
                )
            }
        } catch {
            dlog("⚠️ SuggestedRail: server fetch failed, falling back to local: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Current User Profile

    /// Fetches the current user's interests and prayer topics for reason matching.
    private func ensureCurrentUserProfile() async {
        guard !currentUserProfileFetched,
              let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            let data = doc.data() ?? [:]
            currentUserInterests = (data["interests"] as? [String] ?? []).map { $0.lowercased() }
            currentUserPrayerTopics = (data["prayerTopics"] as? [String] ?? []).map { $0.lowercased() }
            currentUserProfileFetched = true
        } catch {
            dlog("⚠️ SuggestedRail: failed to fetch current user profile: \(error.localizedDescription)")
        }
    }

    // MARK: - Local Pipeline (existing 3-phase logic)

    private func fetchLocal(surface: SuggestionSurface, limit: Int) async -> [SuggestionItem] {
        guard let currentUID = Auth.auth().currentUser?.uid else { return [] }

        // Ensure we have the current user's interests for reason matching
        await ensureCurrentUserProfile()

        let alreadyFollowing = FollowService.shared.following
        let blocked = BlockService.shared.blockedUsers
        let dismissed = SuggestedRailViewModel.loadDismissed()
        let muted = ModerationService.shared.mutedUsers
        let restricted = RestrictService.shared.restrictedUserIds

        // Phase 1: Gather candidates from mutual graph
        var candidates: [String: SuggestionCandidate] = [:]

        do {
            let followingSnap = try await db.collection("users")
                .document(currentUID)
                .collection("following")
                .limit(to: 30)
                .getDocuments()

            let followingIds = followingSnap.documents.map(\.documentID)

            for friendId in followingIds.prefix(20) {
                let friendFollowingSnap = try await db.collection("users")
                    .document(friendId)
                    .collection("following")
                    .limit(to: 30)
                    .getDocuments()

                let friendName = try? await db.collection("users").document(friendId).getDocument()
                    .data()?["displayName"] as? String

                for doc in friendFollowingSnap.documents {
                    let candidateId = doc.documentID
                    guard candidateId != currentUID,
                          !alreadyFollowing.contains(candidateId),
                          !blocked.contains(candidateId),
                          !dismissed.contains(candidateId),
                          !muted.contains(candidateId),
                          !restricted.contains(candidateId)
                    else { continue }

                    if candidates[candidateId] == nil {
                        candidates[candidateId] = SuggestionCandidate(id: candidateId)
                    }
                    candidates[candidateId]?.mutualFollowerIds.insert(friendId)
                    if let name = friendName {
                        candidates[candidateId]?.mutualFollowerNames.append(name)
                    }
                }
            }
        } catch {
            dlog("⚠️ SuggestedRail: mutual graph fetch failed: \(error.localizedDescription)")
        }

        // Phase 2: Fill remaining slots from popular accounts
        if candidates.count < limit * 2 {
            do {
                let popularSnap = try await db.collection("users")
                    .order(by: "followersCount", descending: true)
                    .limit(to: limit * 3)
                    .getDocuments()

                for doc in popularSnap.documents {
                    let uid = doc.documentID
                    guard uid != currentUID,
                          !alreadyFollowing.contains(uid),
                          !blocked.contains(uid),
                          !dismissed.contains(uid),
                          !muted.contains(uid),
                          !restricted.contains(uid),
                          candidates[uid] == nil
                    else { continue }

                    let d = doc.data()
                    var c = SuggestionCandidate(id: uid)
                    c.followersCount = d["followersCount"] as? Int ?? 0
                    c.prefetchedData = d
                    candidates[uid] = c
                }
            } catch {
                dlog("⚠️ SuggestedRail: popular fetch failed: \(error.localizedDescription)")
            }
        }

        // Phase 3: Fetch profiles, build items, score & rank
        var items: [SuggestionItem] = []
        let sortedCandidates = candidates.values.sorted { $0.score > $1.score }

        for candidate in sortedCandidates.prefix(limit * 2) {
            do {
                let data: [String: Any]
                if let prefetched = candidate.prefetchedData {
                    data = prefetched
                } else {
                    let doc = try await db.collection("users").document(candidate.id).getDocument()
                    guard doc.exists else { continue }
                    data = doc.data() ?? [:]
                }

                let displayName = data["displayName"] as? String ?? data["username"] as? String
                guard let name = displayName, !name.isEmpty else { continue }

                let handle = data["username"] as? String ?? candidate.id
                let avatar = data["profileImageURL"] as? String ?? data["photoURL"] as? String
                let verified = data["isVerified"] as? Bool ?? false
                let isPrivate = data["isPrivate"] as? Bool ?? false
                let followersCount = data["followersCount"] as? Int ?? candidate.followersCount
                let accountTypeRaw = data["accountType"] as? String ?? "personal"
                let accountType = SuggestionAccountType(rawValue: accountTypeRaw) ?? .personal

                let mutualCount = candidate.mutualFollowerIds.count
                let uniqueNames = Array(Set(candidate.mutualFollowerNames)).prefix(2)

                let bio = data["bio"] as? String
                let prayerThemes = data["prayerTopics"] as? [String] ?? []
                let postCount = data["postsCount"] as? Int ?? 0
                let sharedTopics = data["interests"] as? [String] ?? []

                let (reasonType, reasonText, contextLine) = buildReason(
                    mutualCount: mutualCount,
                    mutualNames: Array(uniqueNames),
                    accountType: accountType,
                    followersCount: followersCount,
                    isVerified: verified,
                    surface: surface,
                    candidateInterests: sharedTopics.map { $0.lowercased() },
                    candidatePrayerTopics: prayerThemes.map { $0.lowercased() }
                )

                var mutualAvatarURLs: [String] = []
                for mutualId in candidate.mutualFollowerIds.prefix(3) {
                    if let mutDoc = try? await db.collection("users").document(mutualId).getDocument(),
                       let url = mutDoc.data()?["profileImageURL"] as? String ?? mutDoc.data()?["photoURL"] as? String {
                        mutualAvatarURLs.append(url)
                    }
                }

                let finalScore = computeScore(
                    mutualCount: mutualCount,
                    followersCount: followersCount,
                    isVerified: verified,
                    accountType: accountType,
                    surface: surface
                )

                items.append(SuggestionItem(
                    id: candidate.id,
                    displayName: name,
                    handle: handle,
                    avatarURL: avatar,
                    isVerified: verified,
                    isPrivate: isPrivate,
                    accountType: accountType,
                    reasonType: reasonType,
                    reasonText: reasonText,
                    mutualCount: mutualCount,
                    mutualNames: Array(uniqueNames).map { String($0) },
                    mutualAvatarURLs: mutualAvatarURLs,
                    score: finalScore,
                    contextLine: contextLine,
                    bio: bio,
                    prayerThemes: prayerThemes,
                    followerCount: followersCount,
                    postCount: postCount,
                    sharedTopics: sharedTopics
                ))

                if items.count >= limit { break }
            } catch {
                continue
            }
        }

        // Apply fatigue multiplier to scores
        items = items.map { item in
            let multiplier = SuggestedRailViewModel.fatigueMultiplier(for: item.id)
            guard multiplier < 1.0 else { return item }
            return SuggestionItem(
                id: item.id,
                displayName: item.displayName,
                handle: item.handle,
                avatarURL: item.avatarURL,
                isVerified: item.isVerified,
                isPrivate: item.isPrivate,
                accountType: item.accountType,
                reasonType: item.reasonType,
                reasonText: item.reasonText,
                mutualCount: item.mutualCount,
                mutualNames: item.mutualNames,
                mutualAvatarURLs: item.mutualAvatarURLs,
                score: item.score * multiplier,
                contextLine: item.contextLine,
                bio: item.bio,
                prayerThemes: item.prayerThemes,
                recentTestimonyExcerpt: item.recentTestimonyExcerpt,
                followerCount: item.followerCount,
                postCount: item.postCount,
                sharedTopics: item.sharedTopics
            )
        }.filter { !SuggestedRailViewModel.isFatigued(userId: $0.id) }

        items.sort { $0.score > $1.score }

        // Diversity pass: max 2 of same accountType, ensure at least 1 mutual-based if available
        items = applyDiversityRules(to: items)

        return items
    }

    /// Ensures diversity in the suggestion list.
    private func applyDiversityRules(to items: [SuggestionItem]) -> [SuggestionItem] {
        var result: [SuggestionItem] = []
        var typeCount: [SuggestionAccountType: Int] = [:]
        var hasMutualBased = false
        var overflow: [SuggestionItem] = []

        for item in items {
            let currentCount = typeCount[item.accountType] ?? 0
            if currentCount >= 2 {
                overflow.append(item)
                continue
            }
            typeCount[item.accountType] = currentCount + 1
            if item.reasonType == .mutuals { hasMutualBased = true }
            result.append(item)
        }

        // If we have no mutual-based suggestion, try to swap one in from overflow
        if !hasMutualBased, let mutualItem = overflow.first(where: { $0.reasonType == .mutuals }) {
            result.insert(mutualItem, at: min(1, result.count))
        }

        return result
    }

    // MARK: - Reason Generation

    private func buildReason(
        mutualCount: Int,
        mutualNames: [String],
        accountType: SuggestionAccountType,
        followersCount: Int,
        isVerified: Bool,
        surface: SuggestionSurface,
        candidateInterests: [String] = [],
        candidatePrayerTopics: [String] = []
    ) -> (SuggestionReasonType, String, String?) {
        // Mutual followers — strongest signal across all surfaces
        if mutualCount >= 3 {
            if let firstName = mutualNames.first {
                let othersCount = mutualCount - 1
                return (.mutuals, "Followed by \(firstName) + \(othersCount) others", "Mutuals · community overlap")
            }
            return (.mutuals, "\(mutualCount) people you follow", "Shared connections")
        }
        if mutualCount > 0 {
            if let firstName = mutualNames.first {
                if mutualCount == 1 {
                    return (.mutuals, "Followed by \(firstName)", "Mutual connection")
                }
                return (.mutuals, "Followed by \(firstName) + \(mutualCount - 1) other", "Mutual connections")
            }
            return (.mutuals, "\(mutualCount) mutual follow\(mutualCount == 1 ? "" : "s")", "Shared connections")
        }

        // Topic overlap — data-driven reason from shared interests
        let overlappingInterests = candidateInterests.filter { currentUserInterests.contains($0) }
        if overlappingInterests.count >= 2 {
            let topTwo = overlappingInterests.prefix(2).map { $0.capitalized }
            return (.topicOverlap, "Posts about \(topTwo[0]) and \(topTwo[1])", "Shared interests")
        } else if overlappingInterests.count == 1 {
            return (.topicOverlap, "Posts about \(overlappingInterests[0].capitalized)", "Shared interest")
        }

        // Prayer theme overlap — for prayer surface especially
        if surface == .prayer || !candidatePrayerTopics.isEmpty {
            let overlappingPrayer = candidatePrayerTopics.filter { currentUserPrayerTopics.contains($0) }
            if overlappingPrayer.count >= 2 {
                let topTwo = overlappingPrayer.prefix(2).map { $0.capitalized }
                return (.prayerThemeMatch, "Prays about \(topTwo[0]) and \(topTwo[1])", "Shared prayer heart")
            } else if overlappingPrayer.count == 1 {
                return (.prayerThemeMatch, "Prays about \(overlappingPrayer[0].capitalized)", "Prayer connection")
            }
        }

        // Surface-specific reason flavoring
        switch surface {
        case .prayer:
            if accountType == .church {
                return (.prayerActive, "Prayer community near you", "Faith community")
            }
            return (.prayerActive, "Active in prayer", "Prayer community")

        case .testimonies:
            if accountType == .creator {
                return (.testimonyActive, "Shares powerful testimonies", "Creator · active voice")
            }
            return (.testimonyActive, "Active in testimony", "Story community")

        case .openTable:
            break // Fall through to account-type logic
        }

        // Account type based reasons (OpenTable default)
        switch accountType {
        case .church:
            return (.churchNear, "Church in your community", "Faith community")
        case .creator:
            return (.popularCreator, "Popular faith creator", "Creator · active voice")
        case .ministry:
            return (.communityOverlap, "Active ministry", "Community")
        case .business:
            return (.communityOverlap, "Faith-based business", nil)
        case .official:
            return (.popularInAMEN, "Official AMEN account", nil)
        case .personal:
            if isVerified {
                return (.popularInAMEN, "Trusted voice in AMEN", "Verified account")
            }
            if followersCount > 5_000 {
                return (.popularInAMEN, "Popular in AMEN", "Active community member")
            }
            if followersCount > 500 {
                return (.communityOverlap, "Active in the community", nil)
            }
            return (.generic, "Suggested for you", nil)
        }
    }

    // MARK: - Scoring

    private func computeScore(
        mutualCount: Int,
        followersCount: Int,
        isVerified: Bool,
        accountType: SuggestionAccountType,
        surface: SuggestionSurface
    ) -> Double {
        var score: Double = 0
        // Mutual graph (strongest signal)
        score += Double(mutualCount) * 15.0
        // Popularity (logarithmic)
        score += log2(Double(max(followersCount, 1))) * 2.0
        // Verification bonus
        if isVerified { score += 10.0 }
        // Account type diversity bonus
        switch accountType {
        case .church:   score += 5.0
        case .creator:  score += 4.0
        case .ministry: score += 3.0
        default: break
        }

        // Surface-specific boosting
        switch surface {
        case .prayer:
            if accountType == .church { score += 3.0 }
        case .testimonies:
            if accountType == .creator { score += 3.0 }
        case .openTable:
            break
        }

        return score
    }

    // MARK: - Internal Types

    private struct SuggestionCandidate {
        let id: String
        var mutualFollowerIds: Set<String> = []
        var mutualFollowerNames: [String] = []
        var followersCount: Int = 0
        var prefetchedData: [String: Any]?

        var score: Double {
            Double(mutualFollowerIds.count) * 15.0 + log2(Double(max(followersCount, 1))) * 2.0
        }
    }
}

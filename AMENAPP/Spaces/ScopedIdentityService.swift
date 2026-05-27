// ScopedIdentityService.swift
// AMENAPP — Phase 0: Privacy Boundary Service
//
// THE ONLY sanctioned way to read another user's data inside a Space.
// All agents MUST go through this service — never read /users/{uid} directly
// when constructing a Space-scoped view of another member.
//
// Privacy contract:
//   - A user's global profile (displayName, photoURL) is readable by any
//     signed-in user (existing Firestore rule: /users/{uid} read = isSignedIn()).
//   - A user's SCOPED profile (Space-specific bio, gifts, anonymous flag) is
//     readable only by other members of that same Space.
//   - Private insights (/users/{uid}/privateInsights) are NEVER exposed here.
//     They are owner-read only, written by Cloud Functions.
//   - Cross-space leakage is impossible by design: projections are keyed to
//     a specific spaceId and cannot be composed to reconstruct a global profile.
//
// Architecture:
//   ScopedIdentityService          ← this file (client-side, async/await)
//   ├── verifyMembership()          ← membership check before any projection read
//   ├── projectionFor(userId:spaceId:) ← main entry point
//   ├── batchProjections(userIds:spaceId:) ← for member lists
//   └── updateOwnScopedProfile()   ← owner-only mutation (calls Cloud Function)
//
// Firestore paths read:
//   /spaces/{spaceId}/members/{userId}          ← membership + scopedProfile
//   /users/{userId}                              ← public fields only
//   /spaces/{spaceId}/roles/{roleId}             ← role assignments
//
// Firestore paths NEVER read:
//   /users/{userId}/privateInsights/...
//   /users/{userId}/safety/...
//   /spaces/{otherSpaceId}/members/{userId}      ← cross-space projection blocked

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Projection Result

/// The controlled view of a user within a specific Space.
/// This is what agents display — never a raw /users/{uid} document with cross-space data.
struct AmenScopedIdentityProjection: Identifiable {
    let userId: String
    let spaceId: String

    // From global profile (always available to signed-in users)
    let globalDisplayName: String
    let globalPhotoURL: String?

    // From scoped profile (Space-specific, may be anonymous)
    let effectiveDisplayName: String    // scoped override or global fallback
    let bio: String?
    let visibleGifts: [AmenGiftType]
    let isAnonymous: Bool
    let showsPrayerActivity: Bool
    let showsStudyActivity: Bool

    // Role within this Space
    let roles: [AmenSpaceRoleType]
    let primaryRole: AmenSpaceRoleType  // highest-privilege role
    let joinedAt: Date?
    let membershipStatus: AmenMembershipStatus

    var id: String { "\(spaceId)_\(userId)" }

    /// True when the requester and subject are the same user.
    var isOwnProfile: Bool {
        Auth.auth().currentUser?.uid == userId
    }

    var displayName: String {
        isAnonymous && !isOwnProfile ? "Anonymous Member" : effectiveDisplayName
    }

    var photoURL: String? {
        isAnonymous && !isOwnProfile ? nil : globalPhotoURL
    }

    static func anonymous(userId: String, spaceId: String) -> AmenScopedIdentityProjection {
        AmenScopedIdentityProjection(
            userId: userId,
            spaceId: spaceId,
            globalDisplayName: "Member",
            globalPhotoURL: nil,
            effectiveDisplayName: "Anonymous Member",
            bio: nil,
            visibleGifts: [],
            isAnonymous: true,
            showsPrayerActivity: false,
            showsStudyActivity: false,
            roles: [.member],
            primaryRole: .member,
            joinedAt: nil,
            membershipStatus: .active
        )
    }
}

// MARK: - Error

enum ScopedIdentityError: LocalizedError {
    case notAuthenticated
    case notAMember(spaceId: String)
    case subjectNotAMember(userId: String, spaceId: String)
    case spaceNotFound(spaceId: String)
    case insufficientPermission

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to view member profiles."
        case .notAMember(let spaceId):
            return "You are not a member of this space (\(spaceId))."
        case .subjectNotAMember(let userId, let spaceId):
            return "User \(userId) is not a member of space \(spaceId)."
        case .spaceNotFound(let spaceId):
            return "Space \(spaceId) could not be found."
        case .insufficientPermission:
            return "You do not have permission to perform this action."
        }
    }
}

// MARK: - Service

@MainActor
final class ScopedIdentityService {

    static let shared = ScopedIdentityService()

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    // In-memory cache: keyed by "spaceId_userId", evicted on Space change or logout
    private var cache: [String: AmenScopedIdentityProjection] = [:]
    private var membershipCache: [String: Bool] = [:]   // "spaceId_uid" → isMember

    private init() {}

    // MARK: - Main Entry Point

    /// Returns the scoped identity projection for `userId` inside `spaceId`.
    /// Throws `ScopedIdentityError.notAMember` if the requester is not a member.
    /// Throws `ScopedIdentityError.subjectNotAMember` if the subject is not a member.
    func projectionFor(userId: String, spaceId: String) async throws -> AmenScopedIdentityProjection {
        guard let requesterId = Auth.auth().currentUser?.uid else {
            throw ScopedIdentityError.notAuthenticated
        }

        // 1. Verify requester membership (gate on self first — owner can always view)
        let requesterIsOwn = requesterId == userId
        if !requesterIsOwn {
            guard try await isMember(uid: requesterId, spaceId: spaceId) else {
                throw ScopedIdentityError.notAMember(spaceId: spaceId)
            }
        }

        // 2. Return cached projection if fresh
        let cacheKey = "\(spaceId)_\(userId)"
        if let cached = cache[cacheKey] { return cached }

        // 3. Fetch global public profile
        let globalDoc = try await db.collection("users").document(userId).getDocument()
        guard globalDoc.exists else {
            // User deleted — return anonymous shell
            return .anonymous(userId: userId, spaceId: spaceId)
        }
        let globalData = globalDoc.data() ?? [:]
        let globalDisplayName = globalData["displayName"] as? String ?? "Member"
        let globalPhotoURL    = globalData["photoURL"] as? String

        // 4. Fetch Space membership doc (contains scopedProfile + roles)
        let memberDoc = try await db
            .collection("spaces").document(spaceId)
            .collection("members").document(userId)
            .getDocument()

        guard memberDoc.exists, let memberData = memberDoc.data() else {
            // Subject not in this Space — may still be owner visible in admin context
            throw ScopedIdentityError.subjectNotAMember(userId: userId, spaceId: spaceId)
        }

        // 5. Parse membership fields
        let statusRaw   = memberData["status"] as? String ?? "active"
        let status      = AmenMembershipStatus(rawValue: statusRaw) ?? .active
        let rolesRaw    = memberData["roles"] as? [String] ?? ["member"]
        let roles       = rolesRaw.compactMap { AmenSpaceRoleType(rawValue: $0) }
        let primaryRole = roles.sorted { $0.canManageSpace && !$1.canManageSpace }.first ?? .member
        let joinedAt    = (memberData["joinedAt"] as? Timestamp)?.dateValue()

        // 6. Parse scoped profile (nested map)
        var scopedProfile = AmenScopedProfile.defaultOpen
        if let sp = memberData["scopedProfile"] as? [String: Any] {
            scopedProfile = AmenScopedProfile(
                displayName: sp["displayName"] as? String,
                bio: sp["bio"] as? String,
                visibleGifts: (sp["visibleGifts"] as? [String] ?? []).compactMap { AmenGiftType(rawValue: $0) },
                isAnonymous: sp["isAnonymous"] as? Bool ?? false,
                showsPrayerActivity: sp["showsPrayerActivity"] as? Bool ?? false,
                showsStudyActivity: sp["showsStudyActivity"] as? Bool ?? false,
                joinedAt: joinedAt
            )
        }

        let effectiveName = scopedProfile.displayName ?? globalDisplayName

        let projection = AmenScopedIdentityProjection(
            userId: userId,
            spaceId: spaceId,
            globalDisplayName: globalDisplayName,
            globalPhotoURL: globalPhotoURL,
            effectiveDisplayName: effectiveName,
            bio: scopedProfile.bio,
            visibleGifts: scopedProfile.visibleGifts,
            isAnonymous: scopedProfile.isAnonymous,
            showsPrayerActivity: scopedProfile.showsPrayerActivity,
            showsStudyActivity: scopedProfile.showsStudyActivity,
            roles: roles.isEmpty ? [.member] : roles,
            primaryRole: primaryRole,
            joinedAt: joinedAt,
            membershipStatus: status
        )

        cache[cacheKey] = projection
        return projection
    }

    // MARK: - Batch Projection (member lists)

    /// Fetches projections for multiple users in the same Space.
    /// Skips users who are not members — does not throw for individual misses.
    func batchProjections(userIds: [String], spaceId: String) async throws -> [AmenScopedIdentityProjection] {
        guard let requesterId = Auth.auth().currentUser?.uid else {
            throw ScopedIdentityError.notAuthenticated
        }
        guard try await isMember(uid: requesterId, spaceId: spaceId) else {
            throw ScopedIdentityError.notAMember(spaceId: spaceId)
        }

        return await withTaskGroup(of: AmenScopedIdentityProjection?.self) { group in
            for uid in userIds {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    return try? await self.projectionFor(userId: uid, spaceId: spaceId)
                }
            }
            var results: [AmenScopedIdentityProjection] = []
            for await projection in group {
                if let p = projection { results.append(p) }
            }
            return results
        }
    }

    // MARK: - Own Scoped Profile Update

    /// Updates the caller's own scoped profile for a Space.
    /// Routes through the updateScopedProfile Cloud Function — never writes directly.
    func updateOwnScopedProfile(_ profile: AmenScopedProfile, spaceId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw ScopedIdentityError.notAuthenticated
        }
        guard try await isMember(uid: uid, spaceId: spaceId) else {
            throw ScopedIdentityError.notAMember(spaceId: spaceId)
        }

        let payload: [String: Any] = [
            "spaceId": spaceId,
            "scopedProfile": [
                "displayName":        profile.displayName as Any,
                "bio":                profile.bio as Any,
                "visibleGifts":       profile.visibleGifts.map(\.rawValue),
                "isAnonymous":        profile.isAnonymous,
                "showsPrayerActivity": profile.showsPrayerActivity,
                "showsStudyActivity":  profile.showsStudyActivity
            ]
        ]

        _ = try await functions
            .httpsCallable(SpacesCallable.updateScopedProfile.rawValue)
            .call(payload)

        // Invalidate cache so next read reflects new profile
        cache.removeValue(forKey: "\(spaceId)_\(uid)")
    }

    // MARK: - Membership Check

    /// Returns true if `uid` is an active member of `spaceId`.
    /// Results are cached per session; invalidated on Space leave/suspend.
    func isMember(uid: String, spaceId: String) async throws -> Bool {
        let key = "\(spaceId)_\(uid)"
        if let cached = membershipCache[key] { return cached }

        let doc = try await db
            .collection("spaces").document(spaceId)
            .collection("members").document(uid)
            .getDocument()

        let result = doc.exists &&
            (doc.data()?["status"] as? String).map { AmenMembershipStatus(rawValue: $0) == .active } == true

        membershipCache[key] = result
        return result
    }

    // MARK: - Cache Management

    func invalidateCache(spaceId: String) {
        let prefix = "\(spaceId)_"
        cache = cache.filter { !$0.key.hasPrefix(prefix) }
        membershipCache = membershipCache.filter { !$0.key.hasPrefix(prefix) }
    }

    func clearAllCaches() {
        cache.removeAll()
        membershipCache.removeAll()
    }
}

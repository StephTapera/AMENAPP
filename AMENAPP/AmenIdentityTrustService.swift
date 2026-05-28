//
//  AmenIdentityTrustService.swift
//  AMENAPP
//
//  Fetches and caches identity trust profiles.
//  Exposes trust level, unverified claims, and impersonation flags.
//  Feeds VerifiedIdentityBadge and TrustDetailsSheet UI components.
//

import Foundation
import SwiftUI
import FirebaseFunctions

@MainActor
final class AmenIdentityTrustService: ObservableObject {

    static let shared = AmenIdentityTrustService()

    private let functions = Functions.functions()
    private let flags = AmenSafetyFeatureFlags.shared

    // Simple LRU-style cache
    private var profileCache: [String: (profile: IdentityTrustProfile, fetchedAt: Date)] = [:]
    private let cacheMaxAge: TimeInterval = 300  // 5 minutes

    private init() {}

    // MARK: - Fetch trust profile

    func trustProfile(for uid: String) async -> IdentityTrustProfile? {
        // Cache hit
        if let cached = profileCache[uid],
           Date().timeIntervalSince(cached.fetchedAt) < cacheMaxAge {
            return cached.profile
        }

        do {
            let result = try await functions
                .httpsCallable("getIdentityTrustProfile")
                .call(["uid": uid])
            guard let data = result.data as? [String: Any] else { return nil }
            let profile = parseProfile(data, uid: uid)
            profileCache[uid] = (profile, Date())
            return profile
        } catch {
            return nil
        }
    }

    // MARK: - Convenience

    func trustLevel(for uid: String) async -> IdentityTrustLevel {
        await trustProfile(for: uid)?.trustLevel ?? .basic
    }

    func hasUnverifiedClaims(for uid: String) async -> [String] {
        await trustProfile(for: uid)?.unverifiedClaims ?? []
    }

    func isSuspectedImpersonation(_ uid: String) async -> Bool {
        await trustProfile(for: uid)?.isSuspectedImpersonation ?? false
    }

    // MARK: - Report impersonation

    func reportImpersonation(targetUid: String, reason: String) async {
        _ = try? await functions.httpsCallable("flagSuspectedImpersonation").call([
            "targetUid": targetUid,
            "reason": reason,
        ])
    }

    // MARK: - Parse

    private func parseProfile(_ data: [String: Any], uid: String) -> IdentityTrustProfile {
        let levelStr = data["trustLevel"] as? String ?? "basic"
        return IdentityTrustProfile(
            uid: uid,
            trustLevel: IdentityTrustLevel(rawValue: levelStr) ?? .basic,
            verifiedAt: nil,
            verificationSource: data["verificationSource"] as? String,
            claimedRoles: data["claimedRoles"] as? [String] ?? [],
            unverifiedClaims: data["unverifiedClaims"] as? [String] ?? [],
            isSuspectedImpersonation: data["isSuspectedImpersonation"] as? Bool ?? false,
            trustScore: data["trustScore"] as? Int ?? 20,
            policyVersion: data["policyVersion"] as? String ?? AmenTrustSafetyOSVersion
        )
    }

    func invalidateCache(for uid: String) {
        profileCache.removeValue(forKey: uid)
    }
}

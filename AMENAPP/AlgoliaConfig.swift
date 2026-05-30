//
//  AlgoliaConfig.swift
//  AMENAPP
//
//  Created by Steph on 1/28/26.
//
//  Algolia API configuration
//

import Foundation
import FirebaseRemoteConfig

enum AlgoliaConfig {
    /// Your Algolia Application ID — read from Info.plist, which is substituted at
    /// build time from Config.xcconfig (gitignored). Do not hardcode here.
    // SECURITY: Rotate the search key in Algolia dashboard — the old key is in git history.
    static let applicationID = Bundle.main.infoDictionary?["AlgoliaAppID"] as? String ?? ""

    /// Search-Only API Key — baked into the bundle at build time.
    /// Use `effectiveSearchAPIKey` instead so callers pick up Remote Config overrides.
    static let searchAPIKey = Bundle.main.infoDictionary?["AlgoliaSearchKey"] as? String ?? ""

    /// The search key to use at runtime. Remote Config `algolia_search_key` overrides the
    /// bundle value so the key can be rotated without an App Store update.
    static var effectiveSearchAPIKey: String {
        let rcValue = RemoteConfig.remoteConfig()["algolia_search_key"].stringValue
        if !rcValue.isEmpty { return rcValue }
        return searchAPIKey
    }

    /// Organizations Algolia index name — used for org stub directory search.
    static let organizationsIndex = "organizations"

    /// Write API Key: NEVER include in the client binary.
    /// Algolia sync must go through a Cloud Function (server-side).
    /// This property is intentionally empty — the key lives in Firebase Remote Config / Cloud Functions only.
    /// See: https://www.algolia.com/doc/guides/security/api-keys/#secured-api-keys
    static let writeAPIKey = ""  // ⛔️ Removed from client. Use server-side Cloud Function for writes.
}

// MARK: - Usage Instructions

/*
 📝 How to Get Your Algolia API Keys:
 
 1. Go to https://www.algolia.com
 2. Sign in to your account
 3. Go to Settings → API Keys
 4. You'll need THREE keys:
    ✅ Application ID (public, safe to share)
    ✅ Search-Only API Key (public, safe for client apps)
    ✅ Write API Key or Admin API Key (PRIVATE, for syncing data)
 
 5. Replace the values in AlgoliaConfig enum above
 
 ⚠️ SECURITY NOTE:
 - Application ID: ✅ Public
 - Search-Only API Key: ✅ Safe to use in iOS app (read-only)
 - Write/Admin API Key: ⛔️ Must NEVER be in the client binary (already removed)
 
 🏭 PRODUCTION SETUP:
 For production apps, the Write/Admin API Key should be:
 - Stored in Firebase Functions (server-side)
 - Used via Firebase Extension for Algolia
 - Never exposed to client apps
 
 ⛔️ The writeAPIKey has been removed from the client. All Algolia index writes
 must go through a Firebase Cloud Function or the Firebase Extension for Algolia.
 */

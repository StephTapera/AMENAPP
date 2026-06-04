//
//  AlgoliaConfig.swift
//  AMENAPP
//
//  Created by Steph on 1/28/26.
//
//  Algolia API configuration
//

import Foundation

enum AlgoliaConfig {
    /// Your Algolia Application ID
    /// Found in: Algolia Dashboard → Settings → API Keys
    static let applicationID = "182SCN7O9S"
    
    /// Search-Only API Key — read from Config.xcconfig (gitignored).
    /// The previous hardcoded key was rotated 2026-06-03 after it appeared in git history.
    /// To set: add ALGOLIA_SEARCH_KEY = <your_key> to Config.xcconfig,
    /// then add <key>ALGOLIA_SEARCH_KEY</key><string>$(ALGOLIA_SEARCH_KEY)</string> to Info.plist.
    static let searchAPIKey: String = {
        (Bundle.main.object(forInfoDictionaryKey: "ALGOLIA_SEARCH_KEY") as? String ?? "").trimmingCharacters(in: .whitespaces)
    }()
    
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

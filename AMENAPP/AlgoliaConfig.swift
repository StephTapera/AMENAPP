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
    
    /// Your Search-Only API Key (safe for client-side use)
    /// Found in: Algolia Dashboard → Settings → API Keys → Search-Only API Key
    /// ✅ Safe to use in iOS app (read-only)
    static let searchAPIKey = "8727f5af5779e9795b12b565bba20dc3"
    
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
 - Write/Admin API Key: ⚠️ Should be server-side in production
   (For development/testing, okay to include temporarily)
 
 🏭 PRODUCTION SETUP:
 For production apps, the Write/Admin API Key should be:
 - Stored in Firebase Functions (server-side)
 - Used via Firebase Extension for Algolia
 - Never exposed to client apps
 
 ⛔️ The writeAPIKey has been removed from the client. All Algolia index writes
 must go through a Firebase Cloud Function or the Firebase Extension for Algolia.
 */

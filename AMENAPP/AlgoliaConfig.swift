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
    
    /// Your Write API Key (for syncing data to Algolia)
    /// Found in: Algolia Dashboard → Settings → API Keys → Write API Key or Admin API Key
    /// ⚠️ KEEP THIS SECURE - Should only be used server-side in production
    /// For development/testing, it's okay to use in the app temporarily
    static let writeAPIKey = "5343b0c07447ab2490b5a2283e1557e8"  // TODO: Replace with your Write/Admin API Key
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
 
 For now (development), it's okay to use it directly in the app.
 */

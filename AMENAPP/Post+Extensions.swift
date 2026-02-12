//
//  Post+Extensions.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Extensions for Post model to work with Firestore
//

import Foundation

extension Post {
    /// ✅ FIXED: Get the correct Firestore document ID
    /// Always use firebaseId (the real Firestore ID), fallback to UUID only if nil
    /// 
    /// CRITICAL FIX (2026-02-11): Posts loaded from Firestore must have their firebaseId
    /// property populated with the Firestore document ID. This is done in FirebasePostService.swift
    /// by explicitly setting `firestorePost.id = doc.documentID` after decoding.
    /// 
    /// Without this, firebaseId is nil and this property returns the full UUID, causing
    /// a mismatch when checking lightbulb/amen state (cache stores short IDs like "DB103656"
    /// but PostCards check using full UUIDs like "DB103656-3089-4B1F-9591-8A1CD2C3EBE2").
    var firestoreId: String {
        firebaseId ?? id.uuidString
    }
    
    /// Check if user has amened this post (requires checking amenUserIds from Firestore)
    func hasAmened(by userId: String) -> Bool {
        amenUserIds.contains(userId)
    }
    
    /// Check if user has lit lightbulb (requires checking lightbulbUserIds from Firestore)
    func hasLitLightbulb(by userId: String) -> Bool {
        lightbulbUserIds.contains(userId)
    }
    
    /// Get amenUserIds and lightbulbUserIds (these should be added to Post model)
    var amenUserIds: [String] {
        // TODO: This should be fetched from Firestore or stored in the Post model
        []
    }
    
    var lightbulbUserIds: [String] {
        // TODO: This should be fetched from Firestore or stored in the Post model
        []
    }
    
    // MARK: - Mention Utilities
    
    /// Extract all @username mentions from text
    static func extractMentionUsernames(from text: String) -> [String] {
        let pattern = "@([a-zA-Z0-9_]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        
        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        
        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let usernameRange = match.range(at: 1)
            return nsString.substring(with: usernameRange)
        }
    }
    
    /// Get unique mention usernames from this post's content
    var mentionedUsernames: [String] {
        Array(Set(Post.extractMentionUsernames(from: content)))
    }
}

extension FirestorePost {
    /// Check if current user has amened this post
    func hasAmened(by userId: String) -> Bool {
        amenUserIds.contains(userId)
    }
    
    /// Check if current user has lit lightbulb
    func hasLitLightbulb(by userId: String) -> Bool {
        lightbulbUserIds.contains(userId)
    }
}


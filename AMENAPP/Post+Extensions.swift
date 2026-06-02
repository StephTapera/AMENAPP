//
//  Post+Extensions.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Extensions for Post model to work with Firestore
//

import Foundation
import SwiftUI

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
    nonisolated var firestoreId: String {
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
    
    /// NOTE: The Post struct does not carry per-user interaction state.
    /// Use PostInteractionsService.shared.userAmenedPosts / userLightbulbedPosts for real state.
    /// These stubs exist only to satisfy the hasAmened(by:)/hasLitLightbulb(by:) protocol API.
    var amenUserIds: [String] { [] }
    var lightbulbUserIds: [String] { [] }
    
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

// MARK: - Equatable override

extension Post {
    // PERF FIX: Custom == excludes the four engagement counters (amenCount,
    // lightbulbCount, commentCount, repostCount) from equality.
    //
    // WHY SAFE:
    //   PostCard stores these counts in its own @State vars and reads them from
    //   PostInteractionsService — the Post struct values are only used as the
    //   initial seed on first render.  Consequently, when PostsManager updates
    //   a post to bump a counter, the synthesised == would return false,
    //   triggering a SwiftUI re-render of *every* PostCard in the feed.
    //   Excluding the counters means minor counter ticks no longer cause
    //   full-feed re-renders or reset CachedAsyncImage @State.
    //
    // WHAT STILL TRIGGERS RE-RENDER:
    //   Any change to content, author data, media, visibility, category,
    //   translation state, or any other display-affecting field — exactly as
    //   intended.
    static func == (lhs: Post, rhs: Post) -> Bool {
        lhs.id                      == rhs.id
        && lhs.firebaseId           == rhs.firebaseId
        && lhs.authorId             == rhs.authorId
        && lhs.authorName           == rhs.authorName
        && lhs.authorUsername       == rhs.authorUsername
        && lhs.authorProfileImageURL == rhs.authorProfileImageURL
        && lhs.content              == rhs.content
        && lhs.category             == rhs.category
        && lhs.topicTag             == rhs.topicTag
        && lhs.visibility           == rhs.visibility
        && lhs.allowComments        == rhs.allowComments
        && lhs.imageURLs            == rhs.imageURLs
        && lhs.linkURL              == rhs.linkURL
        && lhs.verseReference       == rhs.verseReference
        && lhs.verseText            == rhs.verseText
        && lhs.createdAt            == rhs.createdAt
        && lhs.updatedAt            == rhs.updatedAt
        && lhs.isRepost             == rhs.isRepost
        && lhs.originalAuthorName   == rhs.originalAuthorName
        && lhs.prayerStatus         == rhs.prayerStatus
        && lhs.linkedTestimonyId    == rhs.linkedTestimonyId
        && lhs.isAnsweredPrayer     == rhs.isAnsweredPrayer
        && lhs.isTranslated         == rhs.isTranslated
        && lhs.originalContent      == rhs.originalContent
        && lhs.detectedLanguage     == rhs.detectedLanguage
        && lhs.contentSource        == rhs.contentSource
        && lhs.hasSensitiveContent  == rhs.hasSensitiveContent
        && lhs.removed              == rhs.removed
        && lhs.poll                 == rhs.poll
        && lhs.threadId             == rhs.threadId
        && lhs.threadIndex          == rhs.threadIndex
        && lhs.isThreadHead         == rhs.isThreadHead
        && lhs.threadPostCount      == rhs.threadPostCount
        && lhs.isPinned             == rhs.isPinned
        // amenCount, lightbulbCount, commentCount, repostCount intentionally omitted
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

// MARK: - Post RenderModel bridge properties

extension Post {
    var mediaItems: [PostMediaItem]? { nil }
    var witnessMedia: String? { nil }
    var lowTrustAuthor: Bool { false }
    var sharedChurchId: String? { nil }
    var sharedChurchAddress: String? { nil }
    var dynamicReplyPreviewCandidates: [DynamicReplyPreview]? { nil }
    var aiUsage: PostAIUsage? { nil }
    var contextStableId: String { firebaseId ?? id.uuidString }
}

// MARK: - PostCategory display helpers

extension Post.PostCategory {
    var icon: String {
        switch self {
        case .openTable:   return "bubble.left.and.bubble.right.fill"
        case .testimonies: return "star.fill"
        case .prayer:      return "hands.sparkles"
        case .tip:         return "lightbulb.fill"
        case .funFact:     return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .openTable:   return .blue
        case .testimonies: return .orange
        case .prayer:      return .purple
        case .tip:         return .yellow
        case .funFact:     return .teal
        }
    }
}

// MARK: - PostVisibility top-level alias

typealias PostVisibility = Post.PostVisibility


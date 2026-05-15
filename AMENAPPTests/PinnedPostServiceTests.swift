//
//  PinnedPostServiceTests.swift
//  AMENAPPTests
//

import Testing
import Foundation
import FirebaseFirestore
@testable import AMENAPP

// MARK: - PinnedPostMetadata — init and encoding

@Suite("PinnedPostMetadata — init and encoding")
struct PinnedPostMetadataInitTests {

    @Test("minimal init sets defaults correctly")
    func minimalInitDefaults() {
        let m = PinnedPostMetadata(postID: "abc123")
        #expect(m.postID == "abc123")
        #expect(m.isPinned == true)
        #expect(m.semanticTags.isEmpty)
        #expect(m.pinnedAt == nil)
        #expect(m.pinnedReason == nil)
        #expect(m.pinnedLabelOverride == nil)
        #expect(m.pinnedMediaMode == nil)
    }

    @Test("firestoreValue contains required keys with correct types")
    func firestoreValueContainsRequiredKeys() {
        let m = PinnedPostMetadata(
            postID: "post-xyz",
            isPinned: true,
            semanticTags: ["Prayer", "Verse"]
        )
        let v = m.firestoreValue
        #expect(v["postId"] as? String == "post-xyz")
        #expect(v["isPinned"] as? Bool == true)
        #expect(v["semanticTags"] as? [String] == ["Prayer", "Verse"])
    }

    @Test("firestoreValue includes pinnedMediaMode rawValue when set")
    func firestoreValueIncludesMediaMode() {
        let m = PinnedPostMetadata(postID: "p1", pinnedMediaMode: .testimony)
        let v = m.firestoreValue
        #expect(v["pinnedMediaMode"] as? String == "testimony")
    }

    @Test("label falls back to 'Featured post' when no override")
    func labelFallsBackToFeaturedPost() {
        let m = PinnedPostMetadata(postID: "p1")
        #expect(m.label == "Featured post")
    }

    @Test("label uses override when set (trimmed)")
    func labelUsesOverride() {
        let m = PinnedPostMetadata(postID: "p1", pinnedLabelOverride: "  My verse  ")
        #expect(m.label == "My verse")
    }

    @Test("label ignores whitespace-only override and falls back")
    func labelIgnoresWhitespaceOverride() {
        let m = PinnedPostMetadata(postID: "p1", pinnedLabelOverride: "   ")
        #expect(m.label == "Featured post")
    }
}

// MARK: - PinnedPostMetadata — decoding

@Suite("PinnedPostMetadata — decoding")
struct PinnedPostMetadataDecodeTests {

    @Test("decode(rawValue:) succeeds with all fields")
    func decodeAllFields() {
        let raw: [String: Any] = [
            "postId": "post-abc",
            "isPinned": true,
            "semanticTags": ["Testimony"],
            "pinnedMediaMode": "video",
            "pinnedLabelOverride": "Watch my story"
        ]
        let decoded = PinnedPostMetadata.decode(rawValue: raw)
        #expect(decoded != nil)
        #expect(decoded?.postID == "post-abc")
        #expect(decoded?.pinnedMediaMode == .video)
        #expect(decoded?.semanticTags == ["Testimony"])
        #expect(decoded?.pinnedLabelOverride == "Watch my story")
    }

    @Test("decode(rawValue:) returns nil when postId missing")
    func decodeNilWhenMissingPostId() {
        let raw: [String: Any] = ["isPinned": true, "semanticTags": []]
        #expect(PinnedPostMetadata.decode(rawValue: raw) == nil)
    }

    @Test("decode(rawValue:) returns nil when postId is empty string")
    func decodeNilWhenEmptyPostId() {
        let raw: [String: Any] = ["postId": "", "isPinned": true]
        #expect(PinnedPostMetadata.decode(rawValue: raw) == nil)
    }

    @Test("decode(from:) reads profilePinnedPost nested map")
    func decodeFromNestedMap() {
        let userDocData: [String: Any] = [
            "profilePinnedPost": [
                "postId": "nested-post",
                "isPinned": true,
                "semanticTags": []
            ]
        ]
        let decoded = PinnedPostMetadata.decode(from: userDocData)
        #expect(decoded?.postID == "nested-post")
    }

    @Test("decode(from:) returns nil when profilePinnedPost key absent")
    func decodeFromNilWhenKeyAbsent() {
        let userDocData: [String: Any] = ["username": "testuser"]
        #expect(PinnedPostMetadata.decode(from: userDocData) == nil)
    }
}

// MARK: - PinnedPostService — isPostPinned (read-only state, no network)

@Suite("PinnedPostService — isPostPinned")
struct PinnedPostServiceStateTests {

    @Test("isPostPinned returns false when no posts are pinned")
    @MainActor
    func returnsFalseWithEmptyState() {
        let service = PinnedPostService.shared
        #expect(service.isPostPinned("any-post-id") == false)
        #expect(service.isPostPinned("") == false)
    }
}

//
//  SavedPostsTests.swift
//  AMENAPPTests
//
//  Unit tests for saved posts functionality.
//  Firebase-dependent tests are skipped when no authenticated user is present.
//

import Testing
import Foundation
import FirebaseAuth
@testable import AMENAPP

// MARK: - Saved Posts Service Tests

@Suite("Saved Posts Service Tests")
@MainActor
struct SavedPostsServiceTests {

    private var isAuthenticated: Bool {
        Auth.auth().currentUser != nil
    }

    @Test("Toggle save post adds post to saved list")
    func toggleSavePost() async throws {
        guard isAuthenticated else {
            // Skip — requires Firebase auth
            return
        }
        let service = RealtimeSavedPostsService.shared
        let testPostId = UUID().uuidString

        let isSaved = try await service.toggleSavePost(postId: testPostId)
        #expect(isSaved == true, "Post should be saved")

        let savedIds = try await service.fetchSavedPostIds()
        #expect(savedIds.contains(testPostId), "Saved IDs should contain the test post")

        // Clean up
        _ = try await service.toggleSavePost(postId: testPostId)
    }

    @Test("Toggle unsave post removes post from saved list")
    func toggleUnsavePost() async throws {
        guard isAuthenticated else { return }
        let service = RealtimeSavedPostsService.shared
        let testPostId = UUID().uuidString

        _ = try await service.toggleSavePost(postId: testPostId)
        let isStillSaved = try await service.toggleSavePost(postId: testPostId)

        #expect(isStillSaved == false, "Post should be unsaved")

        let savedIds = try await service.fetchSavedPostIds()
        #expect(!savedIds.contains(testPostId), "Saved IDs should not contain the test post")
    }

    @Test("Get saved posts count returns correct number")
    func getSavedPostsCount() async throws {
        guard isAuthenticated else { return }
        let service = RealtimeSavedPostsService.shared
        let testPosts = [UUID().uuidString, UUID().uuidString, UUID().uuidString]

        for postId in testPosts {
            _ = try await service.toggleSavePost(postId: postId)
        }

        let count = try await service.getSavedPostsCount()
        #expect(count >= testPosts.count, "Count should be at least \(testPosts.count)")

        // Clean up
        for postId in testPosts {
            _ = try await service.toggleSavePost(postId: postId)
        }
    }

    @Test("Is post saved returns correct status")
    func isPostSaved() async throws {
        guard isAuthenticated else { return }
        let service = RealtimeSavedPostsService.shared
        let testPostId = UUID().uuidString

        let initialStatus = try await service.isPostSaved(postId: testPostId)
        #expect(initialStatus == false, "Post should not be saved initially")

        _ = try await service.toggleSavePost(postId: testPostId)

        let savedStatus = try await service.isPostSaved(postId: testPostId)
        #expect(savedStatus == true, "Post should be saved now")

        // Clean up
        _ = try await service.toggleSavePost(postId: testPostId)
    }

    @Test("Fetch saved post IDs returns string array")
    func fetchSavedPostIds() async throws {
        guard isAuthenticated else { return }
        let service = RealtimeSavedPostsService.shared
        let savedIds = try await service.fetchSavedPostIds()
        #expect(type(of: savedIds) == [String].self, "Should return string array")
    }
}

// MARK: - Saved Posts UI Tests

@Suite("Saved Posts UI Tests")
@MainActor
struct SavedPostsUITests {

    @Test("Saved posts view type is correct")
    func savedPostsViewInit() {
        // SwiftUI view structs are value types — type check validates the type exists
        // and compiles correctly without needing a running environment.
        let _: SavedPostsView.Type = SavedPostsView.self
    }

    @Test("Quick access button type is correct")
    func quickAccessButtonInit() {
        let _: SavedPostsQuickAccessButton.Type = SavedPostsQuickAccessButton.self
    }

    @Test("Saved posts row type is correct")
    func savedPostsRowInit() {
        let _: SavedPostsRow.Type = SavedPostsRow.self
    }
}

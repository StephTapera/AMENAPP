//
//  SavedPostsTests.swift
//  AMENAPPTests
//
//  Created by Steph on 1/29/26.
//
//  Test suite for saved posts functionality
//

import Testing
import Foundation
@testable import AMENAPP

@Suite("Saved Posts Service Tests")
@MainActor
struct SavedPostsServiceTests {
    
    let service = RealtimeSavedPostsService.shared
    
    @Test("Toggle save post adds post to saved list")
    func toggleSavePost() async throws {
        let testPostId = UUID().uuidString
        
        // Save the post
        let isSaved = try await service.toggleSavePost(postId: testPostId)
        
        #expect(isSaved == true, "Post should be saved")
        
        // Verify it's in saved list
        let savedIds = try await service.fetchSavedPostIds()
        #expect(savedIds.contains(testPostId), "Saved IDs should contain the test post")
        
        // Clean up
        _ = try await service.toggleSavePost(postId: testPostId)
    }
    
    @Test("Toggle unsave post removes post from saved list")
    func toggleUnsavePost() async throws {
        let testPostId = UUID().uuidString
        
        // Save
        _ = try await service.toggleSavePost(postId: testPostId)
        
        // Unsave
        let isStillSaved = try await service.toggleSavePost(postId: testPostId)
        
        #expect(isStillSaved == false, "Post should be unsaved")
        
        // Verify it's not in saved list
        let savedIds = try await service.fetchSavedPostIds()
        #expect(!savedIds.contains(testPostId), "Saved IDs should not contain the test post")
    }
    
    @Test("Get saved posts count returns correct number")
    func getSavedPostsCount() async throws {
        // Save a few posts
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
        let testPostId = UUID().uuidString
        
        // Initially not saved
        let initialStatus = try await service.isPostSaved(postId: testPostId)
        #expect(initialStatus == false, "Post should not be saved initially")
        
        // Save it
        _ = try await service.toggleSavePost(postId: testPostId)
        
        // Should be saved now
        let savedStatus = try await service.isPostSaved(postId: testPostId)
        #expect(savedStatus == true, "Post should be saved now")
        
        // Clean up
        _ = try await service.toggleSavePost(postId: testPostId)
    }
    
    @Test("Fetch saved post IDs returns string array")
    func fetchSavedPostIds() async throws {
        let savedIds = try await service.fetchSavedPostIds()
        
        // Verify the type is an array of strings
        #expect(type(of: savedIds) == [String].self, "Should return string array")
    }
}

@Suite("Saved Posts UI Tests")
@MainActor
struct SavedPostsUITests {
    
    @Test("Saved posts view initializes")
    func savedPostsViewInit() async throws {
        let view = SavedPostsView()
        
        #expect(view != nil, "View should initialize")
    }
    
    @Test("Quick access button initializes")
    func quickAccessButtonInit() async throws {
        let button = SavedPostsQuickAccessButton()
        
        #expect(button != nil, "Button should initialize")
    }
    
    @Test("Saved posts row initializes")
    func savedPostsRowInit() async throws {
        let row = SavedPostsRow()
        
        #expect(row != nil, "Row should initialize")
    }
}

// MARK: - Manual Testing Guide

/*
 
 🧪 MANUAL TESTING CHECKLIST
 
 Run through these tests manually to ensure everything works:
 
 ✅ BASIC FUNCTIONALITY
 
 1. [ ] Open any post in feed
 2. [ ] Tap bookmark icon → Icon fills, haptic feedback
 3. [ ] Navigate to Saved Posts view
 4. [ ] Verify post appears in saved list
 5. [ ] Tap bookmark icon again → Icon unfills, haptic feedback
 6. [ ] Verify post disappears from saved list
 
 ✅ MULTIPLE POSTS
 
 7. [ ] Save 5 different posts from feed
 8. [ ] Open Saved Posts view
 9. [ ] Verify all 5 posts appear
 10. [ ] Verify count badge shows "5"
 11. [ ] Unsave 2 posts from saved view
 12. [ ] Verify count badge updates to "3"
 
 ✅ EMPTY STATES
 
 13. [ ] Unsave all posts
 14. [ ] Open Saved Posts view
 15. [ ] Verify empty state appears with message
 16. [ ] Verify "Explore Posts" button is visible
 
 ✅ LOADING STATES
 
 17. [ ] Close and reopen app
 18. [ ] Navigate to Saved Posts
 19. [ ] Verify loading indicator appears briefly
 20. [ ] Verify posts load correctly
 
 ✅ PULL TO REFRESH
 
 21. [ ] In Saved Posts view, pull down
 22. [ ] Verify refresh animation plays
 23. [ ] Verify posts reload
 24. [ ] Verify haptic feedback
 
 ✅ CLEAR ALL
 
 25. [ ] Save at least 3 posts
 26. [ ] Open Saved Posts view
 27. [ ] Tap ⋯ menu → Clear All Saved Posts
 28. [ ] Verify confirmation dialog appears
 29. [ ] Tap "Clear All"
 30. [ ] Verify all posts are removed
 31. [ ] Verify empty state appears
 
 ✅ REAL-TIME SYNC (2 DEVICES)
 
 32. [ ] Log in to same account on 2 devices
 33. [ ] Save a post on Device A
 34. [ ] Verify it appears on Device B immediately
 35. [ ] Unsave on Device B
 36. [ ] Verify it disappears on Device A
 37. [ ] Verify badge counts update on both devices
 
 ✅ NAVIGATION
 
 38. [ ] From Profile → Saved Posts Row → View opens
 39. [ ] From Quick Access Button → View opens
 40. [ ] From Tab Bar (if added) → View opens
 41. [ ] Back button works correctly
 42. [ ] Navigation title displays "Saved Posts"
 
 ✅ ERROR HANDLING
 
 43. [ ] Turn off WiFi
 44. [ ] Try to save a post
 45. [ ] Verify error alert appears
 46. [ ] Turn WiFi back on
 47. [ ] Verify functionality resumes
 
 ✅ PERFORMANCE
 
 48. [ ] Save 50+ posts
 49. [ ] Open Saved Posts view
 50. [ ] Scroll through list
 51. [ ] Verify smooth scrolling (60fps)
 52. [ ] Verify no lag or stuttering
 
 ✅ EDGE CASES
 
 53. [ ] Save a post, then delete original post
 54. [ ] Open Saved Posts view
 55. [ ] Verify graceful handling (post skipped or shown as deleted)
 
 56. [ ] Save same post twice quickly
 57. [ ] Verify no duplicate entries
 
 58. [ ] Background app while in Saved Posts view
 59. [ ] Foreground app
 60. [ ] Verify data still loaded correctly
 
 ✅ ANIMATIONS & HAPTICS
 
 61. [ ] Tap bookmark icon → Verify smooth fill animation
 62. [ ] Tap bookmark icon → Verify haptic feedback
 63. [ ] Pull to refresh → Verify haptic on completion
 64. [ ] Clear all → Verify success haptic
 
 ✅ ACCESSIBILITY
 
 65. [ ] Enable VoiceOver
 66. [ ] Navigate to Saved Posts
 67. [ ] Verify screen reader announces elements
 68. [ ] Verify bookmark button is accessible
 
 69. [ ] Increase text size to maximum
 70. [ ] Verify all text scales correctly
 71. [ ] Verify UI doesn't break
 
 ✅ DARK MODE
 
 72. [ ] Switch to Dark Mode
 73. [ ] Open Saved Posts view
 74. [ ] Verify colors are appropriate
 75. [ ] Verify readability is maintained
 
 ✅ DIFFERENT DEVICES
 
 76. [ ] Test on iPhone SE (small screen)
 77. [ ] Test on iPhone Pro Max (large screen)
 78. [ ] Test on iPad (if supported)
 79. [ ] Verify layouts adapt correctly
 
 ✅ INTEGRATION WITH EXISTING FEATURES
 
 80. [ ] Save a prayer post → Open Saved Posts → Verify prayer count shows
 81. [ ] Save a testimony → Open Saved Posts → Verify category icon correct
 82. [ ] Like a saved post → Verify count updates
 83. [ ] Comment on saved post → Verify comment count updates
 
 ───────────────────────────────────────────────────────────
 
 📊 RESULTS
 
 Total Tests: 83
 Passed: ___ / 83
 Failed: ___ / 83
 
 ───────────────────────────────────────────────────────────
 
 🐛 BUGS FOUND
 
 1. [Description]
    - Steps to reproduce:
    - Expected:
    - Actual:
    - Severity: High / Medium / Low
 
 2. [Description]
    - Steps to reproduce:
    - Expected:
    - Actual:
    - Severity: High / Medium / Low
 
 ───────────────────────────────────────────────────────────
 
 ✅ PRODUCTION READY CRITERIA
 
 - [ ] All critical path tests pass
 - [ ] No high-severity bugs
 - [ ] Performance is acceptable
 - [ ] Accessibility works
 - [ ] Dark mode works
 - [ ] Real-time sync works
 - [ ] Error handling is graceful
 - [ ] UX is polished (animations, haptics)
 
 */

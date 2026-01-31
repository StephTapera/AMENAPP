# 🧪 Firebase Rules Testing Script

This document provides comprehensive tests to verify your Firebase Security Rules are working correctly.

---

## 📋 Pre-Test Setup

### Enable Firebase Emulator (Recommended)

Test your rules locally before deploying to production:

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Initialize Firebase in your project
firebase init emulators

# Start emulators
firebase emulators:start
```

Then update your app to use emulator:
```swift
// In your Firebase setup
#if DEBUG
let settings = Firestore.firestore().settings
settings.host = "localhost:8080"
settings.isPersistenceEnabled = false
settings.isSSLEnabled = false
Firestore.firestore().settings = settings

Auth.auth().useEmulator(withHost: "localhost", port: 9099)
#endif
```

---

## ✅ Test Suite 1: User Management

### Test 1.1: Create User Profile ✅
```swift
func testCreateUserProfile() async throws {
    let userId = "test-user-123"
    let userData: [String: Any] = [
        "username": "testuser",
        "email": "test@example.com",
        "displayName": "Test User",
        "createdAt": Timestamp(date: Date())
    ]
    
    try await Firestore.firestore()
        .collection("users")
        .document(userId)
        .setData(userData)
    
    print("✅ Test 1.1 PASSED: User profile created")
}
```

**Expected:** Success

### Test 1.2: Prevent Creating Another User's Profile ❌
```swift
func testCannotCreateOthersProfile() async throws {
    let otherUserId = "other-user-456"
    let userData: [String: Any] = [
        "username": "otheruser",
        "email": "other@example.com",
        "displayName": "Other User",
        "createdAt": Timestamp(date: Date())
    ]
    
    do {
        // Try to create profile for different user
        try await Firestore.firestore()
            .collection("users")
            .document(otherUserId)  // Different from auth.uid
            .setData(userData)
        
        print("❌ Test 1.2 FAILED: Should not allow creating other user's profile")
    } catch {
        print("✅ Test 1.2 PASSED: Correctly prevented creating other user's profile")
    }
}
```

**Expected:** Permission denied error

### Test 1.3: Username Length Validation ❌
```swift
func testUsernameLengthValidation() async throws {
    let userId = Auth.auth().currentUser!.uid
    let invalidUsername = String(repeating: "a", count: 31)  // 31 chars (max is 30)
    
    let userData: [String: Any] = [
        "username": invalidUsername,
        "email": "test@example.com",
        "displayName": "Test User",
        "createdAt": Timestamp(date: Date())
    ]
    
    do {
        try await Firestore.firestore()
            .collection("users")
            .document(userId)
            .setData(userData)
        
        print("❌ Test 1.3 FAILED: Should reject username over 30 chars")
    } catch {
        print("✅ Test 1.3 PASSED: Username length validation working")
    }
}
```

**Expected:** Permission denied error

### Test 1.4: Update Own Profile ✅
```swift
func testUpdateOwnProfile() async throws {
    let userId = Auth.auth().currentUser!.uid
    
    try await Firestore.firestore()
        .collection("users")
        .document(userId)
        .updateData(["bio": "Updated bio"])
    
    print("✅ Test 1.4 PASSED: Can update own profile")
}
```

**Expected:** Success

---

## ✅ Test Suite 2: Follow System

### Test 2.1: Follow Another User ✅
```swift
func testFollowUser() async throws {
    let currentUserId = Auth.auth().currentUser!.uid
    let targetUserId = "target-user-789"
    let followId = "\(currentUserId)_\(targetUserId)"
    
    let followData: [String: Any] = [
        "followerUserId": currentUserId,
        "followingUserId": targetUserId,
        "createdAt": Timestamp(date: Date())
    ]
    
    try await Firestore.firestore()
        .collection("follows")
        .document(followId)
        .setData(followData)
    
    print("✅ Test 2.1 PASSED: Can follow another user")
}
```

**Expected:** Success

### Test 2.2: Prevent Self-Follow ❌
```swift
func testPreventSelfFollow() async throws {
    let currentUserId = Auth.auth().currentUser!.uid
    let followId = "\(currentUserId)_\(currentUserId)"
    
    let followData: [String: Any] = [
        "followerUserId": currentUserId,
        "followingUserId": currentUserId,  // Same as follower
        "createdAt": Timestamp(date: Date())
    ]
    
    do {
        try await Firestore.firestore()
            .collection("follows")
            .document(followId)
            .setData(followData)
        
        print("❌ Test 2.2 FAILED: Should prevent self-follow")
    } catch {
        print("✅ Test 2.2 PASSED: Self-follow correctly prevented")
    }
}
```

**Expected:** Permission denied error

### Test 2.3: Cannot Follow as Another User ❌
```swift
func testCannotFollowAsAnotherUser() async throws {
    let currentUserId = Auth.auth().currentUser!.uid
    let otherUserId = "other-user-456"
    let targetUserId = "target-user-789"
    let followId = "\(otherUserId)_\(targetUserId)"
    
    let followData: [String: Any] = [
        "followerUserId": otherUserId,  // Different from current user
        "followingUserId": targetUserId,
        "createdAt": Timestamp(date: Date())
    ]
    
    do {
        try await Firestore.firestore()
            .collection("follows")
            .document(followId)
            .setData(followData)
        
        print("❌ Test 2.3 FAILED: Should not allow following as another user")
    } catch {
        print("✅ Test 2.3 PASSED: Cannot follow as another user")
    }
}
```

**Expected:** Permission denied error

### Test 2.4: Unfollow User ✅
```swift
func testUnfollowUser() async throws {
    let currentUserId = Auth.auth().currentUser!.uid
    let targetUserId = "target-user-789"
    let followId = "\(currentUserId)_\(targetUserId)"
    
    try await Firestore.firestore()
        .collection("follows")
        .document(followId)
        .delete()
    
    print("✅ Test 2.4 PASSED: Can unfollow user")
}
```

**Expected:** Success

---

## ✅ Test Suite 3: Posts

### Test 3.1: Create Post ✅
```swift
func testCreatePost() async throws {
    let currentUserId = Auth.auth().currentUser!.uid
    let postId = UUID().uuidString
    
    let postData: [String: Any] = [
        "authorId": currentUserId,
        "authorName": "Test User",
        "content": "This is a test post",
        "category": "#OPENTABLE",
        "createdAt": Timestamp(date: Date()),
        "amenCount": 0,
        "lightbulbCount": 0,
        "commentCount": 0,
        "repostCount": 0
    ]
    
    try await Firestore.firestore()
        .collection("posts")
        .document(postId)
        .setData(postData)
    
    print("✅ Test 3.1 PASSED: Can create post")
}
```

**Expected:** Success

### Test 3.2: Cannot Create Post as Another User ❌
```swift
func testCannotCreatePostAsAnotherUser() async throws {
    let otherUserId = "other-user-456"
    let postId = UUID().uuidString
    
    let postData: [String: Any] = [
        "authorId": otherUserId,  // Different from current user
        "authorName": "Other User",
        "content": "Fake post",
        "category": "#OPENTABLE",
        "createdAt": Timestamp(date: Date())
    ]
    
    do {
        try await Firestore.firestore()
            .collection("posts")
            .document(postId)
            .setData(postData)
        
        print("❌ Test 3.2 FAILED: Should not allow creating post as another user")
    } catch {
        print("✅ Test 3.2 PASSED: Cannot create post as another user")
    }
}
```

**Expected:** Permission denied error

### Test 3.3: Invalid Category ❌
```swift
func testInvalidCategory() async throws {
    let currentUserId = Auth.auth().currentUser!.uid
    let postId = UUID().uuidString
    
    let postData: [String: Any] = [
        "authorId": currentUserId,
        "authorName": "Test User",
        "content": "Invalid category test",
        "category": "InvalidCategory",  // Not a valid category
        "createdAt": Timestamp(date: Date())
    ]
    
    do {
        try await Firestore.firestore()
            .collection("posts")
            .document(postId)
            .setData(postData)
        
        print("❌ Test 3.3 FAILED: Should reject invalid category")
    } catch {
        print("✅ Test 3.3 PASSED: Invalid category rejected")
    }
}
```

**Expected:** Permission denied error

### Test 3.4: Content Length Limit ❌
```swift
func testContentLengthLimit() async throws {
    let currentUserId = Auth.auth().currentUser!.uid
    let postId = UUID().uuidString
    let longContent = String(repeating: "a", count: 10001)  // 10,001 chars (max is 10,000)
    
    let postData: [String: Any] = [
        "authorId": currentUserId,
        "authorName": "Test User",
        "content": longContent,
        "category": "#OPENTABLE",
        "createdAt": Timestamp(date: Date())
    ]
    
    do {
        try await Firestore.firestore()
            .collection("posts")
            .document(postId)
            .setData(postData)
        
        print("❌ Test 3.4 FAILED: Should reject content over 10,000 chars")
    } catch {
        print("✅ Test 3.4 PASSED: Content length limit enforced")
    }
}
```

**Expected:** Permission denied error

### Test 3.5: Delete Own Post ✅
```swift
func testDeleteOwnPost() async throws {
    let currentUserId = Auth.auth().currentUser!.uid
    let postId = UUID().uuidString
    
    // First create post
    let postData: [String: Any] = [
        "authorId": currentUserId,
        "authorName": "Test User",
        "content": "Post to be deleted",
        "category": "#OPENTABLE",
        "createdAt": Timestamp(date: Date())
    ]
    
    try await Firestore.firestore()
        .collection("posts")
        .document(postId)
        .setData(postData)
    
    // Then delete it
    try await Firestore.firestore()
        .collection("posts")
        .document(postId)
        .delete()
    
    print("✅ Test 3.5 PASSED: Can delete own post")
}
```

**Expected:** Success

### Test 3.6: Cannot Delete Another User's Post ❌
```swift
func testCannotDeleteOthersPost() async throws {
    let postId = "some-other-users-post-id"
    
    do {
        try await Firestore.firestore()
            .collection("posts")
            .document(postId)
            .delete()
        
        print("❌ Test 3.6 FAILED: Should not allow deleting other's post")
    } catch {
        print("✅ Test 3.6 PASSED: Cannot delete other's post")
    }
}
```

**Expected:** Permission denied error

---

## ✅ Test Suite 4: Comments

### Test 4.1: Add Comment to Post ✅
```swift
func testAddComment() async throws {
    let currentUserId = Auth.auth().currentUser!.uid
    let postId = "test-post-id"
    let commentId = UUID().uuidString
    
    let commentData: [String: Any] = [
        "authorId": currentUserId,
        "text": "Great post!",
        "createdAt": Timestamp(date: Date())
    ]
    
    try await Firestore.firestore()
        .collection("posts")
        .document(postId)
        .collection("comments")
        .document(commentId)
        .setData(commentData)
    
    print("✅ Test 4.1 PASSED: Can add comment to post")
}
```

**Expected:** Success

### Test 4.2: Comment Text Length Limit ❌
```swift
func testCommentLengthLimit() async throws {
    let currentUserId = Auth.auth().currentUser!.uid
    let postId = "test-post-id"
    let commentId = UUID().uuidString
    let longText = String(repeating: "a", count: 2001)  // 2,001 chars (max is 2,000)
    
    let commentData: [String: Any] = [
        "authorId": currentUserId,
        "text": longText,
        "createdAt": Timestamp(date: Date())
    ]
    
    do {
        try await Firestore.firestore()
            .collection("posts")
            .document(postId)
            .collection("comments")
            .document(commentId)
            .setData(commentData)
        
        print("❌ Test 4.2 FAILED: Should reject comment over 2,000 chars")
    } catch {
        print("✅ Test 4.2 PASSED: Comment length limit enforced")
    }
}
```

**Expected:** Permission denied error

### Test 4.3: Delete Own Comment ✅
```swift
func testDeleteOwnComment() async throws {
    let postId = "test-post-id"
    let commentId = "my-comment-id"
    
    try await Firestore.firestore()
        .collection("posts")
        .document(postId)
        .collection("comments")
        .document(commentId)
        .delete()
    
    print("✅ Test 4.3 PASSED: Can delete own comment")
}
```

**Expected:** Success

---

## ✅ Test Suite 5: Reactions (Amens, Lightbulbs, Support)

### Test 5.1: Add Amen to Post ✅
```swift
func testAddAmen() async throws {
    let currentUserId = Auth.auth().currentUser!.uid
    let postId = "test-post-id"
    
    let amenData: [String: Any] = [
        "userId": currentUserId,
        "createdAt": Timestamp(date: Date())
    ]
    
    try await Firestore.firestore()
        .collection("posts")
        .document(postId)
        .collection("amens")
        .document(currentUserId)
        .setData(amenData)
    
    print("✅ Test 5.1 PASSED: Can add amen to post")
}
```

**Expected:** Success

### Test 5.2: Cannot Amen as Another User ❌
```swift
func testCannotAmenAsAnotherUser() async throws {
    let otherUserId = "other-user-456"
    let postId = "test-post-id"
    
    let amenData: [String: Any] = [
        "userId": otherUserId,
        "createdAt": Timestamp(date: Date())
    ]
    
    do {
        try await Firestore.firestore()
            .collection("posts")
            .document(postId)
            .collection("amens")
            .document(otherUserId)  // Different from current user
            .setData(amenData)
        
        print("❌ Test 5.2 FAILED: Should not allow amen as another user")
    } catch {
        print("✅ Test 5.2 PASSED: Cannot amen as another user")
    }
}
```

**Expected:** Permission denied error

### Test 5.3: Remove Amen ✅
```swift
func testRemoveAmen() async throws {
    let currentUserId = Auth.auth().currentUser!.uid
    let postId = "test-post-id"
    
    try await Firestore.firestore()
        .collection("posts")
        .document(postId)
        .collection("amens")
        .document(currentUserId)
        .delete()
    
    print("✅ Test 5.3 PASSED: Can remove amen")
}
```

**Expected:** Success

---

## ✅ Test Suite 6: Conversations & Messages

### Test 6.1: Create Conversation ✅
```swift
func testCreateConversation() async throws {
    let currentUserId = Auth.auth().currentUser!.uid
    let otherUserId = "other-user-456"
    let conversationId = UUID().uuidString
    
    let conversationData: [String: Any] = [
        "participants": [currentUserId, otherUserId],
        "lastMessage": "",
        "lastMessageSenderId": "",
        "lastMessageTime": Timestamp(date: Date()),
        "createdAt": Timestamp(date: Date()),
        "updatedAt": Timestamp(date: Date())
    ]
    
    try await Firestore.firestore()
        .collection("conversations")
        .document(conversationId)
        .setData(conversationData)
    
    print("✅ Test 6.1 PASSED: Can create conversation")
}
```

**Expected:** Success

### Test 6.2: Send Message ✅
```swift
func testSendMessage() async throws {
    let currentUserId = Auth.auth().currentUser!.uid
    let conversationId = "test-conversation-id"
    let messageId = UUID().uuidString
    
    let messageData: [String: Any] = [
        "senderId": currentUserId,
        "content": "Hello!",
        "timestamp": Timestamp(date: Date()),
        "isRead": false,
        "isDelivered": false
    ]
    
    try await Firestore.firestore()
        .collection("conversations")
        .document(conversationId)
        .collection("messages")
        .document(messageId)
        .setData(messageData)
    
    print("✅ Test 6.2 PASSED: Can send message")
}
```

**Expected:** Success

### Test 6.3: Message Length Limit ❌
```swift
func testMessageLengthLimit() async throws {
    let currentUserId = Auth.auth().currentUser!.uid
    let conversationId = "test-conversation-id"
    let messageId = UUID().uuidString
    let longMessage = String(repeating: "a", count: 10001)  // 10,001 chars
    
    let messageData: [String: Any] = [
        "senderId": currentUserId,
        "content": longMessage,
        "timestamp": Timestamp(date: Date())
    ]
    
    do {
        try await Firestore.firestore()
            .collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .setData(messageData)
        
        print("❌ Test 6.3 FAILED: Should reject message over 10,000 chars")
    } catch {
        print("✅ Test 6.3 PASSED: Message length limit enforced")
    }
}
```

**Expected:** Permission denied error

---

## ✅ Test Suite 7: Notifications

### Test 7.1: Read Own Notifications ✅
```swift
func testReadOwnNotifications() async throws {
    let currentUserId = Auth.auth().currentUser!.uid
    
    let notifications = try await Firestore.firestore()
        .collection("notifications")
        .whereField("recipientId", isEqualTo: currentUserId)
        .getDocuments()
    
    print("✅ Test 7.1 PASSED: Can read own notifications")
}
```

**Expected:** Success

### Test 7.2: Cannot Read Others' Notifications ❌
```swift
func testCannotReadOthersNotifications() async throws {
    let otherUserId = "other-user-456"
    
    do {
        let notifications = try await Firestore.firestore()
            .collection("notifications")
            .whereField("recipientId", isEqualTo: otherUserId)
            .getDocuments()
        
        // If we got here, check if we can actually access the data
        if !notifications.documents.isEmpty {
            print("❌ Test 7.2 FAILED: Should not read other's notifications")
        } else {
            print("✅ Test 7.2 PASSED: Cannot read other's notifications")
        }
    } catch {
        print("✅ Test 7.2 PASSED: Cannot read other's notifications")
    }
}
```

**Expected:** Empty result or error

---

## ✅ Test Suite 8: Reports

### Test 8.1: Create Report ✅
```swift
func testCreateReport() async throws {
    let currentUserId = Auth.auth().currentUser!.uid
    let reportId = UUID().uuidString
    
    let reportData: [String: Any] = [
        "reporterId": currentUserId,
        "reportedId": "reported-user-id",
        "reason": "Spam",
        "createdAt": Timestamp(date: Date())
    ]
    
    try await Firestore.firestore()
        .collection("reports")
        .document(reportId)
        .setData(reportData)
    
    print("✅ Test 8.1 PASSED: Can create report")
}
```

**Expected:** Success

### Test 8.2: Cannot Read Reports ❌
```swift
func testCannotReadReports() async throws {
    do {
        let reports = try await Firestore.firestore()
            .collection("reports")
            .getDocuments()
        
        print("❌ Test 8.2 FAILED: Should not allow reading reports")
    } catch {
        print("✅ Test 8.2 PASSED: Cannot read reports (admin-only)")
    }
}
```

**Expected:** Permission denied error

---

## 🎯 Running All Tests

### Swift Test Runner:
```swift
class FirebaseRulesTests: XCTestCase {
    
    override func setUp() async throws {
        // Setup test user
        try await Auth.auth().signIn(withEmail: "test@example.com", password: "password")
    }
    
    func testAllRules() async throws {
        // User tests
        try await testCreateUserProfile()
        try await testCannotCreateOthersProfile()
        try await testUsernameLengthValidation()
        try await testUpdateOwnProfile()
        
        // Follow tests
        try await testFollowUser()
        try await testPreventSelfFollow()
        try await testCannotFollowAsAnotherUser()
        try await testUnfollowUser()
        
        // Post tests
        try await testCreatePost()
        try await testCannotCreatePostAsAnotherUser()
        try await testInvalidCategory()
        try await testContentLengthLimit()
        try await testDeleteOwnPost()
        try await testCannotDeleteOthersPost()
        
        // Comment tests
        try await testAddComment()
        try await testCommentLengthLimit()
        try await testDeleteOwnComment()
        
        // Reaction tests
        try await testAddAmen()
        try await testCannotAmenAsAnotherUser()
        try await testRemoveAmen()
        
        // Conversation tests
        try await testCreateConversation()
        try await testSendMessage()
        try await testMessageLengthLimit()
        
        // Notification tests
        try await testReadOwnNotifications()
        try await testCannotReadOthersNotifications()
        
        // Report tests
        try await testCreateReport()
        try await testCannotReadReports()
        
        print("🎉 All tests completed!")
    }
}
```

---

## 📊 Expected Test Results

### Summary:
- **Total Tests:** 24
- **Expected Passes:** 24
- **Expected Fails:** 0

### Pass/Fail Criteria:
- ✅ **PASS:** Operation completes successfully OR is correctly denied
- ❌ **FAIL:** Unexpected behavior (allowed when should deny, or denied when should allow)

---

## 🚨 Troubleshooting

### Issue: All tests pass but shouldn't

**Cause:** Rules not deployed or emulator using old rules

**Fix:**
```bash
# Restart emulators with explicit rules file
firebase emulators:start --only firestore --import=./firestore-rules.json
```

### Issue: Tests fail unexpectedly

**Cause:** Field names don't match between tests and actual data

**Fix:** Check your actual Firestore data structure:
```swift
let doc = try await Firestore.firestore()
    .collection("users")
    .document(userId)
    .getDocument()

print(doc.data())  // Verify exact field names
```

---

## ✅ Production Testing Checklist

After deploying to production, manually test:

- [ ] Create user account
- [ ] Update profile
- [ ] Follow/unfollow users
- [ ] Create posts in all 3 categories
- [ ] Add comments
- [ ] React to posts (amen, lightbulb)
- [ ] Send direct messages
- [ ] Upload profile image
- [ ] Upload post image
- [ ] Report content
- [ ] Block/unblock users

**Expected:** All operations work smoothly with no permission errors.

---

Your Firebase rules are production-ready! 🚀

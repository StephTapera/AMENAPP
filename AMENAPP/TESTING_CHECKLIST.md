# 🧪 Security Rules Testing Checklist

## Quick Test After Deployment

Use this checklist to verify your rules are working correctly.

---

## ✅ Test Suite A: Messaging (CRITICAL)

### Test 1.1: Create New Conversation
```
Steps:
1. Open Messages tab
2. Tap + to create new conversation
3. Select a user
4. Send first message

Expected: ✅ Conversation created, message sent
Actual: _____________

Status: ☐ Pass  ☐ Fail
```

### Test 1.2: Send Message in Existing Conversation
```
Steps:
1. Open existing conversation
2. Type a message
3. Tap send

Expected: ✅ Message appears immediately
Actual: _____________

Status: ☐ Pass  ☐ Fail
```

### Test 1.3: Read Messages
```
Steps:
1. Open any conversation you're in
2. Scroll through messages

Expected: ✅ All messages load
Actual: _____________

Status: ☐ Pass  ☐ Fail
```

### Test 1.4: Delete Own Message
```
Steps:
1. Long press your own message
2. Select "Delete"

Expected: ✅ Message deleted
Actual: _____________

Status: ☐ Pass  ☐ Fail
```

---

## ✅ Test Suite B: Social Features

### Test 2.1: Follow User
```
Steps:
1. Go to any user's profile
2. Tap "Follow" button
3. Check follower count

Expected: ✅ Followed, count updates
Actual: _____________

Status: ☐ Pass  ☐ Fail
```

### Test 2.2: Unfollow User
```
Steps:
1. Go to followed user's profile
2. Tap "Unfollow" button
3. Check follower count

Expected: ✅ Unfollowed, count updates
Actual: _____________

Status: ☐ Pass  ☐ Fail
```

### Test 2.3: View Followers List
```
Steps:
1. Go to your profile
2. Tap followers count
3. View list

Expected: ✅ Followers list loads
Actual: _____________

Status: ☐ Pass  ☐ Fail
```

---

## ✅ Test Suite C: Posts & Comments

### Test 3.1: Create Post
```
Steps:
1. Tap + to create post
2. Write content (under 10,000 chars)
3. Tap Post

Expected: ✅ Post published
Actual: _____________

Status: ☐ Pass  ☐ Fail
```

### Test 3.2: Edit Own Post
```
Steps:
1. Go to your post
2. Tap edit (•••) 
3. Make changes
4. Save

Expected: ✅ Post updated
Actual: _____________

Status: ☐ Pass  ☐ Fail
```

### Test 3.3: Delete Own Post
```
Steps:
1. Go to your post
2. Tap delete (•••)
3. Confirm

Expected: ✅ Post deleted
Actual: _____________

Status: ☐ Pass  ☐ Fail
```

### Test 3.4: Comment on Post
```
Steps:
1. Open any post
2. Tap comment button
3. Write comment (under 2,000 chars)
4. Tap send

Expected: ✅ Comment posted
Actual: _____________

Status: ☐ Pass  ☐ Fail
```

### Test 3.5: Like Post
```
Steps:
1. Tap ❤️ on any post
2. Check like count

Expected: ✅ Like registered, count updates
Actual: _____________

Status: ☐ Pass  ☐ Fail
```

---

## ✅ Test Suite D: Profile & Images

### Test 4.1: Update Profile
```
Steps:
1. Go to profile
2. Tap edit
3. Change bio/name
4. Save

Expected: ✅ Profile updated
Actual: _____________

Status: ☐ Pass  ☐ Fail
```

### Test 4.2: Upload Profile Picture
```
Steps:
1. Go to profile
2. Tap profile picture
3. Select new image (under 10MB)
4. Save

Expected: ✅ Image uploaded
Actual: _____________

Status: ☐ Pass  ☐ Fail
```

### Test 4.3: Upload Post Image
```
Steps:
1. Create new post
2. Add image (under 10MB)
3. Post

Expected: ✅ Image attached to post
Actual: _____________

Status: ☐ Pass  ☐ Fail
```

---

## ✅ Test Suite E: Prayers & Testimonies

### Test 5.1: Create Prayer Request
```
Steps:
1. Go to Prayer tab
2. Tap + to create prayer
3. Write request (under 5,000 chars)
4. Submit

Expected: ✅ Prayer posted
Actual: _____________

Status: ☐ Pass  ☐ Fail
```

### Test 5.2: Support Prayer
```
Steps:
1. View any prayer
2. Tap support/pray button

Expected: ✅ Support registered
Actual: _____________

Status: ☐ Pass  ☐ Fail
```

### Test 5.3: Create Testimony
```
Steps:
1. Go to Testimonies tab
2. Tap + to create testimony
3. Write content (under 10,000 chars)
4. Submit

Expected: ✅ Testimony posted
Actual: _____________

Status: ☐ Pass  ☐ Fail
```

---

## ❌ Test Suite F: Security Validation (Should FAIL)

### Test 6.1: Manually Change Follower Count (Should Fail)
```
Console Command (Run in Xcode console or Firebase Console):
```swift
// This should be REJECTED by security rules
db.collection("users").document(currentUserId).updateData([
    "followersCount": 999999
])
```

Expected: ❌ Permission denied error
Actual: _____________

Status: ☐ Correctly blocked  ☐ SECURITY ISSUE!
```

### Test 6.2: Try to Read Someone Else's Messages (Should Fail)
```
Console Command:
```swift
// Get a conversation ID you're NOT in
let someOtherConvId = "..." // Not your conversation
db.collection("conversations")
  .document(someOtherConvId)
  .collection("messages")
  .getDocuments { snapshot, error in
    print("Error: \(error)")  // Should show permission denied
  }
```

Expected: ❌ Permission denied error
Actual: _____________

Status: ☐ Correctly blocked  ☐ SECURITY ISSUE!
```

---

## 📊 Test Results Summary

```
Total Tests: 21
Passed: _____ / 21
Failed: _____ / 21

Security Tests (Should Fail):
Correctly Blocked: _____ / 2
Security Issues: _____ / 2

Overall Grade:
☐ ✅ All tests passed - Ready for production
☐ ⚠️ Some tests failed - Needs investigation
☐ ❌ Security issues found - DO NOT DEPLOY

Date Tested: ___________
Tested By: ___________
App Version: ___________
```

---

## 🔍 Common Error Messages (and what they mean)

### ✅ Expected Errors (Good!):

```
"Missing or insufficient permissions"
→ Security rules working correctly
→ User tried unauthorized action
```

```
"Permission denied"
→ Security rules blocked invalid operation
→ Check if user is authenticated and authorized
```

### ❌ Unexpected Errors (Bad!):

```
"auth/user-not-found"
→ User not logged in
→ Check authentication state
```

```
"storage/unauthorized"
→ File upload issue
→ Check file size/type/path
```

```
"firestore/unavailable"
→ Network issue
→ Check internet connection
```

---

## 🐛 Debugging Failed Tests

### If Test Fails, Check:

1. **Is user logged in?**
   ```swift
   print("Current User: \(Auth.auth().currentUser?.uid ?? "Not logged in")")
   ```

2. **Check Firebase Console logs:**
   - Go to Firestore → Rules → View Logs
   - Look for specific rule violations

3. **Verify field names match rules:**
   - Check that you're using correct field names
   - e.g., `participantIds` not `participants`

4. **Check data types:**
   - Ensure arrays are arrays, strings are strings
   - e.g., `participantIds: [String]` not `String`

5. **Verify you're using correct IDs:**
   ```swift
   let myId = Auth.auth().currentUser?.uid
   print("My ID: \(myId)")
   print("Sender ID: \(message.senderId)")
   print("Match? \(myId == message.senderId)")
   ```

---

## 📱 Testing in Xcode Console

### Enable Verbose Logging:

Add to your AppDelegate or main app file:
```swift
import FirebaseFirestore

// In application(_:didFinishLaunchingWithOptions:)
let settings = FirestoreSettings()
settings.isPersistenceEnabled = true
Firestore.firestore().settings = settings

// Enable debug logging
FirebaseConfiguration.shared.setLoggerLevel(.debug)
```

### Useful Debug Prints:

```swift
// Before sending message
print("📤 Attempting to send message:")
print("  Conversation ID: \(conversationId)")
print("  Sender ID: \(senderId)")
print("  Current User ID: \(Auth.auth().currentUser?.uid ?? "nil")")
print("  Participant IDs: \(participantIds)")

// After operation
print("✅ Message sent successfully")
// OR
print("❌ Error: \(error.localizedDescription)")
```

---

## 🎯 Priority Test Order

If you have limited time, test in this order:

1. **Critical** (Must work):
   - [ ] Test 1.1: Create conversation
   - [ ] Test 1.2: Send message
   - [ ] Test 3.1: Create post
   - [ ] Test 4.1: Update profile

2. **High** (Should work):
   - [ ] Test 2.1: Follow user
   - [ ] Test 3.4: Comment on post
   - [ ] Test 4.2: Upload profile picture

3. **Medium** (Nice to verify):
   - [ ] Test 3.5: Like post
   - [ ] Test 5.1: Create prayer
   - [ ] Test 5.3: Create testimony

4. **Security** (Must be blocked):
   - [ ] Test 6.1: Try to manipulate counts
   - [ ] Test 6.2: Try to read private data

---

## ✅ Sign-Off

```
I have tested the Firebase security rules and confirm:

☐ All messaging features work correctly
☐ All social features work correctly
☐ All post/comment features work correctly
☐ Profile and image uploads work correctly
☐ Security tests correctly block unauthorized actions
☐ No permission denied errors on valid operations
☐ App is ready for production deployment

Signature: ___________________
Date: ___________________
```

---

## 📞 Support

If tests fail:
1. Check `DEPLOY_RULES_NOW.md` for troubleshooting
2. Review `SECURITY_ARCHITECTURE.md` for understanding rules
3. Check Firebase Console logs for specific errors
4. Verify rules were published (not just saved)

**Firebase Console:** https://console.firebase.google.com

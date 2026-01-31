# 🧪 Messaging Testing Guide

## Quick Test Plan

### Test 1: Basic Conversation Creation ✅
**Steps:**
1. Tap "New Message" button (pencil icon)
2. Search for and select a user you follow mutually
3. Verify: ChatView opens immediately
4. Type a message and tap send
5. Verify: Message appears in chat
6. Go back to Messages list
7. Verify: Conversation appears with correct last message

**Expected:**
- ✅ ChatView opens without delay
- ✅ Message sends successfully
- ✅ Conversation appears in list

### Test 2: Message Request Flow ✅
**Steps:**
1. Have User A (not following User B) message User B
2. On User A's device:
   - Find User B in search
   - Send first message
   - Verify: Can send 1 message
   - Try sending second message
   - Verify: Error shown about message request limit
3. On User B's device:
   - Switch to "Requests" tab
   - Verify: Request from User A appears
   - Tap on request
   - Verify: Can view the message
   - Tap "Accept"
4. On User A's device:
   - Verify: Can now send unlimited messages

**Expected:**
- ✅ 1-message limit enforced for non-followers
- ✅ Request appears in recipient's Requests tab
- ✅ After acceptance, unlimited messaging works

### Test 3: Privacy Settings ✅
**Steps:**
1. User B sets privacy to "Followers only"
2. User A (not following User B) tries to message
3. Verify: Request is created (pending status)
4. User B changes privacy to "Anyone"
5. User C (not following) messages User B
6. Verify: Message goes through immediately

**Expected:**
- ✅ Followers-only creates pending request
- ✅ Anyone allows immediate messaging

### Test 4: Blocking ✅
**Steps:**
1. User A blocks User B
2. User A tries to message User B
3. Verify: Error shown "Cannot message this user"
4. User B tries to message User A
5. Verify: Error shown "Cannot message this user"
6. User A unblocks User B
7. Verify: Both can message again

**Expected:**
- ✅ Blocked users cannot send messages
- ✅ Users who blocked you cannot receive messages
- ✅ Unblocking restores messaging

### Test 5: Conversation Features ✅
**Steps:**
1. Open a conversation
2. Long-press on conversation
3. Tap "Mute"
4. Verify: Notification muted indicator appears
5. Tap "Pin"  
6. Verify: Conversation moves to top
7. Tap "Archive"
8. Verify: Conversation moves to Archived tab
9. In Archived tab, tap conversation
10. Select "Unarchive"
11. Verify: Returns to Messages tab

**Expected:**
- ✅ Mute works
- ✅ Pin moves to top
- ✅ Archive/Unarchive works

### Test 6: Real-time Updates ✅
**Steps:**
1. Have 2 devices logged in as different users
2. Start a conversation
3. Send messages from Device A
4. Verify: Messages appear immediately on Device B
5. Send messages from Device B
6. Verify: Messages appear immediately on Device A
7. Start typing on Device A
8. Verify: "Typing..." indicator appears on Device B

**Expected:**
- ✅ Messages sync in real-time
- ✅ Typing indicators work
- ✅ Read receipts update

### Test 7: Offline Mode ✅
**Steps:**
1. Turn on Airplane Mode
2. Open Messages
3. Verify: Cached conversations load
4. Open a conversation
5. Verify: Cached messages load
6. Try to send a message
7. Verify: Message queued (or error shown)
8. Turn off Airplane Mode
9. Verify: Messages sync

**Expected:**
- ✅ Offline data loads from cache
- ✅ When online, data syncs

### Test 8: Error Handling ✅
**Steps:**
1. Try to message yourself
2. Verify: Error shown "Cannot create conversation with yourself"
3. Message a user who doesn't exist
4. Verify: Appropriate error shown
5. Try messaging with no internet
6. Verify: User-friendly error shown

**Expected:**
- ✅ All errors show user-friendly messages
- ✅ No silent failures

## Debug Checklist

### If ChatView Doesn't Open:

**Check Console Logs:**
```
========================================
🚀 START CONVERSATION DEBUG
========================================
```

Look for:
- ✅ "Step 1: Calling getOrCreateDirectConversation..."
- ✅ "Step 2: Got conversation ID: xxx"
- ✅ "Step 4: Dismissing search sheet..."
- ✅ "Step 7a: Found existing conversation" OR "Step 7b: Creating temporary"
- ✅ "Set showChatView = true"

**Common Issues:**
1. ❌ Error at Step 1: Check Firebase authentication
2. ❌ Error at Step 2: Check network/Firestore connection
3. ❌ showChatView stays false: Check sheet modifier bindings

**Quick Fix:**
```swift
// In MessagesView, verify the ChatSheetModifier is applied:
.modifier(ChatSheetModifier(
    showChatView: $showChatView,
    selectedConversation: $selectedConversation
))
```

### If Messages Don't Send:

**Check Console Logs:**
```
Looking for:
✅ "📝 Sending message to conversation: xxx"
✅ "✅ Message sent successfully"
OR
❌ "❌ Error sending message: xxx"
```

**Common Issues:**
1. Permission denied → Check Firestore security rules
2. Network error → Check internet connection
3. User blocked → Verify block status

### If Message Requests Don't Work:

**Check:**
1. Conversation status is "pending" in Firestore
2. `requesterId` field is set correctly
3. User is checking Requests tab (not Messages tab)
4. Real-time listener is active

**Console Logs:**
```
✅ "Loaded X message requests"
✅ "Real-time update: X pending"
```

## Performance Metrics

**Target Metrics:**
- Conversation list load: < 1 second
- Message send: < 500ms
- Real-time message receive: < 200ms
- ChatView open: < 300ms
- Search results: < 800ms

**Monitor For:**
- Memory leaks (listeners not cleaned up)
- Duplicate listeners
- Excessive network calls
- Large attachment uploads

## Firestore Queries to Monitor

**Check Firestore Console:**

1. **Active Conversations:**
```javascript
conversations
  .where('participantIds', 'array-contains', currentUserId)
  .orderBy('updatedAt', 'desc')
```

2. **Pending Requests:**
```javascript
conversations
  .where('participantIds', 'array-contains', currentUserId)
  .where('conversationStatus', '==', 'pending')
```

3. **Messages in Conversation:**
```javascript
conversations/{conversationId}/messages
  .orderBy('timestamp', 'desc')
  .limit(50)
```

## Security Validation

**Test These Scenarios:**

1. ✅ User cannot read conversations they're not in
2. ✅ User cannot send messages to conversations they're not in
3. ✅ User cannot delete other users' messages
4. ✅ User cannot modify other users' block lists
5. ✅ Blocked users cannot bypass blocks

**How to Test:**
Use Firebase Console to try accessing data with different user IDs.

## Common Error Messages

### User-Facing Errors:
- ❌ "You must be logged in to send messages"
  - **Fix:** User needs to authenticate

- ❌ "You cannot message this user"
  - **Fix:** Either blocked or permission denied

- ❌ "Message request already sent. Wait for them to follow you back."
  - **Fix:** This is correct behavior - limit enforced

- ❌ "Failed to send message. Please check your connection and try again."
  - **Fix:** Check internet connection

### Developer Errors (Console):
- ❌ "Type 'UserService' has no member 'shared'"
  - **Fixed:** Now using `UserServiceExtensions.shared`

- ❌ "Cannot find 'checkIfBlocked' in scope"
  - **Fixed:** Extension method added to FirebaseMessagingService

- ❌ "Cannot find type 'ConversationService'"
  - **Fixed:** Changed to FirebaseMessagingService

- ❌ "Cannot find type 'BlockService'"
  - **Fixed:** BlockService class created

## Load Testing

**Recommended Tests:**
1. Create 100+ conversations → Verify smooth scrolling
2. Load conversation with 1000+ messages → Check pagination
3. Send 10 messages rapidly → Verify all send
4. Have 5+ users typing simultaneously → Check indicators
5. Receive 50+ messages while offline → Verify sync on reconnect

## Final Verification Checklist

Before going to production:

### Code Quality ✅
- [x] All compiler errors fixed
- [x] All warnings resolved
- [x] No force unwraps in production code
- [x] Proper error handling everywhere
- [x] Console logs informative but not excessive

### Functionality ✅
- [x] Can create conversations
- [x] Can send/receive messages
- [x] Message requests work
- [x] Blocking works
- [x] Privacy settings work
- [x] Mute/Pin/Archive work
- [x] Real-time updates work
- [x] Offline mode works

### User Experience ✅
- [x] ChatView opens quickly
- [x] No crashes or freezes
- [x] Error messages are clear
- [x] Animations are smooth
- [x] Loading states shown
- [x] Empty states handled

### Security ✅
- [x] Firestore rules deployed
- [x] User can't access others' data
- [x] Block list is private
- [x] Messages are private to participants

### Performance ✅
- [x] Queries are indexed
- [x] Pagination implemented
- [x] Listeners cleaned up
- [x] Images optimized
- [x] Caching working

## Ship It! 🚀

Once all tests pass, you're ready to ship! 

**Final Steps:**
1. Test on real devices (not just simulator)
2. Test with slow network
3. Test with multiple users
4. Verify Firestore security rules in production
5. Monitor error logs after release
6. Have rollback plan ready

Good luck! 🎉

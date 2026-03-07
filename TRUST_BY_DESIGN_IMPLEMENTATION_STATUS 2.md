# Trust-by-Design Messaging & Contact Controls - Implementation Status

## ✅ COMPLETED

### 1. Core Service & Models
- ✅ `TrustByDesignMessagingControls.swift` - Main service (478 lines)
  - Permission levels (DM, Comment, Mention)
  - Quiet block actions
  - Anti-harassment detection
  - **Build: Success** - All type conflicts resolved

### 2. UI Components  
- ✅ `PrivacyControlsSettingsView.swift` - Settings UI (210 lines)
- ✅ `MessageRequestsView.swift` - Requests inbox (275 lines)
- ✅ `PostCommentControlsSheet.swift` - Per-post controls (107 lines)
- ✅ `QuietBlockActionsMenu.swift` - Block/mute menu (188 lines)

### 3. Type Definitions
- ✅ `TrustPrivacySettings` - User privacy preferences (renamed to avoid conflict)
- ✅ `DMPermissionLevel` - Everyone/Followers/Mutuals/Nobody
- ✅ `CommentPermissionLevel` - Same 4 levels
- ✅ `MentionPermissionLevel` - Same 4 levels
- ✅ `QuietBlockAction` - Block/Mute/Restrict/HideReplies/LimitMentions
- ✅ `QuietBlockRecord` - Firestore records
- ✅ `RepeatedContactAttempt` - Anti-harassment tracking

---

## 🔄 IN PROGRESS

### Integration into Existing Services

**What remains:**

#### A. MessageService.swift Integration
```swift
// NEEDED: Before sending message
let canSend = try await TrustByDesignService.shared.canSendDM(
    from: senderId, 
    to: recipientId
)

if !canSend {
    // Create message request instead of direct conversation
    try await TrustByDesignService.shared.createMessageRequest(
        from: senderId,
        to: recipientId,
        initialMessage: messageText
    )
    return
}
```

#### B. CommentService.swift Integration
```swift
// NEEDED: Before posting comment
let canComment = try await TrustByDesignService.shared.canComment(
    userId: commenterId,
    on: postId,
    authorId: postAuthorId,
    postPermission: post.commentPermission  // From post model
)

if !canComment {
    // Show error: "The author has limited who can comment"
    return
}
```

#### C. Mention Processing
```swift
// NEEDED: When processing @mentions in posts/comments
for username in extractedMentions {
    let userId = await getUserId(for: username)
    let canMention = try await TrustByDesignService.shared.canMention(
        from: authorId,
        mention: userId
    )
    
    if !canMention {
        // Skip this mention, don't create notification
        continue
    }
}
```

---

## 📋 TODO

### 1. Add UI Links (15 minutes)

**A. Account Settings**
Location: `AccountSettingsView.swift`
```swift
// Add after existing privacy sections
Section {
    NavigationLink("Privacy & Contact Controls") {
        PrivacyControlsSettingsView()
    }
} header: {
    Text("TRUST & SAFETY")
}
```

**B. Messages Tab**
Location: `MessagesView.swift`
```swift
// Add button in navigation bar
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        NavigationLink {
            MessageRequestsView()
        } label: {
            HStack {
                Text("Requests")
                if trustService.unreadRequestCount > 0 {
                    Text("\(trustService.unreadRequestCount)")
                        .font(.caption)
                        .padding(4)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
            }
        }
    }
}
```

**C. Create Post Flow**
Location: `CreatePostView.swift`
```swift
// Add comment control picker
@State private var commentPermission: CommentPermissionLevel = .everyone
@State private var showCommentControls = false

// In post composer
Button("Comment Controls") {
    showCommentControls = true
}
.sheet(isPresented: $showCommentControls) {
    PostCommentControlsSheet(selectedPermission: $commentPermission)
}

// Save with post
let post = Post(
    // ... existing fields
    commentPermission: commentPermission.rawValue
)
```

**D. User Profile Menu**
Location: `ProfileView.swift` or `UserProfileView.swift`
```swift
// Add to user actions menu
Button {
    showBlockMenu = true
} label: {
    Label("Manage User", systemImage: "hand.raised")
}
.sheet(isPresented: $showBlockMenu) {
    QuietBlockActionsMenu(
        targetUserId: userId,
        targetUsername: username
    )
}
```

---

### 2. Firestore Rules (30 minutes)

**File:** `firestore 18.rules`

```javascript
// Add privacy permission enforcement

// User privacy settings
match /user_privacy_settings/{userId} {
  allow read: if request.auth != null;
  allow write: if request.auth.uid == userId;
}

// Quiet blocks
match /quiet_blocks/{blockId} {
  allow read: if request.auth.uid == resource.data.userId;
  allow write: if request.auth.uid == request.resource.data.userId;
}

// Repeated contact attempts
match /repeated_contact_attempts/{attemptId} {
  allow read: if request.auth.uid == resource.data.targetUserId;
  allow write: if request.auth != null;
}

// Conversations - enforce pending status for requests
match /conversations/{conversationId} {
  allow read: if request.auth.uid in resource.data.participants;
  
  allow create: if request.auth.uid in request.resource.data.participants
    && (
      // Either direct conversation if allowed
      canSendDirectMessage(request.auth.uid, getOtherParticipant())
      // Or message request (pending status)
      || request.resource.data.conversationStatus == "pending"
    );
  
  allow update: if request.auth.uid in resource.data.participants;
}

// Helper functions
function canSendDirectMessage(fromId, toId) {
  let settings = get(/databases/$(database)/documents/user_privacy_settings/$(toId)).data;
  let level = settings.dmPermissionLevel;
  
  return level == "everyone"
    || (level == "followers_only" && isFollower(fromId, toId))
    || (level == "mutuals_only" && areMutuals(fromId, toId));
}

function isFollower(followerId, followingId) {
  return exists(/databases/$(database)/documents/follows/$(followerId + "_" + followingId));
}

function areMutuals(user1, user2) {
  return isFollower(user1, user2) && isFollower(user2, user1);
}

function getOtherParticipant() {
  let participants = request.resource.data.participants;
  return participants[0] == request.auth.uid ? participants[1] : participants[0];
}
```

---

### 3. Firestore Indexes (5 minutes)

**File:** `firestore.indexes.json`

Add these indexes:
```json
{
  "collectionGroup": "user_privacy_settings",
  "queryScope": "COLLECTION",
  "fields": [
    {"fieldPath": "userId", "order": "ASCENDING"}
  ]
},
{
  "collectionGroup": "quiet_blocks",
  "queryScope": "COLLECTION",
  "fields": [
    {"fieldPath": "userId", "order": "ASCENDING"},
    {"fieldPath": "targetUserId", "order": "ASCENDING"},
    {"fieldPath": "action", "order": "ASCENDING"}
  ]
},
{
  "collectionGroup": "repeated_contact_attempts",
  "queryScope": "COLLECTION",
  "fields": [
    {"fieldPath": "targetUserId", "order": "ASCENDING"},
    {"fieldPath": "fromUserId", "order": "ASCENDING"}
  ]
},
{
  "collectionGroup": "conversations",
  "queryScope": "COLLECTION",
  "fields": [
    {"fieldPath": "participants", "arrayConfig": "CONTAINS"},
    {"fieldPath": "conversationStatus", "order": "ASCENDING"},
    {"fieldPath": "createdAt", "order": "DESCENDING"}
  ]
}
```

Deploy with:
```bash
firebase deploy --only firestore:indexes,firestore:rules
```

---

## 🎯 Conservative Defaults Applied

New users automatically get:
- ✅ DMs: **Mutuals Only**
- ✅ Mentions: **Followers Only**
- ✅ Comments: **Everyone** (can change per-post)
- ✅ Hide links in requests: **ON**
- ✅ Hide media in requests: **ON**
- ✅ Block repeated attempts: **ON**
- ✅ Auto-restrict after 3 reports: **ON**

---

## 📊 Firestore Collections

| Collection | Purpose | Indexed |
|------------|---------|---------|
| `user_privacy_settings` | User privacy preferences | ✅ userId |
| `quiet_blocks` | Block/mute/restrict records | ✅ userId + targetUserId + action |
| `repeated_contact_attempts` | Anti-harassment tracking | ✅ targetUserId + fromUserId |
| `conversations` (updated) | Now supports "pending" status for requests | ✅ participants + status + createdAt |

---

## 🚀 Deployment Checklist

- [x] Core service implementation
- [x] UI components created
- [x] Build errors resolved
- [ ] Integrate into MessageService
- [ ] Integrate into CommentService
- [ ] Add mention permission checks
- [ ] Add UI navigation links
- [ ] Update firestore 18.rules
- [ ] Add Firestore indexes
- [ ] Deploy rules & indexes
- [ ] Test DM permissions
- [ ] Test comment controls
- [ ] Test message requests
- [ ] Test quiet block actions

---

## 📝 Testing Script

```
1. Enable conservative privacy settings for test user
2. Try to send DM from non-mutual → Should create request
3. Accept request → Conversation becomes "accepted"
4. Create post with "Mutuals Only" comments
5. Try to comment from non-mutual → Should be blocked
6. Try to @mention user with "Followers Only" setting
7. Block user → They can't see/contact you
8. Mute user → Their content hidden
9. Restrict user → Comments shadowbanned
10. Test repeated contact auto-block (3 attempts)
```

---

## ✨ Impact

**Prevents abuse before it starts:**
- No unwanted DMs (message requests only)
- No spam comments (permission levels)
- No mention harassment (permission controls)
- Quiet moderation tools (restrict/hide without confrontation)
- Automatic protection (repeated contact detection)

**All without changing existing designs** - Pure additive features.

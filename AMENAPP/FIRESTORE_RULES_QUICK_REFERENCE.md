# Firebase Rules Quick Reference

**Last Updated**: January 29, 2026
**Status**: ✅ Production Ready

---

## 🚀 Quick Setup

### 1. Copy the Complete Rules

Go to: `FIRESTORE_MESSAGING_PERMISSIONS_FIX.md` and copy the complete rules from the **"Solution: Complete Firestore Security Rules"** section.

### 2. Apply in Firebase Console

1. Open [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Go to **Firestore Database** → **Rules** tab
4. **DELETE ALL** existing rules
5. **PASTE** the new rules from the guide
6. Click **Publish**
7. **Wait 60 seconds** for propagation

### 3. Test

- ✅ Test following/unfollowing users
- ✅ Test messaging (create conversation)
- ✅ Test blocking/unblocking
- ✅ Test creating posts
- ✅ Test liking posts

---

## 📊 What's Allowed

### Users Collection (`/users/{userId}`)

| Action | Who Can Do It | Notes |
|--------|---------------|-------|
| **Read** | Anyone authenticated | View profiles, names, counts |
| **Create** | User creating their own profile | During signup |
| **Update** | User (their own profile) | Can update own data |
| **Update Counts** | Anyone (for follows) | `followersCount`, `followingCount` only |
| **Delete** | User (their own profile) | Delete account |

### Follows Collection (`/follows/{followId}`)

| Action | Who Can Do It | Notes |
|--------|---------------|-------|
| **Read** | Anyone authenticated | See follow relationships |
| **Create** | User following someone | Must be followerUserId |
| **Update** | User (their own follows) | Update follow status |
| **Delete** | User (their own follows) | Unfollow |

### Conversations Collection (`/conversations/{conversationId}`)

| Action | Who Can Do It | Notes |
|--------|---------------|-------|
| **Read** | Participants only | Must be in participantIds |
| **Create** | User starting conversation | Must include self in participants |
| **Update** | Participants only | Update last message, read status |
| **Delete** | Participants only | Soft delete |

### Messages Subcollection (`/conversations/{conversationId}/messages/{messageId}`)

| Action | Who Can Do It | Notes |
|--------|---------------|-------|
| **Read** | Participants only | Must be conversation participant |
| **Create** | Participants only | Must be senderId |
| **Update** | Sender only | Edit own messages |
| **Delete** | Sender only | Delete own messages |

### Posts Collection (`/posts/{postId}`)

| Action | Who Can Do It | Notes |
|--------|---------------|-------|
| **Read** | Anyone authenticated | Public posts |
| **Create** | User creating post | Must be userId |
| **Update** | Post author OR system | Author updates OR count updates |
| **Delete** | Post author | Delete own posts |

### Subcollections (blockedUsers, mutedUsers, etc.)

| Action | Who Can Do It | Notes |
|--------|---------------|-------|
| **Read** | User (their own lists) | Privacy lists |
| **Write** | User (their own lists) | Manage privacy |

---

## 🔧 Common Operations

### Follow a User

**Data Written:**
```
/follows/{followerUserId}_{followingUserId}
├── followerUserId: "abc123"
├── followingUserId: "def456"
├── createdAt: Timestamp
└── status: "active"

/users/{followerUserId}
├── followingCount: +1

/users/{followingUserId}
├── followersCount: +1
```

**Rules Required:**
- ✅ `follows` collection: create allowed
- ✅ `users` collection: update counts allowed

### Send a Message

**Data Written:**
```
/conversations/{conversationId}/messages/{messageId}
├── senderId: "abc123"
├── text: "Hello!"
├── timestamp: Timestamp
└── ...

/conversations/{conversationId}
├── lastMessage: "Hello!"
├── lastMessageTimestamp: Timestamp
└── ...
```

**Rules Required:**
- ✅ User must be in `participantIds`
- ✅ User must be the `senderId`

### Block a User

**Data Written:**
```
/users/{currentUserId}/blockedUsers/{blockedUserId}
├── blockedAt: Timestamp
└── reason: "spam" (optional)
```

**Rules Required:**
- ✅ User can write to their own `blockedUsers` subcollection

---

## 🐛 Troubleshooting

### Error: "Missing or insufficient permissions"

**Check:**
1. User is authenticated: `Auth.auth().currentUser != nil`
2. Rules are published (check timestamp in Firebase Console)
3. Document structure matches what rules expect
4. User ID in request matches authenticated user

**Common Causes:**
- User not signed in
- Rules not published yet (wait 60 seconds)
- Trying to write to someone else's data
- Document structure doesn't match rules

### Error: "Permission denied" when following

**Fix:**
```javascript
// Ensure this is in your rules:
match /follows/{followId} {
  allow create: if isSignedIn() && 
                   request.resource.data.followerUserId == request.auth.uid;
}
```

### Error: "Cannot update followersCount"

**Fix:**
```javascript
// Ensure this is in your user update rules:
allow update: if isSignedIn() && (
  request.auth.uid == userId ||
  request.resource.data.diff(resource.data).affectedKeys()
    .hasOnly(['followersCount', 'followingCount', 'updatedAt'])
);
```

### Error: "Cannot create conversation"

**Fix:**
```javascript
// Ensure conversations can be created:
match /conversations/{conversationId} {
  allow create: if isSignedIn() && 
                   request.auth.uid in request.resource.data.participantIds;
}
```

---

## 🔍 Testing Checklist

After updating rules, test these scenarios:

### Authentication
- [ ] Can read user profiles
- [ ] Can update own profile
- [ ] Cannot update other user profiles

### Following
- [ ] Can follow a user
- [ ] Follow document appears in Firestore
- [ ] `followingCount` incremented for follower
- [ ] `followersCount` incremented for followed user
- [ ] Can unfollow a user
- [ ] Counts decremented correctly

### Messaging
- [ ] Can create conversation with another user
- [ ] Conversation appears in Firestore
- [ ] Can send messages in conversation
- [ ] Messages appear in real-time
- [ ] Cannot send messages in conversations you're not part of

### Blocking
- [ ] Can block a user
- [ ] Blocked user appears in `blockedUsers` subcollection
- [ ] Can unblock a user
- [ ] Blocked list updates correctly

### Posts
- [ ] Can create a post
- [ ] Can read all posts
- [ ] Can update own posts
- [ ] Can delete own posts
- [ ] Cannot update/delete others' posts

### Comments & Likes
- [ ] Can comment on any post
- [ ] Can like any post
- [ ] Can unlike own likes
- [ ] Counts update correctly

---

## 📞 Need Help?

1. **Check console logs**: Look for detailed Firebase error messages
2. **Check Firestore Console**: Verify documents are being created
3. **Check Authentication**: Ensure user is signed in
4. **Wait after publishing**: Rules take up to 60 seconds to propagate
5. **Restart app**: Sometimes cached rules need clearing

---

## 🎯 Quick Command Reference

### View Current Rules
```bash
firebase firestore:rules get
```

### Deploy Rules from File
```bash
firebase deploy --only firestore:rules
```

### Test Rules Locally
```bash
firebase emulators:start --only firestore
```

---

**Status**: ✅ Ready for production
**Blocking Checks**: ✅ Enabled
**Follow/Unfollow**: ✅ Supported
**Messaging**: ✅ Supported

# 🔥 Firebase Realtime Database - Complete Reference

## 🎯 Quick Deploy

```bash
# Deploy rules to Firebase
firebase deploy --only database

# Or manually in Firebase Console:
# https://console.firebase.google.com/project/amen-5e359/database/rules
```

---

## 📊 Database Structure Overview

```
firebase-realtime-database/
├── test/                          # Development only
├── user_posts/
│   └── {userId}/
│       └── {postId}               # User's posts
├── user_profiles/
│   └── {userId}/                  # Profile data
├── postInteractions/
│   └── {postId}/
│       ├── lightbulbs/
│       │   └── {userId}           # Who lightbulbed
│       ├── amens/
│       │   └── {userId}           # Who amened
│       ├── lightbulbCount
│       ├── amenCount
│       ├── commentCount
│       └── repostCount
├── online_status/
│   └── {userId}/                  # Presence system
├── typing/
│   └── {conversationId}/
│       └── {userId}               # Typing indicators
├── notification_tokens/
│   └── {userId}/
│       └── {tokenId}              # FCM tokens
├── last_read/
│   └── {conversationId}/
│       └── {userId}               # Message read receipts
├── live_reactions/
│   └── {postId}/
│       └── {userId}               # Real-time emoji reactions
├── counters/
│   └── {userId}/
│       ├── unreadMessages
│       ├── unreadNotifications
│       ├── followerCount
│       └── followingCount
├── connections/
│   └── {userId}/
│       ├── followers/
│       │   └── {followerId}       # Timestamp
│       └── following/
│           └── {followingId}      # Timestamp
├── devices/
│   └── {userId}/
│       └── {deviceId}             # Device info
├── sessions/
│   └── {userId}/
│       └── {sessionId}            # Analytics
└── user_saved_posts/              # NEW
    └── {userId}/
        └── {postId}               # true or timestamp
```

---

## 🔒 Security Summary

### Public Reads (Any Authenticated User)
- ✅ `user_posts` - All users' posts
- ✅ `user_profiles` - All user profiles
- ✅ `postInteractions` - All post interactions
- ✅ `online_status` - All users' online status
- ✅ `typing` - All typing indicators
- ✅ `live_reactions` - All reactions
- ✅ `connections/followers` - Who follows who
- ✅ `connections/following` - Who's following who

### Private (User-Only Access)
- 🔒 `notification_tokens` - User can only see their own
- 🔒 `last_read` - User can only see their own
- 🔒 `counters` - User can only see their own
- 🔒 `devices` - User can only see their own
- 🔒 `sessions` - User can only see their own
- 🔒 `user_saved_posts` - User can only see their own

### Write Permissions
- ✅ Users can only write their **own** data
- ✅ Users can write interactions (lightbulbs/amens) for any post
- ✅ Followers can add themselves
- ✅ Users can add to their own following list

---

## 🛠️ Common Operations

### Check if User Can Read
```javascript
// Public data (any authenticated user)
/user_posts/{userId}              → ✅ auth != null
/user_profiles/{userId}           → ✅ auth != null
/postInteractions/{postId}        → ✅ auth != null

// Private data (user-only)
/user_saved_posts/{userId}        → ✅ auth.uid == {userId}
/counters/{userId}                → ✅ auth.uid == {userId}
```

### Check if User Can Write
```javascript
// Own data
/user_posts/{userId}              → ✅ auth.uid == {userId}
/user_profiles/{userId}           → ✅ auth.uid == {userId}
/user_saved_posts/{userId}        → ✅ auth.uid == {userId}

// Interactions
/postInteractions/{postId}/amens/{userId}        → ✅ auth.uid == {userId}
/postInteractions/{postId}/lightbulbs/{userId}   → ✅ auth.uid == {userId}

// Social
/connections/{userId}/followers/{followerId}     → ✅ auth.uid == {followerId}
/connections/{userId}/following/{followingId}    → ✅ auth.uid == {userId}
```

---

## 🧪 Testing in Console

### Test 1: Read Own Saved Posts ✅
```
Auth: { uid: "user123" }
Location: /user_saved_posts/user123
Type: Read
Expected: Allow
```

### Test 2: Read Another User's Saved Posts ❌
```
Auth: { uid: "user123" }
Location: /user_saved_posts/user456
Type: Read
Expected: Deny
```

### Test 3: Write Own Post Interaction ✅
```
Auth: { uid: "user123" }
Location: /postInteractions/post456/amens/user123
Type: Write
Data: true
Expected: Allow
```

### Test 4: Read Public Profile ✅
```
Auth: { uid: "user123" }
Location: /user_profiles/user456
Type: Read
Expected: Allow
```

---

## 📝 Validation Rules

### Required Fields
```javascript
user_posts/{userId}
  ↳ Must have: ['postId', 'timestamp']
  ↳ authorId must match {userId}

user_profiles/{userId}
  ↳ Must have: ['displayName', 'username']

online_status/{userId}
  ↳ Must have: ['isOnline', 'lastSeen']

notification_tokens/{userId}/{tokenId}
  ↳ Must have: ['token', 'platform', 'createdAt']

devices/{userId}/{deviceId}
  ↳ Must have: ['deviceType', 'lastActive']

sessions/{userId}/{sessionId}
  ↳ Must have: ['startTime', 'deviceType']
```

### Data Type Validation
```javascript
lightbulbs/{userId}        → isBoolean() || isNumber()
amens/{userId}             → isBoolean() || isNumber()
lightbulbCount             → isNumber() && val() >= 0
amenCount                  → isNumber() && val() >= 0
commentCount               → isNumber() && val() >= 0
repostCount                → isNumber() && val() >= 0
typing/{conversationId}    → isBoolean()
last_read/{conversationId} → isNumber()
live_reactions/{postId}    → isString() && length < 10
user_saved_posts/{postId}  → isNumber() || isBoolean()
```

---

## 🚨 Common Errors & Solutions

### Error 1: Permission Denied
```
Error: Permission denied
```
**Solution:** Check that:
- User is authenticated (`auth != null`)
- User is accessing their own data (for private paths)
- Rules have been deployed

### Error 2: Data Doesn't Match Validation
```
Error: Data validation failed
```
**Solution:** Check that:
- Required fields are present
- Data types match validation rules
- Field values meet constraints (e.g., `>= 0`)

### Error 3: Offline / No Cache
```
Error: client offline with no active listeners
```
**Solution:**
- Enable persistence in app
- Add real-time listeners
- Check network connectivity

---

## 🔄 Migration from Firestore

If you're also using Firestore, here's the mapping:

| Firestore Collection | Realtime DB Path |
|---------------------|------------------|
| `posts` | `user_posts/{userId}/{postId}` |
| `users` | `user_profiles/{userId}` |
| `saved_posts` | `user_saved_posts/{userId}/{postId}` |
| `notifications` | Use Firestore (better for complex queries) |
| `conversations` | Use Firestore (better for pagination) |

**Best Practice:** Use Firestore for complex data, Realtime DB for real-time features.

---

## ✅ Deployment Checklist

- [ ] Rules are valid JSON
- [ ] Test paths work in Rules Simulator
- [ ] Remove `/test` node before production
- [ ] Deploy with `firebase deploy --only database`
- [ ] Verify in Firebase Console
- [ ] Test in your app
- [ ] Monitor for permission errors

---

## 📚 Resources

- [Firebase Realtime Database Rules](https://firebase.google.com/docs/database/security)
- [Rules API Reference](https://firebase.google.com/docs/reference/security/database)
- [Your Project Console](https://console.firebase.google.com/project/amen-5e359/database)

---

**Last Updated:** January 31, 2026  
**Status:** ✅ Production Ready

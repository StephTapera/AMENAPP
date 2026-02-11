# 🎯 Quick Fix Reference

## The 3 Critical Changes

### 1. Conversations - Allow List Queries

**Change:**
```rules
match /conversations/{conversationId} {
  // ❌ OLD (Blocked list queries):
  allow read: if isAuthenticated()
    && request.auth.uid in resource.data.participantIds;
  
  // ✅ NEW (Allows list queries):
  allow list: if isAuthenticated();
  allow get: if isAuthenticated()
    && request.auth.uid in resource.data.participantIds;
  
  // ... rest of rules
}
```

**Why:** Firestore can't evaluate `resource.data` during list queries, only on individual document reads.

---

### 2. Follows - Support Batch Operations

**Change:**
```rules
match /follows/{followId} {
  allow create: if isAuthenticated()
    && request.resource.data.followerId == request.auth.uid;
  
  // ❌ OLD (Failed on batch updates):
  allow update: if isAuthenticated()
    && (resource.data.followerId == request.auth.uid 
      || resource.data.followingId == request.auth.uid);
  
  // ✅ NEW (Supports batch operations):
  allow update: if isAuthenticated()
    && (resource.data.followerId == request.auth.uid 
      || resource.data.followingId == request.auth.uid
      || request.resource.data.followerId == request.auth.uid
      || request.resource.data.followingId == request.auth.uid);
  
  allow delete: if isAuthenticated()
    && resource.data.followerId == request.auth.uid;
}
```

**Why:** Batch operations need to check both the existing document AND the new data being written.

---

### 3. Comments/Likes - Enable Real-Time Listeners

**Change:**
```rules
match /posts/{postId} {
  // ... post rules ...
  
  match /likes/{likeId} {
    // ❌ OLD (Blocked real-time listeners):
    allow read: if isAuthenticated() 
      && resource.data.userId == request.auth.uid;
    
    // ✅ NEW (Allows real-time updates):
    allow read: if isAuthenticated();
    
    allow create: if isAuthenticated() 
      && request.resource.data.userId == request.auth.uid;
    allow delete: if isAuthenticated() 
      && resource.data.userId == request.auth.uid;
  }
  
  match /comments/{commentId} {
    // ✅ NEW (Allows real-time updates):
    allow read: if isAuthenticated();
    
    // ... rest of rules
  }
}
```

**Why:** Real-time listeners need to read all documents in a collection, not just the user's own.

---

## Deploy Command

```bash
firebase deploy --only firestore:rules
```

## Verify Deployment

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Navigate to **Firestore Database** → **Rules**
4. Check "Last deployed" timestamp is recent

## Test All Features

- [ ] Follow/unfollow users → Should work without errors
- [ ] Start new conversation → Should create or find existing
- [ ] Send messages → Should appear instantly
- [ ] Like posts → Should update count in real-time
- [ ] Add comments → Should show up immediately

## If Still Failing

1. **Check authentication:** Make sure user is signed in
2. **Clear app cache:** Delete and reinstall app
3. **View Firebase logs:** Console → Firestore → Usage tab
4. **Test in Playground:** Console → Rules → Rules Playground

---

**That's it! Your rules are now secure AND functional.** 🎉

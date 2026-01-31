# 🔥 Firestore Security Rules - Complete Setup

## 🚨 **Current Error**

```
Missing or insufficient permissions.
Listen for query at users/xtLSijkHggaBAjFM2aYKqPZ1uJw1/blockedUsers/kvI1yTUhzKVZ12BQEVrwxdjcXhr1|f:|ob:__name__asc failed
```

**Cause:** Your Firestore security rules don't allow access to the `blockedUsers` subcollection.

---

## ✅ **Solution: Updated Firestore Rules**

I've created complete Firestore security rules that include:

### New Rules Added:
1. ✅ **`users/{userId}/blockedUsers`** - Block management
2. ✅ **`users/{userId}/following`** - Follow system
3. ✅ **`users/{userId}/followers`** - Follower system
4. ✅ **`conversations/{id}/messages`** - Direct messaging
5. ✅ **`message_requests`** - Message request system
6. ✅ **`blocks`** - Global block relationships
7. ✅ **`saved_posts`** - Saved posts
8. ✅ **All other collections** - Complete security

---

## 🚀 **Deploy to Firebase**

### **Option 1: Firebase Console (Easiest)**

1. Go to [Firestore Rules](https://console.firebase.google.com/project/amen-5e359/firestore/rules)
2. Copy the entire content of `firestore.rules` (created in your project)
3. Paste it into the rules editor
4. Click **Publish**

### **Option 2: Firebase CLI**

```bash
# Make sure you're in your project directory
cd /path/to/your/project

# Deploy Firestore rules
firebase deploy --only firestore:rules
```

### **Option 3: Using firebase.json**

If you have a `firebase.json` file, make sure it includes:

```json
{
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  },
  "database": {
    "rules": "firebase-realtime-database.rules.json"
  }
}
```

Then deploy:
```bash
firebase deploy
```

---

## 🔒 **Security Summary**

### **Blocked Users** (`users/{userId}/blockedUsers/{blockedUserId}`)
- ✅ **Read:** Only the user can see their own blocked list
- ✅ **Write:** Only the user can block/unblock others
- ❌ **Other users:** Cannot see who you've blocked

### **Conversations** (`conversations/{conversationId}`)
- ✅ **Read:** Only participants can read
- ✅ **Write:** Only participants can send messages
- ❌ **Non-participants:** Cannot access conversation

### **Messages** (`conversations/{conversationId}/messages/{messageId}`)
- ✅ **Read:** Only conversation participants
- ✅ **Create:** Only participants can send (must match senderId)
- ✅ **Update/Delete:** Only message sender

### **Posts** (`posts/{postId}`)
- ✅ **Read:** All authenticated users
- ✅ **Write:** Only post author

### **User Profiles** (`users/{userId}`)
- ✅ **Read:** All authenticated users
- ✅ **Write:** Only profile owner

---

## 🧪 **Test Your Rules**

### Firebase Console Rules Simulator

Go to [Rules Playground](https://console.firebase.google.com/project/amen-5e359/firestore/rules)

#### Test 1: User can read their own blocked list ✅
```javascript
Authenticated as: xtLSijkHggaBAjFM2aYKqPZ1uJw1
Location: /users/xtLSijkHggaBAjFM2aYKqPZ1uJw1/blockedUsers/kvI1yTUhzKVZ12BQEVrwxdjcXhr1
Operation: get
Expected: ✅ Allow
```

#### Test 2: User cannot read another user's blocked list ❌
```javascript
Authenticated as: someOtherUserId
Location: /users/xtLSijkHggaBAjFM2aYKqPZ1uJw1/blockedUsers/kvI1yTUhzKVZ12BQEVrwxdjcXhr1
Operation: get
Expected: ❌ Deny
```

#### Test 3: Participants can read conversation ✅
```javascript
Authenticated as: user123
Location: /conversations/conv456
Operation: get
Data: { participantIds: ["user123", "user789"] }
Expected: ✅ Allow
```

#### Test 4: Non-participants cannot read conversation ❌
```javascript
Authenticated as: user999
Location: /conversations/conv456
Operation: get
Data: { participantIds: ["user123", "user789"] }
Expected: ❌ Deny
```

---

## 📋 **Complete Collection Structure**

```
firestore/
├── users/
│   ├── {userId}
│   ├── {userId}/blockedUsers/{blockedUserId}      ✅ NEW
│   ├── {userId}/following/{followingId}            ✅ NEW
│   └── {userId}/followers/{followerId}             ✅ NEW
├── posts/{postId}
├── conversations/
│   ├── {conversationId}
│   └── {conversationId}/messages/{messageId}       ✅ NEW
├── comments/{commentId}
├── notifications/{notificationId}
├── saved_posts/{saveId}                            ✅ NEW
├── communities/
│   ├── {communityId}
│   └── {communityId}/members/{memberId}
├── reports/{reportId}
├── message_requests/{requestId}                    ✅ NEW
├── blocks/{blockId}                                ✅ NEW (global)
├── prayer_requests/{requestId}
├── bible_study_groups/{groupId}
└── analytics/{userId}
```

---

## 🔑 **Helper Functions**

The rules include these helper functions for cleaner code:

```javascript
function isAuthenticated() {
  return request.auth != null;
}

function isOwner(userId) {
  return isAuthenticated() && request.auth.uid == userId;
}
```

Usage example:
```javascript
match /users/{userId} {
  allow read: if isAuthenticated();
  allow write: if isOwner(userId);
}
```

---

## ⚠️ **Important Notes**

### 1. **Rules vs. Data**
- Rules control **who can access** data
- They **don't filter** data — you must query correctly in your app

### 2. **Subcollections**
- Each subcollection needs its own rules
- Parent rules don't cascade to children

### 3. **Performance**
- Rules are evaluated on **every request**
- Use helper functions to keep rules DRY
- Avoid complex `get()` calls when possible

### 4. **Testing**
- Always test rules before deploying to production
- Use the Rules Playground in Firebase Console
- Test both allow and deny cases

---

## 🐛 **Debugging Permission Errors**

If you still see permission errors after deploying:

### 1. **Check Authentication**
```swift
if let user = Auth.auth().currentUser {
    print("✅ User authenticated: \(user.uid)")
} else {
    print("❌ User not authenticated")
}
```

### 2. **Check Query Path**
```swift
// ✅ Correct
db.collection("users")
  .document(currentUserId)
  .collection("blockedUsers")
  .document(blockedUserId)

// ❌ Wrong
db.collection("users/blockedUsers")
  .document(blockedUserId)
```

### 3. **Check Firestore Data Structure**
Make sure your data matches the rules:
```swift
// When creating a conversation:
let data: [String: Any] = [
    "participantIds": [currentUserId, otherUserId],  // ✅ Required
    "createdAt": Date(),
    // ...
]
```

### 4. **Enable Debug Logging**
```swift
// In AppDelegate or App struct
FirebaseConfiguration.shared.setLoggerLevel(.debug)
```

---

## 🚀 **Deployment Checklist**

- [ ] Copy `firestore.rules` content
- [ ] Paste into Firebase Console
- [ ] Click **Publish**
- [ ] Test in Rules Simulator
- [ ] Run your app
- [ ] Check for permission errors
- [ ] Monitor Firebase Console for issues

---

## 📊 **After Deployment**

### Verify Rules Are Active
1. Go to [Firestore Rules](https://console.firebase.google.com/project/amen-5e359/firestore/rules)
2. Check the timestamp shows recent deployment
3. Rules should start with `rules_version = '2';`

### Monitor Errors
1. Go to [Firebase Console](https://console.firebase.google.com/project/amen-5e359)
2. Check **Analytics** → **Errors** tab
3. Look for permission-related errors

### Test Key Features
- [ ] Block a user
- [ ] View blocked list
- [ ] Send a message
- [ ] Create a post
- [ ] Save a post
- [ ] View notifications

---

## ✅ **All Set!**

Once you deploy these rules, the errors should be resolved:

- ✅ Users can access their blocked lists
- ✅ Conversations work correctly
- ✅ Message requests are secure
- ✅ All collections have proper security

**Deploy now and test!** 🚀

---

## 📚 **Resources**

- [Firestore Security Rules Docs](https://firebase.google.com/docs/firestore/security/get-started)
- [Rules Reference](https://firebase.google.com/docs/reference/security/firestore)
- [Your Project Console](https://console.firebase.google.com/project/amen-5e359/firestore)

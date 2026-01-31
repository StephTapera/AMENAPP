# Firebase Rules Quick Reference

## 🚨 **Common Errors & Quick Fixes**

---

### ❌ Error: "Missing or insufficient permissions"

**Cause:** Firestore Security Rules deny the operation

**Quick Fix:**
```bash
# 1. Deploy rules
firebase deploy --only firestore:rules

# 2. Wait 1-2 minutes for propagation

# 3. Verify in Firebase Console
# Go to: Firestore → Rules → Check "Last Published"
```

**Check if user is authenticated:**
```swift
// In your Swift code
guard let userId = Auth.auth().currentUser?.uid else {
    print("❌ User not authenticated")
    return
}
```

---

### ❌ Error: "The query requires an index"

**Cause:** Missing composite index in Firestore

**Quick Fix:**
```bash
# Click the error link in Xcode console, OR:
firebase deploy --only firestore:indexes

# Wait 5-10 minutes for index to build
```

**Verify index status:**
```
Firebase Console → Firestore → Indexes
Status should show: ✅ Enabled
```

---

### ❌ Error: "Permission denied" (Storage)

**Cause:** Storage Security Rules deny upload/download

**Quick Fix:**
```bash
# Deploy storage rules
firebase deploy --only storage

# Verify path matches rules:
# ✅ Good: profile_images/{userId}/profile.jpg
# ❌ Bad: images/profile.jpg (no userId)
```

**Check storage path in code:**
```swift
// ✅ Correct format
let path = "profile_images/\(userId)/profile.jpg"

// ❌ Wrong format
let path = "images/profile.jpg" // Missing userId!
```

---

### ❌ Error: "AppCheck failed"

**Cause:** App Check not configured (safe to ignore in development)

**For Development:**
```
Ignore this error - it's a security feature for production
```

**For Production:**
```bash
# Enable App Check in Firebase Console
# iOS: Use DeviceCheck or App Attest
# Android: Use Play Integrity API
```

---

### ❌ Duplicate Comment IDs

**Cause:** Frontend rendering same comment twice

**Quick Fix in Code:**
```swift
// Add .removeDuplicates() or check for unique IDs
let uniqueComments = Array(Set(comments))

// Or use proper ID generation
let commentId = UUID().uuidString // Unique every time
```

---

## 📋 **Deployment Checklist**

```bash
# 1. Backup current rules
firebase firestore:rules:get > firestore.rules.backup

# 2. Test rules locally (optional)
firebase emulators:start

# 3. Deploy everything
firebase deploy

# 4. Verify deployment
firebase firestore:indexes:list  # Check indexes
firebase firestore:rules:get      # Check rules

# 5. Monitor for errors
# Watch Xcode console for 10 minutes
```

---

## 🔍 **Debug Commands**

### Check Current Rules
```bash
firebase firestore:rules:get
```

### List All Indexes
```bash
firebase firestore:indexes:list
```

### Test a Specific Rule
```bash
firebase firestore:rules:test read /users/test_id --auth='{"uid": "test_id"}'
```

### View Deployment History
```
Firebase Console → Firestore → Rules → History tab
```

---

## 🎯 **Quick Security Audit**

Run these queries to check security:

### ✅ Check: Can users read others' profiles?
```
Expected: YES (profiles are public)
```

### ✅ Check: Can users update others' profiles?
```
Expected: NO (only own profile)
```

### ✅ Check: Can users read others' conversations?
```
Expected: NO (only participants)
```

### ✅ Check: Can users delete others' posts?
```
Expected: NO (only own posts)
```

---

## 📱 **App-Specific Fixes**

### Issue: "Can't send messages"

**Check:**
1. User is authenticated: `Auth.auth().currentUser != nil`
2. User is participant: `conversationId` contains `userId`
3. Message has required fields: `senderId`, `content`, `timestamp`

**Fix:**
```swift
// Ensure you're in the conversation
let participantIds = [currentUserId, otherUserId]
try await db.collection("conversations").document(convId).setData([
    "participantIds": participantIds,
    "createdAt": Timestamp(date: Date()),
    "updatedAt": Timestamp(date: Date())
])
```

---

### Issue: "Can't follow users"

**Check:**
1. `followerId` matches `Auth.auth().currentUser.uid`
2. Has required fields: `followerId`, `followingId`, `timestamp`

**Fix:**
```swift
// Make sure followerId is YOU
try await db.collection("follows").addDocument(data: [
    "followerId": currentUserId,      // ✅ Must be you
    "followingId": otherUserId,       // ✅ User you're following
    "timestamp": Timestamp(date: Date())
])
```

---

### Issue: "Can't upload profile image"

**Check:**
1. Path format: `profile_images/{userId}/filename.jpg`
2. File size < 10MB
3. File type is image: `.jpg`, `.png`, `.heic`

**Fix:**
```swift
// Correct storage reference
let storageRef = Storage.storage().reference()
let path = "profile_images/\(userId)/profile.jpg"  // ✅ Correct
let fileRef = storageRef.child(path)

// Wrong path
let wrongPath = "images/profile.jpg"  // ❌ Missing userId
```

---

## ⚡ **Performance Tips**

### Use .limit() on queries
```swift
// ✅ Good
db.collection("posts")
    .limit(20)
    .getDocuments()

// ❌ Bad (loads entire collection)
db.collection("posts")
    .getDocuments()
```

### Create proper indexes
```javascript
// Index for: posts by category, sorted by time
{
  fields: [
    { fieldPath: "category", order: "ASCENDING" },
    { fieldPath: "timestamp", order: "DESCENDING" }
  ]
}
```

### Cache frequently accessed data
```swift
// Cache user profile locally
UserDefaults.standard.set(displayName, forKey: "userName")

// Read from cache first
if let cached = UserDefaults.standard.string(forKey: "userName") {
    return cached
}
```

---

## 🆘 **Emergency Rollback**

If deployment breaks the app:

```bash
# 1. Go to Firebase Console
# 2. Firestore → Rules → History
# 3. Click previous version
# 4. Click "Restore"
# 5. Wait 1 minute

# OR via CLI:
firebase firestore:rules:release <RELEASE_NAME>
```

---

## 📞 **Support Contacts**

- **Firebase Status:** https://status.firebase.google.com
- **Stack Overflow:** Tag `firebase` + `security-rules`
- **Firebase Community:** https://firebase.community

---

## 🎓 **Learning Resources**

- [Security Rules Documentation](https://firebase.google.com/docs/rules)
- [Firestore Security Rules](https://firebase.google.com/docs/firestore/security/get-started)
- [Common Security Patterns](https://firebase.google.com/docs/rules/rules-and-auth)
- [Rules Simulator](https://firebase.google.com/docs/rules/simulator)

---

**Keep this document handy during development!**  
Last Updated: January 31, 2026

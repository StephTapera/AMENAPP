# Firebase Security Rules Deployment Guide

## 🎯 Overview

This guide will help you deploy production-ready Firestore Security Rules, Storage Rules, and Indexes for the AMEN app.

---

## 📋 **Prerequisites**

Before deploying, ensure you have:
- Firebase CLI installed: `npm install -g firebase-tools`
- Firebase project initialized in your project directory
- Admin/Owner access to your Firebase project
- Latest rules files in your repository

---

## 🚀 **Quick Deployment**

### Option 1: Firebase Console (Recommended for First Time)

#### **Firestore Security Rules**

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project: `amen-5e359`
3. Navigate to **Firestore Database** → **Rules** tab
4. Copy the entire content from `firestore.rules`
5. Paste into the rules editor
6. Click **Publish**

#### **Firebase Storage Rules**

1. In Firebase Console, navigate to **Storage** → **Rules** tab
2. Copy the entire content from `storage.rules`
3. Paste into the rules editor
4. Click **Publish**

#### **Firestore Indexes**

1. Navigate to **Firestore Database** → **Indexes** tab
2. You can either:
   - **Option A**: Let Firebase auto-create indexes as you use the app (click the error links)
   - **Option B**: Manually create each index using the JSON configuration

---

### Option 2: Firebase CLI (Recommended for Production)

#### **1. Install Firebase CLI**
```bash
npm install -g firebase-tools
```

#### **2. Login to Firebase**
```bash
firebase login
```

#### **3. Initialize Firebase (if not already done)**
```bash
cd /path/to/your/project
firebase init

# Select:
# - Firestore
# - Storage
# 
# When prompted:
# - Firestore rules file: firestore.rules
# - Firestore indexes file: firestore.indexes.json
# - Storage rules file: storage.rules
```

#### **4. Deploy Rules**

**Deploy everything:**
```bash
firebase deploy
```

**Deploy only Firestore rules:**
```bash
firebase deploy --only firestore:rules
```

**Deploy only Firestore indexes:**
```bash
firebase deploy --only firestore:indexes
```

**Deploy only Storage rules:**
```bash
firebase deploy --only storage
```

---

## 🔍 **Verify Deployment**

### Test Firestore Rules

Run this in your Firebase Console (or Firebase CLI):

```javascript
// Test reading users collection (should succeed if authenticated)
firebase firestore:rules:test read /users/test_user_id --auth='{"uid": "test_user_id"}'

// Test writing to another user's profile (should fail)
firebase firestore:rules:test update /users/other_user_id --auth='{"uid": "test_user_id"}'
```

### Test Storage Rules

Upload a test image:
```bash
# Should succeed (user uploading their own profile image)
firebase storage:rules:test upload profile_images/test_user_id/profile.jpg \
  --auth='{"uid": "test_user_id"}' \
  --file=test_image.jpg

# Should fail (user uploading someone else's profile image)
firebase storage:rules:test upload profile_images/other_user_id/profile.jpg \
  --auth='{"uid": "test_user_id"}' \
  --file=test_image.jpg
```

---

## 📊 **Create Missing Indexes**

Based on your error logs, you need these specific indexes:

### **Index 1: Conversations by Participant & Updated Date**
```javascript
Collection: conversations
Fields:
  - participantIds (Array-contains)
  - updatedAt (Descending)
```

### **Index 2: Archived Conversations**
```javascript
Collection: conversations
Fields:
  - participantIds (Array-contains)
  - archivedBy.<userId> (Ascending) // Replace <userId> with actual field
  - updatedAt (Descending)
```

### **Quick Way to Create Indexes:**

1. Run your app and trigger the queries that fail
2. Click the error links in Xcode console (they create indexes automatically)
3. Wait 5-10 minutes for indexes to build

**Example error link:**
```
https://console.firebase.google.com/v1/r/project/amen-5e359/firestore/indexes?create_composite=...
```

Just click it and Firebase will create the index for you!

---

## ⚠️ **Critical Security Fixes**

Your error logs show permission issues. Here's what the new rules fix:

### **Before (Insecure)**
```javascript
// Anyone could read/write everything
match /{document=**} {
  allow read, write: if request.auth != null;
}
```

### **After (Secure)**
```javascript
// Users can only access their own data or public content
match /users/{userId} {
  allow read: if isAuthenticated();
  allow write: if isOwner(userId);
}

match /conversations/{conversationId} {
  allow read: if isParticipant(resource.data.participantIds);
  allow write: if isParticipant(resource.data.participantIds);
}
```

---

## 🐛 **Fixing Current Issues**

### Issue 1: Missing Conversation Indexes

**Solution:** Deploy the `firestore.indexes.json` file or click the error links

### Issue 2: Permission Denied Errors

**Cause:** Old rules don't allow certain operations

**Fix:** Deploy new `firestore.rules` which properly handles:
- User profile updates
- Conversation creation
- Message sending
- Follow/unfollow
- Block/unblock
- Saved posts

### Issue 3: Storage Permission Denied

**Cause:** Storage rules too restrictive or missing

**Fix:** Deploy `storage.rules` which allows:
- Users to upload their own profile images
- Users to upload post media
- Users to upload message attachments

### Issue 4: Duplicate Comment Replies

**Cause:** Frontend issue (not rules related)

**Fix needed in code:**
- Check for duplicate reply IDs before rendering
- Ensure reply submission only happens once
- Add `.onlyOnce()` to Firestore listeners

---

## 📱 **Testing Checklist**

After deployment, test these scenarios:

### Authentication
- [ ] Sign up new user
- [ ] Sign in existing user
- [ ] Update own profile
- [ ] Try to update another user's profile (should fail)

### Posts
- [ ] Create post
- [ ] Read posts
- [ ] Update own post
- [ ] Try to update another user's post (should fail)
- [ ] Delete own post

### Conversations
- [ ] Start new conversation
- [ ] Send message
- [ ] Read messages
- [ ] Archive conversation
- [ ] Try to read someone else's conversation (should fail)

### Follows
- [ ] Follow user
- [ ] Unfollow user
- [ ] View followers/following

### Block
- [ ] Block user
- [ ] Unblock user
- [ ] Verify blocked user can't message you

### Storage
- [ ] Upload profile image
- [ ] Upload post image
- [ ] Upload message attachment
- [ ] Try to upload to another user's path (should fail)

---

## 🔧 **Rollback Plan**

If something breaks after deployment:

### Option 1: Revert via Console
1. Go to Firebase Console → Firestore → Rules
2. Click "History" tab
3. Select previous version
4. Click "Restore"

### Option 2: Revert via CLI
```bash
# Keep a backup of old rules
cp firestore.rules firestore.rules.backup

# Restore old rules
cp firestore.rules.old firestore.rules
firebase deploy --only firestore:rules
```

---

## 📈 **Performance Optimization**

### Index Best Practices

1. **Only create indexes you need** - Each index costs storage
2. **Monitor index usage** - Firebase Console shows which indexes are used
3. **Delete unused indexes** - Clean up to save costs

### Query Optimization

The new indexes support these optimized queries:

```javascript
// Efficient: Uses index
db.collection('conversations')
  .where('participantIds', 'array-contains', userId)
  .orderBy('updatedAt', 'desc')
  .limit(20)

// Inefficient: Full collection scan
db.collection('conversations')
  .get() // Don't do this!
```

---

## 🛡️ **Security Best Practices**

### DO's ✅
- Always check `request.auth != null`
- Validate user is owner before writes
- Use field-level security (check specific fields)
- Limit query results with `.limit()`
- Validate data types and required fields

### DON'Ts ❌
- Never allow unrestricted reads: `allow read: if true`
- Don't expose sensitive data (passwords, tokens)
- Avoid allowing deletion of critical data
- Don't trust client-side validation alone
- Never use `{document=**}` for production

---

## 📞 **Troubleshooting**

### Error: "Missing or insufficient permissions"

**Cause:** Rules not deployed or too restrictive

**Fix:**
1. Check rules are deployed: `firebase deploy --only firestore:rules`
2. Verify user is authenticated
3. Check user has permission for that operation
4. Look at Firebase Console → Firestore → Rules → Playground to test

### Error: "The query requires an index"

**Cause:** Missing composite index

**Fix:**
1. Click the error link in Xcode console
2. Wait 5-10 minutes for index to build
3. Or deploy: `firebase deploy --only firestore:indexes`

### Error: "Permission denied" for Storage

**Cause:** Storage rules not deployed

**Fix:**
```bash
firebase deploy --only storage
```

### Rules Not Taking Effect

**Cause:** Caching or propagation delay

**Fix:**
1. Wait 1-2 minutes for propagation
2. Clear app cache
3. Reinstall app
4. Check Firebase Console that rules were published

---

## 📚 **Additional Resources**

- [Firebase Security Rules Docs](https://firebase.google.com/docs/rules)
- [Firestore Security Rules Guide](https://firebase.google.com/docs/firestore/security/get-started)
- [Storage Security Rules](https://firebase.google.com/docs/storage/security)
- [Rules Testing](https://firebase.google.com/docs/rules/unit-tests)

---

## ✅ **Deployment Checklist**

Before going to production:

- [ ] Backup existing rules
- [ ] Test rules in development project first
- [ ] Deploy Firestore rules
- [ ] Deploy Storage rules
- [ ] Deploy Firestore indexes
- [ ] Verify all indexes are built (check console)
- [ ] Test all user flows
- [ ] Monitor error logs for 24 hours
- [ ] Set up Firebase alerts for rule violations
- [ ] Document any custom rules added

---

## 🎉 **Success Criteria**

Your deployment is successful when:

✅ No "Missing or insufficient permissions" errors  
✅ No "The query requires an index" errors  
✅ All user actions work as expected  
✅ Unauthorized actions are properly blocked  
✅ Firebase Console shows no rule violations  
✅ App performance is good (queries fast)  

---

## 🚨 **Emergency Contacts**

If you encounter critical issues:

1. **Firebase Support:** https://firebase.google.com/support
2. **StackOverflow:** Tag with `firebase` + `security-rules`
3. **Firebase Slack:** https://firebase.community/

---

**Last Updated:** January 31, 2026  
**Rules Version:** 1.0  
**Author:** AMEN Development Team

# Complete Firestore Index Guide - All Indexes Your App Needs

Based on a comprehensive analysis of your entire codebase, here are ALL the Firestore indexes you need.

---

## ✅ Indexes You Already Have (3)

### 1. Posts by Author (User Profile) ✅
```
Collection: posts
Fields:
  - authorId (Ascending)
  - isRepost (Ascending)
  - createdAt (Descending)
  - __name__ (Ascending)
```
**Status:** ✅ Active
**Used for:** User profile Posts & Reposts tabs

---

### 2. Comments by Author (User Profile Replies) ✅
```
Collection: comments
Fields:
  - authorId (Ascending)
  - createdAt (Descending)
  - __name__ (Ascending)
```
**Status:** ✅ Active
**Used for:** User profile Replies tab

---

### 3. Conversations for Message Requests ✅
```
Collection: conversations
Fields:
  - participantIds (Ascending)
  - conversationStatus (Ascending)
  - requesterId (Ascending)
  - updatedAt (Descending)
  - __name__ (Ascending)
```
**Status:** ✅ Active
**Used for:** Message requests with complex filtering

---

## 🔴 CRITICAL Indexes Needed (Create These First)

### 4. Basic Conversations List (REQUIRED) 🔴
```
Collection: conversations
Fields:
  - participantIds (Ascending)
  - updatedAt (Descending)
```

**Priority:** 🔴 **HIGH** - Main messaging inbox
**Used in:** `FirebaseMessagingService.swift` line 184-186
**Query:**
```swift
db.collection("conversations")
    .whereField("participantIds", arrayContains: currentUserId)
    .order(by: "updatedAt", descending: true)
```

**Why critical:** Used every time user opens their messages inbox

---

### 5. Posts by Category (REQUIRED for Feed) 🔴
```
Collection: posts
Fields:
  - category (Ascending)
  - createdAt (Descending)
```

**Priority:** 🔴 **HIGH** - Category feeds
**Used in:** `FirebasePostService.swift` line 497-507
**Query:**
```swift
db.collection("posts")
    .whereField("category", isEqualTo: "openTable")
    .order(by: "createdAt", descending: true)
```

**Why critical:** Used for Open Table, Testimonies, and Prayer feeds

---

### 6. Posts by Category with Topic Tag 🔴
```
Collection: posts
Fields:
  - category (Ascending)
  - topicTag (Ascending)
  - createdAt (Descending)
```

**Priority:** 🔴 **HIGH** - Topic filtering in feeds
**Used in:** `FirebasePostService.swift` line 501-503
**Query:**
```swift
db.collection("posts")
    .whereField("category", isEqualTo: "openTable")
    .whereField("topicTag", isEqualTo: "Faith")
    .order(by: "createdAt", descending: true)
```

**Why critical:** Used when users filter posts by topic tags

---

### 7. Posts for Following Feed 🔴
```
Collection: posts
Fields:
  - authorId (Ascending)
  - createdAt (Descending)
```

**Priority:** 🔴 **HIGH** - Following feed
**Used in:** `FirebasePostService.swift` line 522-523
**Query:**
```swift
db.collection("posts")
    .whereField("authorId", in: followingIds)
    .order(by: "createdAt", descending: true)
```

**Why critical:** "Following" filter in feeds

---

## 🟡 IMPORTANT Indexes (Create for Better Performance)

### 8. Archived Conversations 🟡
```
Collection: conversations
Fields:
  - participantIds (Ascending)
  - archivedBy.[userId] (Ascending)
  - archivedAt.[userId] (Descending)
```

**Priority:** 🟡 **MEDIUM**
**Used in:** `FirebaseMessagingService.swift` line 1549-1552
**Query:**
```swift
db.collection("conversations")
    .whereField("participantIds", arrayContains: currentUserId)
    .whereField("archivedBy.\(currentUserId)", isEqualTo: true)
    .order(by: "archivedAt.\(currentUserId)", descending: true)
```

**Why needed:** Archive feature in messaging

---

### 9. Comments by Post (For Post Detail) 🟡
```
Collection: comments
Fields:
  - postId (Ascending)
  - createdAt (Ascending)
```

**Priority:** 🟡 **MEDIUM** - Will be needed when you add post detail view
**Query:**
```swift
db.collection("comments")
    .whereField("postId", isEqualTo: postId)
    .order(by: "createdAt", descending: false)
```

**Why needed:** Displaying comments on individual posts

---

### 10. Trending Posts (Past 7 Days) 🟡
```
Collection: posts
Fields:
  - createdAt (Ascending)
```

**Priority:** 🟡 **MEDIUM**
**Used in:** `SearchService.swift` line 498-500
**Query:**
```swift
db.collection("posts")
    .whereField("createdAt", isGreaterThan: sevenDaysAgo)
    .limit(to: 100)
```

**Why needed:** Trending topics feature

---

## 🟢 OPTIONAL Search Indexes (For Better Search)

**Note:** These require adding lowercase fields to your data model first!

### 11. User Search by Username 🟢
```
Collection: users
Fields:
  - usernameLowercase (Ascending)
  - __name__ (Ascending)
```

**Priority:** 🟢 **LOW** - Only if you add lowercase fields
**Used in:** `SearchService.swift` line 173-177
**Query:**
```swift
db.collection("users")
    .whereField("usernameLowercase", isGreaterThanOrEqualTo: query)
    .whereField("usernameLowercase", isLessThanOrEqualTo: query + "\u{f8ff}")
```

**Why optional:** Currently using client-side filtering as fallback

---

### 12. User Search by Display Name 🟢
```
Collection: users
Fields:
  - displayNameLowercase (Ascending)
  - __name__ (Ascending)
```

**Priority:** 🟢 **LOW** - Only if you add lowercase fields
**Similar to username search**

---

### 13. Community Search 🟢
```
Collection: communities
Fields:
  - nameLowercase (Ascending)
  - __name__ (Ascending)
```

**Priority:** 🟢 **LOW** - Only if you add lowercase fields
**Used in:** `SearchService.swift` line 287-290

---

### 14. Post Content Search 🟢
```
Collection: posts
Fields:
  - contentLowercase (Ascending)
  - __name__ (Ascending)
```

**Priority:** 🟢 **LOW** - Only if you add lowercase fields
**Better solution: Use Algolia for full-text search**

---

## 📋 Summary: What to Create Now

### Phase 1: Essential (Create ASAP) 🔴
1. ✅ Posts by Author + isRepost + Date (DONE)
2. ✅ Comments by Author + Date (DONE)
3. ✅ Conversations Message Requests (DONE)
4. ❌ **Conversations List** (participantIds + updatedAt)
5. ❌ **Posts by Category** (category + createdAt)
6. ❌ **Posts by Category + Topic** (category + topicTag + createdAt)
7. ❌ **Posts Following Feed** (authorId + createdAt)

### Phase 2: Important (Create This Week) 🟡
8. ❌ Archived Conversations
9. ❌ Comments by Post
10. ❌ Trending Posts

### Phase 3: Optional (Only if Needed) 🟢
11-14. Search indexes (requires data model changes)

---

## 🚀 Quick Creation Guide

### Method 1: Use Error Links (Easiest)
1. Use each feature in your app
2. When you get "query requires an index" error
3. Click the Firebase Console link in the error
4. Index created automatically!

### Method 2: Manual Creation
Go to Firebase Console → Firestore → Indexes → Create Index

**For Conversations List:**
- Collection: `conversations`
- Field 1: `participantIds` - Ascending
- Field 2: `updatedAt` - Descending
- Click Create

**For Posts by Category:**
- Collection: `posts`
- Field 1: `category` - Ascending
- Field 2: `createdAt` - Descending
- Click Create

**For Posts by Category + Topic:**
- Collection: `posts`
- Field 1: `category` - Ascending
- Field 2: `topicTag` - Ascending
- Field 3: `createdAt` - Descending
- Click Create

**For Posts Following Feed:**
- Collection: `posts`
- Field 1: `authorId` - Ascending
- Field 2: `createdAt` - Descending
- Click Create

---

## ⚠️ Important Notes

### Indexes #4-7 are CRITICAL
Your app will show "query requires an index" errors without them:
- Conversations list won't load
- Category feeds won't work
- Topic filtering will fail
- Following feed will error

### Index Creation Time
- Small database: 5-10 minutes per index
- Medium database: 10-20 minutes per index
- Large database: 30+ minutes per index

### Index Storage
- Each index adds ~5-10% to document size
- 10 indexes ≈ 50-100% overhead
- Worth it for performance!

### Alternative: Algolia
For better search (indexes #11-14), consider **Algolia**:
- Full-text search
- Typo tolerance
- Instant results
- Firebase Extension available

---

## 🔍 Testing Your Indexes

### After Creating Each Index:

1. **Check Status**
   - Firebase Console → Indexes
   - Wait for "Enabled" status (not "Building")

2. **Test in App**
   - Use the feature that needs the index
   - Check Xcode console for success messages
   - Should see faster load times

3. **Monitor Usage**
   - Firebase Console → Usage tab
   - Look for "Composite index entries read"
   - High numbers = indexes working!

---

## 📊 Expected Impact

### Without Critical Indexes (Current State):
- ❌ Conversations list errors
- ❌ Category feeds error
- ❌ Following feed errors
- ❌ Topic filtering errors

### With Critical Indexes (After Creation):
- ✅ All features work
- ✅ Fast query performance
- ✅ Better user experience
- ✅ Production ready

---

## 🆘 Need Help?

If you get errors when creating indexes:
1. Check that your queries match the index fields exactly
2. Verify field names are spelled correctly
3. Ensure query operators match (Ascending vs Descending)
4. Check Firestore security rules allow queries

If app still errors after indexes created:
1. Wait 15 minutes for indexes to fully deploy
2. Restart your app
3. Check Firebase Console for index status
4. Verify you're using the latest Firebase SDK

---

## ✨ Final Checklist

Before launching to production:

- [ ] Create indexes #4-7 (CRITICAL)
- [ ] Test all main features (posts, messages, profiles)
- [ ] Verify indexes show "Enabled" in console
- [ ] Check Xcode console for no index errors
- [ ] Monitor Firebase Usage tab for index reads
- [ ] Consider adding indexes #8-10 (IMPORTANT)
- [ ] Plan for Algolia if search is important (indexes #11-14)

---

**Your app is almost ready!** Create those 4 critical indexes and you'll be production-ready! 🚀

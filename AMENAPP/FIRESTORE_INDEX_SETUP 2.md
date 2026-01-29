# Firestore Index Setup Guide

## Issue Fixed ✅
The "query requires an index" error when viewing user profiles has been resolved.

## What Was Changed

I've updated the following queries to **NOT require composite indexes** by removing server-side sorting and doing it client-side instead:

### Files Modified:
1. **FirebasePostService.swift**
   - `fetchUserOriginalPosts(userId:)` - Now sorts posts client-side
   - `fetchUserReposts(userId:)` - Now sorts reposts client-side
   - `fetchUserReplies(userId:)` - Now sorts comments client-side

2. **FollowService.swift**
   - `fetchFollowerIds(userId:)` - Removed ordering
   - `fetchFollowingIds(userId:)` - Removed ordering

## Quick Fix Applied (Current Solution)

The queries now:
- ✅ Fetch data with `whereField` only (no `order(by:)`)
- ✅ Sort results client-side using Swift's `.sorted()`
- ✅ Work **without requiring any Firestore indexes**
- ✅ Handle small to medium datasets efficiently

### Trade-offs:
- 📊 Slightly more data transferred (we fetch more then filter/sort)
- 💾 More memory used on device for sorting
- ⚡ Totally fine for <1000 items per query

---

## Production Solution (Recommended for Scale)

For better performance at scale, you should create composite indexes in Firebase:

### How to Create Indexes

#### Method 1: Auto-Create from Error Link
When you get an index error, Firebase often shows a URL like:
```
https://console.firebase.google.com/project/YOUR_PROJECT/firestore/indexes?create_composite=...
```
Click that link and it will auto-create the index for you!

#### Method 2: Manual Creation in Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Navigate to **Firestore Database** → **Indexes**
4. Click **Create Index**

Create these indexes:

##### Index 1: Posts by Author (Ordered by Date)
- **Collection ID**: `posts`
- **Fields indexed**:
  - `authorId` - Ascending
  - `createdAt` - Descending
- **Query scope**: Collection

##### Index 2: Comments by Author (Ordered by Date)
- **Collection ID**: `comments`
- **Fields indexed**:
  - `authorId` - Ascending
  - `createdAt` - Descending
- **Query scope**: Collection

##### Index 3: Follows by Following (Ordered by Date)
- **Collection ID**: `follows`
- **Fields indexed**:
  - `followingId` - Ascending
  - `createdAt` - Descending
- **Query scope**: Collection

##### Index 4: Follows by Follower (Ordered by Date)
- **Collection ID**: `follows`
- **Fields indexed**:
  - `followerId` - Ascending
  - `createdAt` - Descending
- **Query scope**: Collection

⏱️ **Index creation takes 5-15 minutes** depending on database size.

---

## When to Switch to Indexes

You should consider re-enabling server-side sorting with indexes when:

1. 📈 Users have >1000 posts/followers
2. 🐌 Profile loading feels slow
3. 📱 App uses too much memory on older devices
4. 🌍 You want to reduce data transfer costs

### How to Re-Enable Server-Side Sorting

Once indexes are created, you can revert to server-side sorting:

```swift
// Example: FirebasePostService.swift - fetchUserOriginalPosts
let query = db.collection(FirebaseManager.CollectionPath.posts)
    .whereField("authorId", isEqualTo: userId)
    .order(by: "createdAt", descending: true)  // ✅ Now works with index
    .limit(to: 50)  // Can limit earlier now
```

Benefits:
- ⚡ Faster queries
- 📉 Less data transferred
- 💾 Less memory used
- 📊 Better pagination support

---

## Monitoring Index Usage

To check if your indexes are being used:

1. Go to Firebase Console → Firestore → Usage tab
2. Look at "Composite index entries read"
3. Compare with "Document reads"

If composite index reads are high, your indexes are working!

---

## Current Status

✅ **User profiles now load without errors**
✅ **No indexes required** (using client-side sorting)
✅ **Works for development and small-scale production**
⚠️ **Consider adding indexes for production scale**

---

## Testing

After this fix, you should be able to:
- ✅ View any user's profile
- ✅ See their posts, replies, and reposts
- ✅ View followers/following lists
- ✅ No "query requires an index" errors

---

## Additional Resources

- [Firestore Indexing Guide](https://firebase.google.com/docs/firestore/query-data/indexing)
- [Best Practices for Indexes](https://firebase.google.com/docs/firestore/query-data/index-overview)
- [Firestore Pricing (Index Impact)](https://firebase.google.com/docs/firestore/quotas)

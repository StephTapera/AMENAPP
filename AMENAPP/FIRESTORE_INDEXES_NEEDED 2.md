# Firestore Composite Indexes Required

## ✅ Index You Have Created
- **posts** collection: `authorId` + `isRepost` + `createdAt` + `__name__`

## 📋 Additional Indexes Needed

Based on your app's queries, here are the remaining composite indexes you should create:

---

### 1. Comments by Author (for User Replies)
**Collection**: `comments`
**Fields**:
- `authorId` - Ascending
- `createdAt` - Descending

**Usage**: Fetching all replies/comments made by a user on their profile

**Query**:
```swift
db.collection("comments")
    .whereField("authorId", isEqualTo: userId)
    .order(by: "createdAt", descending: true)
```

---

### 2. Follows by Following (for Followers List)
**Collection**: `follows`
**Fields**:
- `followingId` - Ascending
- `createdAt` - Descending

**Usage**: Getting all followers of a user

**Query**:
```swift
db.collection("follows")
    .whereField("followingId", isEqualTo: userId)
    .order(by: "createdAt", descending: true)
```

---

### 3. Follows by Follower (for Following List)
**Collection**: `follows`
**Fields**:
- `followerId` - Ascending
- `createdAt` - Descending

**Usage**: Getting all users that a user is following

**Query**:
```swift
db.collection("follows")
    .whereField("followerId", isEqualTo: userId)
    .order(by: "createdAt", descending: true)
```

---

### 4. Posts by Category and Time (for Feed)
**Collection**: `posts`
**Fields**:
- `category` - Ascending
- `createdAt` - Descending

**Usage**: Fetching posts for specific categories (Open Table, Testimonies, Prayer)

**Query**:
```swift
db.collection("posts")
    .whereField("category", isEqualTo: "openTable")
    .order(by: "createdAt", descending: true)
```

---

### 5. Comments by Post (for Post Detail)
**Collection**: `comments`
**Fields**:
- `postId` - Ascending
- `createdAt` - Ascending

**Usage**: Loading all comments for a specific post

**Query**:
```swift
db.collection("comments")
    .whereField("postId", isEqualTo: postId)
    .order(by: "createdAt", descending: false)
```

---

### 6. Posts by Visibility and Time (for Feed Filtering)
**Collection**: `posts`
**Fields**:
- `visibility` - Ascending
- `createdAt` - Descending

**Usage**: Filtering posts by visibility level (everyone, followers, community)

**Query**:
```swift
db.collection("posts")
    .whereField("visibility", in: ["everyone", "followers"])
    .order(by: "createdAt", descending: true)
```

---

## How to Create These Indexes

### Method 1: Click Error Links (Easiest)
When you run a query that needs an index, Firestore will give you an error with a direct link like:
```
https://console.firebase.google.com/project/YOUR_PROJECT/firestore/indexes?create_composite=...
```
Just click that link and Firebase will create it for you!

### Method 2: Firebase Console (Manual)
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Click **Firestore Database** in the left menu
4. Click **Indexes** tab
5. Click **Create Index** button
6. Fill in the details from above
7. Click **Create**

⏱️ Each index takes 5-15 minutes to build.

---

## Priority Order

Create these indexes in this order based on importance:

1. **🔴 HIGH PRIORITY** - Comments by Author (user profile replies)
2. **🟡 MEDIUM PRIORITY** - Follows indexes (followers/following lists)
3. **🟢 LOWER PRIORITY** - Category/Visibility indexes (already working with client-side filtering)

---

## Current Query Status

### ✅ Working with Index:
- `fetchUserOriginalPosts()` - Uses your existing index
- `fetchUserReposts()` - Uses your existing index

### ⚠️ Working without Index (client-side sort):
- `fetchUserReplies()` - Will be faster with index #1
- `fetchFollowerIds()` - Will be faster with index #2
- `fetchFollowingIds()` - Will be faster with index #3

---

## Testing After Index Creation

Once you create an index, you can verify it's working:

1. Check the Firebase Console → Indexes tab
2. Status should show "Enabled" (not "Building")
3. Run your app and check Xcode console logs
4. You should see faster query times

---

## Monitoring

To monitor index usage:
1. Firebase Console → Firestore → Usage tab
2. Look at "Composite index entries read"
3. Compare before/after index creation

If you see high composite index reads, your indexes are working!

---

## Notes

- Indexes are **per-collection**
- You can have multiple indexes on the same collection
- Indexes increase database size slightly (usually <5%)
- Indexes improve query speed dramatically (10-100x faster)
- Indexes are required for complex queries (multiple `where` + `order`)

---

## Do I Need to Update Code?

**For indexes #2 and #3 (Follows):**
Yes, I can update the code to re-enable server-side sorting once you create those indexes. Let me know when they're ready!

**For index #1 (Comments):**
Yes, same as above.

**For your existing posts index:**
✅ Already updated! The code now uses server-side filtering for `isRepost`.

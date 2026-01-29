# Firestore Indexes - Current Status

## ✅ Indexes You Have Created

### 1. Posts Index ✅
```
Collection: posts
Fields:
  - authorId (Ascending)
  - isRepost (Ascending)
  - createdAt (Descending)
  - __name__ (Ascending)
```
**Status**: ✅ **Active & Optimized**
**Used by**: User profile posts and reposts tabs

---

### 2. Comments Index ✅
```
Collection: comments
Fields:
  - authorId (Ascending)
  - createdAt (Descending)
  - __name__ (Ascending)
```
**Status**: ✅ **Active & Optimized**
**Used by**: User profile replies tab

---

## 🔵 Optional Indexes (App Works Without These)

The following indexes are **optional**. Your app currently works without them by fetching all data and sorting client-side. Create these if you want to optimize performance:

### 3. Follows by Following (Optional)
```
Collection: follows
Fields:
  - followingId (Ascending)
  - createdAt (Descending)
```
**Status**: ⚪ Not created (app uses client-side sorting)
**Used by**: Followers list on user profile
**Impact**: Low - most users have <1000 followers, so client-side sorting is fine
**When to create**: If users have >1000 followers

---

### 4. Follows by Follower (Optional)
```
Collection: follows
Fields:
  - followerId (Ascending)
  - createdAt (Descending)
```
**Status**: ⚪ Not created (app uses client-side sorting)
**Used by**: Following list on user profile
**Impact**: Low - most users follow <1000 people, so client-side sorting is fine
**When to create**: If users follow >1000 people

---

## 📊 Other Common Indexes You Might Need

### 5. Comments by Post (Recommended for Post Detail View)
```
Collection: comments
Fields:
  - postId (Ascending)
  - createdAt (Ascending)
```
**Used by**: Loading comments on a post detail page
**Impact**: Medium - improves comment loading speed
**When to create**: When you implement post detail view with comments

---

### 6. Posts by Category (Optional - for Feed)
```
Collection: posts
Fields:
  - category (Ascending)
  - createdAt (Descending)
```
**Used by**: Category-specific feeds (Open Table, Testimonies, Prayer)
**Impact**: Medium - if you filter by category often
**When to create**: If category feeds are slow

---

### 7. Posts for Feed with Multiple Filters (Advanced)
```
Collection: posts
Fields:
  - visibility (Ascending)
  - category (Ascending)
  - createdAt (Descending)
```
**Used by**: Complex feed filtering (e.g., "show me public posts in Open Table category")
**Impact**: Low - rarely used
**When to create**: Only if you do complex multi-field filtering

---

## 🎯 Recommended Action Plan

### Phase 1: Core Indexes (DONE ✅)
- ✅ Posts by author and type
- ✅ Comments by author

### Phase 2: User Profile Performance (Optional)
Create these only if you notice slow loading:
- Follows indexes (#3 and #4)

### Phase 3: Feature-Specific (Create When Needed)
- Comments by post (#5) - when you build post detail view
- Posts by category (#6) - if category filtering is slow

---

## 📈 Current Performance Status

### ✅ Fully Optimized (Using Indexes):
- User profile **Posts** tab - Uses posts index
- User profile **Reposts** tab - Uses posts index  
- User profile **Replies** tab - Uses comments index

### ⚪ Working Well (Client-Side):
- **Followers** list - No index needed for <1000 followers
- **Following** list - No index needed for <1000 following

---

## 🔧 How to Create Additional Indexes

If you want to create the optional indexes:

### Method 1: Let the App Tell You
Just use the feature that needs an index. When you get an error like:
```
The query requires an index. You can create it here: https://...
```
Click that link!

### Method 2: Manual Creation
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Your Project → **Firestore Database** → **Indexes**
3. Click **Create Index**
4. Copy the field configuration from above
5. Click **Create**

---

## 💡 Performance Tips

### When Client-Side Sorting is Fine:
- ✅ Datasets with <1,000 items
- ✅ Rarely-accessed queries
- ✅ Development/testing environments

### When You Need an Index:
- ❌ Datasets with >1,000 items
- ❌ Frequently-accessed queries (every page load)
- ❌ Production apps with many users
- ❌ Queries that feel slow (>2 seconds)

---

## 🎉 Summary

**Your app is now fully functional!**

✅ User profiles load fast with optimized queries
✅ Posts, reposts, and replies use database indexes
✅ Followers/following work without needing indexes yet

**You're good to go!** Only create additional indexes if you notice performance issues or when building new features.

---

## 📱 Testing Your Indexes

To verify everything is working:

1. **Open a user profile**
   - ✅ Posts tab should load instantly
   - ✅ Replies tab should load instantly
   - ✅ Reposts tab should load instantly
   - ⚪ Followers/following may take slightly longer (still fast for <1000)

2. **Check Xcode Console**
   Look for these success messages:
   ```
   ✅ Fetched X original posts for user
   ✅ Fetched X replies for user
   ✅ Fetched X reposts for user
   ✅ Fetched X followers
   ✅ Fetched X following
   ```

3. **Firebase Console → Usage Tab**
   - Should see "Composite index entries read" increasing
   - This means your indexes are being used!

---

## 🆘 Troubleshooting

### If you get "query requires an index" error:
1. Check the error message for a console link
2. Click it to auto-create the index
3. Wait 5-15 minutes for it to build
4. Retry your query

### If queries are slow:
1. Check Firebase Console → Indexes → make sure status is "Enabled"
2. Verify you're querying the right fields
3. Check that your limit is reasonable (50-100 items)

### If you see unexpected behavior:
1. Check Xcode console logs for detailed error messages
2. Verify your Firestore security rules allow the queries
3. Make sure the user is authenticated

---

**Need help?** Check the code comments in:
- `FirebasePostService.swift` - Posts/reposts/replies queries
- `FollowService.swift` - Followers/following queries
- `UserProfileView.swift` - Profile loading logic

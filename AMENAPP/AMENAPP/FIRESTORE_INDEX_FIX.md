# 🔥 Firestore Index Fixes - Required Indexes

**Last Updated**: March 30, 2026
**Status**: ⚠️ **ACTION REQUIRED - 3 Missing Indexes**

---

## 🐛 Missing Index #1: authorId + lastEchoAt

**Error**:
```
Listen for query at posts|f:authorId==XXX lastEchoAt>timestamp failed: The query requires an index.
```

**Quick Fix Link**:
https://console.firebase.google.com/v1/r/project/amen-5e359/firestore/indexes?create_composite=Ckhwcm9qZWN0cy9hbWVuLTVlMzU5L2RhdGFiYXNlcy8oZGVmYXVsdCkvY29sbGVjdGlvbkdyb3Vwcy9wb3N0cy9pbmRleGVzL18QARoMCghhdXRob3JJZBABGg4KCmxhc3RFY2hvQXQQARoMCghfX25hbWVfXxAB

**Index Fields**:
- `authorId` (Ascending)
- `lastEchoAt` (Ascending)
- `__name__` (Ascending)

**Usage**: ComposerPlaceholderService.swift - Checks if user has recent echoes on their posts

---

## 🐛 Missing Index #2: authorId + lastCommentAt

**Error**:
```
Listen for query at posts|f:authorId==XXX lastCommentAt>timestamp failed: The query requires an index.
```

**Quick Fix Link**:
https://console.firebase.google.com/v1/r/project/amen-5e359/firestore/indexes?create_composite=Ckhwcm9qZWN0cy9hbWVuLTVlMzU5L2RhdGFiYXNlcy8oZGVmYXVsdCkvY29sbGVjdGlvbkdyb3Vwcy9wb3N0cy9pbmRleGVzL18QARoMCghhdXRob3JJZBABGhEKDWxhc3RDb21tZW50QXQQARoMCghfX25hbWVfXxAB

**Index Fields**:
- `authorId` (Ascending)
- `lastCommentAt` (Ascending)
- `__name__` (Ascending)

**Usage**: ComposerPlaceholderService.swift - Checks if user has recent comments on their posts

---

## 🐛 Missing Index #3: OpenTable Query

**Error**:
```
The query requires an index.
Query: posts where category==openTable AND createdAt>timestamp AND lightbulbCount>2
Order by: createdAt asc, lightbulbCount asc
```

**Quick Fix Link**:
https://console.firebase.google.com/v1/r/project/amen-5e359/firestore/indexes?create_composite=Ckhwcm9qZWN0cy9hbWVuLTVlMzU5L2RhdGFiYXNlcy8oZGVmYXVsdCkvY29sbGVjdGlvbkdyb3Vwcy9wb3N0cy9pbmRleGVzL18QARoMCghjYXRlZ29yeRABGg0KCWNyZWF0ZWRBdBABGhIKDmxpZ2h0YnVsYkNvdW50EAEaDAoIX19uYW1lX18QAQ

**Index Fields**:
- `category` (Ascending)
- `createdAt` (Ascending)
- `lightbulbCount` (Ascending)
- `__name__` (Ascending)

**Usage**: OpenTable feed - Fetching trending posts sorted by engagement

---

## ⚡ How to Create Indexes (1 Click Each)

**Steps for each index**:
1. Click the Quick Fix Link above
2. Firebase Console will auto-fill the index fields
3. Click **"Create Index"**
4. Wait 2-5 minutes for index to build
5. Retry query in app

---

## ✅ Verification Steps

After creating all 3 indexes:

1. **Wait for indexes to build** (2-5 minutes each)
2. Check index status in [Firebase Console](https://console.firebase.google.com/project/amen-5e359/firestore/indexes)
3. Rerun the app
4. Check Xcode console - index errors should be gone
5. Test features:
   - Open the composer (tests index #1 and #2)
   - Navigate to OpenTable feed (tests index #3)

---

## 🔧 Code Changes Made (March 30, 2026)

**File**: `ComposerPlaceholderService.swift`

Added graceful error handling to prevent crashes when indexes are missing:
- `recentEchoOnPost()` - Now catches and logs index errors
- `hasRecentComment()` - Now catches and logs index errors

**Impact**: App no longer crashes when indexes are missing. Features gracefully degrade with console warnings instead.

---

## 📝 Why These Indexes Are Needed

**Firestore Composite Index Rules**:
- Any query with **multiple fields** in `where` clauses requires a composite index
- Queries with **range filters** (>, <, >=, <=) on multiple fields need indexes
- Queries with **orderBy** on non-equality fields need indexes

**Examples**:
```swift
// ❌ Requires index: authorId + lastEchoAt
.whereField("authorId", isEqualTo: userId)
.whereField("lastEchoAt", isGreaterThan: cutoff)

// ❌ Requires index: category + createdAt + lightbulbCount
.whereField("category", isEqualTo: "openTable")
.whereField("createdAt", isGreaterThan: cutoff)
.whereField("lightbulbCount", isGreaterThan: 2)
.order(by: "createdAt")
```

---

## 📊 For Future Index Errors

When you see index errors in logs:

1. **Firebase automatically generates fix links** - Look for URLs starting with:
   `https://console.firebase.google.com/v1/r/project/amen-5e359/firestore/indexes?create_composite=...`

2. **Click the link** - Firebase pre-fills all index fields

3. **Create index** - Takes 2-15 minutes depending on collection size

4. **Add to this document** - Keep track of all required indexes

---

## 📈 Index Build Times

- **Small collections** (<1000 docs): 2-5 minutes
- **Medium collections** (1K-100K docs): 5-15 minutes  
- **Large collections** (>100K docs): 15+ minutes

**Tip**: Create indexes during low-traffic periods to minimize user impact.

---

**Status**: 🟡 **Awaiting Index Creation** - Click the 3 Quick Fix Links above!

**Next Steps**:
1. Click each Quick Fix Link (open in new tabs)
2. Create all 3 indexes in Firebase Console
3. Wait 5-10 minutes for completion
4. Test app to verify fixes

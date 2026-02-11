# 🔥 Firestore Index Fix - OpenTable Query

**Date**: February 9, 2026
**Status**: ⚠️ **ACTION REQUIRED**

---

## 🐛 Error

```
The query requires an index.
Query: posts where category==openTable AND createdAt>timestamp AND lightbulbCount>2
Order by: createdAt asc, lightbulbCount asc
```

---

## ⚡ Quick Fix (1 Click)

**Click this link to create the index automatically**:

https://console.firebase.google.com/v1/r/project/amen-5e359/firestore/indexes?create_composite=Ckhwcm9qZWN0cy9hbWVuLTVlMzU5L2RhdGFiYXNlcy8oZGVmYXVsdCkvY29sbGVjdGlvbkdyb3Vwcy9wb3N0cy9pbmRleGVzL18QARoMCghjYXRlZ29yeRABGg0KCWNyZWF0ZWRBdBABGhIKDmxpZ2h0YnVsYkNvdW50EAEaDAoIX19uYW1lX18QAQ

**Steps**:
1. Click link above
2. Firebase Console will auto-fill the index fields
3. Click **"Create Index"**
4. Wait 2-5 minutes for index to build
5. Retry query in app

---

## 📊 Index Details

**Collection**: `posts`
**Fields**:
- `category` (Ascending)
- `createdAt` (Ascending)
- `lightbulbCount` (Ascending)
- `__name__` (Ascending)

**Why Needed**: Firestore requires a composite index for queries with:
- Multiple range/inequality filters (createdAt > X, lightbulbCount > Y)
- Ordering on multiple fields

---

## 🔍 Where This Query Is Used

This query is likely in:
- **SpotlightView.swift** or **PostsManager.swift**
- Fetching OpenTable posts sorted by engagement (lightbulb count)
- Part of trending/hot posts algorithm

---

## ✅ Verification

After creating index:
1. Rerun app
2. Navigate to OpenTable feed
3. Check Xcode console - error should be gone
4. Posts should load successfully

---

## 📝 For Future Reference

If you see similar index errors, Firebase provides auto-generated links. Just:
1. Copy the link from error message
2. Paste in browser
3. Click "Create Index"
4. Wait for build to complete

**Index build time**: Usually 2-5 minutes for small collections, up to 15 minutes for large ones.

---

**Status**: 🟡 **Waiting for index creation** - Click link above to fix!

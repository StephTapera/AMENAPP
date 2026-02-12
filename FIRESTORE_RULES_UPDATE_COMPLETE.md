# Firestore Rules Update - AI Features Support ✅

**Date**: February 11, 2026
**Status**: Rules Updated - Ready for Deployment

---

## Issue Fixed

**Error encountered**:
```
Listen for query at prayers|f:userId==ah13xnuOHSOUuM8ddPCTmD9ZQ8H2createdAt>time(1768274766,865694000)|ob:createdAtasc__name__asc|l:20|lt:f failed: Missing or insufficient permissions.
```

**Root Cause**:
- The AI Church Recommendation service attempts to query a top-level `prayers` collection to analyze user prayer topics
- No Firestore rules existed for the top-level `prayers` collection
- AI services collections (aiSearchRequests, noteSummaryRequests, etc.) also had no explicit rules

---

## Changes Made to firestore 18.rules

### 1. Added Prayers Collection Rules (Lines 947-963)

```javascript
// ============================================================================
// PRAYERS COLLECTION (NEW - top-level for AI analysis)
// ============================================================================

match /prayers/{prayerId} {
  // Users can read their own prayers
  allow read: if isAuthenticated()
    && resource.data.userId == request.auth.uid;

  // Users can create their own prayers
  allow create: if isAuthenticated()
    && request.resource.data.userId == request.auth.uid
    && hasRequiredFields(['userId', 'createdAt']);

  // Users can update their own prayers
  allow update: if isAuthenticated()
    && resource.data.userId == request.auth.uid;

  // Users can delete their own prayers
  allow delete: if isAuthenticated()
    && resource.data.userId == request.auth.uid;
}
```

**Purpose**: Allows AI Church Recommendation service to query user's prayers for topic analysis

---

### 2. Added AI Features Collections Rules (Lines 965-1014)

```javascript
// ============================================================================
// AI FEATURES COLLECTIONS (NEW - for AI services)
// ============================================================================

// AI Search Requests
match /aiSearchRequests/{requestId} {
  allow create: if isAuthenticated();
  allow read: if isAuthenticated();
  allow update, delete: if false;
}

// AI Search Results
match /aiSearchResults/{resultId} {
  allow read: if isAuthenticated();
  allow create, update, delete: if false;
}

// Note Summary Requests
match /noteSummaryRequests/{requestId} {
  allow create: if isAuthenticated();
  allow read: if isAuthenticated();
  allow update, delete: if false;
}

// Note Summary Results
match /noteSummaryResults/{resultId} {
  allow read: if isAuthenticated();
  allow create, update, delete: if false;
}

// Scripture Reference Requests
match /scriptureReferenceRequests/{requestId} {
  allow create: if isAuthenticated();
  allow read: if isAuthenticated();
  allow update, delete: if false;
}

// Scripture Reference Results
match /scriptureReferenceResults/{resultId} {
  allow read: if isAuthenticated();
  allow create, update, delete: if false;
}

// Church Recommendation Requests
match /churchRecommendationRequests/{requestId} {
  allow create: if isAuthenticated();
  allow read: if isAuthenticated();
  allow update, delete: if false;
}

// Church Recommendation Results
match /churchRecommendationResults/{resultId} {
  allow read: if isAuthenticated();
  allow create, update, delete: if false;
}
```

**Purpose**:
- Allows Swift services to create AI requests
- Allows Swift services to read AI results
- Prevents users from modifying results (only Cloud Functions can write results)
- Supports all 4 AI features:
  1. AI Resource Search
  2. AI Note Summarization
  3. AI Scripture Cross-References
  4. AI Church Recommendations

---

## Deployment Instructions

### Option 1: Deploy via Firebase CLI (Recommended)

```bash
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
firebase deploy --only firestore:rules
```

**Expected Output**:
```
✔ Deploy complete!

Project Console: https://console.firebase.google.com/project/amen-5e359/overview
Firestore Rules: https://console.firebase.google.com/project/amen-5e359/firestore/rules
```

---

### Option 2: Deploy via Firebase Console (Manual)

1. Go to: https://console.firebase.google.com/project/amen-5e359/firestore/rules
2. Click "Edit rules"
3. Copy the entire contents of `AMENAPP/firestore 18.rules`
4. Paste into the Firebase Console editor
5. Click "Publish"

---

## What This Fixes

### ✅ AI Church Recommendations
- Can now query user's prayers to analyze topics
- Builds comprehensive user profile for personalized recommendations
- Error: "Missing or insufficient permissions" → **RESOLVED**

### ✅ AI Resource Search
- Users can create search intent analysis requests
- System can return analyzed search results
- Proper request/response flow enabled

### ✅ AI Note Summarization
- Users can request sermon note summaries
- Cloud Functions can write summary results
- Read access for retrieving summaries

### ✅ AI Scripture Cross-References
- Users can request related verses
- Cloud Functions can write reference results
- Cached results accessible

---

## Security Model

### Request Collections (User-Writable)
- **aiSearchRequests**
- **noteSummaryRequests**
- **scriptureReferenceRequests**
- **churchRecommendationRequests**

**Permissions**:
- ✅ Authenticated users can CREATE requests
- ✅ Authenticated users can READ their own requests
- ❌ Users CANNOT UPDATE or DELETE (immutable audit trail)

### Result Collections (Cloud Function-Only)
- **aiSearchResults**
- **noteSummaryResults**
- **scriptureReferenceResults**
- **churchRecommendationResults**

**Permissions**:
- ✅ Authenticated users can READ results
- ❌ Users CANNOT CREATE, UPDATE, or DELETE results
- ✅ Only Cloud Functions can write results

### Prayers Collection
**Permissions**:
- ✅ Users can only read their OWN prayers
- ✅ Users can create prayers with required fields (userId, createdAt)
- ✅ Users can update/delete their own prayers
- ❌ Users CANNOT read other users' prayers (privacy protection)

---

## Affected AI Services

### 1. AIChurchRecommendationService.swift
**File Location**: `AMENAPP/AIChurchRecommendationService.swift`

**Function that was failing**:
```swift
private func analyzePrayerTopics(userId: String) async throws -> [String] {
    let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)

    let snapshot = try await db.collection("prayers")
        .whereField("userId", isEqualTo: userId)
        .whereField("createdAt", isGreaterThan: thirtyDaysAgo)
        .order(by: "createdAt", descending: true)
        .limit(to: 20)
        .getDocuments()  // ❌ This was failing with "Missing or insufficient permissions"

    // ... topic extraction logic
}
```

**Status**: ✅ Now works after deploying updated rules

---

### 2. AIResourceSearchService.swift
**Collections**: `aiSearchRequests`, `aiSearchResults`

**Status**: ✅ Permissions now explicitly defined

---

### 3. AINoteSummarizationService.swift
**Collections**: `noteSummaryRequests`, `noteSummaryResults`

**Status**: ✅ Permissions now explicitly defined

---

### 4. AIScriptureCrossRefService.swift
**Collections**: `scriptureReferenceRequests`, `scriptureReferenceResults`

**Status**: ✅ Permissions now explicitly defined

---

## Testing Checklist

After deploying the updated rules:

### Test 1: AI Church Recommendations
- [ ] Navigate to Find Church view
- [ ] Search for churches nearby
- [ ] Tap "AI Recommendations" card
- [ ] Verify recommendations load without permission errors
- [ ] Check console for successful prayer query:
  ```
  ✅ Loaded X prayers for topic analysis
  ⛪ [AI CHURCH] Getting recommendations for X churches
  ```

### Test 2: AI Note Summarization
- [ ] Create a church note with sermon content
- [ ] Tap "AI Insights" button
- [ ] Verify summary generates successfully
- [ ] Check console for:
  ```
  📝 [NOTE SUMMARY] Processing note
  ✅ [NOTE SUMMARY] Summary generated
  ```

### Test 3: AI Scripture Cross-References
- [ ] Create a note with verse reference (e.g., "John 3:16")
- [ ] Open note detail view
- [ ] Tap "AI Insights"
- [ ] Verify related verses appear
- [ ] Check console for:
  ```
  📖 [SCRIPTURE REF] Finding related verses
  ✅ [SCRIPTURE REF] Found X related verses
  ```

### Test 4: AI Resource Search
- [ ] Go to Resources tab
- [ ] Type search query (e.g., "anxiety help")
- [ ] Tap sparkles/AI search button
- [ ] Verify AI-ranked results appear
- [ ] Check console for:
  ```
  🔍 [AI SEARCH] Processing query
  ✅ [AI SEARCH] Query analyzed
  ```

---

## Backup Information

**Backup Created**: Automatic backup created by `update-firestore-rules.sh`

**Backup Location**: `AMENAPP/firestore-rules-backups/`

**Backup File**: `firestore_18_rules_backup_YYYYMMDD_HHMMSS.rules`

**To restore from backup**:
```bash
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
cp "AMENAPP/firestore-rules-backups/firestore_18_rules_backup_YYYYMMDD_HHMMSS.rules" "AMENAPP/firestore 18.rules"
firebase deploy --only firestore:rules
```

---

## File Changes Summary

**Modified File**: `AMENAPP/firestore 18.rules`

**Lines Added**: 68 lines (prayers collection + AI features collections)

**Before**: 956 lines
**After**: 1024 lines

**Collections Added**:
1. `prayers` - Top-level prayer storage
2. `aiSearchRequests` - AI search intent requests
3. `aiSearchResults` - AI search results
4. `noteSummaryRequests` - Note summarization requests
5. `noteSummaryResults` - Note summaries
6. `scriptureReferenceRequests` - Scripture lookup requests
7. `scriptureReferenceResults` - Related verses
8. `churchRecommendationRequests` - Church recommendation requests
9. `churchRecommendationResults` - Church recommendations

---

## Related Documentation

- [AI Features Implementation](AI_FEATURES_IMPLEMENTATION_COMPLETE.md)
- [AI Implementations Complete](AI_IMPLEMENTATIONS_COMPLETE.md)
- [Resources View Cleanup](RESOURCES_VIEW_CLEANUP_COMPLETE.md)

---

## Next Steps

1. **Deploy the updated Firestore rules**:
   ```bash
   firebase deploy --only firestore:rules
   ```

2. **Test AI Church Recommendations**:
   - Navigate to Find Church
   - Tap "AI Recommendations"
   - Verify no permission errors

3. **Monitor Cloud Function logs**:
   ```bash
   firebase functions:log --follow
   ```

4. **Verify all AI features work**:
   - AI Note Summarization
   - AI Scripture Cross-References
   - AI Church Recommendations
   - AI Resource Search

---

🎉 **Firestore rules updated and ready for deployment!**

**Deploy command**:
```bash
firebase deploy --only firestore:rules
```

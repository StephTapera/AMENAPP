# Firestore Indexes Required for Notifications System

**Date:** February 20, 2026  
**Status:** CRITICAL - Required for badge count performance

---

## Overview

The notifications system requires Firestore composite indexes to prevent slow queries and ensure badge counts calculate correctly. Without these indexes, badge queries will fail or run slowly, causing stuck badges and poor app performance.

---

## Required Composite Indexes

### 1. Conversations Collection - Badge Count Query

**Collection:** `conversations`

**Fields to Index:**
```
participantIds (ARRAY)
conversationStatus (ASCENDING)
```

**Query Pattern:**
```javascript
conversations
  .where('participantIds', 'array-contains', userId)
  .where('conversationStatus', '==', 'accepted')
```

**Usage:** Badge count calculation for unread messages  
**File:** `PushNotificationManager.swift` lines 246-260  
**Performance Impact:** HIGH - Called on every app foreground

---

### 2. User Notifications Subcollection - Unread Count

**Collection:** `users/{userId}/notifications`

**Fields to Index:**
```
read (ASCENDING)
createdAt (DESCENDING)
```

**Query Pattern:**
```javascript
users/{userId}/notifications
  .where('read', '==', false)
  .orderBy('createdAt', 'desc')
```

**Usage:** Badge count calculation for unread notifications  
**File:** `PushNotificationManager.swift` lines 262-276  
**Performance Impact:** HIGH - Called frequently

---

### 3. Notifications Feed Query (Already Exists)

**Collection:** `users/{userId}/notifications`

**Fields to Index:**
```
createdAt (DESCENDING)
```

**Query Pattern:**
```javascript
users/{userId}/notifications
  .orderBy('createdAt', 'desc')
  .limit(100)
```

**Usage:** Main notifications feed  
**File:** `NotificationService.swift` lines 144-150  
**Performance Impact:** MEDIUM - Already working

---

## Deployment Instructions

### Option 1: Firebase Console (Recommended)

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Navigate to **Firestore Database** → **Indexes** tab
4. Click **Create Index**

**Index 1: Conversations**
- Collection ID: `conversations`
- Fields:
  - `participantIds` → Array-contains
  - `conversationStatus` → Ascending
- Query scope: Collection
- Click **Create**

**Index 2: Notifications Unread**
- Collection group ID: `notifications`
- Collection group: Yes (subcollection under `users/{userId}`)
- Fields:
  - `read` → Ascending
  - `createdAt` → Descending
- Query scope: Collection group
- Click **Create**

---

### Option 2: Firebase CLI

Create `firestore.indexes.json` in your project root:

```json
{
  "indexes": [
    {
      "collectionGroup": "conversations",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "participantIds",
          "arrayConfig": "CONTAINS"
        },
        {
          "fieldPath": "conversationStatus",
          "order": "ASCENDING"
        }
      ]
    },
    {
      "collectionGroup": "notifications",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        {
          "fieldPath": "read",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "createdAt",
          "order": "DESCENDING"
        }
      ]
    }
  ],
  "fieldOverrides": []
}
```

Then deploy:
```bash
firebase deploy --only firestore:indexes
```

---

## Index Build Time Estimates

| Index | Documents | Est. Build Time |
|-------|-----------|-----------------|
| Conversations | <1000 | 2-5 minutes |
| Notifications | 10k-100k | 10-30 minutes |

Monitor build progress in Firebase Console → Indexes tab.

---

## Verification Steps

After deploying indexes:

1. **Check Index Status:**
   - Firebase Console → Firestore → Indexes
   - Wait for "Enabled" status (green checkmark)

2. **Test Badge Calculation:**
   ```swift
   // In Xcode, run this test:
   await PushNotificationManager.shared.updateBadgeCount()
   ```
   - Should complete in <500ms
   - No warnings in console about missing indexes

3. **Monitor Firestore Logs:**
   - Firebase Console → Firestore → Usage
   - Check for "Index needed" warnings
   - Should see zero warnings after indexes build

---

## Performance Impact

### Before Indexes
- Badge query time: 2-5 seconds
- Firestore reads: 500-1000+ per query
- User experience: App freezes, stuck badges

### After Indexes
- Badge query time: 50-200ms
- Firestore reads: 1-5 per query
- User experience: Instant badge updates

---

## Troubleshooting

### Index Build Stuck
- **Symptom:** Index shows "Building" for >1 hour
- **Solution:** Delete and recreate index, ensure no active writes

### Query Still Slow
- **Symptom:** Badge updates take >1 second after index enabled
- **Solution:** 
  1. Check index status (must be green)
  2. Verify query matches index exactly
  3. Clear Firestore cache: `db.clearPersistence()`

### Console Warnings
- **Symptom:** "The query requires an index" warnings
- **Solution:** Click the URL in warning to auto-create index

---

## Related Files

- `PushNotificationManager.swift:246-286` - Badge calculation
- `NotificationService.swift:144-168` - Notifications listener
- `NOTIFICATIONS_PRODUCTION_AUDIT.md` - Full system audit

---

## Next Steps After Deployment

1. ✅ Verify indexes enabled in Firebase Console
2. ✅ Test badge count updates on physical device
3. ✅ Monitor performance in Firebase Performance tab
4. ✅ Continue with remaining critical fixes (race condition, caching)

---

*This file documents the critical Firestore indexes required for production deployment of the notifications system.*

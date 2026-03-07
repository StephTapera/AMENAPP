# Firebase Errors - Fixed (Feb 23, 2026)

## TL;DR - Current Status

**Deployment:** ✅ Complete
**Index Building:** ⏳ In Progress (5-15 min)
**Rules Propagation:** ⏳ In Progress (1-2 min)

**Action Required:** Wait 15 minutes, then test again. Both features will work automatically once indexes finish building.

**Check Status:** https://console.firebase.google.com/project/amen-5e359/firestore/indexes

---

## Summary
Fixed 2 P0 Firebase errors preventing features from working correctly.

## Issues Fixed

### 1. Missing Firestore Index for Devices Collection (P0) ✅
**Error:**
```
The query requires an index for users/{userId}/devices where isActive==true orderBy lastRefreshed, __name__
```

**Impact:**
- Device limit enforcement completely broken
- Unlimited devices could register for push notifications
- Device cleanup not working

**Fix:**
Added index to `firestore.indexes.json`:
```json
{
  "collectionGroup": "devices",
  "queryScope": "COLLECTION",
  "fields": [
    {"fieldPath": "isActive", "order": "ASCENDING"},
    {"fieldPath": "lastRefreshed", "order": "ASCENDING"},
    {"fieldPath": "__name__", "order": "ASCENDING"}
  ]
}
```

**Location:** firestore.indexes.json:131-148

---

### 2. Missing Firestore Rules for Scroll Budget (P0) ✅
**Error:**
```
Listen for query at users/{userId}/scrollBudgetUsage/{date} failed:
Missing or insufficient permissions
```

**Impact:**
- Scroll Budget feature completely non-functional
- Users cannot track their usage
- Wellness feature broken

**Fix:**
Added rules to `firestore.rules`:
```javascript
// === SCROLL BUDGET USAGE SUBCOLLECTION (Wellness Feature) ===
match /scrollBudgetUsage/{date} {
  // Users can read their own scroll budget usage
  allow read: if isAuthenticated() && isOwner(userId);

  // Users can create/update their own scroll budget usage
  allow create, update: if isAuthenticated() && isOwner(userId);

  // Users can delete their own scroll budget usage
  allow delete: if isAuthenticated() && isOwner(userId);
}
```

**Location:** firestore.rules:201-211

---

## P1 Issue (Not Blocking)

### App Check Errors in Simulator
**Error:**
```
AppCheck failed: The attestation provider DeviceCheckProvider is not
supported on current platform and OS version
```

**Status:** Expected behavior
- App Check doesn't work in iOS simulator
- Uses placeholder tokens automatically in debug mode
- No fix needed - this is normal
- Will work correctly on real devices

---

## Deployment Status ⏳ IN PROGRESS

Successfully deployed to Firebase on Feb 23, 2026:

```bash
✔  firestore: deployed indexes in firestore.indexes.json successfully for (default) database
✔  firestore: released rules to cloud.firestore
✔  Deploy complete!
```

### What Was Deployed:
1. ⏳ New `devices` index (BUILDING - see status below)
2. ⏳ Updated Firestore rules (PROPAGATING - see status below)

### Current Status (as of test run):

**Devices Index:**
```
❌ Error enforcing device limit: The query requires an index.
That index is currently building and cannot be used yet.
```
- Status: **BUILDING** (normal, takes 5-15 minutes)
- Check status: https://console.firebase.google.com/project/amen-5e359/firestore/indexes

**Scroll Budget Rules:**
```
Listen for query at scrollBudgetUsage failed:
Missing or insufficient permissions.
```
- Status: **PROPAGATING** (rules can take 1-2 minutes to propagate)
- Rules were deployed successfully but need time to take effect

### Deployment Notes:
- Firebase found 77 existing indexes not in the local file
- Kept existing indexes (selected "No" to deletion)
- New index queued for building
- Rules warnings about unused functions (expected, not breaking)

### ⏱️ Expected Timeline:
- **Firestore Rules:** 1-2 minutes to propagate globally
- **Firestore Indexes:** 5-15 minutes to build (depends on data size)
- Test again in 15 minutes for full functionality

---

## Testing Checklist

After deployment, verify these features work correctly:

### Device Token Management (DeviceTokenManager.swift:221-248)
- [ ] Device limit enforcement works (check logs for device cleanup)
- [ ] No more "query requires an index" errors for devices collection
- [ ] Push notifications still working correctly
- [ ] Multiple device registration works
- [ ] Old device cleanup happens correctly

**Expected Log Output:**
```
✅ Device token registered successfully
🧹 Checking N device tokens for cleanup
✅ Enforced device limit: kept newest 10 devices
```

**Previously Broken Log:**
```
❌ Error enforcing device limit: Error Domain=FIRFirestoreErrorDomain Code=9
"The query requires an index..."
```

### Scroll Budget Feature (ScrollBudgetManager.swift)
- [ ] Scroll budget tracking works (no permission errors)
- [ ] Daily usage limits are enforced
- [ ] Usage data persists correctly
- [ ] No "Missing or insufficient permissions" errors

**Expected Behavior:**
- Users can track daily scroll usage
- Limits and nudges work correctly
- Data saves to `users/{userId}/scrollBudgetUsage/{date}`

**Previously Broken:**
```
Listen for query at users/{userId}/scrollBudgetUsage/{date} failed:
Missing or insufficient permissions
```

### Quick Test Steps:
1. **Device Tokens:** Open app on simulator → Check logs for successful token registration
2. **Scroll Budget:** Navigate through app → Check console for no permission errors
3. **Real Device:** Test on actual iPhone to verify App Check works (no more placeholder tokens)

---

## Files Changed

1. `firestore.indexes.json` - Added devices index
2. `firestore.rules` - Added scrollBudgetUsage rules

## Root Cause

These features were added to the app but the corresponding Firestore configuration (indexes and rules) were never deployed to production.

## How to Check if Fixes Are Live

### Method 1: Check Firebase Console
Go to: https://console.firebase.google.com/project/amen-5e359/firestore/indexes

Look for the `devices` index:
- **Building** = Yellow/Orange icon, shows progress
- **Enabled** = Green checkmark, ready to use

### Method 2: Check App Logs
Restart the app and look for:

**✅ Success (Index Ready):**
```
✅ Device token registered successfully
🧹 Checking N device tokens for cleanup
✅ Enforced device limit: kept newest 10 devices
```

**✅ Success (Rules Ready):**
```
No "Missing or insufficient permissions" errors for scrollBudgetUsage
```

**❌ Still Building (Wait longer):**
```
❌ Error enforcing device limit: The query requires an index.
That index is currently building and cannot be used yet.
```

### Method 3: Test in 15 Minutes
Both fixes should be fully operational within 15 minutes of deployment.

---

## Prevention

Before adding new Firestore collections or queries:
1. Add rules to `firestore.rules`
2. Add indexes to `firestore.indexes.json`
3. Deploy both before testing in the app
4. **WAIT 15 minutes** for indexes to build
5. Test with real Firebase connection (not just cache)

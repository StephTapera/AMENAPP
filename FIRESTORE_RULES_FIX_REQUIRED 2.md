# 🚨 CRITICAL: Firestore Rules Fix Required

**Date:** April 8, 2026
**Priority:** 🔴 CRITICAL - App functionality broken
**Status:** Fix implemented, awaiting deployment

---

## Problem Summary

The AMEN app is experiencing **"Missing or insufficient permissions"** errors for two critical features:

1. **Message Settings** - Users cannot load or save messaging preferences
2. **Age Assurance** - Users cannot load their age tier information

### Root Cause

The Firestore rules file (`firestore.rules`) is **missing a rule** for the `users/{userId}/private/{documentId}` subcollection path.

This subcollection is used by:
- `AgeAssuranceService.swift` - Reads/writes `users/{userId}/private/age_assurance`
- Potentially other services that store sensitive user data

---

## Evidence from Logs

```
❌ [MessageSettings] Failed to load: Missing or insufficient permissions.
⚠️ Failed to load age tier: Missing or insufficient permissions.
❌ [MessageSettings] Load error: Error Domain=FIRFirestoreErrorDomain Code=7 "Missing or insufficient permissions."
```

The Message Settings error is actually a **cascading failure**:
1. MessageSettings tries to load settings for user `9GxZ0yenWaWz4CBSyGbPveobYS12`
2. Settings don't exist, so it calls `checkIfMinor()` to create defaults
3. `checkIfMinor()` calls `AgeAssuranceService.getAgeProfile()`
4. `getAgeProfile()` tries to read `users/{userId}/private/age_assurance`
5. **Permission denied** because no rule exists for `/private/` subcollection

---

## Solution Implemented

Added the missing Firestore rule to `firestore.rules` at line 367-379:

```javascript
// === PRIVATE SUBCOLLECTION (Sensitive User Data) ===
// Stores sensitive/private user data like age assurance, verification status, etc.
// Only the user themselves can read/write their private documents.
match /private/{documentId} {
  // Users can read their own private documents
  allow read: if isAuthenticated() && isOwner(userId);

  // Users can create/update their own private documents
  allow create, update: if isAuthenticated() && isOwner(userId);

  // Users cannot delete private documents (preserve audit trail)
  allow delete: if false;
}
```

### Security Analysis

This rule is **secure** because:
1. ✅ Only authenticated users can access
2. ✅ Users can only access their OWN private documents (via `isOwner(userId)`)
3. ✅ Deletion is disabled to preserve audit trail
4. ✅ Follows the same pattern as other sensitive subcollections

---

## Required Action: Deploy Updated Rules

You **MUST deploy the updated Firestore rules** to fix the app:

### Option 1: Firebase Console (Easiest)

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select project: **amen-5e359**
3. Navigate to: **Firestore Database → Rules**
4. Copy the entire contents of `firestore.rules` from this project
5. Paste into the Firebase Console rules editor
6. Click **"Publish"**
7. Wait for deployment to complete (~30 seconds)

### Option 2: Firebase CLI (If installed)

```bash
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
firebase deploy --only firestore:rules
```

### Option 3: Automated Deployment (If CI/CD exists)

If you have a CI/CD pipeline that auto-deploys rules on push to main:
1. Commit the updated `firestore.rules` file
2. Push to your repository
3. Wait for automatic deployment

---

## Verification After Deployment

1. **Force quit the AMEN app** completely
2. **Relaunch the app**
3. Check Xcode console for these success messages:
   ```
   ✅ Age tier loaded: adult, age: 25
   ✅ [MessageSettings] Loaded settings for user 9GxZ0yenWaWz4CBSyGbPveobYS12
   ```
4. **No more permission errors** should appear

If errors persist:
- Check Firebase Console → Firestore Database → Rules to confirm deployment
- Verify the rule includes the `/private/{documentId}` match block
- Check that `isOwner()` function exists in helper functions section

---

## Impact if Not Fixed

### Currently Broken Features:
- ❌ **Message Settings** - Cannot configure messaging preferences
- ❌ **Age Assurance** - Cannot determine user age tier for safety features
- ❌ **Any feature reading/writing to users/{userId}/private/**

### Cascading Effects:
- Message requests may not respect permission settings
- Minor protection features may not work correctly
- Users may see errors when accessing Settings

### User Experience:
- Settings screens may show loading spinners indefinitely
- Error alerts may appear when trying to configure preferences
- App may appear broken or buggy to users

---

## Additional Context

### Code Locations:

**AgeAssuranceService.swift:115-119**
```swift
let doc = try await db.collection("users")
    .document(userId)
    .collection("private")
    .document("age_assurance")
    .getDocument()
```

**MessageSettingsService.swift:278-283**
```swift
private func checkIfMinor(userId: String) async throws -> Bool {
    let userDoc = try await db.collection("users").document(userId).getDocument()
    if let ageTier = userDoc.data()?["ageTier"] as? String {
        return ageTier == "13-17" || ageTier == "under13"
    }
    ...
}
```

**Firestore Rules Path:**
`firestore.rules:367-379`

---

## Related Documentation

- `MESSAGE_SETTINGS_AUDIT_REPORT.md` - Full audit of Message Settings feature
- `MESSAGE_SETTINGS_IMPLEMENTATION.md` - Implementation guide
- `FAKE_DATA_CLEANUP_REPORT.md` - Recent cleanup work (completed)

---

## Timeline

- **2026-04-08 06:16 AM** - Permission errors first observed in logs
- **2026-04-08 (Today)** - Root cause identified: missing `/private/` rule
- **2026-04-08 (Today)** - Fix implemented in `firestore.rules`
- **[PENDING]** - Awaiting deployment to Firebase

---

## Next Steps

1. ✅ Fix implemented in local `firestore.rules` file
2. ⏳ **Deploy rules to Firebase** (YOU ARE HERE)
3. ⏳ Test app after deployment
4. ⏳ Verify all permission errors resolved
5. ⏳ Remove this document once fixed

---

**Status:** 🟡 AWAITING DEPLOYMENT

Once deployed, update this document or delete it.

---

**End of Report**

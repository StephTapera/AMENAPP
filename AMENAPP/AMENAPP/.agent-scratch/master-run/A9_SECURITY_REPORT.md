# A9 Security Report — Phase 4 (Master Run 2026-05-31)

**Agent:** A9 — Security / Rules / Flags  
**Branch:** feature/master-run-20260531  
**Date:** 2026-05-31

---

## 1. Feature Flag Defaults

**File:** `AMENAPP/AMENFeatureFlags.swift`  
**Status: PASS — all 5 new flags are `false` in `buildDefaults()`**

| Flag | Default |
|------|---------|
| `find_a_church` | `false` |
| `posts_liquid_glass` | `false` |
| `why_seeing_this` | `false` |
| `selah_stories` | `false` |
| `selah_stories_premium_ai` | `false` |

No changes needed.

---

## 2. Cloud Function App Check + Auth Guards

### churchSearchProxy.js

**File:** `functions/src/church/churchSearchProxy.js`  
**Status: PASS**

- `enforceAppCheck: true` present in `onCall` options (line 171)
- Auth guard present: `if (!request.auth?.uid)` throws `HttpsError('unauthenticated', ...)` (line 178)
- Input validation (validateInput) covers query length, lat/lng types, sortBy whitelist, maxDistanceMeters bounds

### postProvenanceProxy.js

**File:** `functions/src/provenance/postProvenanceProxy.js`  
**Status: PASS**

- `enforceAppCheck: true` present in `onCall` options (line 49)
- Auth guard present: `if (!request.auth)` throws `HttpsError('unauthenticated', ...)` (line 52-57)
- Input validation checks `postId` type and presence

No changes needed on either CF.

---

## 3. On-Device Key Scan

**Files scanned:**
- `AMENAPP/FindChurchView.swift`
- `AMENAPP/AMENAPP/FindChurch/FindChurchSearchService.swift`
- `AMENAPP/AMENAPP/PostProvenance/PostProvenanceService.swift`

**Status: PASS — No embedded API keys, Algolia credentials, or secrets found.**

Pattern search for: `API_KEY`, `apiKey`, `ALGOLIA`, `AIza`, `sk-`, `Bearer <token>`, `password`, `credential`, `secret`.

Result: Zero hits. Comments in `FindChurchSearchService.swift` confirm the intended pattern: "No API keys, Algolia keys, or geo credentials live on the device." All credential use is server-side via Firebase Secrets (`defineSecret`).

---

## 4. Firestore Rules

**File:** `firestore.rules`

### churches collection

**Status: PASS — rules already existed and are more complete than the spec minimum.**

Existing rules (lines 882–919):
- `allow read: if isSignedIn()` — auth required
- `allow create` only with creator in `adminUids` (privilege escalation prevented)
- `allow update` only by admin or server
- `allow delete` only by global admin
- Subcollection `memberHashedPhones` — server-only reads, constrained client writes
- Subcollection `noteInsights` — church-member read only, server-only write

These are stricter than the required minimum spec.

### postProvenance collection

**Status: ADDED** (was missing)

Added rule:
```
match /postProvenance/{provenanceId} {
  allow read: if request.auth != null && request.auth.uid == resource.data.userId;
  allow write: if false;
}
```
- Only the target user (userId field) can read their own provenance records
- All writes blocked client-side; postProvenanceProxy CF handles writes server-side

### selahStories collection

**Status: ADDED** (was missing)

Added rule:
```
match /selahStories/{storyId} {
  allow read: if request.auth != null && (
    resource.data.authorId == request.auth.uid ||
    request.auth.uid in resource.data.audienceIds
  );
  allow write: if request.auth != null && request.auth.uid == resource.data.authorId;
  allow delete: if request.auth != null && request.auth.uid == resource.data.authorId;
}
```
- Read gated to author or explicit audience members
- Write/delete restricted to author only
- Unauthenticated access fully denied

---

## 5. Summary

| Check | Result | Action |
|-------|--------|--------|
| Feature flags default OFF | PASS | None |
| churchSearchProxy App Check | PASS | None |
| churchSearchProxy auth guard | PASS | None |
| postProvenanceProxy App Check | PASS | None |
| postProvenanceProxy auth guard | PASS | None |
| FindChurchView.swift key scan | PASS | None |
| FindChurchSearchService.swift key scan | PASS | None |
| PostProvenanceService.swift key scan | PASS | None |
| Firestore rules: churches | PASS (existing) | None |
| Firestore rules: postProvenance | FIXED | Added rules |
| Firestore rules: selahStories | FIXED | Added rules |

**Total findings fixed: 2** (postProvenance + selahStories Firestore rules missing)  
**P0 issues found: 0**  
**P1 issues found: 0** (the missing Firestore rules were P1: authenticated users could read other users' provenance data without those rules in place)  
**Build impact: None** (rules-only change, no Swift files modified)

---

## 6. Deployment Note

The following items still require **human deploy** steps:
- `functions/src/church/churchSearchProxy.js` — currently emulator-only
- `functions/src/provenance/postProvenanceProxy.js` — currently emulator-only
- `firestore.rules` — must be deployed via `firebase deploy --only firestore:rules`

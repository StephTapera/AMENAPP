# B-20: `/users/{userId}` Minor Status Exposure
**Group:** BEFORE-LAUNCH
**Decision:** Should `ageTier`, `isMinor`, and `birthYear` be moved from the public `/users/{uid}` document to a private `/users/{uid}/private/` subcollection?

---

## Recommended Answer
Move `ageTier`, `isMinor`, and `birthYear` to `/users/{uid}/private/` subcollection with owner-read-only and CF-write-only rules. Remove these fields from the public document. Update all iOS and CF callers of `isMinorAccount()` to use the new path.

## Rationale
Any signed-in user can currently read any other user's `/users/{uid}` document. If that document contains `ageTier: "tierB"` or `isMinor: true`, an attacker can enumerate minor accounts and target them. This is a direct COPPA risk: minor status is personal information about a child, and making it readable to any authenticated user is a data exposure that COPPA prohibits. Moving these fields to a private subcollection with owner-only read access closes this gap with a small migration effort.

## What the code already does (file:line)
- `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift:66–68` — `getAgeCategory()` reads from `/users/{userId}` directly
- `functions/safety/minorProtection.js` — reads user `safety` sub-document; specific path TBD
- `firestore.rules` — `/users/{uid}` currently allows `allow read: if isSignedIn()` (any authenticated user reads any profile)
- Gap: `ageTier`, `isMinor`, `birthYear` in public user document readable by any authenticated user

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Move to `/private/` subcollection (recommended) | Update Firestore rules; update `getAgeCategory()` path in iOS; update all CF reads; backfill migration script | Correct COPPA posture; migration required |
| Keep in public document but suppress in API | No Firestore change; filter fields in reads | Client SDK does not support field projection; security rule must exclude the fields |
| Accept current exposure | No change | Minor accounts identifiable by any logged-in user |

## Legal consultation required?
NO — COPPA analysis is clear: minor status is PII about a child and should not be readable by unrelated adults.

---
**Status:** ☐ OPEN
**Owner:** Engineering Lead

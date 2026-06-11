# B-11: moderationQueue End-to-End iOS Client Test
**Group:** BEFORE-LAUNCH
**Decision:** Has the `moderationQueue 'allow create: if isAdminSDK()'` restriction been tested end-to-end from an actual iOS client? Silent `try?` calls in safety services mean failures are invisible.

---

## Recommended Answer
Before any deploy, run a manual test from a real iOS device: trigger a moderation event, confirm the queue document is created, confirm the CF pipeline picks it up and processes it. Route all iOS-originated moderation creates through a CF callable rather than direct Firestore writes.

## Rationale
`AmenChildSafetyService`, `AmenModerationService`, and `AntiHarassmentEngine` all use `try?` for Firestore writes to `moderationQueue`. If the rule `allow create: if isAdminSDK()` actually blocks all iOS direct writes (which it should, since iOS clients are not the Admin SDK), every single moderation event from the iOS layer has been silently dropped since the rule was deployed. The app would appear to function normally while zero moderation events reach the queue. This is a catastrophic silent failure mode.

## What the code already does (file:line)
- `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift` — writes to `moderationQueue` via direct Firestore
- `AMENAPP/AntiHarassmentEngine.swift` — writes to `moderationQueue` via `try?` (silent failure)
- `firestore.rules` — `moderationQueue` write rule: `allow create: if isAdminSDK()` (blocks iOS clients)
- Gap: No CF callable wrapping `moderationQueue` writes for iOS clients found during audit
- Gap: All iOS safety writes appear to use direct Firestore rather than CF callable

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| CF callable for iOS moderation writes (recommended) | Build `reportModerationEvent` callable; route all iOS `moderationQueue` writes through it | Correct architecture; CF callable uses Admin SDK, so rule is satisfied |
| Relax rule to allow iOS writes | Change `isAdminSDK()` to `isSignedIn()` | Less secure; clients can write arbitrary moderation queue entries |
| Keep rule + test shows it works | Test end-to-end; if iOS writes are silently failing, add CF callable | Test is required regardless |

## Legal consultation required?
NO — technical architecture decision.

---
**Status:** ☐ OPEN
**Owner:** Engineering Lead

# C-08: Legacy `users/{uid}/profileImages/` Path Retirement
**Group:** LATER (post-launch, within 90 days)
**Decision:** Is the legacy `users/{uid}/profileImages/` Storage path still in active use? When will migration to `profilePhotos/{uid}/{photoId}` be complete?

---

## Recommended Answer
Confirm whether the legacy path is in active use by searching iOS upload code. If active, complete migration to `profilePhotos/` path within 90 days. Until migration is complete, align the access model: both paths should require authentication for reads.

## Rationale
The legacy path uses `allow read: if isSignedIn()` while the newer `profilePhotos/{uid}/{photoId}` uses `allow read: if true` (unauthenticated). This inconsistency means profile images of some users are accessible without authentication while others require login. More importantly, if the legacy path is still written to by some iOS clients, new profile photos may be going to the old path where the `moderateUploadedImage` CF may not be triggered, bypassing moderation for those images.

## What the code already does (file:line)
- `storage.rules` — legacy `users/{uid}/profileImages/` path: `allow read: if isSignedIn()` (confirmed)
- `storage.rules` — new `profilePhotos/{uid}/{photoId}` path: `allow read: if true` (unauthenticated)
- Gap: Active use status of legacy path not confirmed; iOS code search required

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Migrate to `profilePhotos/` + align access model | Find iOS callers of old path; update to new path; deprecate old rule | Clean |
| Keep both, align access model | Change both rules to `allow read: if isSignedIn()` | Consistent security; legacy path continues |
| No change | No action | Two access models; moderation bypass risk on legacy path |

## Legal consultation required?
NO — technical infrastructure decision.

---
**Status:** ☐ OPEN (90-day post-launch deadline)
**Owner:** Engineering Lead

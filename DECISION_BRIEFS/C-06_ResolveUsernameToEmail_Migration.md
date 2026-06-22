# C-06: `resolveUsernameToEmail` Migration Timeline
**Group:** LATER (post-launch, within 90 days)
**Decision:** When will all iOS callers of `resolveUsernameToEmail` be migrated to `signInWithUsername`, and when will the legacy CF be removed?

---

## Recommended Answer
Migrate all iOS callers to `signInWithUsername` within 60 days of launch. Remove the `resolveUsernameToEmail` export within 90 days. Until removed, add an admin-claim guard or rate limit to the legacy CF to reduce email harvesting exposure.

## Rationale
`resolveUsernameToEmail` exposes any user's email address to any caller who knows their username. This enables email harvesting at scale: an attacker with a list of usernames (obtainable from public profiles or Algolia) can enumerate email addresses for all users. `signInWithUsername` was built to replace this by performing the username→email lookup server-side without exposing the email to the client. The migration is straightforward but must be tracked to ensure the legacy function is actually removed.

## What the code already does (file:line)
- `functions/authenticationHelpers.js` — `signInWithUsername` callable exists as the replacement
- Gap: `resolveUsernameToEmail` export still present in `index.js`; migration status of iOS callers unconfirmed
- Gap: No rate limit or admin guard on `resolveUsernameToEmail` currently

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Migrate + remove (recommended) | Update iOS callers; remove export from `index.js` | Clean; eliminates email harvesting vector |
| Rate limit only | Add rate limit to `resolveUsernameToEmail`; keep export | Reduces but does not eliminate harvesting |
| Keep legacy indefinitely | No change | Email harvesting risk grows with user base |

## Legal consultation required?
NO — technical security migration.

---
**Status:** ☐ OPEN (90-day post-launch deadline)
**Owner:** Engineering Lead

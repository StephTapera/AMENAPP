# C-07: Phone Auth Rate-Limit Gen2 Migration
**Group:** LATER (post-launch, within 90 days)
**Decision:** When will `phoneAuthRateLimit.js` functions be migrated from Gen1 `runWith()` to Firebase Functions v2 with `defineSecret`?

---

## Recommended Answer
Migrate `phoneAuthRateLimit.js` to Functions v2 with `defineSecret` within 90 days of launch. Until migration, ensure the phone number hashes handled by these functions are stored only in memory and not logged.

## Rationale
Gen1 functions using `runWith()` have lower process isolation than Gen2 functions using `defineSecret`. Functions that handle phone number hashes have access to sensitive PII — the Gen2 migration improves isolation, provides better secret management, and reduces the attack surface if another function in the same Gen1 process is compromised. This is a hygiene improvement, not a critical vulnerability, but appropriate to address within the first quarter.

## What the code already does (file:line)
- `functions/phoneAuthRateLimit.js` — Gen1 `runWith()` pattern; phone hash processing
- Gap: `defineSecret` migration not started for this file

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Migrate to Gen2 (recommended) | Replace `runWith()` with v2 `onCall()`; add `defineSecret` for any secrets used | Improved isolation; minor operational change |
| Keep Gen1 | No change | Lower process isolation; acceptable risk if no secrets are in this function |
| Disable function | Remove export | Phone auth rate limiting disabled; abuse risk |

## Legal consultation required?
NO — technical infrastructure decision.

---
**Status:** ☐ OPEN (90-day post-launch deadline)
**Owner:** Engineering Lead

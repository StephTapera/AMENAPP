# C-12: Gen-1 Quota Impact on `moderateDMMessage`
**Group:** LATER (post-launch, within 90 days)
**Decision:** Is Cloud Run Gen-1 quota exhaustion affecting `moderateDMMessage` reliability? Is a Gen-2 migration planned?

---

## Recommended Answer
Assess Gen-1 quota impact within 60 days of launch by reviewing Firebase Functions logs for `moderateDMMessage` execution failures or timeouts. Migrate to Gen-2 if quota issues are confirmed or if the function exceeds 100ms p99 latency.

## Rationale
`moderateDMMessage` is a Gen-1 Firestore trigger on DM message writes. Gen-1 Cloud Functions share Cloud Run quota with all other Gen-1 functions in the project. If other high-volume Gen-1 functions (e.g., `moderatePost`, notification triggers) are consuming quota, `moderateDMMessage` may be throttled or dropped during peak usage. DM moderation being silently dropped means harmful content can reach recipients without server-side review. This is not a critical pre-launch issue but becomes critical under real usage load.

## What the code already does (file:line)
- Reference in audit Q-17: `moderateDMMessage` is a Gen-1 trigger
- `functions/index.js` or equivalent — `moderateDMMessage` function definition location TBD
- Gap: No performance baseline or quota monitoring found in the codebase

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Monitor then migrate if needed (recommended) | Add Cloud Functions error metric alerts; migrate to Gen-2 onCall if quota issues found | Low-risk incremental approach |
| Migrate to Gen-2 proactively | Rewrite `moderateDMMessage` as v2 trigger | More work; eliminates quota concern preemptively |
| Accept Gen-1 | No change | DM moderation drops during peak load; harmful content may reach users |

## Legal consultation required?
NO — technical infrastructure decision.

---
**Status:** ☐ OPEN (90-day post-launch deadline)
**Owner:** Engineering Lead

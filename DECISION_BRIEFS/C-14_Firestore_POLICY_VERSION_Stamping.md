# C-14: Firestore `POLICY_VERSION` Stamping
**Group:** LATER (post-launch, within 90 days)
**Decision:** Should a `POLICY_VERSION` constant be stamped on all moderation subdocuments and queue entries so future auditors can determine which policy version produced a given moderation decision?

---

## Recommended Answer
Add a `POLICY_VERSION` constant to `moderateUGC.js` and apply it to all moderation subdocuments and queue entries. Format: `"2026-06-11-v1"`. Update the version when moderation policy thresholds change.

## Rationale
Without `POLICY_VERSION` stamping, it is impossible to retrospectively determine which moderation rules applied to a given content decision. In a legal dispute or regulatory inquiry, the ability to say "this content was moderated under policy version 2026-Q3-v2, which had these thresholds" is a meaningful defense. The cost of adding a single field to every moderation document write is negligible.

## What the code already does (file:line)
- `functions/moderation/cyberTiplineInterface.js:182` — `policyVersion: "2026-06-10-v1"` exists in `markReportSubmitted` — the pattern already exists for NCMEC reports
- Gap: `policyVersion` not found in general moderation queue writes in `moderateUGC.js`
- Gap: No `POLICY_VERSION` constant defined at module level in `moderateUGC.js`

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Add `POLICY_VERSION` constant + stamp all writes (recommended) | Define `const POLICY_VERSION = "2026-06-11-v1"` in `moderateUGC.js`; add to all document writes | Low effort; high audit value |
| Stamp only CSAM-related documents | Partial implementation | Inconsistent audit trail |
| Skip versioning | No change | Cannot audit historical moderation decisions by policy version |

## Legal consultation required?
NO — technical audit trail decision.

---
**Status:** ☐ OPEN (90-day post-launch deadline)
**Owner:** Engineering Lead

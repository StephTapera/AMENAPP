# B-13: Guardian Approval Scope (OPEN-2)
**Group:** BEFORE-LAUNCH
**Decision:** What does "guardian approval" mean in practice? The `isGuardianApprovedContact()` function is currently fail-open (allows when document missing). Must be decided and inverted before launch.

---

## Recommended Answer
Active approve/deny model. Invert `isGuardianApprovedContact()` to fail-closed (return `false` when the document does not exist). Implement the `onDocumentCreated` CF for `/guardianLinkRequests` to send the guardian a verification notification and create the approval document after guardian confirms.

## Rationale
This is the same OPEN-2 gap documented in A-03. This brief covers the implementation decision specifically. The current `isGuardianApprovedContact()` has a two-part behavior: if the document doesn't exist, it returns `true` (wrong — allows DM); if the document exists but `approved` field is missing, it returns `false` (correct — denies). Only one line needs to change to invert the missing-document case. The `requestGuardianLink()` function already writes the request correctly; the gap is the downstream CF that processes it.

## What the code already does (file:line)
- `AmenChildSafetyService.swift:549–573` — `isGuardianApprovedContact()`: line 566 `if !doc.exists { return true }` — this is the fail-open bug
- `AmenChildSafetyService.swift:568–571` — existing document with missing `approved` field: correctly fails closed (`?? false`)
- `AmenChildSafetyService.swift:222–244` — `requestGuardianLink()` writes to `/guardianLinkRequests` correctly
- `functions/safety/minorProtection.js:46` — schema has `guardianLinked`, `guardianIds` fields
- Gap: `onDocumentCreated` CF for `/guardianLinkRequests` not confirmed to exist

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Active approve/deny fail-closed (recommended) | Change line 566 from `return true` to `return false`; implement `/guardianLinkRequests` CF | One line fix + new CF; correct behavior |
| Read-only oversight | `isGuardianApprovedContact()` always returns true; add guardian read access to thread | Weaker; guardian cannot prevent contact |
| Emergency-only | Return true until safety flag; notify guardian reactively | Allows all DMs to minors proactively |

## Legal consultation required?
YES — overlaps A-03 COPPA consultation. The model selected must be documented as the "verifiable parental consent" implementation.

---
**Status:** ☐ OPEN
**Owner:** Engineering Lead (one-line fix is ready once A-03 decision is made)

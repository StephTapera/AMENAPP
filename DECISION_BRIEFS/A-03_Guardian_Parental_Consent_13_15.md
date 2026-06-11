# A-03: Guardian / Parental Consent for Ages 13–15
**Group:** ANSWER-NOW (HARD BLOCKER)
**Decision:** Is verifiable parental consent required for accounts aged 13–15, and which guardian permission model (read-only / active approve/deny / emergency-only) will be used?

---

## Recommended Answer
Require verifiable parental consent for all 13–15 accounts. Invert `isGuardianApprovedContact()` to fail-closed (deny) when no guardian document exists. Use the active approve/deny model — guardian receives a notification and must approve each new contact before DMs are permitted.

## Rationale
The current code contains a documented bug labeled OPEN-2: `isGuardianApprovedContact()` returns `true` (allow) when the `/guardianApprovedContacts/{minorId}/contacts/{contactId}` document does not exist. The comment explicitly says this is a placeholder until T&S Lead resolves the guardian scope. In production this means the guardian DM gate is a no-op — any mutual-follow contact can DM a 13-year-old without guardian approval. The FTC's "actual knowledge" standard under COPPA applies if the platform has or should have known a user is under 13; for 13–15, the safer posture is to still require guardian visibility. The `requestGuardianLink()` function is implemented and writes to `guardianLinkRequests/` correctly; the gap is that the downstream CF (`onDocumentCreated` on `/guardianLinkRequests`) has not been confirmed to exist.

## What the code already does (file:line)
- `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift:549–573` — `isGuardianApprovedContact()`: returns `true` when document is absent (OPEN-2 placeholder; fail-open)
- `AmenChildSafetyService.swift:566` — comment: "document absent means guardian tools not yet active — allow" — this is the bug
- `AmenChildSafetyService.swift:568–571` — if doc exists: fails closed on missing `approved` field (`?? false`) — this part is correct
- `AmenChildSafetyService.swift:222–244` — `requestGuardianLink()` writes to `/guardianLinkRequests` correctly
- `functions/safety/minorProtection.js:42` — schema defines `guardianLinked`, `guardianIds`, `dmSafetyMode` fields
- Gap: No confirmed `onDocumentCreated` CF for `/guardianLinkRequests` — the document is written but the downstream approval workflow is unconfirmed

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Active approve/deny (recommended) | Invert line 566: `if !doc.exists { return false }`; implement `/guardianLinkRequests` CF | Correct COPPA posture; requires guardian onboarding UI |
| Read-only oversight | Change the DM permission model; guardian reads all threads but doesn't gate contacts | Weaker protection; guardian cannot prevent contact |
| Emergency-only notification | Guardian only notified on safety flag; no contact approval | Fails COPPA "verifiable parental consent" requirement for 13-year-olds |
| No restriction | Remove guardian check entirely | COPPA violation risk for 13–15 accounts |

## Legal consultation required?
YES — statute: COPPA, 15 U.S.C. § 6501 et seq.; FTC Rule 16 C.F.R. Part 312.
Obligation: "verifiable parental consent" before collecting personal information from children under 13. For ages 13–15, the platform's directed-at-minors analysis determines whether COPPA applies at all.

---
**Status:** ☐ OPEN
**Owner:** Legal counsel + Safety Officer + Engineering Lead

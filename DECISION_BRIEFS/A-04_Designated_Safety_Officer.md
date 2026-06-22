# A-04: Designated Safety Officer
**Group:** ANSWER-NOW (HARD BLOCKER)
**Decision:** Who is the safety officer assigned to receive CSAM escalations, manage NCMEC submissions, and hold legal hold review authority? Has the `legalReviewer` Firebase custom claim been defined and minted?

---

## Recommended Answer
Appoint a named safety officer with 24/7 reachability before any beta launch. Immediately define the `legalReviewer` custom claim in the CF admin token-minting flow and assign it only to that person's Firebase UID.

## Rationale
The `legalHolds` Firestore rule explicitly requires `request.auth.token.get('legalReviewer', false) == true` before allowing any read access to legal hold documents. If no user has this claim, no human can read legal holds through the app — the NCMEC reporting pipeline queues documents but no legitimate operator can retrieve them. Conversely, if the claim is simply never minted and the rule falls through to a broader permission, legal hold data could be exposed to unintended parties. The claim is tested in `functions/test/safety-rules.test.js` (lines 137–315) and referenced in the rules at `firestore.rules:2833`, but no CF that mints this claim was found during audit.

## What the code already does (file:line)
- `firestore.rules:2832–2833` — `legalHolds` collection: `allow read: if isSignedIn() && request.auth.token.get('legalReviewer', false) == true`
- `functions/test/safety-rules.test.js:302` — test defines `legalReviewer` claim in mock auth token
- `functions/test/safety-rules.test.js:138` — rule logic comment confirms the claim name
- Gap: No CF found that calls `admin.auth().setCustomUserClaims(uid, { legalReviewer: true })`

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Appoint officer + mint claim (recommended) | Add `setLegalReviewerClaim` admin-only CF; call it for safety officer UID | None |
| Use existing admin claim as proxy | Modify Firestore rule to `token.admin == true` in addition to `legalReviewer` | Broadens access to all admins, not just safety officer |
| Defer until post-launch | No code change | Legal holds are inaccessible; NCMEC queued reports cannot be acted on |

## Legal consultation required?
NO — technical and organizational decision. However, the safety officer's responsibilities touch on legal hold management, which should be reviewed with counsel for chain-of-custody requirements.

---
**Status:** ☐ OPEN
**Owner:** Founder (appoint the person) + Engineering Lead (mint the claim)

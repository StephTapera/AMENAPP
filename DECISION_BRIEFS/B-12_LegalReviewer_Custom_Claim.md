# B-12: `legalReviewer` Custom Claim Definition
**Group:** BEFORE-LAUNCH
**Decision:** Where is the `legalReviewer` Firebase custom claim defined and minted? The `legalHolds` Firestore rule requires this claim for read access but no CF that mints it was found.

---

## Recommended Answer
Define a `setLegalReviewerClaim` admin-only CF callable that sets `{ legalReviewer: true }` on a specified UID. Run it once for the safety officer's UID (from A-04). This is a one-time setup step that must be done before the safety officer can read any legal hold documents in the app.

## Rationale
The `legalHolds` Firestore rule at `firestore.rules:2833` requires `request.auth.token.get('legalReviewer', false) == true`. Without a CF to mint this claim, the token is never set, and the legal holds collection is permanently inaccessible to any user through the app. The NCMEC queue and legal evidence preservation pipeline write documents to `legalHolds` and `ncmecReports`, but the safety officer who needs to read and act on them cannot access them. The claim is tested in `safety-rules.test.js` but the function that creates it in production is missing.

## What the code already does (file:line)
- `firestore.rules:2832–2833` — rule requires `legalReviewer` claim; no fallback for missing claim
- `functions/test/safety-rules.test.js:302` — test mock defines the claim correctly
- `functions/authenticationHelpers.js:992–1034` — `setAdminClaim` callable exists as a pattern; `legalReviewer` equivalent not present
- Gap: No `setLegalReviewerClaim` function found in `authenticationHelpers.js` or any other CF file

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Add `setLegalReviewerClaim` CF (recommended) | ~20 lines following `setAdminClaim` pattern; admin-claim guard required | Correct; minimal code change |
| Use admin claim as proxy | Change `firestore.rules:2833` to `token.admin == true` | All admins can read legal holds; not appropriate for sensitive evidence |
| Firebase Console custom claim (manual) | No code; set claim via Admin SDK in CLI | Works but not repeatable; no audit trail |

## Legal consultation required?
NO — technical decision. Chain of custody for legal holds is improved by having a CF-minted claim with audit log.

---
**Status:** ☐ OPEN
**Owner:** Engineering Lead

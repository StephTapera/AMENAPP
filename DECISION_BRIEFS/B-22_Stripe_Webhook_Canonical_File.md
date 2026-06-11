# B-22: Stripe Webhook Canonical File
**Group:** BEFORE-LAUNCH
**Decision:** Which `stripeWebhook.js` is the canonical deployed version — `stripe/stripeWebhook.js` or the root `stripeWebhook.js`? Are both deployed simultaneously?

---

## Recommended Answer
`stripe/stripeWebhook.js` is the canonical hardened version. Confirm `index.js` imports from there (it does at line 489). Remove or disable the root `stripeWebhook.js` export. Verify only one webhook handler is registered in Firebase.

## Rationale
`index.js:489` already imports from `./stripe/stripeWebhook` and exports it as `stripeWebhook`. However, the root `stripeWebhook.js` also exports a `stripeWebhook` function. If both are deployed under the same function name, Firebase will use only the last registration, but the build may be ambiguous. If the root file is deployed under a different name or via a legacy path, duplicate event processing creates idempotency failures: the same Stripe event (subscription created, payment succeeded) could be processed twice, charging customers incorrectly or creating duplicate subscription records.

## What the code already does (file:line)
- `functions/index.js:489` — `const { stripeWebhook } = require("./stripe/stripeWebhook")` — imports hardened version
- `functions/index.js:490` — `exports.stripeWebhook = stripeWebhook` — exports canonical version
- `functions/stripeWebhook.js:11–14` — comment says this is a "legacy fallback" pointing to `stripe/stripeWebhook.js`
- `functions/stripeWebhook.js:39` — still exports `stripeWebhook` function (potential conflict)
- `functions/stripeWebhook 2.js` — a second legacy copy exists (Gen1 pattern)

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Delete root `stripeWebhook.js` (recommended) | Remove the file; `index.js` already imports the right version | Eliminates ambiguity |
| Keep both, document that root is legacy | Add comment; ensure root is not exported | Ongoing confusion risk |
| Deploy both | Both active | Duplicate event processing; financial integrity failure |

## Legal consultation required?
NO — technical financial integrity decision.

---
**Status:** ☐ OPEN
**Owner:** Engineering Lead

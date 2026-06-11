# B-21: App Check Project-Level Enforcement
**Group:** BEFORE-LAUNCH
**Decision:** Is Firebase App Check enforcement enabled at the project level in the Firebase Console? Are all Berean OS and Selah CFs migrated to `enforceAppCheck: true`?

---

## Recommended Answer
Enable App Check enforcement in the Firebase Console project settings. Migrate all Berean OS and Selah CFs to `enforceAppCheck: true`. Use `FUNCTIONS_EMULATOR` guard for local development only.

## Rationale
`enforceAppCheck: true` on individual CF functions is meaningless if the Firebase Console project-level enforcement toggle is disabled — it can be bypassed entirely via the Firebase REST API. The audit found 33+ Berean OS and Selah CFs with `enforceAppCheck: false`, meaning those functions accept calls from any source, including web scrapers and automated bots. In the faith-community context, Berean AI callable endpoints being accessible to unauthenticated automation creates LLM abuse risk and cost exposure.

## What the code already does (file:line)
- `functions/v2triggers/selah/discernmentEngine.js:380` — `enforceAppCheck: false` with comment "tracked separately"
- `functions/v2triggers/selah/discernmentEngine.js:630` — second instance: `enforceAppCheck: false`
- `functions/creatorDraftFunctions.js:218` — `enforceAppCheck: false` with comment "set to true once enforced in all environments"
- Several other CFs with `enforceAppCheck: true` (safety-hardening branch progress)
- Gap: Firebase Console project-level enforcement toggle status: unconfirmed

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Enable project-level + migrate all CFs (recommended) | Enable in Console; change `false` to `true` in all remaining CFs; add `FUNCTIONS_EMULATOR` guard | Correct; closes App Check bypass |
| Migrate CFs only, skip Console toggle | Change code only | Still bypassable via Firebase REST API |
| Accept current state | No change | 33+ endpoints accessible without App Check; automation and scraping risk |

## Legal consultation required?
NO — technical security configuration.

---
**Status:** ☐ OPEN
**Owner:** Engineering Lead

# URGENT RULES DEPLOY PACKAGE — P0 wave (2026-06-10)

**Status:** ⏸ AWAITING HUMAN REVIEW — rules/minors/PII changes, same-day review class. **No deploy was run.**
**Restores:** all DMs (currently 100% denied in production) + closes both deployed COPPA holes, in one `firebase deploy --only firestore:rules`.
**Branch:** `feature/connected-intelligence-20260609-r2` · **Commits:** `9bbfe47f` (rules), `7af3204b` (functions COPPA/PII), `248df4ac` (index), `41bdf467` (iOS gate).

---

## What ships in this package

| Item | File | Commit | Proof |
|---|---|---|---|
| P0-1 DM field (`participantUids`→`participantIds` via helper) | `firestore.rules` | `9bbfe47f` | emulator 10/10 |
| P0-3 minor vocab (`isMinor`/`isUnderMinimum`/`isMinorAccount`) | `firestore.rules` | `9bbfe47f` | emulator 10/10 |
| isMinorSafeDM wiring (now actually reachable) | `firestore.rules` | `9bbfe47f` | `minor-safe-dm` 8/8 |
| P0-2 phone-PII (hash IDs + redact logs) | `functions/phoneAuthRateLimit.js` | `7af3204b` | jest 3/3 |
| P0-2 supporting index | `firestore.indexes.json` | `248df4ac` | JSON valid |
| P0-11 COPPA test wiring | `functions/ageTier.js`, `…/test/ageTier.test.js`, `package.json` | `7af3204b` | jest 84/84 |
| CI block (P0-9 start) | `.github/workflows/rules-coppa-ci.yml` | this commit | runs both suites on PR |

**Note:** P0-4 (iOS `AMENSecureMessagingService`) and the iOS unit test are committed (`41bdf467`) but ship via the **app binary**, not this rules deploy. Their green-build proof is gated on the in-flight FirebaseAI-unlink lane.

---

## Consolidated rules diff (append-only behaviour; `firestore.rules`, +37 / −19)

Three helper changes + the conversations rewire:

```
isMinor():        ageTier in ['teen','under_minimum']
              →   ageTier in ['blocked','tierB','tierC','teen','under_minimum']

isUnderMinimum(): ageTier == 'under_minimum'
              →   ageTier in ['blocked','under_minimum']

isMinorAccount(): [...'tierA','tierB','tierC']          (missing 'blocked')
              →   ['blocked',...'tierA','tierB','tierC']  (under-13 now gated)

NEW helper conversationParticipants(data):
              return data.get('participantIds', data.get('participantUids', []))

conversations + messages read/create/update:
              resource.data.get('participantUids', [])
              →   conversationParticipants(resource.data)
```

Authoritative vocabulary (source: `functions/authenticationHelpers.js` → now `functions/ageTier.js`):
`blocked`(<13) · `tierB`(13–15) · `tierC`(16–17) · `tierD`(18+). The legacy strings
`teen`/`under_minimum`/`tierA` are retained in the lists so any stale token still fails safe.

---

## Emulator proof (Firestore emulator, `@firebase/rules-unit-testing`)

New suite `Backend/rules-tests/gap-p0-dm-and-minor.rules.test.ts` loads the **same repo-root
`firestore.rules` that `firebase.json` deploys**:

```
FIXED rules:    Tests: 10 passed, 10 total          (gap-p0-dm-and-minor)
PRE-FIX rules:  Tests: 6 failed, 4 passed, 10 total  ← fail-before proof
Combined:       Tests: 18 passed, 18 total           (+ minor-safe-dm 8/8, no regression)
```

The 6 pre-fix failures are exactly the P0-1 participant-denied and P0-3 minor-gate cases.
Coverage: participant read/create/send allowed · non-participant denied · tierB minor needs
mutual-follow · `blocked` requester denied · adult↔tierC and adult↔`blocked` recipient gated.

Functions suite (`cd functions && npm test`): **3 suites / 84 tests green** (discussion +
`ageTier` + `phoneAuthPii`); the 261-failure ledger was deliberately **not** awakened.

---

## ⚠️ Required deploy steps (human, same-day)

1. **Set the phone pepper secret** (P0-2 functions will not start without it):
   ```
   firebase functions:secrets:set PHONE_HASH_PEPPER   # paste a long random value
   ```
2. **Deploy rules** (restores DMs + closes COPPA holes):
   ```
   firebase deploy --only firestore:rules --project amen-5e359
   ```
3. **Deploy the index** (P0-2 suspicious-activity query):
   ```
   firebase deploy --only firestore:indexes --project amen-5e359
   ```
4. **Deploy the phone functions** (only after the secret exists):
   ```
   firebase deploy --only functions:checkPhoneVerificationRateLimit,functions:reportPhoneVerificationFailure,functions:unblockPhoneNumber
   ```

### Data migration note (P0-2)
Existing `phoneAuthRateLimits/{rawPhone}` docs and `securityEvents` rows carry raw numbers
under the old keys. New writes use `phoneHash`. Existing rate-limit docs simply age out (15-min
windows); a one-off backfill is **not required** for correctness, but a cleanup job may purge
the legacy plaintext-keyed docs. Until purged, old docs retain raw numbers — schedule a delete.

---

## Rollback

- **Rules:** redeploy the previously reviewed `firestore.rules` revision:
  `git show 9bbfe47f^:firestore.rules > /tmp/rollback.rules` then deploy that file. (Reverting
  re-denies all DMs and re-opens the COPPA gate — only roll back if a NEW deny-too-much regression
  appears; the emulator suite covers the known matrix.)
- **Functions:** redeploy the prior `phoneAuthRateLimit.js` revision; the pepper secret can remain.
- **Index:** composite indexes are additive; leaving the new one in place is harmless on rollback.

---

## Human review checklist (sign-off before deploy)

- [ ] Confirm `participantIds` is the canonical field for ALL conversation writers (client + any CF).
- [ ] Confirm the minor-DM product intent: under-13 (`blocked`) fully barred; 13–17 (`tierB`/`tierC`)
      allowed only with mutual-follow. (This package enforces exactly that.)
- [ ] Approve PII posture: phone numbers hashed (HMAC + pepper), logs last-4 only, no raw number in
      any doc path. Approve scheduling the legacy-doc purge.
- [ ] Approve the `PHONE_HASH_PEPPER` secret creation.

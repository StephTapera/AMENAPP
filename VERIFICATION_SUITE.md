# Verification Test Suite — Ship Order Stage 2 rules gate

All suites run against the **real root `firestore.rules`** via the Firestore emulator.
Emulator devDeps already installed in `Backend/rules-tests/node_modules`
(`@firebase/rules-unit-testing@^3.0.4`, `firebase`, `ts-jest`) — **no package.json
change was required** (deps already declared + installed).

## Per-case results (2026-06-10, run against emulator)

| Suite | File | Result |
|-------|------|--------|
| **AI / Action Intelligence** (other lane's suite — run, not authored by claude) | `Backend/actionIntelligenceRules.test.js` | **26/26 PASS** ✅ |
| **[MINOR] DM safety matrix** | `Backend/rules-tests/minor-safe-dm.rules.test.ts` | **8/8 PASS** ✅ |
| **NoteShare access + Settings owner-only** | `Backend/verification/noteShareAccess.rules.test.js` | **15/15 PASS** ✅ |
| **ConnectSpaces prepared-ground** | `Backend/verification/connectSpacesAccess.rules.test.js` | **5/7 PASS + 2 EXPECTED-RED** ⏳ |
| Presence fail-closed + Comment enforcement | `AMENAPPTests/PresenceAndCommentEnforcementTests.swift` | Swift (Xcode), not emulator: 1 model test + 4 named `.disabled` seams |

**Total emulator: 54 green + 2 expected-red.**

The 2 ConnectSpaces RED cases are the **TDD signal**, not failures:
`spaceFiles_member_canRead` / `spaceFiles_member_canUpload_ownFile` stay RED until the
`spaces/{spaceId}/files` rule is appended (the rule is in the file header). The 3
discovery cases + 4 negative file cases pass against the existing `spaces` rule.

### isMinorSafeDM matrix (8/8)
`minorDM_nonMinorRecipient_allowed_withoutFollows`, `minorDM_minorRecipient_mutualFollows_allowed`,
`minorDM_minorRecipient_onlyForwardEdge_denied`, `minorDM_minorRecipient_onlyReverseEdge_denied`,
`minorDM_minorRecipient_noEdges_denied`, `minorDM_signedOut_denied`,
`minorDM_underMinimumSender_denied_evenWithMutualFollows`, `minorDM_noMemberRole_denied`.

### NoteShare (15/15) — note
The rule was hardened by another lane after first authoring: `followers` visibility now
requires `isMutualConnectionWith` (BOTH `follows_index` edges) and `church` now requires
`isOrganizationMember` (a real `organizations/{orgId}/members/{uid}` edge, NOT a client
`churchId` claim). The two positive cases were updated to seed those predicates → green.

## Run commands

**Harness TS suites** (`minor-safe-dm`, `current-stack`, etc.) — canonical:
```bash
cd /path/to/repo && firebase emulators:exec --only firestore --project amen-rules-verify \
  "cd Backend/rules-tests && npx jest --forceExit"
```

**The `.js` suites** (AI + verification) live outside the harness rootDir; until they are
folded into `Backend/rules-tests/` (at quiesce — commits currently held), run them with
`NODE_PATH` pointed at the harness deps:
```bash
REPO=/path/to/repo
firebase emulators:exec --only firestore --project amen-rules-verify \
  "cd Backend/rules-tests && NODE_PATH=$REPO/Backend/rules-tests/node_modules \
   npx jest --roots $REPO/Backend \
   --testPathPattern '(actionIntelligenceRules|verification/.*rules\\.test)' --forceExit"
```

**Fold step (at quiesce):** move `Backend/verification/*.rules.test.js` into
`Backend/rules-tests/`, and have the AI lane move `actionIntelligenceRules.test.js` there
too, so a single `cd Backend/rules-tests && npm test` runs all Stage-2 suites. (Not done now:
commits are held until HEAD returns to the integration branch; `AMENAPPTests/` is being swept.)

---

## Backend/functions application-logic suite — DORMANT TEST SWEEP (2026-06-10, claude/Pulse)

**Finding (fleet-significant):** `Backend/functions` jest `testMatch` was `["**/__tests__/**/*.test.ts"]`,
so **37 colocated `src/**/*.test.ts` suites had NEVER run** (the runner only matched `__tests__/`).
Fixed at the config layer (non-recurring) in `Backend/functions/package.json`:
`testMatch` now `["**/__tests__/**/*.test.ts", "**/*.test.ts"]` with
`testPathIgnorePatterns: ["/node_modules/", "/lib/"]` (so compiled `lib/*.test.js` isn't double-run).

**Corrected run command** (full application-logic suite — distinct from the rules-emulator suites above):
```bash
cd Backend/functions && npx jest --forceExit            # full suite
cd Backend/functions && npx jest src/__tests__/pulseEngine.deeplink.test.ts   # single suite
```

**Full-suite result @ 2026-06-10 (was 21 suites running; now 58):**

| | Suites | Tests |
|---|---|---|
| Total now executing | 58 | 907 |
| Pass | 27 | 646 |
| Fail | 31 | 261 |

The suite was **already red before this change** (9 of the failing suites live in `__tests__/`
and were running + failing prior). This change AWAKENED **22 newly-running colocated suites** and
their passing tests; it did not break a green suite. Failures = real findings, **triaged to owners
below** (not fixed by this lane):

| Failing suite(s) | Likely owner lane | Dominant failure class |
|---|---|---|
| `__tests__/{aiAppCheckEnforcement,aiBackendOwnership,aiUnsafeReport,berean.*,remainingReleaseScopes,semanticIntelligence}` | Berean LLM / AI | pre-existing (already in `__tests__`); stale source-path reads (ENOENT on moved/sibling-codebase files) + mock setup |
| `accountLifecycle.static`, `securityLaunchReadiness`, `securityPosture` | Auth / Security | static reads of `twoFactorAuth.ts` etc. at paths that moved → stale path or real deletion |
| `covenant/{createCovenantCheckoutSession,createCovenantThreadReply,setCommunitySaved,stripeCovenantWebhook,validateCovenantPostSafety}` | Covenant / monetization | newly awakened |
| `churchNotes/{churchNotesDocumentExtraction,churchNotesProcessing}` | Church Notes | newly awakened |
| `messaging/{privateMessageActions,productionIntelligenceActions}` | Messaging | newly awakened |
| `{explainVideoContent,selahMedia,generateDynamicReplyPreviews}` | Media | newly awakened |
| `amenConnect`, `communityHubs`, `churchDiscoveryPhase2`, `profileMini/getUserProfileMiniContext`, `spiritualSystems`, `bereanPremiumContracts` | resp. Connect/Community/Church-Discovery/Profile/SpiritualOS/Berean | newly awakened |
| `utils/previewLogger` | Moderation/preview | `logger.info as jest.Mock` undefined — missing shared jest setup (mock not configured) |

**Two common, low-effort root causes for owners:** (1) **static tests read source by hardcoded path**
— several point at files that moved or live in the sibling `functions/` codebase (ENOENT); update the
path or delete the obsolete test. (2) **missing mock setup** — `firebase-functions` logger isn't mocked
(no `setupFiles`); add a shared setup or per-file `jest.mock("firebase-functions")`.

**Legacy `functions/` codebase — NOT swept (judgment).** Its `testMatch` is deliberately narrow
(`**/src/discussion/**/*.test.ts`); ~13 other `.test.{ts,js}` files there are dormant. Left for that
codebase's owner: it mixes `.js`/`.ts`, is emulator-gated, and the narrow scope may be intentional.
Recommended fix mirrors the above if the owner wants them live.

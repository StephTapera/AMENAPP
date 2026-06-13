# AMEN App — Decision Log

Decisions made under safety-hardening that require explicit human review before reversal.

---

## P0-8 — requireParentalConsentUnder16 protective default

**Date:** 2026-06-12
**Branch:** safety-hardening
**File:** AMENAPP/AMENAPP/AgeAssuranceModels.swift

**Decision:**
`requireParentalConsentUnder16` was `false`, making the COPPA/GDPR-K parental consent
code path dead code. Under-16 users (EU: all 13-15 year olds; US: under-13 already
blocked by minimumAge) had data collected without verifiable parental consent,
contradicting the Terms of Service and EU GDPR Article 8 / UK GDPR AADC requirements.

**Change:** Set `requireParentalConsentUnder16 = true`.

**Effect:** Teen-tier users (age 13-17) are blocked from directMessages, sensitiveContent,
liveStreaming, and commerce feature access until a guardian consent UI is complete and
consent is on file. Public profile access is still permitted for teens.

**Open item (OPEN-2):** Guardian consent UI is not yet built. Until it is, all teen-tier
users are restricted — this is intentionally conservative. When OPEN-2 is complete and
the UI is shipping, the gate can be relaxed to "teen with consent on file → access allowed"
rather than reverting to `false`.

**To relax this default:** Steph explicit decision required. Do not set
`requireParentalConsentUnder16 = false` without a written product decision and legal review.
The correct path is: build OPEN-2 guardian consent UI, then gate on `hasConsent == true`
rather than removing the gate entirely.

---

## Berean Reconciliation Decisions — 2026-06-12

**Date:** 2026-06-12
**Branch:** safety-hardening
**Author:** Claude Code (orchestrated decision; requires Steph sign-off before retire step)

### Background

Two independent Berean backend systems exist in the same Firebase project (amen-5e359):

- **System A** — `functions/berean/` compiled into the `default` Firebase codebase; exports callable `bereanConstitutionalPipeline` at `us-east1`; 250 eval test cases; uses `firebase-functions ^7.2.5`; no source maps.
- **System B** — `Backend/functions/src/berean/` compiled into the `creator` Firebase codebase; exports callable `bereanPipeline` at `us-east1`; 75 eval test cases; uses `firebase-functions ^4.5.0`; has source maps; has a richer layered architecture (12 controllers, 5 feature modules, repositories, prompts, services).

The shipping iOS client (`BereanPipelineClient.swift`) calls `httpsCallable("bereanPipeline")` with `Functions.functions(region: "us-central1")` — meaning it targets the System B callable name but the wrong region. System A's callable name (`bereanConstitutionalPipeline`) is not called by the primary iOS surface. System B's callable `bereanPipeline` is deployed at `us-east1`, not `us-central1`.

### Decision Rule Application

**Rule 1 — Skeleton is the system deployed and wired to shipping iOS surfaces.**
System B's callable name (`bereanPipeline`) is what the iOS client sends. System A's callable (`bereanConstitutionalPipeline`) is not the primary target. System B is the skeleton.

**Rule 2 — Eval infrastructure.** System A has 250 seeded, machine-gradable test cases with a live `runEvalSuite()` + `checkDeploymentGate()` framework that actually runs via `bereanRunEvals` callable. System B's eval harness is interface-only (no runner, no gate). System A's eval infrastructure is superior and must be ported into the canonical `creator` codebase.

**Rule 3 — P0-06 fix.** System B (`bereanPipeline.ts`) was designed fail-closed from inception — no `legacyPipelineCall`, catch block returns `buildDegradedResponse()` only. P0-06 does NOT need porting. System A (`constitutionalPipeline.ts`) has `legacyPipelineCall` defined as dead code but its flag-check and catch paths also return `_safeUnavailableOutput()` — also safe. No port needed.

**Rule 4 — P0-05 cascade.** `functions/accountDeletion.js` already covers both camelCase and snake_case collections from both systems. Two gaps must be added: `bereanMemoryVectors` (top-level) and `bereanAuditLog` subcollection. See P0-05 section below.

**Rule 5 — One memory schema, one flag namespace, one iOS client.** System A uses `users/{uid}/bereanMemory/{entryId}` (camelCase) and flag namespace `featureFlags/trustArchitecture`. System B uses `berean_memory/{userId}/entries/{entryId}` (snake_case) and flag `system/serverFeatureFlags.berean_memory_enabled`. Canonical = System B's snake_case memory path because it is what the live `bereanMemoryWrite/Read/Delete/DeleteAll/Update` callables write to. iOS client memory callable names must be updated.

**Rule 6 — Loser never deploys.** System A `functions/berean/` is NOT retired — it contains `bereanConstitutionalPipeline` which is called CF-to-CF by System B's Stage 5 constitutional review (see `bereanPipeline.ts` line 710: `adminFunctions.httpsCallable("bereanConstitutionalPipeline")`). System A therefore STAYS deployed. What is retired is System A as the primary pipeline — the iOS client switches to System B. System A becomes the constitutional review sub-callable only.

---

### Component Decision Table

| Component | Canonical Source | Rationale |
|---|---|---|
| **Primary callable (iOS entry point)** | System B — `Backend/functions/src/berean/bereanPipeline.ts` | iOS client calls `bereanPipeline`; System B is `creator` codebase; deployed at `us-east1` |
| **Constitutional review sub-callable** | System A — `functions/berean/constitutionalPipeline.ts` | System B Stage 5 calls `bereanConstitutionalPipeline` via admin SDK; must remain deployed |
| **Pipeline orchestrator** | System B — `bereanPipeline.ts` (7 stages, fail-closed, rate-limited) | Designed fail-closed from inception; no legacy bypass; has rate limiting, App Check, proper secrets |
| **Model router** | System B — `Backend/functions/src/berean/modelRouter.ts` | Part of canonical codebase; more complete routing logic |
| **Memory store callables** | System B — `Backend/functions/src/berean/bereanMemory.ts` | Exports `bereanMemoryWrite/Read/Delete/DeleteAll/Update`; writes to `berean_memory/{userId}/entries/` |
| **Memory Firestore path** | `berean_memory/{userId}/entries/{entryId}` (snake_case) | System B's live callables write here; iOS must update callable names to match |
| **Eval framework (runner + gate)** | System A — `functions/berean/evalFramework.ts` + `evalTestCases.ts` | 250 seeded cases vs 75 interface-only; `runEvalSuite()` + `checkDeploymentGate()` are real runners |
| **Eval suites (all 5)** | Merge — keep System B's predicate helpers, keep System A's 250 test cases | System B's safetyCompliance.ts has richer `hasCrisisResources()` + `hasProfessionalDisclaimer()` predicates; System A has volume |
| **Bible accuracy suite** | System A (50 cases) + System B predicates | Port B's grader predicates; keep A's test volume |
| **Safety compliance suite** | System A (50 cases) + System B predicates | System B predicates are more complete for crisis/professional framing |
| **Moderation accuracy suite** | System A (50 cases) + System B predicates | Same merge pattern |
| **Theological neutrality suite** | System A (50 cases) | System A is canonical; B's suite is interface-only |
| **Product workflows suite** | System A (50 cases) | System A is canonical; B's suite is interface-only |
| **iOS client** | `BereanPipelineClient.swift` — update region to `us-east1` | Callable name `bereanPipeline` is already correct; region must change from `us-central1` to `us-east1` |
| **iOS memory callable names** | Update to `bereanMemoryRead`, `bereanMemoryDelete`, `bereanMemoryDeleteAll`, `bereanMemoryUpdate` | Current names (`bereanGetMemory`, `bereanDeleteMemory`, `bereanDeleteAllMemory`, `bereanToggleMemoryLock`) have no backend counterpart in System B |
| **Feature flag namespace** | `system/amenAIFlags` (System B Stage 1 reads `constitutionalIntelligence_enabled` OR `berean_pipeline_enabled`) | System B already accepts both flags; no change needed in the pipeline; Remote Config flag `constitutionalIntelligence_enabled` is retained |
| **Firestore collections (canonical)** | See P0-05 section | |
| **Firebase codebase for primary pipeline** | `creator` — `Backend/functions/` | System B lives here |
| **Firebase codebase for constitutional review** | `default` — `functions/` | System A stays deployed as review sub-callable |

---

### SKELETON

**Canonical codebase:** `creator` (`Backend/functions/`)
**Canonical directory:** `Backend/functions/src/berean/`
**Primary callable:** `bereanPipeline` at `us-east1`

System B is the skeleton because the shipping iOS client calls `bereanPipeline` (System B's export). System B also has a richer architecture (12 controllers, 5 feature modules, repositories, prompts, services, rate limiting via `enforceRateLimit`).

System A is NOT retired — it remains deployed as the `bereanConstitutionalPipeline` sub-callable that System B invokes CF-to-CF during Stage 5 constitutional review.

---

### PIPELINE ORCHESTRATOR

**Canonical:** System B — `Backend/functions/src/berean/bereanPipeline.ts`

Rationale: Designed fail-closed from inception. Two-layer safety: (1) local HARD_BLOCKS regex scan (9 patterns) before any CF call, (2) CF-to-CF review via `bereanConstitutionalPipeline`. Rate limiting enforced via `enforceRateLimit`. Uses `defineSecret("ANTHROPIC_API_KEY")` correctly. Memory is 512MiB at 120s timeout. Source maps present for debugging.

---

### CONSTITUTIONAL REVIEW

**Canonical:** System A — `functions/berean/constitutionalPipeline.ts` (deployed, called CF-to-CF by System B)

System B's Stage 5 (`stageConstitutionalReview`) calls `bereanConstitutionalPipeline` on `us-east1` via admin SDK. This is an intentional architectural dependency. System A's `constitutionalPipeline.ts` remains the review callable — it is NOT retired.

P0-06 status: CLOSED in both systems. System B never had a legacy bypass. System A's `legacyPipelineCall` is dead code in a catch path that exclusively returns `_safeUnavailableOutput()`.

---

### MODEL ROUTER

**Canonical:** System B — `Backend/functions/src/berean/modelRouter.ts`

System A's `modelRouter.ts` is superseded. System B's router is part of the canonical `creator` codebase.

---

### MEMORY STORE

**Canonical:** System B — `Backend/functions/src/berean/bereanMemory.ts`
**Canonical Firestore path:** `berean_memory/{userId}/entries/{entryId}`
**Canonical callable names:** `bereanMemoryWrite`, `bereanMemoryRead`, `bereanMemoryDelete`, `bereanMemoryDeleteAll`, `bereanMemoryUpdate`

System A's callable names (`bereanGetMemory`, `bereanDeleteMemory`, `bereanToggleMemoryLock`, `bereanUpdateMemory`, `bereanDeleteAllMemory`) and its Firestore path (`users/{uid}/bereanMemory/{entryId}`) are SUPERSEDED.

`bereanToggleMemoryLock` has no System B counterpart — this feature must be either added to `bereanMemoryUpdate` in System B (set `locked: true/false` via the update callable) or dropped from the iOS client.

---

### EVAL FRAMEWORK

**Canonical framework (runner + gate):** System A — `functions/berean/evalFramework.ts` + `evalTestCases.ts` (250 test cases)
**Action:** Port `evalFramework.ts`, `evalTestCases.ts`, and the 5 eval suite files from System A into System B as `Backend/functions/src/berean/evalFramework.ts` etc. Update import paths. The System B `evaluationHarness.ts` (interface-only) is replaced by the ported System A framework.

---

### EVAL SUITES (all 5)

For each suite, System B has richer predicate helpers; System A has volume (50 cases each). The merge strategy is: use System B's predicate helper functions as the grading layer, use System A's 250 test cases as the test input layer.

| Suite | Cases to Keep | Predicate Source |
|---|---|---|
| `bibleAccuracy` | 50 from System A | System B helpers |
| `safetyCompliance` | 50 from System A | System B (richer crisis + professional-disclaimer checks) |
| `moderationAccuracy` | 50 from System A | System B helpers |
| `theologicalNeutrality` | 50 from System A | System A (System B is interface-only) |
| `productWorkflows` | 50 from System A | System A (System B is interface-only) |

---

### iOS CLIENT

**File:** `AMENAPP/AMENAPP/AIIntelligence/BereanPipelineClient.swift`

Required changes (two fixes, not filed as new bugs — these are consequences of the reconciliation):

1. **Region:** Change `Functions.functions(region: "us-central1")` to `Functions.functions(region: "us-east1")` at line 42. The comment on line 23 must also be updated.
2. **Memory callable names:** Any iOS file calling `bereanGetMemory`, `bereanDeleteMemory`, `bereanDeleteAllMemory`, `bereanToggleMemoryLock` must be updated to `bereanMemoryRead`, `bereanMemoryDelete`, `bereanMemoryDeleteAll`, and either `bereanMemoryUpdate` (with a `locked` field) or a new `bereanMemoryToggleLock` callable added to System B.

These are blocking bugs: the current iOS memory calls hit `NOT_FOUND` at runtime.

---

### FEATURE FLAGS

**Canonical flag namespace:** Remote Config key `constitutionalIntelligence_enabled` (iOS gate, unchanged)
**Server-side flag:** System B Stage 1 already checks `system/amenAIFlags.constitutionalIntelligence_enabled` OR `system/amenAIFlags.berean_pipeline_enabled` — both accepted, no change needed.
**System A flag:** `featureFlags/trustArchitecture.constitutionalPipeline` — retained because System A is still deployed as the review sub-callable and reads this flag.
**Memory flag:** `system/serverFeatureFlags.berean_memory_enabled` (System B) — canonical; System A's `featureFlags/trustArchitecture.memoryLayer` is superseded.

---

### FIRESTORE COLLECTIONS

Collections written by the canonical System B pipeline:

| Collection | Owner | P0-05 covered? |
|---|---|---|
| `berean_pipeline_traces/{traceId}` | System B Stage 7 | YES — `deleteDocsWhere('berean_pipeline_traces', 'userId', uid)` |
| `berean_memory/{userId}/entries/{entryId}` | System B memory | YES — `deleteCollection(berean_memory.doc(uid).collection('entries')); berean_memory.doc(uid).delete()` |
| `bereanPipelineTraces/{traceId}` | System A constitutional | YES — `deleteDocsWhere('bereanPipelineTraces', 'userId', uid)` |
| `bereanFeedback/{feedbackId}` | System A feedback | YES — `deleteDocsWhere('bereanFeedback', 'userId', uid)` |
| `users/{uid}/bereanMemory/` | System A memory (superseded) | YES — `USER_SUBCOLLECTIONS` list |
| `bereanMemoryVectors/{vectorDocId}` | System A memory (optional embeddings) | GAP — NOT covered |
| `bereanAuditLog/{userId}/memoryDeletes/` | System A memory delete receipts | GAP — NOT covered |
| `bereanAuditLog/cascade/{userId}` | System A cascade receipt | GAP — NOT covered |
| `bereanEvalRuns/{evalRunId}` | System A eval runner | NOT needed (admin audit only, not PII) |
| `bereanTrustScores/{traceId}` | System A trust scoring | Add to cascade if keyed by userId |
| `berean/{uid}/memory/`, `berean/{uid}/threads/`, `berean/{uid}/messages/` | Firestore rules | Add to USER_SUBCOLLECTIONS cascade |

---

### P0-06 FIX

**Status:** CLOSED IN BOTH SYSTEMS. No port needed.

System B (`bereanPipeline.ts`): catch block at line 782 returns `buildDegradedResponse()` — no legacy bypass callable exists. The HARD_BLOCKS local scan also prevents unsafe content from reaching the review stage.

System A (`constitutionalPipeline.ts`): `legacyPipelineCall` is defined (lines 236–286) but is dead code. The flag-check catch block (lines 339–343) returns `_safeUnavailableOutput()` exclusively. No query bypasses review.

---

### P0-05 CASCADE — GAPS TO CLOSE

The following collections are NOT currently covered in `functions/accountDeletion.js` but contain user PII from the canonical Berean systems:

**MUST ADD to accountDeletion.js:**

1. `bereanMemoryVectors` — top-level collection; delete docs where `userId == uid`. Written by System A memoryStore when embeddings are generated.
2. `bereanAuditLog/{uid}/memoryDeletes/` — subcollection; delete via `deleteCollection(db.collection('bereanAuditLog').doc(uid).collection('memoryDeletes'))`.
3. `bereanAuditLog/cascade/{uid}` — the cascade receipt document itself; confirm path structure against `memoryStore.ts` line 471 before implementing.
4. `berean/{uid}/memory/`, `berean/{uid}/threads/`, `berean/{uid}/messages/`, `berean/{uid}/usage/`, `berean/{uid}/capabilities/`, `berean/{uid}/connectors/` — Firestore rules show these exist under `berean/{uid}/`; add to `USER_SUBCOLLECTIONS` or delete the parent `berean/{uid}` doc and all subcollections.

**Already covered (confirmed):**
- `berean_pipeline_traces` (snake_case) — covered
- `berean_feedback` (snake_case) — covered
- `berean_model_logs` (snake_case) — covered
- `berean_memory/{userId}/entries` + parent doc — covered
- `bereanPipelineTraces`, `bereanFeedback`, `bereanModelLogs`, `bereanMemory` (camelCase subcollections) — covered
- `aiBibleStudyConversations`, `realtimeSessions` — covered

---

### RETIREMENT DECISION

**System B is the skeleton. System A is NOT retired — it remains as the constitutional review sub-callable.**

Files in `Backend/functions/src/berean/` that are SUPERSEDED (by System A components being ported in) and should eventually be cleaned up — but NOT deleted until the eval port is complete and `bereanRunEvals` is re-wired to the canonical codebase:

- `Backend/functions/src/berean/evaluationHarness.ts` — superseded by ported System A `evalFramework.ts`
- `Backend/functions/src/berean/evalSuites/*.ts` — superseded by merged suites

**No System A berean files should be moved to `/retired/`** because `constitutionalPipeline.ts` and the other System A components remain live. If a future decision is made to inline constitutional review directly into System B (eliminating the CF-to-CF call), then and only then should System A berean files be retired to `retired/berean-duplicate-<date>/`.

---

### OPEN ITEMS

| ID | Item | Owner |
|---|---|---|
| OI-BR-1 | Fix iOS region in `BereanPipelineClient.swift` line 42: `us-central1` to `us-east1` | Engineering |
| OI-BR-2 | Update iOS memory callable names: `bereanGetMemory` to `bereanMemoryRead`, etc. | Engineering |
| OI-BR-3 | Decide fate of `bereanToggleMemoryLock`: add to System B as new callable or fold into `bereanMemoryUpdate` | Steph decision |
| OI-BR-4 | Port System A eval framework (250 cases + runner + gate) into `Backend/functions/src/berean/` | Engineering |
| OI-BR-5 | Add 4 missing collections to `functions/accountDeletion.js` (P0-05 gaps) | Engineering |
| OI-BR-6 | Confirm `bereanConstitutionalPipeline` (System A) remains deployed after any `default` codebase redeploy | DevOps |
| OI-BR-7 | Add `enforceAppCheck: true` to System B controllers missing it: `getJourneySnapshot`, `bereanHelper`, `generateChurchNotesSummary` | Engineering |
| OI-BR-8 | Resolve `premiumBereanCallables.ts` region=us-central1 (quota exhausted) — must change to `us-east1` | Engineering |
| OI-BR-9 | Pinecone + API.Bible stubs in System B Stage 3 — these are production gaps; SCRIPTURE_INTEGRITY checks run without real corpus | Engineering (backlog) |

---

## SELAH Build — Wave 4 Integration Decisions (2026-06-13)

| # | Decision | Rationale |
|---|----------|-----------|
| D-001 | TableAnchor uses associated values (enum with payload) | Richer type safety over string keys; matches existing design patterns |
| D-002 | C2PA manifest is a Firestore record stub, not real PKI | Real C2PA signing requires HSM infrastructure not available; stub enables UX flow + future upgrade path |
| D-003 | Tradition-aware uses keyword matching, not LLM classification | LLM adds latency + cost to every Berean query; keyword matching handles 90% of doctrinal questions with zero added latency |
| D-004 | Youth DM block fails silently from sender perspective | Preventing sender awareness of youth status is a safety requirement; revelation enables circumvention |
| D-005 | Aegis C59 confidence threshold = 0.7 | Below 0.7 false positive rate deemed too high for spiritual/religious content where similar phrasing can be benign |
| D-006 | Feed fail-closed: nil explanation → item does not render | Trust architecture requires explainability; allowing unexplained items would make the guarantee meaningless |
| D-007 | Room-first: structural not just visual separation | Visual ordering can be reordered by accessibility tools; structural separation in view hierarchy is the only guarantee |
| D-008 | BreathMotion.ambient = 4.0s full cycle | Derived from literature on physiological breath rate (~15 breaths/min, ~4s per cycle); matches human biology |
| D-009 | Table sunset is required, no default | Tables without sunsets become abandoned spaces; mandatory sunset enforces intentionality |
| D-010 | Living Memory echoes in co-creator are cite-specific | Generic echoes ("you've studied this before") feel hollow; specific citations ("your note from March 12") feel meaningful and earned |

---

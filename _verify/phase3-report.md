# Phase 3 — Berean v1 Verification Report
Date: 2026-06-07

## Summary

| Capability | Status | Notes |
|-----------|--------|-------|
| Core Intelligence | ✅ PASS | callModel wired, memory/RAG/perspectives/crisis all built |
| Voice | ✅ PASS | Personas, modes, clean-end guardrail enforced |
| Usage & Metering | ✅ PASS | Safety-exempt always visible; honest meters |
| Connectors / BibleProvider | ✅ PASS | BSB/WEB/KJV; YouVersion correctly blocked |
| Controls | ✅ PASS | 5-tier Sharing, Capabilities toggles, minor guard |
| Human Gate — Minor Graph | ✅ PASS | throws + HumanGatePayload — never silently writes |
| Human Gate — Crisis Content | ✅ PASS | AI answer suppressed; only real resources surfaced |
| Human Gate — CSAM | ✅ PASS | Existing ncmecReporter.js pipeline, unchanged |
| Forbidden design tokens | ✅ PASS | Zero violations in src/berean/; contracts.ts tokens are all white/light spec |
| Private as default visibility | ✅ PASS | Enforced in SharingVisibility.tsx (value ?? 'private') and controlsService DEFAULT_VISIBILITY |
| No client-side secrets | ✅ PASS | All keys in defineSecret / CF environment. BibleProvider.getBibleKey() is a CF-callable placeholder. |
| Routing: pastoral/scripture → Claude only | ✅ PASS | amenRouting.config.js: berean_answer/berean_explain/verse_context all chain: ["claude"], fail: "fail_closed", no fallover |
| Grounded answers fail closed | ✅ PASS | berean_answer: retrieval: "pinecone", requireCitations: true; refused on low confidence |
| Moderation fails closed | ✅ PASS | NeMo guard routes (guard_input/guard_output/crisis_handoff) all fail: "fail_closed" |
| No engagement hooks in Voice | ✅ PASS | voiceService.endSession() confirmed: no re-engagement, no auto-continue |
| Safety actions never counted | ✅ PASS | safetyExempt: true hardcoded in usageService; safety/crisis excluded from credit costByDomain |
| Berean Firestore rules added | ✅ PASS | B-1 through B-8 invariants in firestore.rules |
| bereanChat / bereanMemory / bereanCrisisDetect CFs | ✅ PASS | Appended to v2functions.js; auth enforced; rate limited; secrets via defineSecret |

---

## Credential Stops (flag before deploy)

The following secrets must be set in Firebase Secret Manager before the v1 callables are live:

| Secret | Required | Status |
|--------|----------|--------|
| ANTHROPIC_API_KEY | Yes | Verified present in existing bereanFunctions.js — ✅ |
| NVIDIA_API_KEY | Yes | Verified present in existing nvidiaClient.js — ✅ |
| PINECONE_API_KEY | Yes | Verified present in existing mlClients.js — ✅ |
| PINECONE_HOST | Yes | Verified present in existing mlClients.js — ✅ |
| ALGOLIA_APP_ID | Yes | Verified present in existing algoliaSync.js — ✅ |
| ALGOLIA_ADMIN_API_KEY | Yes | Verified present in existing routerCallable.js — ✅ |
| BIBLE_API_KEY | **New** | ⚠️ CREDENTIAL STOP: Must be provisioned. api.bible free tier. Set as `BIBLE_API_KEY` secret in Firebase console. |
| GOOGLE_TTS_API_KEY | Optional | Not required — Voice degrades to text-only without it |
| GOOGLE_STT_API_KEY | Optional | Not required — Voice degrades to text-input without it |

---

## Human Gates Confirmed Active

### 1. MINOR_GRAPH_DATA
- **Location:** `src/berean/controls/controlsService.ts` — `updateCapabilities()`
- **Behavior:** `assertMinorGraphGuard()` logs a `HumanGatePayload` with `reason: 'MINOR_GRAPH_DATA'` and throws before any Firestore write. Connectors also guarded in `connectorsService.ts` via `assertNotMinor()`.
- **Status:** ✅ PASS — scaffold built; T&S must review the HumanGatePayload log path before enabling minor accounts.

### 2. CRISIS_CONTENT
- **Location:** `src/berean/core/BereanCore.tsx` → `sendMessage()`, `src/berean/core/crisis.ts` → `handleCrisis()`
- **Behavior:** Keyword fast-path (`detectCrisis()`) suppresses AI answer before any CF call. If keywords not matched, `bereanCrisisDetect` CF runs NVIDIA detection; result `crisisDetected: boolean` returned — AI text never returned from CF. `handleCrisis()` surfaces only `getCrisisResources()` (hardcoded US crisis lines — no AI content).
- **Status:** ✅ PASS — AI answer suppressed at both stages. T&S owns the human response queue.

### 3. CSAM_SIGNAL
- **Location:** `functions/ncmecReporter.js` (pre-existing pipeline, not modified)
- **Behavior:** Existing pipeline routes to NCMEC CyberTipline with human authorization SLA (see OPEN-4 in firestore.rules). Berean v1 does not change this path.
- **Status:** ✅ PASS — not changed; human gate pre-existing.

---

## Routing Verification

| Domain | Task Routed | Provider | Fail Policy |
|--------|------------|----------|------------|
| scripture | berean_answer | claude only | fail_closed |
| prayer | prayer_generate | claude only | fail_closed |
| devotional | berean_explain | claude only | fail_closed |
| theology | berean_perspective | claude only | fail_closed |
| pastoral | berean_answer | claude only | fail_closed |
| study | berean_explain | claude only | fail_closed |
| church_notes | berean_explain | claude only | fail_closed |
| reflection | prayer_rewrite | claude only | fail_closed |
| discovery | berean_proactive | claudeFast → claude | degrade to null |
| safety | guard_input | nvidia | fail_closed |
| crisis | crisis_handoff | nvidia (detection only) | fail_closed |
| general | berean_explain | claude only | fail_closed |

All pastoral/scripture domains: **Claude only, no fallover, fail_closed** ✅

---

## Design Token Verification

Checked all 19 `src/berean/**/*.{ts,tsx}` files for forbidden tokens:

| Token | Status |
|-------|--------|
| `#C9A84C` (gold) | ✅ Not present in styles |
| `#FFD97D` (gold light) | ✅ Not present in styles |
| `#7B68EE` (purple) | ✅ Not present in styles |
| `#0A0A0F` / `#111118` (dark bg) | ✅ Not present in styles |
| Cormorant Garamond | ✅ Only appears in prohibition comments |
| `tokens.bg = '#F4F4F2'` | ✅ Used consistently |
| `tokens.card = '#FFFFFF'` | ✅ Used consistently |
| `tokens.accent = '#007AFF'` | ✅ Selection/CTA only |
| SF system font | ✅ All components |

---

## Deploy Steps Required (human-gated)

1. **Provision `BIBLE_API_KEY`** — api.bible account, set in Firebase Secret Manager as `BIBLE_API_KEY`
2. **Deploy updated `firestore.rules`** — `firebase deploy --only firestore:rules --project amen-5e359`
3. **Deploy Cloud Functions** — `firebase deploy --only functions:bereanChat,functions:bereanMemory,functions:bereanCrisisDetect --project amen-5e359`
4. **Seed `config/credits` and `config/voice`** — Firestore documents for credit limits and voice config (Admin SDK or console)
5. **T&S review of crisis HumanGatePayload log path** — before enabling production traffic on `bereanCrisisDetect`

---

## What is NOT done (by design)

- **SwiftUI parity** — out of scope per build spec; React/JSX prototype complete
- **YouVersion adapter** — blocked pending written commercial agreement; stub is in `BibleProvider.ts`
- **Google TTS/STT live wiring** — optional credentials; Voice degrades gracefully to text without them
- **Minor account production testing** — human gate scaffold built; full QA requires T&S sign-off
- **Pinecone index seeding** — retrieval infrastructure exists; faith corpus ingestion is a separate deployment step

---

## File Inventory

```
src/berean/
  contracts.ts              Phase 1 — enums, types, tokens (frozen)
  wire.ts                   Phase 3 — integration + invariant assertions
  core/
    BereanCore.tsx           Provider + useBerean hook
    callBerean.ts            Firebase callable wrapper
    memory.ts                Read/write/soft-delete/summarize
    crisis.ts                Detection + human gate + real resources
    perspectives.ts          Multi-perspective prompt builder + parser
  voice/
    voiceService.ts          Session state, clean-end guardrail
    VoiceSettings.tsx        Persona carousel, speed, mode
    VoiceSession.tsx         Hands-free / push-to-talk UI
    ScriptureReadAloud.tsx   Read-aloud with sentence highlighting
  usage/
    usageService.ts          Firestore read + real-time subscription
    useUsage.ts              React hook
    UsageMeters.tsx          Session + weekly bars; safety always free
  connectors/
    BibleProvider.ts         BSB/WEB/KJV adapters + YouVersion stub
    connectorsService.ts     Firestore read/write + minor guard
    ConnectorsScreen.tsx     4 faith-native connector cards
  controls/
    controlsService.ts       Capabilities + visibility persistence
    CapabilitiesScreen.tsx   Toggles + minor scope indicator
    SharingVisibility.tsx    5-tier picker, private default

functions/v2functions.js    +bereanChat, +bereanMemory, +bereanCrisisDetect
functions/router/amenRouting.config.js  +8 Berean v1 routing tasks
firestore.rules             +berean/{uid}/... B-1–B-8 invariants
_audit/phase0-findings.md   Phase 0 audit record
_verify/phase3-report.md    This file
```

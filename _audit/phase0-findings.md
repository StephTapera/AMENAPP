# Phase 0 — Berean v1 Audit Findings
Generated: 2026-06-07

## WHAT EXISTS

### React / Frontend
- `Berean.jsx` (1800 lines) — **P0 BLOCKED**: uses forbidden design tokens
  - Dark theme: `bgDeep: '#0A0A0F'`, `bgMid: '#111118'`, `bgPanel: '#1A1A26'`
  - Gold: `goldPrimary: '#C9A84C'`, `goldLight: '#E8CB7A'` — FORBIDDEN per spec §3.5
  - Font: `'Cormorant Garamond', Georgia, serif` — FORBIDDEN per spec §3.5
  - **Disposition:** Replaced by new `src/berean/` modular structure. Old file preserved as-is.
- `berean-preview.html`, `berean-preview 2.html` — static HTML previews, no impact.
- `BereanOS/` — directory exists, no Swift files found inside.

### Backend (functions/)
- `router/callModel.js` — **HEALTHY**: 8-stage pipeline (flag gate → NVIDIA input guard → Pinecone retrieval → provider call → fail policy → citation validation → NVIDIA output guard → structured log). 30s timeout. Fail-closed semantics correct.
- `router/amenRouting.config.js` — **HEALTHY**: Claude-only for berean_answer/berean_explain/verse_context/prayer_generate/prayer_rewrite/comment_coach. PROVIDERS table has claude-opus-4-7, claude-sonnet-4-6. **GAPS:** missing `crisis`, `berean_memory_summarize`, `berean_perspective`, `berean_proactive`, `berean_voice_tts`, `berean_voice_stt`, `berean_bible_lookup` tasks.
- `bereanFunctions.js` — callables exist (bereanBibleQA, bereanMoralCounsel, etc.), all route through callModel or direct Claude. Secrets via defineSecret ✓.
- `routerCallable.js` — callModelBerean production callable wired. Auth enforced ✓. Rate limit enforced ✓.
- `v2functions.js` — RTDB + Firestore + scheduler triggers, no Berean callables (correct isolation).

### Firestore
- `firestore.rules` (2026-06-05) — comprehensive per-user isolation, minor guards, soft-delete invariant, role-based claims. **CRITICAL GAP:** zero rules for `berean/{uid}/...` sub-collections. Any client can currently read/write these paths (Firestore denies by default for paths with no rule match — but explicit per-path rules required for clarity and audit compliance).

### Contracts
- `Contracts/` — markdown spec files (C1–C6), no typed TypeScript module. `src/berean/contracts.ts` does not exist.

---

## P0 ISSUES FIXED IN THIS BUILD

| # | Issue | Fix |
|---|-------|-----|
| P0-1 | Forbidden design tokens in Berean.jsx | New `src/berean/` structure uses spec-compliant tokens (§3.5) |
| P0-2 | Cormorant Garamond font in Berean.jsx | All new UI uses SF system font only |
| P0-3 | `berean/{uid}/...` paths absent from Firestore rules | Added in Phase 1 `firestore.rules` addition |
| P0-4 | No `contracts.ts` typed module | Created in Phase 1 |
| P0-5 | Routing config missing crisis/memory/perspective tasks | Added in Phase 1 routing update |

---

## WHAT PHASE 1 MUST RECONCILE

1. **Enum drift** — existing `callModel` uses `task` as a plain string; Phase 1 `contracts.ts` introduces `Domain` type. Phase 2 callables must import and narrow to `Domain`.
2. **Model name** — `bereanFunctions.js` references `claude-opus-4-5-20251101` (old) in its local `callClaude` helper. The routing config correctly uses `claude-opus-4-7`. New callables must route through `callModel`, not the local helper.
3. **Schema collisions** — `berean/{uid}/memory` path was not present in rules; no existing data at risk. Safe to add.
4. **safetyLevel** — new parameter in Phase 1 callModel signature. The existing router accepts it as pass-through context; backward-compatible.

---

## HUMAN GATES (do not auto-implement)

- [ ] Minor-account graph data writes → build guard scaffold, STOP, flag
- [ ] Crisis handoff content → build routing scaffold only; real human response queue is owned by T&S
- [ ] CSAM signals → route through existing ncmecReporter.js pipeline; human decision; never silently handled

---

## CREDENTIAL STOPS (flag if secrets missing)

- `ANTHROPIC_API_KEY` — required for all pastoral/scripture tasks
- `NVIDIA_API_KEY` — required for NeMo Guards (input/output moderation)
- `PINECONE_API_KEY` + `PINECONE_HOST` — required for grounded RAG
- `ALGOLIA_APP_ID` + `ALGOLIA_ADMIN_API_KEY` — required for keyword search fallback
- `GOOGLE_TTS_API_KEY` (new) — required for Voice TTS
- `GOOGLE_STT_API_KEY` (new) — required for Voice STT

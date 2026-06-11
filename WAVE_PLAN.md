# AMEN Universal Migration & Context System — WAVE PLAN

> Import the person, not the content. Status: **Wave 0 FROZEN** (2026-06-10).
> Everything behind `AMENFeatureFlags.contextSystemEnabled` (master) + per-wave sub-flags, all default OFF.

## §11 Final-check deltas (recon-grounded)

The draft spec's assumptions were verified against the live codebase. Deltas that
every wave agent must honor:

| Spec assumption | Reality in this repo | Action |
|---|---|---|
| `FeatureFlags.contextSystem` | Canonical flags live in `AMENAPP/AMENFeatureFlags.swift` (`AMENFeatureFlags.shared`, Remote Config–backed, snake_case keys) | Added `contextSystemEnabled` + 6 sub-flags (`context_*_enabled`), all OFF. **No separate flag type.** |
| Aegis registry C1–C58 | No numeric Aegis registry exists. `Contracts/` C1–C6 are the **unrelated SpiritualOS** contracts. The capability set is `AmenCapability` (verbs). C59/C60 are referenced only by the Context skeleton. | Keep **C59 (Injection Defense)** + **C60 (Minor Constraints)** as Context-System capability IDs. Specs frozen in `AegisEnforcementService.swift`. |
| Tiered encryption S/C/P | `EncryptionTier` enum already present | Tier table encoded as code in `ContextTierTable` (not convention). |
| Hey Feed preferences | `HeyFeedPreferencesService` (`userFeedPrefs/{uid}`): `setMode`, `toggleTopicPin`, `recordSignal`, `savePreferences()` | Wave 4 `feed-init` **extends** this; never forks. |
| Find a Church matching | `AlgoliaSearchService` + `ChurchMatcherService.rank(churches:userLocation:)`; explanation via `ChurchMatch.explanation` / `explainMatch()` | Wave 4 `matching-engineer` extends indexes to groups/Spaces/events; reuses explanation pattern. |
| Commitment Objects | `AmenCommitmentObject` + backend `createActionObject` (`actionIntelligence.ts`, coll `actionIntelligenceObjects`); privacy tiers `tier_p/tier_c/tier_s` | Wave 4 `commitment-bridge` reuses this primitive. |
| Living Memory | `LivingMemoryService` is a discontinued stub; **active = `SemanticEmbeddingService`** (server-side embeddings via CFs) | Wave 5 `manual-projection` uses `SemanticEmbeddingService` path for Life Capsule. |
| GlassKit | `AmenLiquidGlassComponents` (`AmenLiquidGlassPillButton`, `.amenLiquidGlassCapsuleSurface`), tokens in `AmenGlassDesignTokens`, **`Motion.adaptive(_:)`** for reduce-motion | All new UI uses these; no glass-on-glass. |
| Berean SSE | Realtime is **Firestore-snapshot-listener** based (`BereanRealtimeSessionManager`, ephemeral OpenAI token broker), not fetch/AbortController | Wave 2 `interview-engineer` models cancellation as `listener.remove()` + ephemeral state clear. |
| Firestore/Functions | `firestore.rules` (deny-by-default, `isSignedIn()/isOwner()`); CFs `onCall` w/ `enforceAppCheck: true`, region `us-central1`, project `amen-5e359`; Gen-1 `functions/index.js`, Gen-2 `functions/v2entry.js` | New collections `contextFacets`, `contextSnapshots`; new CFs `enforceAppCheck:true` in `us-central1`. |

## Waves

- **Wave 0 — Contracts (FROZEN).** Models, tier table, rules, C59/C60, CF signatures, flags. Owner: orchestrator.
- **Wave 1 — Store + Manual Entry + Faith Builder.** `store-engineer`, `passport-ui`, `faith-builder`, `rules-tester`.
- **Wave 2 — Berean Migration Interview.** `interview-prompt-author`, `interview-engineer`, `interview-ui`.
- **Wave 3 — Universal Extractor + Approval UI.** `extractor-engineer`, `aegis-engineer`, `approval-ui`, `red-team`.
- **Wave 4 — Consumers.** `feed-init`, `matching-engineer`, `intro-generator`, `commitment-bridge`.
- **Wave 5 — Exports.** `export-engineer`, `qr-engineer`, `manual-projection`, `docs-publisher`.

## Gate discipline
Each wave runs in parallel only because Wave 0 froze shared surfaces. HTML demo →
SwiftUI for every user-facing flow. Orchestrator verifies every exit-gate checkbox
with evidence (diagnostics, emulator logs, demo links) before opening the next wave.
Three-strikes → `BLOCKED.md` → orchestrator triage.

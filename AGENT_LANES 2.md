# AGENT_LANES.md — Multi-Agent Lane Manifest

**Purpose:** Many agent sessions edit this repo concurrently. This file is the single source of truth for *who owns what*, so agents consult & update it instead of asking the human which surface is clear.

## Convention (read before editing anything)
1. **Claim your lane at session start:** add a row to *Active Lanes* with `agent/task · owned paths · started · status`.
2. **Release at session end:** set status to `released` (or delete the row).
3. **Contested = any path that appears in another `active` row.** Do not edit a contested path. Defer it to a *gated batch*, name the gate (what merges / goes green), and keep working ungated lanes. Never open a parallel worktree that edits a path another active lane owns — that just moves the conflict to merge time.
4. **New files / read-only work are never contested** — do them anytime.
5. **Hotspot files (below): append-only, smallest possible diff, ONE owner at a time, note the claim here.**

## Shared hotspot files (special rule)
| File | Rule |
|------|------|
| `firestore.rules` | append-only, smallest diff, single claimant |
| `firestore.indexes.json` | append-only, single claimant |
| `Backend/functions/src/index.ts` / `functions/index.js` (exports) | append-only export lines only |
| `AMENAPP.xcodeproj/project.pbxproj` | avoid; prefer adding code to existing in-target files |
| `AMENAPP/AMENFeatureFlags.swift` | append-only (new flag = property + default + RC-load line) |

---

## Active Lanes (inferred 2026-06-09 from session list + `git status` + worktrees; agents: correct your own row)

| Agent / task | Owned paths (lane) | Status | Notes |
|--------------|--------------------|--------|-------|
| **Onboarding** | `AMENAPP/AMENAuthLandingView.swift`, `AMENAPP/MinimalAuthenticationView.swift`, `AMENAPP/Onboarding*.swift`, `AMENAPP.xcodeproj/Onboarding*.swift`, GlassButton primitives | active | Refactoring auth landing UI (authLiquidGlassPill already removed). |
| **MERGE** | same auth-UI surface as Onboarding | active | Pairs with Onboarding lane. |
| **Church notes.1 / Church Note.0** | `AMENAPP/ChurchNotes/**`, `AMENAPP/AMENAPP/ChurchNotes/**`, `Backend/functions/src/churchNotes/**` | active | Two sessions on Church Notes. |
| **Berean LLM** | `Backend/functions/src/berean/**`, `bereanChatProxy*.ts`, `bereanPulse*.ts`, `AMENAPP/AIIntelligence/Berean*` | active | TS modules mid-build (missing exports → 24 TS errors, see Handoffs). |
| **Liquid Glass Design** | glass component files (`AmenGlass*`, `LiquidGlass*`, `GlassEffect*`) | active | GlassKit consolidation territory. |
| **Resources UI** | `AMENAPP/ResourcesView.swift` + resources surfaces | active | |
| **Content engine** | `AMENAPP/AMENAPP/SpiritualOS/**`, ObjectHub, ContextEngine | active | Owns ObjectHub (see Handoffs). |
| **audit-UI agents** (×2–3) | read-only | active | UI audits; no writes. |
| **claude / onboarding-auth-remediation** (this agent) | `functions/phoneAuthRateLimit.js`, `functions/authenticationHelpers.js`, `AMENAPP/AuthenticationViewModel.swift`, `AMENAPP/AppLifecycleManager.swift`, `AMENAPP/AccountDeletionService.swift`, `AMENAPP/AMENEncryptionService.swift`, `AMENAPP/AgeAssuranceService.swift` (read), `AMENAPP/ContentView.swift` (age-gate route), `AMENAPP/DateOfBirthCollectionView.swift`, `AMENAPP/AmenPhoneAuthView.swift`, `AMENAPP/PhoneVerificationView.swift`, `Backend/functions/src/mediaGeneration/**`, `Backend/functions/src/covenant/**` (types only), `contracts/onboarding/**`, `AUDIT.md`, `RULES_INDEX_AUDIT*.md`, `AGENT_LANES.md`, `AMENAPPTests/*` (new) | active | Auth/onboarding safety remediation (see `AUDIT.md`). Holds `AMENFeatureFlags.swift` append (`ff_onboarding_v2`). |

> **Worktrees:** ~17 agent worktrees exist under `.claude/worktrees/` (mostly locked at `446fc8cc`). Those agents are isolated; the **main tree is the shared surface** this manifest governs.

---

## Gated batches (parked work, gate named)
| Batch | Owner | Gate |
|-------|-------|------|
| Auth-UI pass (E-01/E-02 Reduce-Transparency, G-01 dark mode, GlassButton consolidation, C-03 welcome_back) | claude | **Onboarding+MERGE refactor merged + green build.** Then one pass on fresh read. |
| TS remainder → green (`npm run build`) | Berean LLM lane (handoff) + covenant Stripe decision | see Handoffs |
| Find-a-Church wiring | claude | `Backend/functions/src/churchDiscovery.ts` stable in git for one session |

---

## Handoff tasks (work assigned to another lane)

### → Berean LLM lane: fix your TS compile errors (global gate: `npm run build` must be green)
`Backend/functions` does not compile. 24 of the remaining errors are in your modules (missing exports / missing files). Per-file list:
- `berean/models/berean.ts` — missing exports: `TopicClass`, `BereanConversation`, `BereanMessage`, `DiscipleshipProfile`, `PracticeRecommendation`, `ReflectionEntry`, `BereanSafetyEvent`, `LLMStructuredOutput`.
- `berean/services/AuthorityGuardrailEngine.ts` / `SpiritualStateEngine.ts` / `DiscipleshipTrackerService.ts` — missing singleton exports (`authorityGuardrailEngine`, etc.).
- `berean/prompts/responseModePrompt.ts` — `ResponseMode` union missing 7 members (`deep_exegesis`, `study`, `gentle_pastoral`, …).
- `berean/services/PromptAssembler.ts` — `buildBereanSystemPrompt` (is `buildSystemPrompt`?), `buildStructuredOutputContract` missing.
- `bereanChatProxy.ts` / `bereanChatProxyStream.ts` — missing `./agents/agentIdentity`, `./agents/agentOutcomes`; `agentObservability` missing `startAgentRun`/`logAgentSpan`/`finishAgentRun`.
- `bereanPulse.ts` (7) / `bereanPulseEngine.ts` (3) — `Record<string,string>` undefined-narrowing + message-shape typing.

### → Content-engine lane: ObjectHub gap spec (handoff, not held)
Wire every ObjectHub "coming soon" sheet end-to-end and integrate the smart-bar requirement. ObjectHub lives in the Content-engine lane (`SpiritualOS/**`); claude is not editing it. Owner to enumerate the coming-soon sheets and complete them per the standing end-to-end definition.

---

## Completed by claude this run (released paths — safe to build on)
Security lane (`functions/*.js`: fail-closed rate limit, `signInWithUsername`, admin gate, deletion cascade), C-02 E2EE key wipe, D-01 universal age gate, D-02 dual-onboarding crash, C-01 Keychain identity hint, F-03 hint clear, H-01 account-switch safety, H-04/H-05 network resilience, B-01/B-02/E-03/E-07 autofill+VoiceOver, isolated TS fixes (`mediaGeneration`, `churchDiscovery` confirmed). Contracts in `contracts/onboarding/`. See `AUDIT.md`.

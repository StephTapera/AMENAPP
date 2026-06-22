# AMEN Connect V1 — Wave 0 Audit (Phase 0 deliverable #1)

**Date:** 2026-06-18 · **Spec:** `AMEN_CONNECT_V1_SPEC.md` · **Status:** Phase 0, contracts frozen, awaiting "proceed."
**Doctrine:** audit before rebuild; existing features are PRESERVED, not removed; nothing is "done" until the human's canonical build is green.

This document is read-only evidence. No existing feature was modified by the audit. The only working-tree changes in Phase 0 are: the new contract file, the new docs, and additive feature-flag scaffolding (all OFF) — itemized in §6 below.

---

## 1. Existing Connect — what V1 PRESERVES

The live Connect surface is **`AmenConnectSpacesHubView`**, mounted on **tab 6**.

| Capability | File | Evidence | Status |
|---|---|---|---|
| Connect hub (entry point) | `AMENAPP/AMENAPP/ConnectSpaces/AmenConnectSpacesHubView.swift:88` | 3-tab hub (My Spaces / Discover / Creator Hub) | LIVE — extend, do not replace |
| Tab mount | `AMENAPP/.../ContentView.swift:707-713` | `viewModel.selectedTab == 6` | LIVE |
| Connect VM + service | `AMENAPP/AmenConnectService.swift:1` | `AmenConnectViewModel`, Firestore listener + cache | LIVE |
| Phase-0 binding | `AMENAPP/AMENAPP/ConnectSpaces/AmenConnectSpacesPhase0BindingService.swift` | space data sync | LIVE |
| For-You rail | `ConnectForYouView.swift` | personalized recs | LIVE |
| Marketplace | `ConnectMarketplaceView.swift` | jobs/tutoring/services | LIVE |
| Forum / channels | `ConnectForumView.swift` | discussions | LIVE |
| Ministries | `ConnectMinistriesView.swift` | ministry discovery | LIVE |
| Serve / volunteer | `ConnectServeView.swift` | opportunities | LIVE |
| Network / mutuals | `ConnectNetworkView.swift` | member network | LIVE |
| AI matching | `AMENConnectAIMatchEngine.swift` | mutual-connection matching | LIVE |
| Offline queue | `ConnectOfflineQueue.swift` + `Backend/functions/src/connectQueue/processConnectQueuedDraft.ts` | draft replay | LIVE |
| Backend Connect | `Backend/functions/src/amenConnect.ts:1` | space CRUD, invites, roles, audit | LIVE |
| Church Notes | `AMENAPP/ChurchNotesService.swift` (+ siblings) | tab 3 Resources | LIVE |
| Find a Church | `AMENAPP/FindChurchView.swift` | tab 3 Resources; backend `churchMatchingEngine` | LIVE |
| Prayer surfaces | `AMENAPP/PrayerChainView.swift`, `ModernPrayerWallView.swift` | prayer | LIVE |

**Dead / superseded (NOT a V1 dependency):**
- `AMENAPP/AmenConnectView.swift:1` — header comment states "superseded by AmenConnectSpacesHubView … zero call sites … dead code." Do not build against it; deletion is a quiet-tree task, out of scope for Wave 0.
- `AMENAPP/AmenConnectV2View.swift:47` (`AmenConnectV2RootView`) — gated behind existing `connectLayoutV2Enabled` (OFF). Distinct from this spec's `connect_v2_home_enabled`; **naming-collision risk** flagged in §5.

**V1 preserves all LIVE rows above.** `assembleConnectHome` is additive: a new intelligence home that renders *above/alongside* the existing hub, gated by `connect_v2_home_enabled` (OFF). The old path stays live while that flag is false.

---

## 2. GlassKit — reuse-vs-build (spec §2 components)

Liquid Glass component libraries already in the repo:
- `AMENAPP/AIIntelligence/LiquidGlass/AmenLiquidGlassComponents.swift` — pill button, control dock, bottom sheet.
- `AMENAPP/AIIntelligence/LiquidGlass/CommunicationOSGlassKit.swift` — insight chip/bar, action sheet, **expandable memory card with chevron toggle** (`:570-573`), note pill. Header `:14`: *"No glass-on-glass stacking."*
- `AMENAPP/AMENAPP/LiquidGlass/` — `LiquidGlassCard`, `LiquidGlassMaterial`, `LiquidGlassTokens.swift` (corner radii, blur materials, shadows, motion).
- `AMENAPP/AMENAPP/AMENAPP/Pulse/PulseGlassKit.swift` — ivory editorial kit: hero card, stat/status row, eyebrow-in-header, reflection card.
- `AMENAPP/DesignSystem/AdaptiveGlassV2/AdaptiveSurfaceModifier.swift:18,64-73` — **no-glass-on-glass invariant** enforced (returns `Color.clear` for roles that own their glass renderer).

Tokens: `AmenColorScheme.swift:37` (`amenBlack == Color.black` — known non-adaptive trap, see memory `amenblack-non-adaptive-root-cause`; new GlassKit must use semantic `.primary`/tokens, not `amenBlack`). Brand colors in `AmenAdaptiveColors.swift`. `amenPurple` is defined inline in `CoCreationCanvasView.swift` only — GlassKit needs a token home for it.

| Spec §2 component | Decision | Basis |
|---|---|---|
| `GlassMediaCard` (collapsed/expanded) | **NEW** | no media card with hero+scrim+overlay+expand exists |
| `GlassFactCard` (image-2 Concierge) | **NEW** | closest is `PulseReflectionCard` (AI prompt, not facts) |
| `GlassStatRow` (3-up) | **NEW** (pattern from `PulseStatusRow`) | existing is verse/prayer/community-specific |
| `GlassPreviewThumb` | **NEW** | none |
| `GlassEyebrow` | **NEW**, extract pattern | currently inlined in `AmenPulseHeader` (`PulseGlassKit.swift:228-232`) |
| `EmphasisText` | **NEW**, thin | gold/blue emphasis exists via tokens; no reusable bold-inline text view |
| `ChevronToggle` | **NEW**, extract pattern | rotation logic inlined in `AmenGlassMemoryCard` (`CommunicationOSGlassKit.swift:570-573`) |

**Conclusion:** all 7 are net-new components in a new `GlassKit/` home, but each can lift a proven pattern from an existing kit. No-glass-on-glass is reused from `AdaptiveSurfaceModifier`. Build once; Spaces adopts (Phase 5).

---

## 3. Engine to mirror — `assembleDiscoveryFeed`

- Callable: `Backend/functions/src/discovery/assembleDiscoveryFeed.ts`, exported `Backend/functions/src/index.ts:158`, **region `us-east1`**, `onCall({ region, timeoutSeconds:15, memory:"256MiB" })`.
- Ranking: `discovery/contracts.ts:202-209` `FORMATION_WEIGHTS` (engagement forbidden = 0); `discovery/formationRanker.ts` `computeFormationScore` / `diversifyAndRank` (MMR per-type caps) / `freshnessScore`.
- CalmCap: `discovery/contracts.ts:24-29` `CALM_CAP_V1` (`infiniteScroll:false`).
- Safety: `discovery/safetyStamper.ts` `filterAndStamp` — every candidate must carry a `SafetyStamp` (`clearedBy: GUARDIAN|AEGIS`) or it is dropped (fail-closed).
- Identity/ACL helpers: `discovery/.../aclHelper.ts` (`isFollowing`, `isMutual`, `isBlocked`).

**`assembleConnectHome` mirrors this exactly**: candidate gen → dedup → `diversifyAndRank` (new `CONNECT_RANKING_WEIGHTS`) → `filterAndStamp` → cap by `CONNECT_CALM_CAP_V1.maxActions`. Lives at `Backend/functions/src/discovery/assembleConnectHome.ts` (sibling) or a new `connect/` dir; exported in `index.ts` near `:158`. **No new `contracts/` dir existed — created at `Backend/functions/src/contracts/connect.ts`.**

---

## 4. Safety infra to reuse (spec §5)

| Need | Existing | Evidence |
|---|---|---|
| `isMinor` (server) | `resolveMinor()` fail-closed | `Backend/functions/src/pulse.ts:95-143`; mirror in `safetyOS.ts` |
| Age tier (client) | `AMENAgeAssuranceTier.isMinor` | `AMENAPP/AgeAssuranceModels.swift:16-27`; `AgeAssuranceService.swift:49-56` (defaults teen) |
| Keychain age gate | survives reinstall | `AMENAPP/AgeGateView.swift:14-97` |
| MEDIA-GATE fail-closed | quarantine state machine | `Backend/functions/src/creatorProfiles/enqueueCreatorMedia.ts` + `creatorProfileTypes.ts:34-44`; iOS `CreatorHubHeroHeader.swift` renders only when `.approved` |
| CSAM / child escalation | Tier-1 immediate freeze | `SafetyReportingService.swift:168-210` (`childSafetyViolation`, `groomingOrTrafficking`) |
| Minor messaging gates | adult→minor blocks | `MinorSafetyService.swift` `requiresGuardianRouting()`; `Backend/.../bereanChatProxy.ts` |
| Feature flags (client) | RC singleton, defaults OFF | `AMENAPP/AMENFeatureFlags.swift` (connect block `:633` region) |
| Feature flags (server safety) | server-authoritative, default ON, fail-closed | `Backend/functions/src/serverFeatureFlags.ts` |

**Guardian link — NEW (this is the safety foundation).** Only stub fields exist: `parentalSupervisionEnabled`, `parentUserId` in `AgeAssuranceModels.swift:88-89` (never wired); a never-populated `parentUserId` in `pulse.ts`. There is **no** verified-guardian primitive today. Contract + state machine landed in Phase 0 (§4 of this doc; types in `contracts/connect.ts`); the callable body is held for the "proceed" gate (see report).

---

## 5. Naming-collision & topology risks (resolve before Wave 1)

1. **`connect_v2_home_enabled` (spec) vs existing `connectLayoutV2Enabled` / `connect_layout_v2_enabled`** — different features, similar names. Keep both; document that spec's flag gates the *intelligence home*, the existing flag gates the *W1/W2/W3 layout*. Do not conflate.
2. **`connect_live_rooms_enabled`** already exists as a hard CSAM gate (`AMENFeatureFlags.swift:633`). Untouched.
3. **Contracts path** — spec says `functions/src/contracts/connect.ts`; actual home is `Backend/functions/src/contracts/connect.ts` (creator codebase; where the mirror engine + `amenConnect.ts` live). **Decision applied.**
4. **`children/**`, `checkIns/**`, `guardianLinks/**`** collections do not exist in `firestore.rules` yet — net-new, default-deny (see `RULES_PLAN_CONNECT.md`).

---

## 6. Working-tree changes made in Phase 0 (additive only)

- `Backend/functions/src/contracts/connect.ts` — NEW. Frozen V1 contracts + `CONNECT_RANKING_WEIGHTS` + `CONNECT_CALM_CAP_V1`. `tsc --noEmit --strict` exit 0.
- `CONNECT_WAVE0_AUDIT.md`, `RULES_PLAN_CONNECT.md`, `CONNECT_WAVE0_SAFETY_CHECKLIST.md` — NEW docs.
- `AMENAPP/AMENFeatureFlags.swift` — additive flag scaffolding (16 `connect_*`/`glasskit_*` flags, all default OFF) at 3 sites: declarations after `:633`, RC defaults after `:1575`, RC reads after `:2242`. No existing flag changed.

No existing feature code, view, or function was modified. No files were committed. No `project.pbxproj` edit. No build or deploy run by the agent.

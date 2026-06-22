# Creator Profiles — Wave 0 Freeze Record

**Frozen:** 2026-06-18
**Feature:** AMEN Creator Profiles (ministry hubs — Apple Music Artist Page + Threads + Liquid Glass + grounded ministry AI)
**Status:** Wave 0 (contracts + flag manifest) code-complete. **STOP — report before Wave 1.**

## Artifacts (frozen)

| File | SHA-256 |
|---|---|
| `Backend/functions/src/creatorProfiles/creatorProfileTypes.ts` (source of truth) | `ff2cdbf803b8c2d42ce40a21a18b855735cb4ea1e45800983b3ccc22fa3c0551` |
| `AMENAPP/AMENAPP/CreatorProfiles/CreatorProfilesContracts.swift` (mirror) | `60661d25c86ed5a84437e04d203fa601a2654b1d90053c08ab493eb485024879` |

## Verification

| Check | Result |
|---|---|
| Swift mirror `swiftc -parse` | **exit 0** (syntactically valid + self-consistent) |
| TS isolated `tsc --noEmit --strict` | **clean** (no diagnostics) |
| Full Swift type-check | **HUMAN-PENDING** — requires target membership (no pbxproj edits by agent) + the reused `CalmCap` symbol, which is confirmed present at `AMENAPP/AMENAPP/DiscoveryOS/DiscoveryContracts.swift:19` (same app target/module). |

## TS ↔ Swift type map (field names match 1:1)

| TS interface/type | Swift type |
|---|---|
| `CreatorHubModerationStatus` | `CreatorHubModerationStatus` |
| `CreatorHubAudienceTag` | `CreatorHubAudienceTag` |
| `CreatorHubMediaRef` | `CreatorHubMediaRef` |
| `CreatorHubLink` | `CreatorHubLink` |
| `CreatorHubGeo` | `CreatorHubGeo` |
| `CreatorHubTicketing` | `CreatorHubTicketing` |
| `CreatorHubCalmCap` / `CREATOR_HUB_CALMCAP_V1` | **reuses existing `CalmCap`** (identical fields) |
| `CreatorHubBadge` | `CreatorHubBadge` |
| `CreatorHubProfile` | `CreatorHubProfile` |
| `CreatorHubEvent` (+Type/Status) | `CreatorHubEvent` (+Type/Status) |
| `CreatorHubTeaching` | `CreatorHubTeaching` |
| `CreatorHubResource` (+Kind) | `CreatorHubResource` (+Kind) |
| `CreatorHubCourse`/`Module`/`Lesson`/`ProgressModel` | same |
| `CreatorHubPrayerRequest` | `CreatorHubPrayerRequest` |
| `CreatorHubCommunityPost` (+Kind) | `CreatorHubCommunityPost` (+Kind) |
| `CreatorHubFollow` (+Category) | `CreatorHubFollow` (+Category) |
| `CreatorHubMetrics` | `CreatorHubMetrics` |
| `CreatorHubHeroState` (union) | `CreatorHubHeroState` (Codable enum, `{type,data}`) |
| `CreatorHubFeaturedModule` (union) | `CreatorHubFeaturedModule` (Codable enum, `{type,data}`) |
| `CreatorHubPillCounts` | `CreatorHubPillCounts` |
| `CreatorHubFirstPages` | `CreatorHubFirstPages` |
| `CreatorHubProfilePayload` | `CreatorHubProfilePayload` |
| `CreatorHubModulePage<T>` | `CreatorHubModulePage<T: Codable>` |
| `CreatorHubCitation` (+Source) | `CreatorHubCitation` (+Source) |
| `CreatorHubAssistantQuery` / `…Answer` | same |
| `CREATOR_HUB_FLAGS` / `…DEFAULTS` | `CreatorHubFlags` |

**Wire conventions:** timestamps are ISO-8601 strings (Swift decodes via `JSONDecoder.creatorHubDecoder`, `.iso8601`); money is integer cents + ISO-4217; discriminated unions carry `{ type, data }` (mirrors the existing `DiscoveryCardPayload` pattern). No `any`/`[String:Any]` escape hatches.

## Feature-flag manifest — ALL DEFAULT OFF

`creator_profiles_enabled`, `creator_events_enabled`, `creator_teaching_search_enabled`,
`creator_resources_enabled`, `creator_prayer_board_enabled`, `creator_community_enabled`,
`creator_ai_assistant_enabled`, `creator_live_mode_enabled`, `creator_support_donations_enabled`,
`creator_voice_consumption_enabled`.

Defined as defaults-OFF in both `creatorProfileTypes.ts` (`CREATOR_HUB_FLAG_DEFAULTS`) and Swift (`CreatorHubFlags`). **Not yet wired** into `remoteconfig.template.json` or `AMENFeatureFlags.swift` — deferred deliberately (see Deviation #2).

## Deviations from the literal build prompt (forced by repo reality)

1. **Namespacing → `CreatorHub*` prefix.** The prompt's bare type names collide with shipped code:
   `CreatorProfile` (`AMENAPP/CreatorProfile.swift:9`, economic-graph model), `CommunityPost`
   (`AMENAPP/Media/AmenMediaCommunityRoomView.swift:59`), `PrayerRequest`
   (`AMENAPP/AMENAPP/CommunityOS/Prayer/PrayerModels.swift:158`). The existing `creator` Firebase
   codebase is a **video-editing studio** (`CreatorProjectPayload`, `CreatorAsset`), a different domain.
   All new types use the `CreatorHub*` prefix; backend lives in a new `creatorProfiles/` subdir, not `creator/`.

2. **Flag manifest NOT yet merged into the shared hot registries.** `remoteconfig.template.json` and
   `AMENFeatureFlags.swift` are large shared files currently being edited by other agents (tree is dirty —
   ~339 modified files). Editing them now risks merge corruption and violates this repo's shared-tree
   discipline. Flags are frozen in self-contained files and will be wired in a later wave / by a human on a
   quiet tree.

3. **Git: no `git add -A`, no branch switch (this turn).** §12 of the prompt assumes a clean tree and
   `git add -A`. The tree is hot with other agents mid-flight. Per this repo's documented shared-tree
   discipline, only the two new Creator-Hub paths should be staged, and branch creation/switch should
   happen on a quiet tree. No git mutation was performed by the agent.

## §3 Human-decision blockers (acknowledged; build around, do NOT mark "done")

- **CSAM scan stays OFF** behind the 4-part gate → creator media uploads must be MEDIA-GATE-quarantined /
  on-device-Vision pre-checked, never opened wide. (`CreatorHubMediaRef.moderation`, `isServable`.)
- **COPPA child-directed** (amended rule in force) → `audienceTag` ∈ {general, youth, kids, mixed} is
  captured now; kids/youth surfaces stay gated pending counsel sign-off.
- **Transcription transport** (on-device vs server) for Teaching Intelligence → flag, human decision.
- **Raw-media retention** → default none until decided.
- **Donations topology** → Stripe Connect Standard, `creator_support_donations_enabled` OFF until legal.
- **Search backend** → prefer Pinecone (avoid the exposed Algolia key in git history).

## §4 Reuse-map corrections found during recon (affect Wave 1+)

- **"Living Memory" iOS client is DISCONTINUED** (`AMENAPP/LivingMemoryService.swift` is a stub). Pinecone
  still exists server-side (`functions/v2functions.js` `bereanChat`, `PINECONE_API_KEY`). → assistant
  grounding (`askCreatorAssistant`, `searchCreatorTeachings`) must target backend Pinecone **directly**,
  not the removed iOS Living Memory layer.
- **"SCRIBE" is not a real service** — only feature flags exist. Smart-Notes wiring must either build SCRIBE
  or reuse `SelahNoteService` / `ChurchNotes` services. Surface as a Wave 5 dependency, not "done."
- **Adaptive Hero Engine** is the external `AdaptiveHeroEngine` framework; surface kinds are added via the
  adapter at `AMENAPP/AMENAPP/Features/HeroSurface/HeroSurfaceAdapter.swift` (a `fromCreatorProfile` factory),
  not by editing an in-repo enum. Note: a `.creator` `HeroSurface.kind` already exists — confirm intent
  before reusing vs. adding a distinct `creatorProfile` kind in Wave 3.
- **Colors:** use `AmenTheme.Colors.*` + `Color(hex:)`, **not** `Color.amenGold` (brand colors were purged).

## Wave 0 EXIT — next gate

Contracts + flag manifest frozen; Swift mirror parses; TS clean; checksums recorded above.
**Awaiting human go/no-go before Wave 1 (backend Cloud Functions).**

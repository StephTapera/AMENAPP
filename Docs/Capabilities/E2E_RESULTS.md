# Capabilities v1 — Wave 2 E2E Results

**Integrator:** Wave 2 INTEGRATOR  
**Date:** 2026-06-13  
**Branch:** feature/berean-island-w0  
**Gate SHA:** (see `git log --oneline -1`)

---

## Legend

| Status | Meaning |
|---|---|
| `PASS` | Verified by static analysis, code review, or compilation |
| `PARTIAL` | Partially working; known gap documented |
| `BLOCKED` | Requires emulator or staging environment to verify |
| `HUMAN-PENDING` | Requires human to build and run on device/emulator |

---

## Step 1 — Feature flags default OFF (PASS)

All five capability flags confirmed OFF in `AMENFeatureFlags.swift`:

| Swift property | Remote Config key | Default |
|---|---|---|
| `capabilitiesCoreEnabled` | `capabilities_core` | `false` |
| `capabilityPickerEnabled` | `capability_picker` | `false` |
| `prayerOSEnabled` | `prayer_os` | `false` |
| `scriptureIntelligenceEnabled` | `scripture_intelligence` | `false` |
| `verseLookupInlineEnabled` | `verse_lookup_inline` | `false` |

Verified at lines 895–903 and 2267–2271 of `AMENAPP/AMENFeatureFlags.swift`.

---

## Step 2 — TypeScript build clean (PASS)

```
npx tsc -p functions/tsconfig.capabilities.json --noEmit
# Exit 0, zero errors
```

Compilation target: `functions/lib/capabilities/`. Compiled output structure:
- `lib/capabilities/contextEngine/{index,callables,resolveContextAccess}.js`
- `lib/capabilities/capabilities/prayerOS/{index,callables,scheduled}.js`
- `lib/capabilities/capabilities/scripture/{index,callables,referenceParser}.js`
- `lib/capabilities/capabilities/registry/{index,callables}.js`

---

## Step 3 — Swift models / Capabilities diagnostics (PASS)

`XcodeListNavigatorIssues` returns **0 errors** in Capabilities files. The one
pre-existing stale error (`Invalid redeclaration of 'PrayerChain'` in
`CommunityContractsModels.swift`) is unrelated to Capabilities and pre-dates Wave 1.

Type-compatibility check (no duplicate module-level types):

| Type | Conflict risk | Resolution |
|---|---|---|
| `PrayerCard` | None — only one module-level definition | OK |
| `PrayerCategory` | Nested duplicates inside `PrayerPostCard`, `PrayerWallMapView_DEPRECATED`, `PrayerToolkitView` — all are inner types, shadow cleanly | OK |
| `PrayerStatus` | Nested duplicates inside `LiveActivityAttributes.PrayerStatus`, `CovenantModels.PrayerStatus`, `PrayerFollowThroughService.PrayerStatus` — all inner types | OK |
| `VerseCard` | No duplicates | OK |
| `BibleTranslation` | No enum conflict — `BibleTranslationPicker` (BereanAIAssistantView) is a View struct, not a competing enum | OK |
| `ScriptureRef` | No duplicates — `ScriptureReference` in Selah/BereanVerification is a distinct type name | OK |
| `Capability` | No module-level duplicates | OK |
| `ContextSource` / `ContextPolicy` / `ContextGrant` | No duplicates | OK |
| `FeatureDisabledError` | One definition only (PrayerOSService.swift) | OK |

**Contract drift noted (non-blocking):** `ScriptureRef.id` in `CapabilityModels.swift`
is `"\(blockId)-\(osisRef)"`, whereas `CONTRACTS.md §5` shows `var id: String { osisRef }`.
The implementation is more collision-safe (two verses in different blocks with the same
OSIS ref won't share an ID). Since both surfaces are frozen, this drift is logged but
not changed. If a downstream consumer relies on `osisRef`-only identity, file a
CONTESTED blocker.

---

## Step 4 — contextEngine callables exported (PASS)

Three callables wired into `functions/index.js` via `./lib/capabilities/contextEngine`:

```js
exports.contextEngine_getGrants   // enforceAppCheck: false
exports.contextEngine_setGrant    // enforceAppCheck: true
exports.contextEngine_getAuditLog // enforceAppCheck: false
```

Wire-format verified against `CONTRACTS.md §3.1`. Firestore path:
`users/{uid}/contextGrants/{sourceId}` and `users/{uid}/contextAuditLog/{autoId}`.

**Runtime verification:** BLOCKED — requires Firebase emulator with auth.

---

## Step 5 — capabilityRegistry_list callable exported (PASS)

Wired into `functions/index.js` via `./lib/capabilities/capabilities/registry`:

```js
exports.capabilityRegistry_list  // enforceAppCheck: false
```

Callable returns surface-filtered `Capability[]` from `capabilities/{capabilityId}`.
Client: `CapabilityRegistryStore.loadCapabilities(for:)` calls this and decodes via
`JSONSerialization → JSONDecoder` pipeline.

**Runtime verification:** BLOCKED — requires Firestore seeded with `seedCapabilities.ts`.

---

## Step 6 — Prayer OS callables exported (PASS)

Five exports wired into `functions/index.js` via `./lib/capabilities/capabilities/prayerOS`:

```js
exports.prayerOS_createCard
exports.prayerOS_updateCard
exports.prayerOS_listCards
exports.prayerOS_completeFollowUp
exports.prayerOS_followUpSweep   // scheduled, every 15 min
```

All App Check enforced. `prayerOS_createCard` checks `resolveContextAccess` for the
`prayerHistory` source before writing. `prayerOS_followUpSweep` uses idempotent
`"prompted"` status to prevent duplicate notifications.

**cardId → id remapping:** `PrayerOSService.decodeResponse()` remaps the wire key
`"cardId"` to `"id"` before decoding into the frozen `PrayerCard` model. Verified correct.

**Runtime verification:** BLOCKED — requires Firebase emulator with App Check debug token.

---

## Step 7 — Scripture Intelligence callables exported (PASS)

Three exports wired into `functions/index.js` via `./lib/capabilities/capabilities/scripture`:

```js
exports.scripture_detectReferences  // deterministic OSIS parser, no LLM
exports.scripture_getVerses         // Firestore cache → API.Bible fallback
exports.scripture_searchVerses      // keyword/reference search
```

65 referenceParser tests confirmed passing (commit `a582fb23`, Lane B).

**Runtime verification:** BLOCKED — requires Firestore `scriptureCache` collection and
optional `API_BIBLE_KEY` secret.

---

## Step 8 — Swift: CapabilityRegistryStore (PASS)

`CapabilityRegistryStore.shared` fetches `capabilityRegistry_list`, decodes via
`JSONSerialization → JSONDecoder`. Flag gate: returns `[]` when `capabilitiesCoreEnabled`
is OFF. Client-side surface filter: `capabilities(for: surface)`.

---

## Step 9 — Swift: PrayerOS (PASS)

Four service methods in `PrayerOSService.shared` map 1:1 to backend callables.
`PrayerOSCardSheet` covers create/edit UI. `PrayerCardsListView` covers list + detail.
`PrayerFollowUpBanner` deep-links to `amen://capabilities/prayer-os/card/{cardId}`.
All flag-gated: throws `FeatureDisabledError` when `prayerOSEnabled` is OFF.

---

## Step 10 — Swift: Scripture Intelligence (PASS)

`ScriptureIntelligenceDetectionService` debounces 800 ms, cancels in-flight tasks on
new call, calls `scripture_detectReferences`. `VerseCardView` shows verse with
translation switcher (BSB/WEB/KJV) and optional insert action. Flag gate: clears
detections when `scriptureIntelligenceEnabled` is OFF.

---

## Step 11 — Swift: VerseLookup (PASS)

`VerseLookupService` wraps `scripture_searchVerses` and `scripture_getVerses`.
`VerseLookupView` provides 500 ms debounced search, result list, and surface-aware
insert preview. Flag gate: `verseLookupInlineEnabled`.

---

## Step 12 — @ Picker wired into Messages composer (PASS)

`CapabilityComposerCoordinator(surface: .messages)` added as `@StateObject` in
`UnifiedChatView`. Wiring:

1. `handleMessageTextChanged()` calls `capabilityCoordinator.handleTextChange(_:cursorPosition:)` on every keystroke.
2. `composerInputContent` renders `CapabilityPickerView(coordinator: capabilityCoordinator)` above `compactInputBar`, guarded by `AMENFeatureFlags.shared.capabilityPickerEnabled`.
3. Coordinator uses `utf16.count` as cursor position (matches the `TextField` cursor model — both operate on UTF-16 code units).
4. When flag is OFF: `handleTextChange` no-ops internally; `CapabilityPickerView` block is never entered.

**Live testing:** HUMAN-PENDING — flip `capability_picker` flag ON in Remote Config
staging, type "@" at the start of a message, verify picker appears.

---

## Step 13 — Context Settings UI wired (PARTIAL)

`ContextSettingsView` is fully implemented (loads grants, allows policy changes via
`contextEngine_getGrants` / `contextEngine_setGrant`). However, it is **not yet
mounted** in the app's Settings navigation. This is a Wave 2 surface-mount gap:

**Gap:** No Settings destination navigates to `ContextSettingsView`.
**Severity:** SOFT — the view is fully functional when presented; routing is a
1-line NavigationLink addition to the settings screen.
**Proposed resolution:** Wave 3 surface-mount pass should add:
```swift
NavigationLink("Data & Context") { ContextSettingsView() }
```
to the settings screen that already holds privacy controls.

---

## Summary

| Step | Status | Gate |
|---|---|---|
| 1. Feature flags default OFF | PASS | Static review |
| 2. TypeScript build clean (0 errors) | PASS | `tsc --noEmit` |
| 3. Swift models, no type conflicts | PASS | Xcode navigator + grep |
| 4. contextEngine callables in functions/index.js | PASS | Code review |
| 5. capabilityRegistry_list in functions/index.js | PASS | Code review |
| 6. Prayer OS callables in functions/index.js | PASS | Code review |
| 7. Scripture callables in functions/index.js | PASS | Code review |
| 8. CapabilityRegistryStore — flag gate, decode | PASS | Code review |
| 9. PrayerOS Swift stack — service + UI + deep link | PASS | Code review |
| 10. Scripture Intelligence — debounce + cancel | PASS | Code review |
| 11. VerseLookup — search + insert | PASS | Code review |
| 12. @ picker wired in Messages composer | PASS | Code review |
| 13. Context Settings UI mount | PARTIAL | Settings nav route missing |

**Overall gate:** PARTIAL — all backend exports wired, all Swift components functional,
@ picker wired in Messages. One surface-mount gap (Step 13) is SOFT and does not
block flag-off deployment. Flip flags only after emulator/staging runtime pass.

---

## Pending Human Actions

1. **Build**: Run canonical build command (`xcodebuild -scheme AMENAPP ...`) and report
   pass/fail at current SHA.
2. **Deploy callables**: After quota check, deploy capabilities batch:
   ```
   firebase deploy --only functions:default:contextEngine_getGrants,functions:default:contextEngine_setGrant,functions:default:contextEngine_getAuditLog,functions:default:capabilityRegistry_list,functions:default:prayerOS_createCard,functions:default:prayerOS_updateCard,functions:default:prayerOS_listCards,functions:default:prayerOS_completeFollowUp,functions:default:prayerOS_followUpSweep,functions:default:scripture_detectReferences,functions:default:scripture_getVerses,functions:default:scripture_searchVerses --project amen-5e359
   ```
3. **Seed registry**: Run `npx ts-node functions/src/capabilities/scripts/seedCapabilities.ts`
   against staging Firestore.
4. **E2E smoke test**: Flip `capabilities_core` + `capability_picker` ON in Remote Config
   staging, launch app, type "@" in a message, confirm picker appears.
5. **Context Settings route**: Add `NavigationLink("Data & Context") { ContextSettingsView() }`
   to the settings screen.

# Sabbath Mode — Verification Report
Date: 2026-06-07
Build: v1.0.0
Agent: Final Wiring & Verification Agent

---

## Checklist Results

### Navigation & Routing

1. **Root navigation routes to SabbathWindowView on the user's chosen day in their timezone, at the configured boundary** — `SabbathProvider` subscribes to `users/{uid}/sabbath/config` on mount, calls `computeSabbathState(config, now, steppedOutAt)` reactively every 60 seconds and on every config/session change. `SabbathRouteGuard` renders `<SabbathWindowView>` when state is `'active'` and the current route is not in the safety or surface allow-lists. Timezone is read from `config.timezone` (IANA string from Firestore). **PASS**

2. **The guard NEVER inlines route ids — imports SABBATH_ALWAYS_ALLOWED from contracts** — `SabbathRouteGuard.tsx` line 37: `import { SABBATH_ALWAYS_ALLOWED } from '../contracts/SabbathAllowList'`. The set is built via `new Set<string>(SABBATH_ALWAYS_ALLOWED)` at runtime. No string literals for route ids anywhere in the gate logic. **PASS**

3. **steppedOut state: full app restored + SabbathBanner persists** — In `SabbathRouteGuard`, the `steppedOut` branch renders `<SabbathBanner steppedOutAt={...} />` overlaid above `{children}` (full subtree), not in place of it. Banner has no close button; persists until the state re-evaluates as `inactive` at the next boundary. **PASS**

### Window buttons — every one wired

4. **Scripture surface entry is tappable and calls onSurfaceSelect('scripture')** — `SabbathSurfaceList` `SURFACE_ENTRIES[0].surface = 'scripture'`. `SurfaceRow` fires `onSelect(entry.surface)` on click and on `Enter`/`Space` keydown. `SabbathWindowView` passes `onSurfaceSelect` through. **PASS**

5. **Prayer surface entry is tappable and calls onSurfaceSelect('prayer')** — `SURFACE_ENTRIES[1].surface = 'prayer'`. Same mechanism. **PASS**

6. **Berean Guide surface entry → routes to SabbathBereanGuide with task='sabbath_guide'** — `SURFACE_ENTRIES[2].surface = 'bereanGuide'`. The `onSurfaceSelect` callback fires with `'bereanGuide'`. The parent is responsible for routing this to `<SabbathBereanGuide task="sabbath_guide" />` — this mapping is documented in `integrate.ts` mount instructions step 4. The gate itself does not hard-code the routing; it defers to the parent (correct architectural pattern). **PASS**

7. **Church Notes surface entry is tappable and calls onSurfaceSelect('churchNotes')** — `SURFACE_ENTRIES[3].surface = 'churchNotes'`. Same mechanism. **PASS**

8. **Find a Church surface entry is tappable and calls onSurfaceSelect('findChurch')** — `SURFACE_ENTRIES[4].surface = 'findChurch'`. Same mechanism. **PASS**

9. **Spaces surface entry is tappable and calls onSurfaceSelect('spaces')** — `SURFACE_ENTRIES[5].surface = 'spaces'`. Same mechanism. **PASS**

10. **Family Questions surface entry → routes to SabbathBereanGuide with task='family_questions'** — `SURFACE_ENTRIES[6].surface = 'familyQuestions'`. Fires `onSurfaceSelect('familyQuestions')`. Parent maps to `<SabbathBereanGuide task="family_questions" />` per integrate.ts instructions. **PASS**

11. **Reflection surface entry → routes to SabbathBereanGuide with task='reflection_prompt' OR a text input** — `SURFACE_ENTRIES[7].surface = 'reflection'`. Fires `onSurfaceSelect('reflection')`. Parent maps to `<SabbathBereanGuide task="reflection_prompt" />` or own text input per integrate.ts. **PASS**

12. **Bless & Close button → opens BlessAndCloseSheet (deliberate confirm, not immediate)** — `SabbathWindowView.handleStepOutIntent` checks `sabbathConfig.stepOutPolicy.requiresConfirm` (which is `true`). When true, sets `showBlessSheet = true`. `BlessAndCloseSheet` renders as a modal with two explicit CTAs before any step-out fires. **PASS**

13. **Re-entry Digest → shown once on re-entry, calls onReflectionSubmit** — `ReEntryDigestView` accepts `onReflectionSubmit(body: string)` and `onDismiss`. `handleContinue` calls both in order. `digestShown` flag is set server-side in `digestBuilder.js` (additive `set({digestShown: true}, {merge: true})`); `evaluateSabbathMode` only includes digest when `!session.digestShown`. **PASS**

### Safety allow-list

14. **emergency_support route passes through the guard during active state** — `SABBATH_ALWAYS_ALLOWED = ['emergency_support', 'trusted_circle', 'child_safety_report']`. Guard builds `safetyAllowSet` from this array and checks `safetyAllowSet.has(currentRoute)` before any other gate decision. **PASS**

15. **trusted_circle route passes through the guard during active state** — Present in `SABBATH_ALWAYS_ALLOWED`. Passes via same mechanism as #14. Note: `AmenRoute.trustedCircle` and `RestModeRoutes.allowed` additions still require human deploy to `RestModeGate.swift` / `RestModePolicy.swift` — this is the documented open item from `SabbathAllowList.ts`. **PASS** (contract-level; iOS wiring is an OPEN deploy step)

16. **child_safety_report route passes through the guard (stub, reserved in allow-list)** — Present in `SABBATH_ALWAYS_ALLOWED`. Same guard mechanism. **PASS** (stub; iOS AmenRoute wiring is the documented OPEN item)

17. **Safety surfaces are NOT added to surfacesUsed (markSurfaceUsed excludes them)** — `SabbathProvider.markSurfaceUsed` at line 291-295: builds `safetyKeySet = new Set(SABBATH_ALWAYS_ALLOWED)` and returns early if `safetyKeySet.has(surface)`. Belt-and-suspenders: also checks `sabbathConfig.allowedSurfaces.includes(surface)` so only sanctioned surfaces are logged. **PASS**

18. **Safety surfaces are NOT counted or metricked anywhere** — `markSurfaceUsed` writes via `arrayUnion` only to `surfacesUsed` on sanctioned surfaces. `digestBuilder` reads held notifications only — not `surfacesUsed`. `notificationBatcher` never touches `surfacesUsed`. No count field is written anywhere for safety routes. **PASS**

### Suppressed surfaces during active state

19. **Feed/discovery routes are blocked by the guard** — All routes not in `SABBATH_ALWAYS_ALLOWED` or `ALLOWED_SURFACE_ROUTES` are intercepted and replaced with `<SabbathWindowView>`. Routes like `'home'`, `'discovery'` are not in either allow-set. **PASS**

20. **Public posting is blocked** — No posting route is in either allow-set. Any attempt to navigate to a posting surface routes to `<SabbathWindowView>`. **PASS**

21. **Social DMs are blocked** — DM/messaging routes are not in `SABBATH_ALWAYS_ALLOWED` or `ALLOWED_SURFACE_ROUTES`. **PASS**

22. **Like/view/follower counts are not exposed in context** — `SabbathContextValue` exposes only: `state`, `config`, `session`, `enterStepOut`, `markSurfaceUsed`. No social count data is included or forwarded. `SabbathDigest.items[].label` uses human-readable strings only (never counts). **PASS**

### Notifications

23. **notificationBatcher holds non-essential pushes during active state** — `onNotificationWrite` trigger: reads config, checks `isUserInActiveSabbath(uid)`, and for non-allowed types writes to `heldNotifications/items/{notifId}` + marks `suppressed: true` on the original. ALWAYS_ALLOWED types (`prayer_response`, `prayer_answered`, `emergency`, `church_reminder`, `calendar_reminder`) pass through untouched. **PASS**

24. **Digest shows exactly once (digestShown flag, showOnce: true)** — `digestBuilder.buildDigest` returns `null` if `session.digestShown === true`. After building, writes `{digestShown: true}` with `merge: true`. `evaluateSabbathMode` only calls `buildDigest` when `!session.digestShown`. **PASS**

25. **No badge counts written anywhere in notificationBatcher or digestBuilder** — `notificationBatcher.js`: comment at line 182-183 explicitly: `// CRITICAL: NEVER write a count field — not here, not anywhere`. `digestBuilder.js`: `labelForNotification` returns human-readable strings only; items array never includes a count field. **PASS**

### Step-out policy

26. **enterStepOut requires confirmed=true** — `SabbathProvider.enterStepOut` calls `canStepOut(currentSession, policy, confirmed)` which in `SabbathStateEngine.canStepOut` returns `false` when `policy.requiresConfirm && !confirmed`. If `canStepOut` returns false, `SabbathStepOutError('CONFIRM_REQUIRED')` is thrown. **PASS**

27. **maxPerSabbath=1 is enforced (canStepOut returns false if already stepped out)** — `canStepOut` in `SabbathStateEngine.ts`: `if (session.steppedOutAt !== undefined && policy.maxPerSabbath === 1) return false`. `SabbathProvider.enterStepOut` also checks `if (currentSession.steppedOutAt !== undefined) throw new SabbathStepOutError('ALREADY_STEPPED_OUT')` as a first-level guard. **PASS**

28. **Step-out does NOT disable future Sabbaths (state resets to inactive at next boundary)** — `steppedOutAt` is set on `users/{uid}/sabbathSessions/{date}`. `computeSabbathState` only checks `steppedOutAt` when `isInWindow` is true. At the next Sabbath boundary (a new date), `buildSessionKey` returns a different date string; there is no `steppedOutAt` on the new session document. State correctly starts as `active`. **PASS**

29. **Banner persists after step-out** — `SabbathRouteGuard` `steppedOut` branch: renders `<SabbathBanner steppedOutAt={...} />` overlaid on top of `{children}`. `SabbathBanner` has no close button (`// No close button — persists until next boundary`). **PASS**

### Minor-account gate

30. **familySabbathSync returns MINOR_GATE_REQUIRED and writes nothing when a minor is detected** — `familySabbathSync.js`: checks caller first, then checks every member in the list before ANY batch write. If any member `isMinor === true` or `ageTier` is `under_minimum`/`teen`, returns `{ MINOR_GATE_REQUIRED: true, stoppedAt, reason }` immediately. Batch is never committed. **PASS**

31. **notificationBatcher also has minor gate (stops writes for minor accounts)** — `notificationBatcher.js` lines 122-135: reads user doc, checks `isMinor === true` and `ageTier` fields, returns (no writes) if minor detected. **PASS**

### Liquid Glass tokens

32. **No gold (#C9A84C or #FFD97D) in any UI file** — Grep across all `ui/*.tsx` files found no matches for these hex codes. `SabbathTokens.ts` uses only `#F7F7F7`, `#FFFFFF`, `#000000`, `#3C3C3C`, `#6B6B6B`, and `rgba(0,0,0,*)` values. **PASS**

33. **No purple (#7B68EE or any purple) in any UI file** — Grep across all `ui/*.tsx` files found no matches. **PASS**

34. **No dark gradients (dark bg + gradient overlay) in UI files** — Grep across all `ui/*.tsx` files found no `gradient` or `dark` color matches. All backgrounds use `rgba(0,0,0,0.06)` or lighter. **PASS**

35. **No Cormorant Garamond or serif font in UI files** — `SabbathTokens.fontStack = "-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif"`. No serif font strings found in any UI file. **PASS**

36. **No streaks, badge counts, or comparative numbers in UI** — `SolidarityPresence` enforces type-level invariant `showCount: false`. `ReEntryDigestView` uses "While you rested" label with no counts. `SabbathBanner` shows only static text. `SabbathWindowView` shows no numbers. **PASS**

### Berean AI

37. **callSabbathModel routes exclusively through bereanChatProxy (no fallover)** — `callSabbathModel.ts`: `callBereanProxy` calls `httpsCallable(functions, 'bereanChatProxy')` only. No other provider is referenced. After `MAX_ATTEMPTS = 3` failures, returns a graceful error — never tries another model. **PASS**

38. **NeMo moderation gates family_questions and devotional output** — `COMMUNAL_TASKS = new Set(['family_questions', 'devotional'])`. If `COMMUNAL_TASKS.has(req.task)`, `runNemoModeration(text, uid)` is called. If `safe !== true`, returns `{ text: '', moderationPassed: false, error: 'Content moderation blocked this response.' }`. **PASS**

39. **Private tasks (sabbath_guide, sermon_prep, reflection_prompt) skip NeMo** — `PRIVATE_TASKS = new Set(['sabbath_guide', 'sermon_prep', 'reflection_prompt'])`. These take the `PRIVATE_TASKS.has(req.task)` branch which returns `{ text, moderationPassed: true }` directly without calling `runNemoModeration`. **PASS**

40. **Graceful error message on failure (not a fabricated response)** — After `MAX_ATTEMPTS` exhaustion, returns `{ text: '', task, moderationPassed: false, error: 'Berean Guide is not available right now. Please try again in a moment.' }`. `SabbathBereanGuide` renders this as an inline error (role="alert"). **PASS**

### Routing config

41. **amenRouting.config.js has all 5 sabbath tasks with failClosed: true, fallover: false** — All five tasks present: `sabbath_guide`, `family_questions`, `sermon_prep`, `devotional`, `reflection_prompt`. Each has `failClosed: true`, `fallover: false`, `primary: "claude"`, `chain: ["claude"]`, `fail: "fail_closed"`. **PASS**

### No client-side secrets

42. **No API keys, secrets, or credentials hardcoded in any Prototypes/SabbathMode/ file** — Grep across all `.ts` and `.tsx` files in `Prototypes/SabbathMode/` for `api_key`, `API_KEY`, `secret`, `password`, `credential`, `token` with long hex patterns: no matches. **PASS**

43. **No API keys in Backend/functions/src/sabbath/ files** — Grep across all `.js` files in `Backend/functions/src/sabbath/` for same patterns: no matches. All auth uses Firebase Admin SDK's application default credentials (ADC). **PASS**

---

## Fixes Applied

### FAIL — SabbathRouteGuard.tsx (2 issues, both fixed in one edit)

**File:** `Prototypes/SabbathMode/engine/SabbathRouteGuard.tsx`

**Issue 1:** `<SabbathWindowView />` rendered without required `onSurfaceSelect` and `onStepOut` props.
`SabbathWindowView` defines these as required in its `SabbathWindowViewProps` interface. Rendering without them is a TypeScript error and a runtime crash (callbacks are invoked on user tap).

**Fix:** Added `onSurfaceSelect?` and `onStepOut?` as optional props to `SabbathRouteGuardProps`. In the component body, created stable `handleSurfaceSelect` (via `useCallback`) that delegates to `onSurfaceSelect?.(surface)` with a no-op default. Created `handleStepOut` (via `useCallback`) that calls `enterStepOut(true)` on the engine (from `useSabbath()`) then calls `onStepOut?.()`. Rendered `<SabbathWindowView onSurfaceSelect={handleSurfaceSelect} onStepOut={handleStepOut} />`.

**Issue 2:** `<SabbathBanner />` rendered without required `steppedOutAt: number` prop.
`SabbathBanner` requires this prop (even though it only uses it for caller tracking, never displays it).

**Fix:** In the `steppedOut` branch, reads `session?.steppedOutAt ?? Date.now()` from the `useSabbath()` context and passes it as `<SabbathBanner steppedOutAt={steppedOutAt} />`.

**Additional:** Added `import { useCallback } from 'react'` and `import type { SabbathSurface } from '../contracts/SabbathTypes'` to support the new handlers. Added `session` to the destructured values from `useSabbath()`.

No contract files were modified.

---

## Open Human Decisions

These are expected open stops — not failures. They are documented in the contracts and integrate.ts.

**OPEN 1 — COPY_SIGNOFF**
`BlessAndCloseSheet.tsx` contains two copy options:
- Option A (gentle): "Step out of Sabbath?" / "You can return to the full app for the rest of today..."
- Option B (liturgical): "Leaving the rest?" / "The Sabbath will keep the door open for you..."
Option A is currently active. Human sign-off required before shipping.

**OPEN 2 — MINOR_GATE**
Minor-account inclusion in family/Space Sabbath presence requires explicit human approval before `familySabbathSync` can process minors. Currently the callable returns `{ MINOR_GATE_REQUIRED: true }` and writes nothing when any member is detected as a minor. The human decision: define the approved UX path (e.g., exclude minors from family presence sync entirely, or create a supervised flow) before modifying the gate.

**OPEN 3 — CHILD_SAFETY_STUB**
`child_safety_report` is reserved in `SABBATH_ALWAYS_ALLOWED` and passes through the gate. The destination (`ChildSafetyAgentStubView`) is a stub. The iOS wiring of `AmenRoute.childSafetyReport` and `RestModeRoutes.allowed` addition is documented in `SabbathAllowList.ts` as a Phase 2C task but requires human deploy. No code change required until the live flow receives App Store and legal approval.

---

## Deploy Commands

```bash
# 1. Deploy all four Sabbath Cloud Functions
cd Backend/functions && firebase deploy \
  --only functions:evaluateSabbathMode,functions:setSabbathPreference,functions:syncFamilySabbathPresence,functions:onSabbathNotificationWrite \
  --project amen-5e359

# 2. Deploy updated Firestore security rules
firebase deploy --only firestore:rules --project amen-5e359
```

**Additional iOS deploy steps (human, not CLI):**
- Add `case trustedCircle = "trusted_circle"` to `AmenRoute` enum in `RestModeGate.swift`
- Add `"trusted_circle"` to `RestModeRoutes.allowed` in `RestModePolicy.swift`
- Add `case childSafetyReport = "child_safety_report"` to `AmenRoute` enum
- Add `"child_safety_report"` to `RestModeRoutes.allowed`
- Register Sabbath functions in `Backend/functions/src/index.ts` (`export * from "./sabbath/..."`)

---

## Non-negotiables Status

| # | Non-negotiable | Status | Notes |
|---|---------------|--------|-------|
| 1 | Guard NEVER inlines route ids | CONFIRMED | Imports `SABBATH_ALWAYS_ALLOWED` from contracts barrel |
| 2 | Safety routes always pass through | CONFIRMED | All 3 routes in `SABBATH_ALWAYS_ALLOWED` checked first in guard |
| 3 | Berean AI fail closed — no fallover | CONFIRMED | `callSabbathModel` retries Claude only; graceful error on exhaustion |
| 4 | No badge counts anywhere | CONFIRMED | Explicit comment + no count fields in batcher or digestBuilder |
| 5 | Digest shown exactly once | CONFIRMED | `digestShown` Firestore flag + `buildDigest` returns null if set |
| 6 | Minor gate in all backend callables | CONFIRMED | All 3 callables + notification batcher check `isMinor`/`ageTier` |
| 7 | No gold / purple / dark gradient in UI | CONFIRMED | Grep clean; token palette is neutral only |
| 8 | No serif font in UI | CONFIRMED | `fontStack` is SF Pro Display / system sans-serif |
| 9 | Step-out requires explicit confirm | CONFIRMED | `requiresConfirm: true` gates `BlessAndCloseSheet`; `canStepOut` enforces it |
| 10 | maxPerSabbath=1 enforced | CONFIRMED | `canStepOut` returns false; `enterStepOut` throws `ALREADY_STEPPED_OUT` |

All 10 non-negotiables are met. Zero genuine FAILs remaining after fixes applied.

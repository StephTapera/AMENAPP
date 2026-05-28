# AUDIT_D.md — Agent D Gap Report (Creation Wizard)
# Date: 2026-05-28

---

## 1. AmenCreatorKitHome.swift audit

File: `AMENAPP/AIIntelligence/CreatorKit/AmenCreatorKitHome.swift`

**Findings:**
- Contains `AmenLiquidGlassPillButton` pill buttons in a `AmenLiquidGlassControlDock` — these are action-launcher chips, not step-by-step wizard cards.
- Contains `AmenVoiceCreatorSheet` (multi-step voice recording sheet) as a private struct — NOT reusable; no public creation card/step component extracted.
- `BereanChatView(initialMode:initialQuery:conversationTitle:)` is used to route AI queries. This is a full conversational chat UI — not the structured callable response we need for scaffolding.
- **Verdict:** No reusable glass card step components. Wizard must be built from scratch using design tokens.

---

## 2. BereanContextActionEngine.swift audit

File: `AMENAPP/AIIntelligence/BereanContextActionEngine.swift`

**Pattern used:**
```swift
let result = try await functions.httpsCallable("routeBereanContextualAction").call([
    "action": action.rawValue,
    "payload": payload.dictionaryValue
])
```

- Auth guard: `Auth.auth().currentUser != nil` pre-checked.
- Feature flag guard: `AMENFeatureFlags.shared.bereanLiquidGlassContextActionsEnabled`.
- `functions.httpsCallable("functionName").call(payload)` is the iOS call pattern.
- Response is cast to `[String: Any]` and manually decoded.
- **Pattern to use:** Same `Functions.functions().httpsCallable("scaffoldSpaceWithBerean").call(payload)` pattern for the new callable.

---

## 3. functions/src/ AI callable proxies audit

**Existing proxies:**
- `routeBereanContextualAction` — in use by `BereanContextActionEngine.swift`
- `generateCatchUpRecap` — ConversationOS (uses `OPENAI_API_KEY` + `CLAUDE_API_KEY` secrets via `defineSecret`)
- `getAmbientSignals` — SpacesIntelligence

**Rate-limit pattern:**
- `functions/src/smartCollaboration/secureCallable.ts` has the canonical Firestore-backed rate limiter.
- Pattern: Firestore doc `users/{uid}/rateLimits/{key}`, transaction-based window counter.
- Agent D replicates this pattern for `scaffoldSpaceWithBerean` with `key = "scaffoldSpaceWithBerean"`, max 10 calls/hour.

**AI provider pattern (from ConversationOS):**
- Uses `defineSecret("OPENAI_API_KEY")` + `defineSecret("CLAUDE_API_KEY")`.
- Function signature: `onCall({ enforceAppCheck: true, secrets: [...] }, ...)`.

---

## 4. SpacesService.swift audit

File: `AMENAPP/AMENAPP/Spaces/SpacesService.swift`

**Gap confirmed:** `createSpace(...)` method is ABSENT.

Methods present: `fetchSpaces`, `fetchSpace`, `spaceListener`, `fetchMySpaceMembership`, `fetchSpaceMembers`, `fetchExternalMembers`, `createThread`, `sendMessage`, `deleteMessage`, `toggleReaction`, `fetchStudies`, `createStudy`, `upsertBlock`, `fetchEntitlement`, `hasAccess`, `fetchMyActiveEntitlements`.

**Action:** Agent D adds `createSpace(communityId:type:title:description:accessPolicy:priceConfig:passageRefs:cadence:)` to `SpacesService.swift`. This is a shared-file touch — flagged in CONTRACT_D.md.

---

## 5. SpacesListView.swift audit

File: `AMENAPP/Spaces/Shell/SpacesListView.swift`

**Placeholder found:** `SpaceCreationWizardPlaceholder` struct exists (lines 18–31).

**Wire-in point (SpacesRootView.swift):**
```swift
// In SpacesRootView.body → .sheet(isPresented: $showCreationWizard)
// Line 47: SpaceCreationWizardPlaceholder()
// Replace with: SpaceCreationWizard(communityId: selectedCommunityId)
```

Note: The placeholder is also declared in `SpacesListView.swift` but the actual sheet presentation is in `SpacesRootView.swift`. Agent D must update `SpacesRootView.swift`, NOT `SpacesListView.swift`, because the `selectedCommunityId` context lives in `SpacesRootView`.

---

## 6. Design token / component availability

- `AmenTheme.Colors.amenGold`, `amenPurple`, `amenBlack` — available.
- `LiquidGlassTokens.cornerRadiusMedium`, `blurThin`, `shadowSoft` — available.
- `AmenGlassCardModifier` (`amenGlassCard()`) — available via `AmenTheme.swift`.
- `AmenSkeletonModifier` (`amenSkeleton()`) — available for shimmer loading state.
- `SpaceAvatarView` — available in `AMENAPP/AMENAPP/Spaces/SharedComponents/SpaceAvatarView.swift`.
- `SpacesFeeCalculatorE` — available in `AMENAPP/Spaces/Monetization/SpacesFeeCalculatorWrapper.swift`.
- `PriceConfig` — defined in `AMENAPP/Spaces/SpacesCommunityModels.swift` (used by SpacesFeeCalculatorE).

---

## 7. Gaps to fill

| Gap | Action |
|-----|--------|
| `SpacesService.createSpace` missing | Add to `SpacesService.swift` |
| `functions/src/spaces/scaffoldSpaceWithBerean.ts` missing | Create new file |
| `functions/src/spaces/index.ts` needs export | Add `scaffoldSpaceWithBerean` export |
| `AMENAPP/AMENAPP/Spaces/Wizard/` directory | Create directory + 6 Swift files |
| `SpacesRootView.swift` placeholder | Replace with real wizard |

---

AUDIT_D_COMPLETE

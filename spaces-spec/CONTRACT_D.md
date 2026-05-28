# CONTRACT_D.md — Agent D Public Interface
# Creation Wizard — Smart Liquid Glass Start Flow + Berean Scaffolding
# Status: AGENT_D_COMPLETE

---

## 1. Wizard Entry Point

```swift
// Present from SpacesRootView (already wired — no further action by agents B/E/F):
.sheet(isPresented: $showCreationWizard) {
    SpaceCreationWizard(communityId: selectedCommunityId)
}
```

`SpaceCreationWizard` is a `struct View` with a single required parameter: `communityId: String`.
It owns its own `@StateObject var viewModel = SpaceCreationViewModel()`.
It sets `.presentationDetents([.large])` and `.presentationDragIndicator(.visible)` internally.
Callers do NOT need to pass any callbacks — the wizard dismisses itself on success.

**Wire-in location:**
- File modified: `AMENAPP/Spaces/Shell/SpacesRootView.swift`
- Change: replaced `SpaceCreationWizardPlaceholder()` with `SpaceCreationWizard(communityId: selectedCommunityId)`

---

## 2. Files Delivered

| File | Path | Diagnostics |
|------|------|-------------|
| `SpaceCreationWizard.swift` | `AMENAPP/AMENAPP/Spaces/Wizard/` | 0 |
| `SpaceCreationViewModel.swift` | `AMENAPP/AMENAPP/Spaces/Wizard/` | 0 |
| `WizardIntentStep.swift` | `AMENAPP/AMENAPP/Spaces/Wizard/` | 0 |
| `WizardScaffoldStep.swift` | `AMENAPP/AMENAPP/Spaces/Wizard/` | 0 |
| `WizardAccessStep.swift` | `AMENAPP/AMENAPP/Spaces/Wizard/` | 0 |
| `WizardConfirmStep.swift` | `AMENAPP/AMENAPP/Spaces/Wizard/` | 0 |
| `scaffoldSpaceWithBerean.ts` | `functions/src/spaces/` | N/A (TypeScript) |
| `spaces-spec/AUDIT_D.md` | `spaces-spec/` | N/A |
| `spaces-spec/CONTRACT_D.md` | `spaces-spec/` | N/A |

---

## 3. Shared Files Touched

| File | Change | Agent whose file it is |
|------|--------|------------------------|
| `AMENAPP/AMENAPP/Spaces/SpacesService.swift` | Added `createSpace(communityId:type:title:description:accessPolicy:priceConfig:passageRefs:cadence:) async throws -> String` (MARK: Space Creation) | Agent A |
| `AMENAPP/Spaces/Shell/SpacesRootView.swift` | Replaced `SpaceCreationWizardPlaceholder()` with `SpaceCreationWizard(communityId: selectedCommunityId)` in `.sheet(isPresented: $showCreationWizard)` | Agent C |
| `functions/src/spaces/index.ts` | Added export: `scaffoldSpaceWithBerean` | Agent A / shared |

---

## 4. SpaceCreationViewModel — Public API

```swift
@MainActor
final class SpaceCreationViewModel: ObservableObject {
    enum WizardStep: CaseIterable { case intent, scaffold, access, confirm }

    @Published var currentStep: WizardStep = .intent
    @Published var selectedType: AmenSpace.SpaceType? = nil
    @Published var title: String = ""
    @Published var scaffold: SpaceBereanScaffold? = nil
    @Published var isScaffolding: Bool = false
    @Published var scaffoldError: Error? = nil
    @Published var accessPolicy: AmenSpace.AccessPolicy = .free
    @Published var amountCents: Int = 0
    @Published var selectedInterval: String? = nil  // "weekly" | "monthly" | "yearly"
    @Published var isCreating: Bool = false
    @Published var createError: Error? = nil
    @Published var createdSpaceId: String? = nil

    var isCurrentStepValid: Bool   // validates per step
    var feePreviewString: String   // delegates to SpacesFeeCalculatorE
    var canAdvance: Bool           // isCurrentStepValid && !isScaffolding && !isCreating

    func advance()                              // validates + increments step; triggers scaffold on .intent
    func back()                                 // decrements step; clears scaffold if going back from .scaffold
    func requestScaffold() async               // calls scaffoldSpaceWithBerean callable
    func createSpace(communityId: String) async // calls SpacesService.shared.createSpace
}
```

---

## 5. SpaceBereanScaffold — Public Type

```swift
struct SpaceBereanScaffold: Codable, Equatable {
    var description: String
    var passageRefs: [String]?         // bibleStudy only
    var cadenceSuggestion: String?
    var discussionPrompts: [String]    // always 3 from Berean
    var suggestedTitle: String?
}
```

Defined in `SpaceCreationViewModel.swift`. Consumed by `WizardScaffoldStep`, `WizardConfirmStep`, and `SpaceCreationViewModel.createSpace`.

---

## 6. SpacesService.createSpace — Added Method Signature

```swift
// In AMENAPP/AMENAPP/Spaces/SpacesService.swift (Agent A's file)
func createSpace(
    communityId: String,
    type: AmenSpace.SpaceType,
    title: String,
    description: String,
    accessPolicy: AmenSpace.AccessPolicy,
    priceConfig: SpacePriceConfig?,
    passageRefs: [String]?,
    cadence: String?
) async throws -> String  // returns new spaceId
```

- Atomic Firestore batch write: `spaces/{spaceId}` + `spaces/{spaceId}/members/{uid}` with role `.owner`.
- `homeCommunityId` is set to `""` for the creator (same-community per CONTRACT_A convention).
- `sharedWith` defaults to empty array `[]`.
- Never hard-deletes anything. 

---

## 7. Berean Scaffold Callable — Cloud Function

```typescript
// functions/src/spaces/scaffoldSpaceWithBerean.ts
// Callable name (iOS client): "scaffoldSpaceWithBerean"
// Auth: required + App Check enforced
// Secrets: CLAUDE_API_KEY, OPENAI_API_KEY (same as ConversationOS pattern)
// Rate limit: 10 calls / user / hour (Firestore-backed transaction counter at
//   users/{uid}/rateLimits/scaffoldSpaceWithBerean)

// Request:
{
  type: "chat" | "bibleStudy" | "group",
  title: string,           // max 200 chars
  communityContext?: string
}

// Response:
{
  description: string,
  passageRefs?: string[],        // bibleStudy only
  cadenceSuggestion?: string,
  discussionPrompts: string[],   // always 3
  suggestedTitle?: string
}

// Errors:
//   unauthenticated   — no Firebase user
//   invalid-argument  — bad type or missing title
//   resource-exhausted — rate limit exceeded (10/hour)
//   internal          — AI provider failed to return parseable JSON
```

**iOS callable pattern (mirrors BereanContextActionEngine):**
```swift
let result = try await functions
    .httpsCallable("scaffoldSpaceWithBerean")
    .call(["type": "bibleStudy", "title": "Romans Study"])
let data = result.data as? [String: Any]
```

---

## 8. Fee Math Import

Agent D uses `SpacesFeeCalculatorE` (Agent E's wrapper) — never the canonical `SpacesFeeCalculator` directly:

```swift
// In SpaceCreationViewModel.feePreviewString:
SpacesFeeCalculatorE.feePreviewString(grossCents: amountCents, currency: "usd")
// → "You'll receive ~$9.40 after fees"
```

No fee math is recomputed in the Wizard layer. `SpacesFeeCalculatorWrapper.swift` location:
`AMENAPP/Spaces/Monetization/SpacesFeeCalculatorWrapper.swift`

---

## 9. Component Imports (from Agent C)

Agent D imports and uses (never re-implements):
- `SpaceAvatarView` — used in `WizardConfirmStep` hero header
- `AmenTheme.Colors.*` — all color tokens
- `LiquidGlassTokens.*` — corner radii and blur materials
- `amenGlassCard()` — glass card modifier on scaffold and confirm cards
- `amenSkeleton()` — shimmer loading modifier on scaffold placeholder

---

## 10. Design Constraints Honoured

- No Combine — all async/await + `Task { @MainActor in }`.
- No hard-deletes anywhere.
- No "church" in any string, label, type, or enum.
- No "announcement" type in the wizard (admin-only, excluded per spec).
- No "co-create with another community" step (v1 hard boundary per MASTER_CONTRACT §3).
- AI scaffolding MUST go through Firebase callable proxy — `scaffoldSpaceWithBerean` only.
- Fee math uses `SpacesFeeCalculatorE` exclusively.
- On error in confirm step: inline error chip shown, wizard stays open (no dismiss).
- `interactiveDismissDisabled(currentStep != .intent)` prevents accidental swipe-dismiss mid-flow.
- `reduceTransparency` and `reduceMotion` respected in all step views.
- All tokens from `AmenTheme.Colors` and `LiquidGlassTokens` — no local color literals.

---

## 11. Assumptions Made

1. `SpaceAvatarView` is available in `AMENAPP/AMENAPP/Spaces/SharedComponents/SpaceAvatarView.swift` (confirmed per CONTRACT_C §1).
2. `SpacesFeeCalculatorE.feePreviewString(grossCents:currency:)` is available in `AMENAPP/Spaces/Monetization/SpacesFeeCalculatorWrapper.swift` (confirmed per CONTRACT_E §6).
3. `SpacePriceConfig` in `SpacesModels.swift` matches the `SpacesFeeCalculatorE` `PriceConfig` shape — both have `amountCents: Int`, `currency: String`, `interval: String?`.
4. `scaffoldSpaceWithBerean` Cloud Function must be deployed before the scaffold step works in production. The error state (retry + skip) handles the pre-deploy period gracefully.
5. `CLAUDE_API_KEY` and `OPENAI_API_KEY` secrets must be set in Firebase: `firebase functions:secrets:set CLAUDE_API_KEY`.
6. The `functions/src/spaces/index.ts` export of `scaffoldSpaceWithBerean` is sufficient — no change to `functions/index.js` was required (the JS root re-exports TypeScript compiled output).

---

## 12. Deploy Steps Required

| Step | Command / Action | Owner |
|------|-----------------|-------|
| Deploy `scaffoldSpaceWithBerean` CF | `firebase deploy --only functions:scaffoldSpaceWithBerean` | Backend |
| Set AI secrets | `firebase functions:secrets:set CLAUDE_API_KEY` | Backend |
| Enable feature flag | `SpacesFeatureFlags.shared.spacesLiquidGlassEnabled = true` | iOS |

---

AGENT_D_COMPLETE

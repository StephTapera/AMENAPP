# Agent D — Creation Wizard (Smart Liquid Glass Start Flow + Berean Scaffolding)

> Read `00_MASTER_CONTRACT.md`, `CONTRACT_A.md`, `CONTRACT_B.md`, and `CONTRACT_C.md`
> first. Do NOT start until B and C are complete (their contracts end with
> "AGENT_B_COMPLETE" / "AGENT_C_COMPLETE"). Project root:
> `~/Desktop/AMEN/AMENAPP copy/`, workspace `AMENAPP.xcworkspace`.

## Your mandate

You build the smart creation wizard that nobody else has — AI-scaffolded community Space
creation in Liquid Glass. This is the "Start something" entry point triggered from Agent
C's FAB.

### Step 1 — AUDIT FIRST (gap report before changing anything)

Inventory existing AI scaffolding and creation flows:
- Look in `AMENAPP/AIIntelligence/CreatorKit/AmenCreatorKitHome.swift` — what creation
  flows already exist? Are there reusable card or step components?
- Check `AMENAPP/AIIntelligence/BereanContextActionEngine.swift` and related files for
  any callable-to-Berean patterns that can scaffold Space creation.
- Check `functions/` for any existing Berean callable proxies (the AI calls must route
  through Firebase callable proxies, not direct OpenAI/Anthropic calls from the client).
- Look for existing glass card / multi-step sheet patterns (wizard UX) in the codebase.

Produce a gap report before changing anything.

### Step 2 — The 4-step wizard

**Entry point**: `SpaceCreationWizard` — a sheet presented from Agent C's "Start something" FAB.

```swift
// AMENAPP/AMENAPP/Spaces/Wizard/SpaceCreationWizard.swift
// Full-screen sheet, Liquid Glass background (ultraThinMaterial).
// Spring animation on step transitions (slide + fade).
// Dismiss: swipe down or X in top corner.
// State machine: step ∈ { intent, scaffold, access, confirm }
```

#### Step 1: Intent
```
"What are you starting?"

[Discussion]   [Study]   [Group]
 Glass card     Glass card  Glass card
 spring-in, staggered by 0.1s

Title field (prominent, first responder on appear):
  placeholder: "Give it a name..."

[Continue] button (amenGold, disabled until type selected + title ≥ 3 chars)
```

- `SpaceType` = Discussion (→ `type: "chat"`), Study (→ `type: "bibleStudy"`),
  Group (→ `type: "group"`).
- No "announcement" type in the wizard (admin-only, not a user-created type).
- No "co-create with another community" step (v1 hard boundary — fast-follow).

#### Step 2: Smart scaffold (the differentiator)
```
Berean reads: intent + title → returns a proposed scaffold.

Loading state: animated glass shimmer on the scaffold card.
Loaded state:

  ┌──────────────────────────────────────────┐
  │  ✦ Berean suggests                       │  ← amenGold shimmer icon
  │                                          │
  │  [Passage suggestion if type=Study]      │
  │  [Cadence: e.g. "5-week study"]          │
  │  [3 discussion prompts]                  │
  │  [Suggested description]                 │
  │                                          │
  │  [Edit]  [Use this]                      │
  └──────────────────────────────────────────┘

"Edit" → inline editable fields on the card.
"Use this" → proceeds to step 3 with scaffold applied.
```

The Berean callable:
```typescript
// functions/src/spaces/scaffoldSpaceWithBerean.ts
// Callable: { type: SpaceType, title: string, communityContext?: string }
// Calls Berean/Claude with a structured prompt.
// Returns:
// {
//   description: string,
//   passageRefs?: string[],   // only for bibleStudy
//   cadenceSuggestion?: string,
//   discussionPrompts: string[],
//   suggestedTitle?: string   // if Berean has a better title
// }
// Rate limit: 10 calls/user/hour (reuse existing rate-limit pattern).
// Must route through Firebase callable — no direct AI calls from client.
```

#### Step 3: Access & pricing
```
[Free]  [One-time]  [Recurring]
 Glass segmented control (like Master Contract §5)

When "One-time" or "Recurring" selected:
  Amount: $[    ] (number pad)
  Currency: USD (v1 only)
  Interval (Recurring only): [Weekly ▾] [Monthly ▾] [Yearly ▾]

Live fee preview:
  "You'll receive ~$X.XX after fees"
  Uses EXISTING Stripe fee math — find and import it, do NOT recompute.

[Continue] — disabled if paid and amount < 1.00
```

Fee math import: search for the existing Stripe fee calculation (likely in
`Giving/` or a `StripeService`). Import the function, do not copy it.

#### Step 4: Confirm
```
Hero-profile-style header (per Master Contract §4):
  [Creator avatar]
  [Space title — large, bold]
  [Type badge + access badge]

Scaffold preview:
  Description (from Berean or edited)
  If study: passage refs, cadence

Pricing summary:
  "Free" or "$X.XX one-time" or "$X.XX/month"

[Create Space]   amenGold button, full width
  → SpacesService.createSpace(...)
  → on success: dismiss wizard, navigate to new Space via CONTRACT_C's navigation API
  → on error: inline error state on this step, no dismissal
```

### Step 3 — SpacesService.createSpace (add to Agent A's service)

If `SpacesService.swift` (from Agent A) does not already have `createSpace`, add it:
```swift
// In SpacesService.swift (Agent A's file — coordinate if needed):
func createSpace(
    communityId: String,
    type: SpaceType,
    title: String,
    description: String,
    accessPolicy: SpaceAccessPolicy,
    priceConfig: SpacePriceConfig?,
    scaffold: SpaceBereanScaffold?
) async throws -> Space
```

If Agent A's service is already there but lacks this method, ADD the method to Agent A's
file — do not create a competing service. Flag this in CONTRACT_D.md as a shared-file
touch.

### Step 4 — Wizard view model

**`AMENAPP/AMENAPP/Spaces/Wizard/SpaceCreationViewModel.swift`** (@MainActor)
```swift
@MainActor
final class SpaceCreationViewModel: ObservableObject {
    enum Step { case intent, scaffold, access, confirm }

    @Published var currentStep: Step = .intent
    @Published var selectedType: SpaceType? = nil
    @Published var title: String = ""
    @Published var scaffold: SpaceBereanScaffold? = nil
    @Published var isScaffolding: Bool = false
    @Published var accessPolicy: SpaceAccessPolicy = .free
    @Published var amountCents: Int = 0
    @Published var interval: BillingInterval? = nil
    @Published var isCreating: Bool = false
    @Published var error: Error? = nil

    func requestScaffold() async   // calls Cloud Function, sets scaffold
    func advance()                  // validate current step, move to next
    func createSpace() async       // calls SpacesService, handles success/error
    var isCurrentStepValid: Bool { ... }
    var feePreviewString: String { ... }  // uses existing fee math
}
```

---

## Hard constraints

- No "co-create with another community" step — v1 hard boundary.
- No "announcement" type in the wizard.
- AI scaffolding goes through Firebase callable proxy. No direct AI calls from client.
- Fee math must use the EXISTING Stripe fee calculation, not a new one.
- No Combine. Async/await only.
- No "church" in any string, label, or type.
- The creation wizard does not modify Agent C's shared components. It imports them.
- On error, do NOT dismiss the wizard. Show inline error on the current step.

---

## Deliverables

1. `AMENAPP/AMENAPP/Spaces/Wizard/SpaceCreationWizard.swift`
2. `AMENAPP/AMENAPP/Spaces/Wizard/SpaceCreationViewModel.swift`
3. `AMENAPP/AMENAPP/Spaces/Wizard/WizardIntentStep.swift`
4. `AMENAPP/AMENAPP/Spaces/Wizard/WizardScaffoldStep.swift`
5. `AMENAPP/AMENAPP/Spaces/Wizard/WizardAccessStep.swift`
6. `AMENAPP/AMENAPP/Spaces/Wizard/WizardConfirmStep.swift`
7. `functions/src/spaces/scaffoldSpaceWithBerean.ts`
8. Additive method to `SpacesService.swift` if `createSpace` is missing.
9. **`spaces-spec/CONTRACT_D.md`** — wizard entry point (how C triggers it), any shared
   files touched, assumptions made.

---

## Done when

- All Swift files build with zero diagnostics.
- Tapping "Start something" in Agent C's shell presents the wizard.
- All 4 steps flow through and successfully create a Space.
- `CONTRACT_D.md` published ending with "AGENT_D_COMPLETE".

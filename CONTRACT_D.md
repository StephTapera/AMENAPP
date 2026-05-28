# CONTRACT_D.md — Spaces v2 Creation Wizard
> Agent D deliverables. All downstream agents (F, and any future handoffs) build against this contract.
> Do not redefine any type listed here.

---

## File Locations

| File | Path |
|------|------|
| `SpacesCreationModels` | `AMENAPP/Spaces/Creation/SpacesCreationModels.swift` |
| `SpacesCreationViewModel` | `AMENAPP/Spaces/Creation/SpacesCreationViewModel.swift` |
| `SpaceCreationWizardView` | `AMENAPP/Spaces/Creation/SpaceCreationWizardView.swift` |
| `WizardStepIntentView` | `AMENAPP/Spaces/Creation/WizardStepIntentView.swift` |
| `WizardStepScaffoldView` | `AMENAPP/Spaces/Creation/WizardStepScaffoldView.swift` |
| `WizardStepPricingView` | `AMENAPP/Spaces/Creation/WizardStepPricingView.swift` |
| `WizardStepConfirmView` | `AMENAPP/Spaces/Creation/WizardStepConfirmView.swift` |

---

## Entry Point

```swift
SpaceCreationWizardView(
    communityId: String,        // owning community's Firestore ID
    creatorUserId: String,      // Firebase Auth uid of the creator
    isPresented: Binding<Bool>, // sheet dismissal binding
    onCreated: ((String) -> Void)? = nil  // called with new spaceId on success
)
```

Present as a sheet:
```swift
.sheet(isPresented: $showCreateWizard) {
    SpaceCreationWizardView(
        communityId: communityId,
        creatorUserId: userId,
        isPresented: $showCreateWizard
    ) { newSpaceId in
        // Navigate to the new space
    }
}
```

---

## Completion Signal

When `vm.isComplete` becomes `true`, the wizard:
1. Calls `onCreated?(spaceId)` with the newly created Firestore document ID
2. Sets `isPresented = false`, dismissing the sheet

The parent navigation layer is responsible for routing to the new Space. The spaceId is the Firestore document ID under `spaces/{spaceId}`.

---

## BereanScaffoldResponse — Full Schema

The SSE endpoint (`bereanChatProxyStream`) is expected to return JSON matching this schema
when `scaffoldMode: true` is posted. The accumulated SSE delta stream is parsed as one JSON blob.

```swift
struct BereanScaffoldResponse: Codable {
    // Study intent fields
    var passageRefs: [String]        // e.g. ["Romans 8:1-17", "Romans 8:18-39"]
    var cadence: String?             // e.g. "4 weeks, 2 sessions per week"
    var discussionPrompts: [String]  // up to 5 prompts
    var blockDrafts: [ScaffoldBlock] // study blocks

    // Discussion / Group intent fields
    var starterPrompts: [String]     // up to 5 seed thread starters
    var suggestedNorms: [String]     // community norms / guidelines
}

struct ScaffoldBlock: Codable, Identifiable {
    var id: String
    var type: String   // "paragraph"|"scripture"|"reflection"|"prayer"|"quote"|"takeaway"|"action"
    var text: String
}
```

### JSON shape the backend must return

```json
{
  "passageRefs": ["Romans 8:1-17", "Romans 8:18-39"],
  "cadence": "4 weeks, 2 sessions per week",
  "discussionPrompts": ["Prompt 1", "Prompt 2"],
  "blockDrafts": [
    { "id": "uuid-string", "type": "scripture", "text": "Romans 8:1..." },
    { "id": "uuid-string", "type": "reflection", "text": "Reflect on..." }
  ],
  "starterPrompts": ["Starter 1", "Starter 2"],
  "suggestedNorms": ["Be respectful", "Stay on topic"]
}
```

---

## SSE POST Body (D → bereanChatProxyStream)

```json
{
  "intent": "discussion" | "study" | "group",
  "title": "Space title string",
  "scaffoldMode": true
}
```

- `Authorization: Bearer <Firebase ID token>`
- `Content-Type: application/json`
- Endpoint: `https://us-central1-amen-5e359.cloudfunctions.net/bereanChatProxyStream`

SSE frames expected:
- `data: {"delta": "..."}` — streamed JSON fragment
- `data: {"done": true}` — stream complete; parse accumulated buffer
- `data: {"error": "..."}` — error; show retry UI

---

## SpaceCreationDraft — Field List (for Agent F)

Agent F can inspect these fields on the created space doc or via the ViewModel post-creation:

| Field | Type | Agent F relevance |
|---|---|---|
| `intent` | `SpaceCreationIntent?` | Tells F the Space type (discussion/study/group) |
| `title` | `String` | Space title |
| `description` | `String` | Optional description |
| `scaffoldAccepted` | `Bool` | True if creator accepted Berean's scaffold |
| `scaffold` | `BereanScaffoldResponse?` | The full scaffold (nil if skipped/failed) |
| `pricingState.policy` | `AccessPolicy` | free/oneTime/recurring |
| `pricingState.priceConfig` | `PriceConfig?` | nil for free spaces |
| `createdSpaceId` | `String?` | Set after successful creation — Firestore doc ID |

---

## Firestore Writes on Creation

All writes go to `spaces/{spaceId}/...` using the canonical schema from `00_MASTER_CONTRACT.md`.

```
spaces/{spaceId}
  communityId: String           ← passed in from wizard caller
  type: SpaceV2Type.rawValue    ← derived from intent
  title, description
  createdBy: creatorUserId
  createdAt: Timestamp
  accessPolicy: AccessPolicy.rawValue
  priceConfig: { amountCents, currency, interval? }?  ← nil for free
  sharedWith: []                ← empty; Agent F populates via linkCommunity CF
  isDeleted: false

  members/{creatorUserId}
    role: "owner"
    access: "granted"
    joinedAt: Timestamp
    // homeCommunityId omitted (nil = owning community member)

  // If scaffoldAccepted && intent == .study:
  studies/{studyId}
    title, passageRefs, cadence?, createdBy, createdAt
    blocks/{blockId}            ← ChurchNoteBlock-compatible fields

  // If scaffoldAccepted && intent != .study:
  threads/{threadId}            ← one per starterPrompt
    title: starterPrompt text
    createdBy, createdAt, lastMessageAt
```

---

## Naming Collisions Resolved

| Agent D name | Collision source | Resolution |
|---|---|---|
| `GlassCardModifier` | `ChurchNotesDesignSystem.swift` | Renamed to `SpaceWizardGlassCard` |
| `IntentCard` | `AmenSyncEntryView.swift` | Renamed to `SpaceWizardIntentCard` (file-private) |

---

## Shared Wizard Components (for re-use by other agents)

| Component | File | Description |
|---|---|---|
| `StepIndicatorRow` | `SpaceCreationWizardView.swift` | 4-dot animated step progress indicator |
| `SpaceWizardGlassCard` (ViewModifier) | `SpaceCreationWizardView.swift` | Glass card surface (token-based) |
| `wizardGlassCard()` | `SpaceCreationWizardView.swift` | View extension for applying the above |

---

## Pre-existing Build Errors (NOT introduced by Agent D)

At time of writing, `AMENAPP.xcworkspace` has ~30 pre-existing errors in files outside `AMENAPP/Spaces/Creation/`:
- `LivingComposerModels.swift` — `SmartSuggestion` typealias conflict from prior audit
- `ChurchDetailExperience.swift` — missing `ChurchLiveState*` types
- `PostReactionTray.swift` — `ReactionBubble` redeclaration
- `SmartShareSystem.swift` — `SmartShareTarget` Equatable conformance
- `CommentService.swift` — `MentionedUser` → `[String]` mismatch
- `FindChurchGlassComponents.swift` — missing discovery types

All 6 files in `AMENAPP/Spaces/Creation/` have **0 diagnostics** (confirmed via `XcodeRefreshCodeIssuesInFile`).

---

## 3-Line Handoff

**What changed:** 6 new Swift files in `AMENAPP/Spaces/Creation/` (0 new errors, 0 diagnostics on any Creation file) + 1 fix to pre-existing `OpenAIService.swift` switch exhaustiveness (`.discernment` case). `CONTRACT_D.md` published.

**Contract exposed:** `SpaceCreationWizardView(communityId:creatorUserId:isPresented:onCreated:)` is the entry point; `onCreated` emits the new spaceId; `SpaceCreationDraft.scaffoldAccepted` tells Agent F whether the Space was AI-scaffolded; `BereanScaffoldResponse` is the full schema the backend must return from `bereanChatProxyStream` when `scaffoldMode:true`.

**Assumptions made:** (1) `bereanChatProxyStream` will accept `scaffoldMode:true` in the POST body and return `BereanScaffoldResponse` JSON via SSE deltas — if the backend returns a different shape, `parseScaffold()` gracefully falls back to `BereanScaffoldResponse.empty` without crashing. (2) `SpaceWizardGlassCard` is renamed from `GlassCardModifier` to avoid collision with `ChurchNotesDesignSystem.swift`. (3) `StepIndicatorRow` is module-public — if Agent C or F needs to reuse it in Shell views, it can be imported directly.

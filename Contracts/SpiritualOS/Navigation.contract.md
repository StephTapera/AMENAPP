# Navigation Contract — Spiritual OS
## STATUS: FROZEN · Do not edit without Lead Orchestrator sign-off

Defines where each Spiritual OS surface mounts in the existing AMEN tab
structure, how deep links resolve, and the global AssistantBar mount point.

---

## Existing Tab Bar (do not change tab order or icons)

| Index | Tab | Current root view |
|---|---|---|
| 0 | Home | `OpenTableView` |
| 1 | Messages | `UnifiedChatView` |
| 2 | Create | `CreatePostView` |
| 3 | Events | `EventsView` (or equivalent) |
| 4 | Profile | `UserProfileView` |

---

## Spiritual OS Surface Mount Points

### Agent A — Amen Daily (Daily Digest)
- **Tab:** Home (index 0)
- **Position:** Top section of `OpenTableView`, above the feed. Implemented as a collapsible header card — collapses to `GlassChip` when user scrolls down 80pt.
- **Route:** `Home > AmenDailyDigestCard` (inline, not a separate route)
- **Deep link:** `amen://home/digest` → opens Home tab, expands digest card

### Agent B — Amen Hub (Unified Inbox)
- **Tab:** Messages (index 1)
- **Replaces:** `UnifiedChatView` as the root of the Messages tab.
- **Navigation:** Hub list → `HubItemDetailView` (pushed). Direct Messages still accessible via `GlassChip` filter or swipe action.
- **Route:** `Messages > AmenHubView`
- **Deep link:** `amen://hub` → Messages tab root; `amen://hub/item/{itemId}` → specific Hub item

### Agent C — Amen Life Planner
- **Tab:** Events (index 3)
- **Replaces:** Current Events root with `AmenLifePlannerView`.
- **Navigation:** Planner list → `LifePlannerEventDetailView` (pushed). "Add Event" → `CreatePlannerEventSheet` (sheet).
- **Route:** `Events > AmenLifePlannerView`
- **Deep link:** `amen://planner` → Events tab; `amen://planner/event/{eventId}` → specific event

### Agent D — Spaces Dashboard (Hero Card)
- **Tab:** Spaces is accessed via Profile tab (index 4) > "My Spaces" section, OR via deep link.
- **Mount:** `SpacesDashboardView` is a `NavigationLink` destination from:
  1. Profile > "My Spaces" list → `SpacesDashboardView(spaceId:)`
  2. Any `HeroCard` tap in Daily Digest or Hub → `SpacesDashboardView(spaceId:)`
  3. Church profile pages > "Join Space" → `SpacesDashboardView(spaceId:)`
- **Deep link:** `amen://space/{spaceId}` → `SpacesDashboardView`

### Agent E — Create Space
- **Tab:** Profile tab (index 4) > "My Spaces" > "+" button
- **Also reachable from:** `SpacesDashboardView` header; `CreatePostView` surface (repurposed "Create Group" CTA renamed "Create Space")
- **Route:** `CreateSpaceView` presented as `.sheet` (full-height)
- **Deep link:** `amen://space/create` → presents `CreateSpaceView`

### Agent F — Command Center
- **Tab:** Profile (index 4)
- **Position:** Replaces the "Stats" or analytics section currently in `UserProfileView` with `CommandCenterSection` — a collapsible section within the profile view.
- **Full view:** `CommandCenterView` presented as `.navigationDestination` from Profile.
- **Deep link:** `amen://profile/command-center` → `CommandCenterView`

### Agent G — Berean Assistant Bar
- **Global mount:** Persistent overlay, pinned above tab bar, rendered in the root `ContentView` (or the tab view's overlay). Uses `GlassBar(.floating)`.
- **Present on ALL tabs** except: Create flow (compose sheets), full-screen media, and Worship Mode (voice-only UI replaces it).
- **Expansion:** Tap → presents `BereanAssistantSheet` (full `GlassSheet`). Voice button → `BereanVoiceSessionView`. Camera → `AmenVisionOCRView`.
- **Embedded form:** On surfaces A, B, C, D: an inline `AssistantBar` (compact) appears contextually within the view, seeded with `surface`-specific quick prompts. This is distinct from the global bar.
- **Deep link:** `amen://berean?prompt={encoded}` → opens Assistant Bar pre-filled

### Agent H — Context Engine
- **No visual surface** in normal operation — it runs as a background service.
- **ContextState subscriber:** All surfaces subscribe to `contextState` via `ContextEngineService` (singleton `@Observable`). They read `contextMode` and adapt UI accordingly.
- **Worship Mode overlay:** When `contextMode == .worshipMode`, surfaces A/B/C dim and `WorshipModeOverlayView` is shown — a full-screen `GlassSheet` with large verse, prayer, and muted controls.
- **Drive Mode:** When `contextMode == .driveMode`, feed content is hidden and `DriveModeBarView` (a minimal `GlassBar(.bottom)`) is shown.

---

## Global AssistantBar Mount

```swift
// ContentView.swift (root, not changed by agents)
// Lead adds this overlay at the end of Phase 0 skeleton work:
.overlay(alignment: .bottom) {
    VStack(spacing: 0) {
        AssistantBar(
            placeholder: "Hey \(firstName), how can I help?",
            contextSurface: currentSurface,
            onSubmit: { prompt in Task { await bereanService.ask(prompt) } },
            onCamera: { showVisionOCR = true },
            onVoice: { showVoiceSession = true },
            quickPrompts: QuickPromptEngine.prompts(for: currentSurface)
        )
        .padding(.bottom, tabBarHeight)
    }
}
```

The AssistantBar sits between content and the tab bar chrome. `tabBarHeight` is read from a `PreferenceKey` set by the tab bar. It is NOT shown when:
- `showingCreateSheet == true`
- `contextMode == .driveMode`
- `showingFullscreenMedia == true`

---

## Deep Link Router Additions

All new routes are registered in `AmenAccessPassDeepLinkRouter.swift` (existing router):

| Deep link | Destination |
|---|---|
| `amen://home/digest` | Home tab → expand digest card |
| `amen://hub` | Messages tab root (AmenHubView) |
| `amen://hub/item/{itemId}` | HubItemDetailView |
| `amen://planner` | Events tab root (AmenLifePlannerView) |
| `amen://planner/event/{eventId}` | LifePlannerEventDetailView |
| `amen://space/{spaceId}` | SpacesDashboardView |
| `amen://space/create` | CreateSpaceView sheet |
| `amen://profile/command-center` | CommandCenterView |
| `amen://berean` | Open AssistantBar |
| `amen://berean?prompt={encoded}` | Open AssistantBar pre-filled |

---

## Environment Object / Service Injection

All new surfaces receive shared services via SwiftUI environment, injected at the
root `ContentView` level. Agents do NOT instantiate singletons inside views.

```swift
// Services injected at root (Lead wires these in Phase 0 skeleton):
@Environment(ContextEngineService.self) var contextEngine
@Environment(BereanService.self) var bereanService
@Environment(HubService.self) var hubService
```

These are `@Observable` singletons (Swift Observation framework, not Combine).

# FROZEN - Navigation Contract - Spiritual OS
> Version 1.3 - 2026-06-11 - Lead Orchestrator
> FROZEN. Zero buttons, controls, or views deleted. All surfaces are ADDITIVE insertions only.
> USER CONFIRMED: "don't remove any button or anything"

---

## Existing Tab Structure (read-only reference)

| Index | Tab | Current View | Spiritual OS Impact |
|---|---|---|---|
| 0 | Home | `HomeView` | ADDITIVE — Daily Digest prepended as top section |
| 1 | Discover | `AMENDiscoveryView` | UNTOUCHED |
| 2 | Messages | `MessagesView` | ADDITIVE — Hub stream section prepended above DM threads |
| 3 | Resources | `ResourcesView` | ADDITIVE — Life Planner section prepended above existing resources |
| 4 | Notifications | `AMENNotificationsView` | UNTOUCHED |
| 5 | Profile | `ProfileView` | ADDITIVE — Command Center prepended as header section |

---

## Surface Mount Points

### Agent A — Amen Daily Digest
Mount: Home tab (index 0) — `AmenDailyDigestSection` inserted ABOVE existing feed in `HomeView`.
Product reconciliation: Amen Daily is the Home presentation of shipped Pulse, not a second product. It must extend the existing Pulse/BereanPulse model, `amenPulseEnabled` gate, and Pulse routes; no separate Daily router, ranking engine, or competing feed store is allowed.
Implementation: New view added to existing ScrollView/LazyVStack above post list. No existing UI removed.
Deep link: `amen://daily` → Home tab, scroll to digest
Feature flag: `spiritualOS_daily_enabled` (Remote Config, default OFF)
Impact: ADDITIVE. Safe to implement without user approval.

---

### Agent B — Amen Hub (Unified Inbox)
Mount: Messages tab (index 2) — ✅ UNBLOCKED (user confirmed Option 1)
Implementation: `AmenHubSectionView` inserted at the TOP of `MessagesView` as a collapsible section.
  Existing DM thread list remains COMPLETELY INTACT below it. No buttons or UI removed.
  When `spiritualOS_hub_enabled` flag is OFF, the section is hidden — MessagesView unchanged.
Deep link: `amen://hub` → Messages tab, Hub mode
Feature flag: `spiritualOS_hub_enabled` (Remote Config, default OFF)

---

### Agent C - Amen Life Planner
Mount: Resources tab (index 3) — ✅ UNBLOCKED (user confirmed Option 2)
Implementation: `AmenLifePlannerSection` inserted at the TOP of `ResourcesView`.
  All existing content (Church Notes, Find a Church, etc.) remains COMPLETELY INTACT below.
  No buttons or UI removed. When flag is OFF, section is hidden — ResourcesView unchanged.
Deep link: `amen://planner` → opens Planner, focuses today's date
Feature flag: `spiritualOS_planner_enabled` (Remote Config, default OFF)

---

### Agent D — Spaces Dashboard HeroCard
Mount: Top of existing Space detail views (`SpaceFeedView`, `AmenCovenantRoomDetailView`).
Implementation: `HeroCard` prepended to ScrollView, ABOVE existing content. No existing UI removed.
Deep link: `amen://space/{spaceId}` → existing route, HeroCard visible at top
Feature flags: per-space `heroCardEnabled` field + global `spiritualOS_spaces_dashboard_enabled` (default OFF)
Impact: ADDITIVE. Safe to implement without user approval.

---

### Agent E — Create Space Enhanced
Mount: Existing Create Space / Create Group sheet flow.
Implementation: Enhance existing `CreateSpaceSheet` with new fields only:
  - Pastoral role assignment (Leader / Member / Moderator / Pastor) — `GlassChip .role` style
  - Encryption toggle for private prayer wall
  - Feature toggles: Church Notes, Berean-as-member, Events, Resources, Prayer Wall
  - "Add Berean as member" option (sets `bereanMemberId`)
Impact: ADDITIVE modifications to existing sheet. No existing fields removed.
Feature flag: `spiritualOS_create_space_enhanced_enabled` (Remote Config, default OFF)
Pre-work: Audit existing `CreateSpaceSheet` fields before writing — do not collide or reorder.

---

### Agent F — Command Center
Mount: Profile tab (index 5) — `AmenCommandCenterSection` inserted ABOVE existing `ProfileView` content.
Implementation: New view added as first section in `ProfileView`'s ScrollView. No existing profile content removed.
Deep link: `amen://commandcenter` → Profile tab, scroll to Command Center
Feature flag: `spiritualOS_command_center_enabled` (Remote Config, default OFF)
Impact: ADDITIVE. Safe to implement without user approval.
Formation rule: ALL counts and progress are PRIVATE (only visible to this user). No comparative display.

---

### Agent G — Berean Assistant Bar
Mount: Global overlay in `ContentView` ZStack, positioned between main content and `AMENTabBar`.
Implementation: `AssistantBar` in `GlassBar(floats: true)` injected at `ContentView` level.
  Floating above content, below tab bar in z-order. On expansion: content shifts up.
Deep links: `amen://berean` (expand bar), `amen://berean?query={encoded}` (pre-fill)
Feature flag: `spiritualOS_assistant_bar_enabled` (Remote Config, default OFF)
Impact: ADDITIVE overlay. Tab bar remains fully accessible at all times.
Driving mode: When contextState.isDriving == true, bar goes voice-only (text input hidden).

---

### Agent H — Context Engine (Cross-cutting)
Mount: `SpiritualOSContextManager` (@MainActor singleton) injected at `ContentView` via `.environmentObject()`.
Implementation: Publishes `AmenContextState`. Surfaces subscribe via `@EnvironmentObject`.
  Calls `updateContextState` CF to sync with server.
Feature flag: `spiritualOS_context_engine_enabled` (Remote Config, default OFF)
Impact: ADDITIVE. Fully inert (no location/motion) unless flag ON AND user has granted permissions.
Privacy gate: Context Engine is dormant until:
  1. Feature flag ON
  2. User has explicitly granted CoreLocation permission
  3. User has explicitly opted into geofence features (geofenceOptIn == true)

---

## Global Feature Flags (all Remote Config, all default OFF)

| Flag | Surface |
|---|---|
| `spiritualOS_daily_enabled` | Agent A — Daily Digest |
| `spiritualOS_hub_enabled` | Agent B — Amen Hub (BLOCKED pending user decision) |
| `spiritualOS_planner_enabled` | Agent C — Life Planner (BLOCKED pending user decision) |
| `spiritualOS_spaces_dashboard_enabled` | Agent D — Spaces HeroCard |
| `spiritualOS_create_space_enhanced_enabled` | Agent E — Create Space Enhanced |
| `spiritualOS_command_center_enabled` | Agent F — Command Center |
| `spiritualOS_assistant_bar_enabled` | Agent G — Assistant Bar |
| `spiritualOS_context_engine_enabled` | Agent H — Context Engine |

---

## Deep Link Routes Summary

| Route | Destination |
|---|---|
| `amen://daily` | Home tab → Daily Digest |
| `amen://hub` | Messages tab → Hub mode |
| `amen://planner` | Life Planner (tab TBD) |
| `amen://space/{spaceId}` | Space detail → HeroCard visible |
| `amen://commandcenter` | Profile tab → Command Center |
| `amen://berean` | Expand global AssistantBar |
| `amen://berean?query={encoded}` | AssistantBar with pre-filled query |

All `amen://` routes are registered with and resolved through existing `DeepLinkRouter.shared`. `NotificationDeepLinkRouter` and `AmenContentRouter` are legacy/adaptor call sites only; Spiritual OS must not introduce a second router or bypass the recently added space/event routes.

---

## Blocked Items

None for Phase 1 HTML prototypes. Any proposal to replace a tab, remove existing UI, add a seventh tab, or move the Assistant Bar above the tab bar must stop and escalate to the Lead.

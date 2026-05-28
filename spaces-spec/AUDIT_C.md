# AUDIT_C.md — Agent C Gap Report

**Date:** 2026-05-28
**Agent:** C — Spaces Shell + Shared Design Components

---

## 1. Audit Scope

Files reviewed in order specified by the task:

| File | Finding |
|---|---|
| `AMENAPP/AIIntelligence/LiquidGlass/AmenLiquidGlassComponents.swift` | Existing glass components |
| `AMENAPP/AMENAPP/CommunicationOS/BereanCommunicationHubView.swift` | Not found in project (Xcode project path mismatch) |
| `AMENAPP/ContentView.swift` | Main navigation entry point |
| `AMENAPP/AMENAPP/AccessPasses/AmenAccessRequestInboxView.swift` | Reference style for Agent F |

---

## 2. Design Tokens — What Exists

### AmenLiquidGlassComponents.swift (`AMENAPP/AIIntelligence/LiquidGlass/`)
Provides **glass surface modifiers + interactive components**, not raw color tokens:
- `AmenLiquidGlassCapsuleSurface` (ViewModifier) — ultraThinMaterial capsule with highlight overlay, inner border, shadow, and press-scale
- `AmenLiquidGlassPillButton` — pill button with bounce symbol effect, loading, disabled states, and a11y label/hint
- `AmenLiquidGlassControlDock` — scrollable horizontal chip dock (used by SpacesNavigationView for filter pills)
- `AmenLiquidGlassBottomSheet` — title/subtitle/AI-disclosure header + scrollable body + footer (used by MemberRosterSheet)

These components are FOUNDATION for Spaces surfaces. No duplication required.

### AmenTheme.swift (`AMENAPP/AMENAPP/AMENAPP/AmenTheme.swift`)
**Single source of truth for all brand tokens.** Already contains:
- `AmenTheme.Colors.amenGold`, `.amenPurple`, `.amenBlue`, `.amenBlack` — all four brand tokens
- Full set of adaptive semantic tokens (backgrounds, surfaces, text, separators, shadows, glass)
- View modifiers: `.amenCard()`, `.amenGlassCard()`, `.amenGlassInputBar()`, `.amenFlatCard()`
- `Color` extension shortcuts for backward compat

### LiquidGlassTokens.swift (`AMENAPP/AMENAPP/AMENAPP/LiquidGlass/LiquidGlassTokens.swift`)
Corner radii (small=14, medium=22, large=32), material aliases (blurThin=ultraThinMaterial), shadow values, motion timing.

### Motion.swift (`AMENAPP/AMENAPP/Motion.swift`)
`Motion.liquidSpring` — canonical spring animation used across all Liquid Glass interactions.

**Decision:** No new token file needed. `AmenTheme.Colors` and `LiquidGlassTokens` cover all required tokens. `SpacesDesignTokens.swift` is NOT created — per "one shared style file" rule. Agents import `AmenTheme` directly.

---

## 3. BereanCommunicationHubView — Not Applicable

The file was not found at the specified path. The Communication OS layer (`CommunicationOS/`) exists in the project tree but `BereanCommunicationHubView.swift` could not be located in the filesystem (project groups may differ from disk paths). This view does NOT conflict with the Spaces shell — Spaces is a distinct tab-level feature and does not extend or replace Communication OS.

---

## 4. Existing Spaces Shell — What Was Pre-Built by Agent A

The following files already exist on disk at `AMENAPP/Spaces/`:

| File | Status |
|---|---|
| `AMENAPP/AMENAPP/Spaces/SpacesModels.swift` | ✅ Complete — `SpacesCommunity`, `AmenSpace`, `SpaceMember`, etc. |
| `AMENAPP/AMENAPP/Spaces/SpacesService.swift` | ✅ Complete — all CONTRACT_A methods present |
| `AMENAPP/Spaces/Shell/SpacesNavigationView.swift` | ✅ Pre-built by Agent A — filter pills, space list, FAB, entitlement tap handler |
| `AMENAPP/Spaces/Shell/SpaceDetailView.swift` | ✅ Pre-built — hero header, SharedCommunityBanner, MemberRosterSheet, LockedPreviewShell, SpacesPurchaseSheet |
| `AMENAPP/Spaces/Shell/SpacesShellViewModel.swift` | ✅ Pre-built — `SpaceListFilter`, `SpacesShellViewModel` with Firestore listener, VIP, unread, external filters |
| `AMENAPP/Spaces/SharedComponents/LinkedGlyph.swift` | ✅ Exists — `LinkedGlyph` (not `LinkedCommunityGlyph`). Correct API, used throughout |
| `AMENAPP/Spaces/SharedComponents/SharedCommunityBanner.swift` | ✅ Exists — `.sharedWith` and `.membersFrom` modes |
| `AMENAPP/Spaces/SharedComponents/MemberRosterSheet.swift` | ✅ Exists — sections external members by homeCommunityId |
| `AMENAPP/Spaces/SharedComponents/LockedPreviewShell.swift` | ✅ Exists — paywall shell with `onUnlock` callback |

**Note on naming difference:** The task asks for `LinkedCommunityGlyph`, `ExternalMemberRoster`, `SpaceAvatarView` — these are the canonical names for the CONTRACT_C public API. `LinkedGlyph` and `MemberRosterSheet` are the implementation files. Agent C provides type-aliases or wrappers to expose the spec-canonical names so B/D/E/F can import them without breaking the existing internal usage.

---

## 5. Gaps (What Agent C Must Add)

| Item | Gap | Action |
|---|---|---|
| `SpacesRootView` | Missing — no top-level entry point with community switcher | CREATE |
| `CommunitySwitcherView` | Missing — no community sidebar/column UI | CREATE |
| `SpacesListView` | Missing by spec name — `SpacesNavigationView` exists but `SpacesListView` is the contracted name | CREATE as thin wrapper + augment |
| `CommunityCreateSheet` | Missing — no community creation sheet | CREATE |
| `LinkedCommunityGlyph.swift` | Missing by spec name — `LinkedGlyph` exists internally | CREATE as re-export/alias |
| `SharedCommunityBanner.swift` | Exists with correct API | EXTEND with communityAvatarURL + externalMemberCount params |
| `ExternalMemberRoster.swift` | Missing by spec name — `MemberRosterSheet` covers it | CREATE as re-export/spec alias |
| `SpaceAvatarView.swift` | Missing — no dedicated avatar component | CREATE |
| Tab wiring | Spaces tab not wired into ContentView / AMENTabBar | WIRE at tab index 6 (after gatherings) |
| `createCommunity` in SpacesService | Not found in SpacesService — only `fetchMyCommunities` exists | FLAG in CONTRACT_C; implement locally in CommunityCreateSheet using raw Firestore writes until callable is deployed |

---

## 6. AmenAccessRequestInboxView — Reference for Agent F

`AmenAccessRequestInboxView` uses: `List`, filter pills via a `@State filter` + `contentUnavailableView`, `LazyVStack` style rows. Agent F's link invite inbox can follow this pattern — glass cards instead of List rows, but same pill filter + empty state structure.

---

## 7. Tab Wiring Plan

Current tabs (0–5): Home, Search, Messages, Library, Notifications + Profile orb.
Tab 6 = `.gatherings` (feature-flagged).
Spaces will be wired as tab 7 (`AMENTab.spaces`) — additive, feature-flagged via `SpacesFeatureFlags.shared.spacesLiquidGlassEnabled`. `selectedTabView` in ContentView gets a new `keepMountedTab(isActive: viewModel.selectedTab == 7)` block wrapping `SpacesRootView`.

---

## 8. createCommunity Gap

`SpacesService` does NOT expose `createCommunity`. `SpacesCallable.createCommunity` is declared in `SpacesCore.swift` as a callable name. `CommunityCreateSheet` will invoke the Firebase callable directly (matching the contract callable name `createCommunity`) for the production path, with a client-side Firestore fallback comment noting the callable must be deployed first.

This gap is flagged in CONTRACT_C.md as: `createCommunity` callable must be deployed before `CommunityCreateSheet` can complete community creation.

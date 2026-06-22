# Capabilities v1 — Lane C Report (CLIENT-CORE)

**Branch:** feature/berean-island-w0
**Lane:** C (CLIENT-CORE)
**Date:** 2026-06-13

---

## Items Delivered

| Item | File | Commit |
|---|---|---|
| CapabilityRegistryStore | `AMENAPP/AMENAPP/Capabilities/CapabilityRegistryStore.swift` | 088f1f22 |
| CapabilityComposerCoordinator | `AMENAPP/AMENAPP/Capabilities/CapabilityPicker/CapabilityComposerCoordinator.swift` | 4b004059 |
| CapabilityPickerView | `AMENAPP/AMENAPP/Capabilities/CapabilityPicker/CapabilityPickerView.swift` | 4f20a9d8 |
| ContextSettingsView | `AMENAPP/AMENAPP/Capabilities/ContextSettings/ContextSettingsView.swift` | e5a61859 |

---

## CapabilityRegistryStore (088f1f22)

- `@MainActor` `ObservableObject` singleton.
- Calls `capabilityRegistry_list` callable with the surface's raw value.
- Decodes `[Capability]` via `JSONSerialization` → `JSONDecoder` pipeline.
- `capabilities(for:)` filters client-side by surface membership and `.active` status.
- Guard on `AMENFeatureFlags.shared.capabilitiesCoreEnabled` — returns `[]` and clears error if OFF.
- Guard on `Auth.auth().currentUser` — silently skips if not signed in.
- `@Published` `isLoading` / `loadError` for UI binding.

---

## CapabilityComposerCoordinator (4b004059)

- Detects `@` at a word boundary by inspecting UTF-16 code units at `cursorPosition - 1`.
- Word boundary: preceding character is space (0x20), newline (0x0A / 0x0D), tab (0x09), or string start.
- Sets `isPickerVisible = true` only when `capabilityPickerEnabled` flag is ON.
- `selectCapability(_:)` records the selection in `selectedCapability` and hides the picker; the owning view drives the entry flow (inline vs sheet) by observing `selectedCapability`.
- `insertContent(_:)` publishes an `InsertionRequest` (position + text); the owning view applies the splice. `acknowledgeInsertion()` clears it after application.

---

## CapabilityPickerView (4f20a9d8)

- Glass panel using `glassSurface(cornerRadius: 16)` (existing design system modifier).
- Calls `store.loadCapabilities(for:)` on appear (`.task(id: coordinator.surface)`).
- Transition: `.easeInOut(duration: 0.2)` when `reduceMotion` is ON, spring otherwise.
- Each row: SF Symbol icon + `.font(.headline)` displayName + `.font(.subheadline)` tagline.
- VoiceOver: `.accessibilityLabel("\(cap.displayName) — \(cap.tagline)")` + `.accessibilityAddTraits(.isButton)`.
- Keyboard navigation: arrow keys move `focusedIndex`; Return/Space selects; Escape dismisses.
- Empty state: icon + "No capabilities available" + explanatory note.
- Loading state: `ProgressView` + label.
- Tier badge ("Plus") shown for `.plus` tier capabilities.

---

## ContextSettingsView (e5a61859)

- SwiftUI `List` with a single `Section` iterating `ContextSource.allCases`.
- On appear: calls `contextEngine_getGrants` callable, decodes `[ContextGrant]` with ISO 8601 dates.
- `.refreshable` pull-to-refresh support.
- Policy change: calls `contextEngine_setGrant` callable; optimistically updates local `grants` array from `SetGrantResponse`, or reloads on decode failure.
- Error state: inline red banner with retry button (does not clear the grant list).
- `ContextGrantRow` for active sources: taps present a `confirmationDialog` with all four `ContextPolicy` cases.
- Device-level sources (`calendar`, `location`, `contacts`): rendered with `.foregroundStyle(.secondary)` + "Coming soon" subtitle + `.disabled(true)`.
- `ContextSource.displayName` extension added in this file (human-readable labels per contract).
- VoiceOver labels on all rows; accessibility hint on active rows.

---

## Flag Dependencies

All client code respects:
- `AMENFeatureFlags.shared.capabilitiesCoreEnabled` — gates registry fetch
- `AMENFeatureFlags.shared.capabilityPickerEnabled` — gates picker trigger

Both flags default `false` per Wave 0 contracts.

---

## Known Limitations / Next Steps

- `XcodeRefreshCodeIssuesInFile` returned error 5 on all four files — this is a headless Xcode editor session limitation (file not open in editor). A full `xcodebuild` pass is required for final diagnostic confirmation (HUMAN-PENDING gate per repo build protocol).
- `CapabilityComposerCoordinator.selectCapability` currently only records the selection; the owning view (lane B or the composer wiring) must observe `selectedCapability` and route to the inline (VerseLookup) or sheet (PrayerOS) flow.
- `ContextSource.displayName` is declared in `ContextSettingsView.swift`. If other files need it, move it to a shared extension file in `Capabilities/`.

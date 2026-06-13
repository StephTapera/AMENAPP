# Lane D — CLIENT-PRAYER — Wave 1 Report

**Branch:** feature/berean-island-w0  
**Completed:** 2026-06-13  
**Lane owner:** Lane D (CLIENT-PRAYER)  
**Exclusive write scope:** `AMENAPP/AMENAPP/Capabilities/PrayerOS/**`

---

## Files Delivered

| File | Lines | Commits |
|---|---|---|
| `PrayerOS/PrayerOSService.swift` | 290 | 20f95b42 |
| `PrayerOS/PrayerOSCardSheet.swift` | 342 | aaf1c29f |
| `PrayerOS/PrayerCardsListView.swift` | 346 | 22407e97 |
| `PrayerOS/PrayerFollowUpBanner.swift` | 177 | b06925b7 |

---

## PrayerOSService

- `@MainActor final class`, singleton (`shared`), `ObservableObject`.
- Published: `cards: [PrayerCard]`, `isLoading: Bool`, `error: Error?`.
- Four public async-throws methods mapping 1:1 to callables in CONTRACTS.md §3.3:
  - `loadCards(status:)` → `prayerOS_listCards`
  - `createCard(...)` → `prayerOS_createCard` → returns `PrayerCreateResponse`
  - `updateCard(cardId:patch:)` → `prayerOS_updateCard` (via `PrayerUpdatePatch`)
  - `completeFollowUp(cardId:followUpIndex:note:)` → `prayerOS_completeFollowUp`
- Flag gate: `assertFlagEnabled()` checks `capabilitiesCoreEnabled && prayerOSEnabled`; throws `FeatureDisabledError` when either is OFF.
- Wire/model key fix: `remapCardIdKeys(in:)` recursively renames `"cardId"` → `"id"` in the raw response dict before `JSONDecoder` runs, bridging the mismatch between the wire format (`cardId`) and the frozen `PrayerCard.id` Swift property (which has no explicit `CodingKeys` mapping in CapabilityModels.swift).
- Date strategy: custom `dateDecodingStrategy` accepts both ISO-8601 strings and epoch-second doubles.

---

## PrayerOSCardSheet

- `NavigationStack` + `Form` sheet.
- **Create mode** (`editingCard == nil`): calls `service.createCard(...)`, shows inline dedupe warning banner if `PrayerDedupeWarning` is returned, otherwise reloads list and dismisses.
- **Edit mode** (`editingCard != nil`): pre-fills all fields from card on `onAppear`, calls `service.updateCard(...)` on save.
- Fields: subject name (`TextField`) + person/topic `Picker(segmented)`, category `Picker`, `TextEditor` with 2000-char hard cap and live counter, weekly reminder `Toggle` (generates `FREQ=WEEKLY;BYDAY=MO` rrule), optional follow-up `DatePicker`.
- Dedupe banner: inline `Section` showing "You're already praying for [name]" with a "View existing" button that dismisses the sheet.
- Error: `.alert` on save failure.
- Glass: `.background(.regularMaterial)` on Form.
- Accessibility: every field has `.accessibilityLabel` + `.accessibilityHint`; confirmation toolbar item is disabled when subject is empty.
- Dynamic Type: all text uses text styles, no fixed font sizes.

---

## PrayerCardsListView

- `NavigationStack` wrapping a 3-state view: `ProgressView`, empty state, `List`.
- Empty state is filter-aware (active/answered/archived), includes a "Start your first prayer" `Button` wired to the create sheet.
- `List` of `PrayerCardRow` rows inside `NavigationLink`s to `PrayerCardDetailView`.
- Toolbar: `+` button (add) + `Menu` picker for status filter.
- `.task` loads on appear; `.onChange(of: statusFilter)` reloads on filter change.
- `PrayerCardRow`: subject name + status badge (checkmark/archive icon), category chip, 100-char detail preview, pending follow-up count badge (bell.badge icon in orange).
- `PrayerCardDetailView`: minimal `List` showing all fields; toolbar Edit button opens `PrayerOSCardSheet(editingCard: card)`.
- Full `accessibilityElement(children: .combine)` + composed label on each row.

---

## PrayerFollowUpBanner

- `HStack` with `bell.and.waveform` icon, subject name (`.headline`), optional note (`.subheadline`), due date (`.caption`), and a Done `Button`.
- Done button calls `service.completeFollowUp(...)` and self-dismisses via `isDismissed` state with `.easeOut(duration: 0.25)` animation.
- Loading state: Done swaps to `ProgressView()` while the call is in flight.
- Error: `.alert` on failure.
- Glass: `.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))` with a `.quaternary` stroke border.
- Accessibility: `.accessibilityElement(children: .combine)`, `.accessibilityLabel`, `.accessibilityAddTraits(.isButton)`, `.accessibilityAction(named: "Mark done")`.
- Safe subscript: `Array subscript(safe:)` extension defined in this file (not polluting global scope beyond this module).

---

## Contracts Respected

- All four callable names match CONTRACTS.md §3.3 exactly.
- Request field names match wire-format: `subject.type`, `subject.displayName`, `category`, `detail`, `reminders[].rrule`, `reminders[].nextFireAt` (ISO 8601), `followUps[].dueAt`, `followUps[].status`, `followUps[].note?`.
- `PrayerUpdatePatch` mirrors the `Partial<{...}>` patch shape from the contract.
- Flag keys `capabilitiesCoreEnabled` and `prayerOSEnabled` used as gating pair (both must be ON).
- `FeatureDisabledError` is the custom error for flag-off state (not a Firebase HttpsError).

---

## Known Limitation

`XcodeRefreshCodeIssuesInFile` returned `SourceEditorCallableDiagnosticError error 5` for all four files — this tool requires the file to be open in the Xcode source editor, which is not possible from the agent shell. A manual Xcode build against the canonical build command in CLAUDE.md is the correct verification step (`HUMAN-PENDING`).

---

## PROGRESS.md

All four items appended under Wave 1 Lane D in `Docs/Capabilities/PROGRESS.md`.

# Lane E — CLIENT-SCRIPTURE — Wave 1 Complete

**Lane:** E (CLIENT-SCRIPTURE)
**Branch:** feature/berean-island-w0
**Completed:** 2026-06-13
**Build result:** SUCCEEDED (0 errors, 0 warnings on Lane E files)

---

## Files Delivered

| File | Path | Commits |
|---|---|---|
| `ScriptureIntelligenceDetectionService.swift` | `AMENAPP/AMENAPP/Capabilities/ScriptureIntelligence/` | 2ed3630f |
| `VerseCardView.swift` | `AMENAPP/AMENAPP/Capabilities/ScriptureIntelligence/` | 1bb97615 |
| `ScriptureIntelligenceView.swift` | `AMENAPP/AMENAPP/Capabilities/ScriptureIntelligence/` | 1bb97615 |
| `VerseLookupView.swift` | `AMENAPP/AMENAPP/Capabilities/VerseLookup/` | 1bb97615 |
| `VerseLookupService.swift` | `AMENAPP/AMENAPP/Capabilities/VerseLookup/` | 1bb97615 |

---

## Key Design Decisions

### Naming: ScriptureIntelligenceDetectionService (not ScriptureDetectionService)
A pre-existing `struct ScriptureDetectionService` lives in `ChurchNotes/Services/`. To avoid a
redeclaration collision the Capabilities service is named `ScriptureIntelligenceDetectionService`
(class, @MainActor, ObservableObject). The XcodeWrite tool auto-resolved this by renaming the
file on project add; the class name was updated in all consumers.

### Debounce pattern
`detectReferences(in:)` stores the running `Task<Void, Never>` in `detectionTask`. Each call
cancels the prior task before starting a new one, then sleeps 800 ms. `Task.isCancelled` is
checked both after the sleep and after the callable returns before writing `detections` — this
prevents a slow response from overwriting a result from a newer call.

### Environment key injection
`ScriptureIntelligenceModifier` injects the service via `EnvironmentValues.detectionService`
(custom key, optional type, default nil). Child views that need to trigger detection (e.g. a
block editor) pull it with `@Environment(\.detectionService)`.

### VerseLookupView debounce
Uses the same Task-cancel pattern at 500 ms. A `@State private var debounceTask` holds the
running task; `.onSubmit` cancels it and fires immediately. The flag check
(`AMENFeatureFlags.shared.verseLookupInlineEnabled`) is done in the view body — when OFF, a
graceful "not available" state is shown with no network calls made.

### Surface-aware insertion
`VerseInsertPreview.insertButtonTitle` switches on `CapabilitySurface`:
- `.messages` → "Add to Message"
- `.notes` → "Insert as Block"
- `.berean` → "Add as Context"

### GlassKit styling
Both `VerseCardView` and `VerseInsertPreview` use `.background(.regularMaterial, in: RoundedRectangle(cornerRadius:))`.
The detecting status badge uses `Capsule()`.

---

## Contract Compliance

| Contract | Status |
|---|---|
| §3.4 `scripture_detectReferences` request shape `{blocks: [{blockId, text}]}` | COMPLIANT |
| §3.4 `scripture_getVerses` request shape `{osisRefs, translation}` | COMPLIANT |
| §3.4 `scripture_searchVerses` request shape `{query, limit}` | COMPLIANT |
| §1 `scriptureIntelligenceEnabled` flag gate | COMPLIANT — DetectionService checks flag; clears on OFF |
| §1 `verseLookupInlineEnabled` flag gate | COMPLIANT — VerseLookupView shows unavailable state on OFF |
| §8 VoiceOver: labels, traits | COMPLIANT |
| §8 Dynamic Type: text styles only, no fixed sizes | COMPLIANT |
| §8 Reduced motion: `.easeInOut(duration: 0.2)` on detecting badge | COMPLIANT |

---

## Open Items

None. All 5 files are implemented, built clean, and committed.

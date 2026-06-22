# NIS Wave 1 — Lane D: Editor Bridge Wiring + Detection Status Bar

## Commit Hashes

| Commit | Content |
|--------|---------|
| `952b269a` | feat(nis/lane-d): wire NISEditorBridge into editor + add NISDetectionStatusBar |

## Entry Point

```
ChurchNoteSemanticEditorView → nisBridge.observe(noteId:) → NISDetectionStatusBar
```

## Files Changed / Created

### Modified

- **`AMENAPP/AMENAPP/ChurchNotes/Views/ChurchNoteSemanticEditorView.swift`**
  - `@StateObject private var nisBridge = NISEditorBridge()` — already present (no change needed)
  - `nisBridge.observe(noteId: vm.note.id)` in `.onAppear` — now gated behind
    `AMENFeatureFlags.shared.nisDetectionLayerEnabled`
  - Replaced inline `NISStatusCapsule(...)` call with `NISDetectionStatusBar(bridge: nisBridge)`

### Created

- **`AMENAPP/AMENAPP/ChurchNotes/Views/NISDetectionStatusBar.swift`**
  - Public `struct NISDetectionStatusBar: View` taking `@ObservedObject var bridge: NISEditorBridge`
  - Gated: `AMENFeatureFlags.shared.nisDetectionLayerEnabled` — renders `EmptyView` when flag is off
  - 4-state rendering:
    - `.idle` / `.done(0)` → `EmptyView` (hidden)
    - `.processing` → pulsing capsule "Analyzing note…" (ultraThinMaterial)
    - `.done(N)` where N > 0 → accent capsule "N suggestion(s) found" with `sparkles` SF Symbol
    - `.error` → muted red capsule "NIS unavailable" (no raw message exposed to user)
  - `.animation(.easeInOut(duration: 0.3), value: bridge.processingState)` on outer container
  - `.transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))` per state

### No Change Required

- **`AMENAPP/AMENFeatureFlags.swift`** — `nisDetectionLayerEnabled = true` was already set in the
  `#if DEBUG` block inside `applyUITestOverrides()` (added by Lane E). Not duplicated.

## Manual Step Required

`NISDetectionStatusBar.swift` needs to be added to the `AMENAPP` Xcode target manually:

1. Open `AMENAPP.xcodeproj` in Xcode
2. In the Project Navigator, locate `AMENAPP/AMENAPP/ChurchNotes/Views/`
3. Right-click → "Add Files to AMENAPP…" and select `NISDetectionStatusBar.swift`
4. Ensure the `AMENAPP` target checkbox is checked, then click Add

## DONE Criteria

- [x] `NISDetectionStatusBar` compiles with 0 diagnostics (confirmed via XcodeRefreshCodeIssuesInFile)
- [x] `ChurchNoteSemanticEditorView` calls `nisBridge.observe(noteId:)` on appear, gated behind flag
- [x] `nisDetectionLayerEnabled = true` in debug config (was already set by Lane E)
- [x] NOTES-LaneD.md written with commit hash and entry point
- [x] Entry point documented: `ChurchNoteSemanticEditorView → nisBridge.observe(noteId:) → NISDetectionStatusBar`

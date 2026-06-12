# NIS Wave 1 — Lane E: Birth Context (C2)

## Commit Hashes

| Commit | Content |
|--------|---------|
| `ba161750` | feat(nis): Lane E — NIS C2 Birth Context (Wave 1) — all four deliverables |

## Entry Points

### iOS

- **Service**: `AMENAPP/ChurchNotes/Models/NIS/NISBirthContextService.swift`
  - `NISBirthContextService.shared.capture(noteId:authorUID:) async`
  - Gated by `AMENFeatureFlags.shared.nisBirthContextEnabled`
  - 5-second CLLocation timeout; no permission request; writes `notes/{noteId}/birthContext`

- **Wire-in**: `AMENAPP/AMENAPP/ChurchNotes/Views/ChurchNoteSemanticEditorView.swift`
  - `ChurchNoteSemanticEditorViewModel.startEditing()` — fires birth context capture
    as fire-and-forget Task on new note creation only (`isNewNote` guard).

- **Flag**: `AMENAPP/AMENFeatureFlags.swift`
  - `nisBirthContextEnabled = true` in `#if DEBUG` override block inside
    `applyUITestOverrides()`. Production value remains `false` until Remote Config flip.

### Backend

- **Enricher**: `Backend/functions/src/nis/birthContextEnricher.ts`
  - Exports `enrichBirthContext(noteId, uid): Promise<void>`
  - Called by Lane B's `detectionPipeline.ts` after note write event.
  - Wave 1 stub: reads `users/{uid}/profile.primaryChurchId`, sets
    `locationMatched: true, confidence: 0.7` if found.
  - Wave 2 TODO: replace stub with schedule-aware ±90-minute matching against
    `services/{churchId}/schedule` docs.

## Firestore Paths

| Path | Content |
|------|---------|
| `notes/{noteId}` (inline key `birthContext`) | `{ createdAt, locationMatched, confidence, latitude?, longitude?, churchId?, churchName?, seriesId? }` |

## Integration Notes for Lane B

Lane B's `detectionPipeline.ts` can call `enrichBirthContext` after any note
write event fires:

```typescript
import { enrichBirthContext } from "./birthContextEnricher";

// Inside nisProcessNote handler:
const uid: string = data.uid ?? data.userId ?? "";
if (uid) {
    await enrichBirthContext(noteId, uid);
}
```

## DONE Criteria

- [x] `NISBirthContextService.swift` compiles clean (0 diagnostics)
- [x] `capture()` is a no-op when flag is off
- [x] `birthContextEnricher.ts` compiles clean (`tsc --noEmit` passes)
- [x] `enrichBirthContext` exported correctly
- [x] Note creation fires `NISBirthContextService.shared.capture(...)` (gated)
- [x] `nisBirthContextEnabled = true` in debug config
- [x] NO-DUPLICATES check passed (single definition each)
NISService.swift listener implementation committed in 4ca93a34 under SANCTUARY prefix — already in history, do not re-commit or report as missing.

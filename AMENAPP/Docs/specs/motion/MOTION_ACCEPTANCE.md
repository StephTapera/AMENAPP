# Motion Acceptance

## CCR-002 Light Glass / Menu / Picker Additions

Status: wired in code and build-verified.

- Default glass surfaces render light-first using `Color.basWarmPaper`, dark ink, white stroke, and low-opacity shadow.
- Reduced transparency collapses CCR-002 surfaces to solid `basWarmPaper` fill plus stroke.
- `LiquidGlassMenu` supports sectioned rows, details, chevrons, dismiss action, and selection handlers for every row.
- `LiquidGlassListPicker` owns selection state, renders selected chips, enforces optional caps, and exposes confirm/dismiss actions.
- `BereanComposerMenu` provides Add Scripture, Attach Note, Scan Text, Photo, and `@` Capabilities rows.
- `BereanAgentActivitySheet` shows real task state from the current running surface and lists actual active plugin provenance.
- Build verification: `BuildProject` succeeded on 2026-06-16.

Open human gates:

1. Dark mode keep/drop remains product decision.
2. Inbox routing for Messages/Files/Canvas remains product decision.
3. Composer Scan Text scope must be confirmed as Berean Lens on-device OCR only.
4. Provenance copy remains pending final wording approval.

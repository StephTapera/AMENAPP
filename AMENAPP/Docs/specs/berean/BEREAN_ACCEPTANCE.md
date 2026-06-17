# Berean Acceptance

## CCR-002 Composer Menu / Agent Activity Additions

Status: wired in code and build-verified.

- `BereanComposerMenu` is available as a shared Berean wrapper over `LiquidGlassMenu`.
- `BereanAgentComposerView` opens `BereanComposerMenu` from the `@` affordance.
- Existing plugin drawer behavior is preserved through the `@ Capabilities` menu row and as the default fallback for newly exposed rows until their owning Lens/Guard routes are attached.
- `BereanAgentActivitySheet` is wired into `BereanAgentModeView` running state.
- Activity provenance is sourced from the existing `activePlugins` list, so the sheet does not invent retrieval sources.
- Build verification: `BuildProject` succeeded on 2026-06-16.

Open human gates:

1. Confirm Scan Text targets physical Bible/bulletin OCR through Berean Lens only, with no image leaving device.
2. Confirm Photo follows the same on-device Lens plus Guard route before save/share.
3. Confirm the provenance wording and only show church/group context when the user is actually in that Space.

# Sanctuary Frozen Files

Frozen: 2026-06-12  
Tag: `sanctuary-w0-frozen`  
Version: `2026-06-12-wave0-v1`

These files are frozen after Wave 0. Later lanes must not edit them without blocker triage and lead architect approval.

| Requested Contract | Workspace Path | Notes |
| --- | --- | --- |
| `/Contracts/Sanctuary/SanctuaryModels.swift` | `AMENAPP/AMENAPP/Shared/Contracts/SanctuaryModels.swift` | Compiled Swift contract location following existing `Shared/Contracts` convention. |
| `/Contracts/Sanctuary/sanctuary.types.ts` | `AMENAPP/AMENAPP/Docs/Contracts/Sanctuary/sanctuary.types.ts` | TypeScript mirror for Cloud Functions lanes. |
| `/Contracts/Sanctuary/FunctionSignatures.md` | `AMENAPP/AMENAPP/Docs/Contracts/Sanctuary/FunctionSignatures.md` | Callable and HTTP/SSE contract signatures. |
| `/Contracts/Sanctuary/firestore-schema.md` | `AMENAPP/AMENAPP/Docs/Contracts/Sanctuary/firestore-schema.md` | Firestore paths and rules sketch. |
| `/Contracts/Sanctuary/DesignTokens.md` | `AMENAPP/AMENAPP/Docs/Contracts/Sanctuary/DesignTokens.md` | Liquid Glass depth, luminance, palette, timing, liturgical tint tokens. |
| `/Contracts/Sanctuary/FROZEN_FILES.md` | `AMENAPP/AMENAPP/Docs/Contracts/Sanctuary/FROZEN_FILES.md` | This manifest. |

## Feature Flag Delta

`AMENAPP/AMENAPP/AMENFeatureFlags.swift` contains the Wave 0 feature flag declarations and Remote Config defaults. It is not globally frozen by this manifest, but the Sanctuary flag names and default-OFF values are frozen.

| Property | Remote Config Key | Default |
| --- | --- | --- |
| `sanctuaryCoreEnabled` | `sanctuary_core` | `false` |
| `sanctuaryLayersEnabled` | `sanctuary_layers` | `false` |
| `sanctuaryThreadEnabled` | `sanctuary_thread` | `false` |
| `sanctuaryReactionsEnabled` | `sanctuary_reactions` | `false` |
| `sanctuaryWatchTogetherEnabled` | `sanctuary_watch_together` | `false` |
| `sanctuarySelahEnabled` | `sanctuary_selah` | `false` |
| `sanctuaryAskMomentEnabled` | `sanctuary_ask_moment` | `false` |
| `sanctuaryJourneyEnabled` | `sanctuary_journey` | `false` |
| `sanctuarySearchEnabled` | `sanctuary_search` | `false` |

# Sanctuary Feature Flags

Frozen: 2026-06-12  
Version: `2026-06-12-wave0-v1`  
Owner: `AMENFeatureFlags` / Firebase Remote Config.  
Rule: every key defaults `false` in app defaults and Remote Config templates until a human flips it after validation.

| Property | Remote Config Key | Default | Owns |
| --- | --- | --- | --- |
| `sanctuaryCoreEnabled` | `sanctuary_core` | `false` | Canvas and player core. |
| `sanctuaryLayersEnabled` | `sanctuary_layers` | `false` | Layer fan, creator notes, group annotations. |
| `sanctuaryThreadEnabled` | `sanctuary_thread` | `false` | Scripture Thread. |
| `sanctuaryReactionsEnabled` | `sanctuary_reactions` | `false` | Sacred reactions and warmth field. |
| `sanctuaryWatchTogetherEnabled` | `sanctuary_watch_together` | `false` | Watch rooms and room sync UI. |
| `sanctuarySelahEnabled` | `sanctuary_selah` | `false` | Selah transition engine. |
| `sanctuaryAskMomentEnabled` | `sanctuary_ask_moment` | `false` | Ask-the-Moment SSE overlay. |
| `sanctuaryJourneyEnabled` | `sanctuary_journey` | `false` | Journey constellation. |
| `sanctuarySearchEnabled` | `sanctuary_search` | `false` | Cross-video search. |

Flag-off behavior must be invisible: no buttons, empty states, background processing, uploads, indexing, or AI calls may run because a Sanctuary flag exists.

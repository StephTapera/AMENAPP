# Selah Sensory Layer

Wave 0 freezes the contract before production assets or call-site wiring. The layer exists for presence, reverence, memory, and immersion. It must never be used as a feedback, reward, streak, or retention system. Silence is a valid complete state.

## Wave 0 Contract

Remote Config flag: `selah_sensory_layer_enabled`, default `false`.

Swift registry: `SelahSensoryRegistry` in `SelahMomentService.swift`.

Core protocols:

| Protocol | Role |
|---|---|
| `SelahSensoryLayering` | Public service for paired sensory events and ambient beds. |
| `SelahAudioRendering` | Audio engine abstraction for one-shots, loops, suspension, and tests. |
| `SelahHapticRendering` | Haptic abstraction for UIKit and Core Haptics rendering. |
| `SelahModifierChain` | Composes time-of-day, Sabbath, reflection decay, and accessibility shaping. |
| `SelahVerseAudioAnchorStore` | Private per-user `verseRef -> anchorToneID` persistence contract. |

Frozen event IDs:

| Event ID | Sound | Haptic |
|---|---|---|
| `open_bible` | Very subtle real Bible opening | `soft_tap` |
| `page_turn_psalms` | Thin page, soft air, low transient | `light_impact` |
| `page_turn_old_testament` | Heavier parchment, restrained body | `light_impact` |
| `page_turn_new_testament` | Modern Bible paper, close and quiet | `light_impact` |
| `chapter_jump_10_plus` | Multi-page riffle scaled by distance | `layered_light_impacts` |
| `verse_highlight` | Soft ink writing on Bible paper | `micro_pulse` |
| `bookmark_verse` | Small leather journal close | `soft_tap` |
| `prayer_start` | Soft non-human inhale | `gentle_pulse` |
| `prayer_end` | Gentle non-human exhale | `release_pulse` |
| `prayer_journal_save` | Pen finish and tiny notebook close | `soft_tap` |
| `selah_start` | Ambient fade-in and real Bible opening | `long_soft_vibration` |
| `selah_complete` | Soft bell, wooden chime, or single piano note | `gentle_pulse` |

Ambient bed IDs:

| Bed ID | Purpose |
|---|---|
| `selah_room_tone` | Signature Selah room tone, subtle air, near-imperceptible chapel ambience. |
| `ancient_jerusalem_courtyard` | Historically inspired courtyard for Scripture and study. |
| `desert_wilderness` | Sparse wind and open air for wilderness passages. |
| `upper_room` | Close, warm room tone for prayer and Gospel study. |
| `galilee_shoreline` | Quiet shoreline movement for Gospel reading. |
| `monastery_library` | Still library air for focused study. |
| `quiet_chapel` | Soft chapel ambience for prayer and reflection. |
| `forest_prayer_walk` | Subtle outdoor prayer walk environment. |
| `psalms_quiet_room` | Quiet room bed for Psalms. |
| `revelation_cinematic_space` | Restrained spacious bed for apocalyptic readings. |
| `sermon_mount_outdoor` | Open hillside air for Sermon on the Mount passages. |

## Audio Asset Manifest

All one-shots ship as mono or stereo CAF, 48 kHz, 24-bit source rendered to app-ready CAF. Ambient beds ship as seamless CAF loops, 48 kHz, with tested loop points. AAC may be used for downloadable premium beds after loop QA. All source must be commissioned or explicitly licensed for in-app distribution, modification, and offline caching.

| Asset ID | Layer | Mode | File | LUFS | Ceiling | Duck/Crossfade | Source/License |
|---|---|---|---|---:|---:|---|---|
| `selah_event_open_bible` | Event | One-shot | `selah_event_open_bible.caf` | -24 | -8 dBTP | No duck, 120 ms edge fade | Commissioned AMEN-owned |
| `selah_event_page_turn_psalms` | Event | One-shot | `selah_event_page_turn_psalms.caf` | -25 | -9 dBTP | Sync to swipe, 80 ms edge fade | Commissioned AMEN-owned |
| `selah_event_page_turn_ot` | Event | One-shot | `selah_event_page_turn_ot.caf` | -24 | -8 dBTP | Sync to swipe, 80 ms edge fade | Commissioned AMEN-owned |
| `selah_event_page_turn_nt` | Event | One-shot | `selah_event_page_turn_nt.caf` | -25 | -9 dBTP | Sync to swipe, 80 ms edge fade | Commissioned AMEN-owned |
| `selah_event_chapter_jump` | Event | One-shot variants | `selah_event_chapter_jump.caf` | -25 | -9 dBTP | Scale duration/intensity by distance | Commissioned AMEN-owned |
| `selah_event_verse_highlight` | Event | One-shot | `selah_event_verse_highlight.caf` | -26 | -10 dBTP | No duck, 80 ms edge fade | Commissioned AMEN-owned |
| `selah_event_bookmark_verse` | Event | One-shot | `selah_event_bookmark_verse.caf` | -25 | -9 dBTP | No duck, 100 ms edge fade | Commissioned AMEN-owned |
| `selah_event_prayer_start` | Event | One-shot | `selah_event_prayer_start.caf` | -26 | -10 dBTP | No human vocal source | Commissioned AMEN-owned |
| `selah_event_prayer_end` | Event | One-shot | `selah_event_prayer_end.caf` | -26 | -10 dBTP | No human vocal source | Commissioned AMEN-owned |
| `selah_event_prayer_journal_save` | Event | One-shot | `selah_event_prayer_journal_save.caf` | -25 | -9 dBTP | No duck, 100 ms edge fade | Commissioned AMEN-owned |
| `selah_event_selah_start` | Event | One-shot | `selah_event_selah_start.caf` | -27 | -10 dBTP | Crossfade into bed over 3 s | Commissioned AMEN-owned |
| `selah_event_selah_complete` | Event | One-shot variants | `selah_event_selah_complete.caf` | -27 | -10 dBTP | No alarm envelope, 500 ms tail | Commissioned AMEN-owned |
| `selah_bed_selah_room_tone` | Bed | Seamless loop | `selah_bed_selah_room_tone.caf` | -30 | -6 dBTP | 3 s fade in/out, duck -8 dB | Commissioned AMEN-owned |
| `selah_bed_ancient_jerusalem_courtyard` | Bed | Seamless loop | `selah_bed_ancient_jerusalem_courtyard.caf` | -30 | -6 dBTP | 3 s crossfade, duck -8 dB | Commissioned AMEN-owned |
| `selah_bed_desert_wilderness` | Bed | Seamless loop | `selah_bed_desert_wilderness.caf` | -31 | -6 dBTP | 3 s crossfade, duck -8 dB | Commissioned AMEN-owned |
| `selah_bed_upper_room` | Bed | Seamless loop | `selah_bed_upper_room.caf` | -30 | -6 dBTP | 3 s crossfade, duck -8 dB | Commissioned AMEN-owned |
| `selah_bed_galilee_shoreline` | Bed | Seamless loop | `selah_bed_galilee_shoreline.caf` | -30 | -6 dBTP | 3 s crossfade, duck -8 dB | Commissioned AMEN-owned |
| `selah_bed_monastery_library` | Bed | Seamless loop | `selah_bed_monastery_library.caf` | -31 | -6 dBTP | 3 s crossfade, duck -8 dB | Commissioned AMEN-owned |
| `selah_bed_quiet_chapel` | Bed | Seamless loop | `selah_bed_quiet_chapel.caf` | -31 | -6 dBTP | 3 s crossfade, duck -8 dB | Commissioned AMEN-owned |
| `selah_bed_forest_prayer_walk` | Bed | Seamless loop | `selah_bed_forest_prayer_walk.caf` | -30 | -6 dBTP | 3 s crossfade, duck -8 dB | Commissioned AMEN-owned |
| `selah_bed_psalms_quiet_room` | Bed | Seamless loop | `selah_bed_psalms_quiet_room.caf` | -32 | -6 dBTP | 3 s crossfade, duck -8 dB | Commissioned AMEN-owned |
| `selah_bed_revelation_cinematic_space` | Bed | Seamless loop | `selah_bed_revelation_cinematic_space.caf` | -32 | -6 dBTP | 3 s crossfade, duck -8 dB | Commissioned AMEN-owned |
| `selah_bed_sermon_mount_outdoor` | Bed | Seamless loop | `selah_bed_sermon_mount_outdoor.caf` | -30 | -6 dBTP | 3 s crossfade, duck -8 dB | Commissioned AMEN-owned |

## Haptic Pattern Catalog

| Haptic ID | Renderer | Pattern |
|---|---|---|
| `soft_tap` | UIKit | `UIImpactFeedbackGenerator(style: .soft)`, intensity 0.55. |
| `light_impact` | UIKit | `UIImpactFeedbackGenerator(style: .light)`, intensity 0.45. |
| `micro_pulse` | UIKit | `UISelectionFeedbackGenerator.selectionChanged()`. |
| `layered_light_impacts` | Core Haptics | Four transient events at 0, 60, 130, 210 ms; intensity 0.28, sharpness 0.2. |
| `gentle_pulse` | Core Haptics | Continuous 450 ms event; intensity 0.22, sharpness 0.08. |
| `release_pulse` | Core Haptics | Continuous 600 ms event, then a tiny transient release. |
| `long_soft_vibration` | Core Haptics | Continuous 1.4 s event; intensity 0.16, sharpness 0.02. |

Core Haptics gates on `CHHapticEngine.capabilitiesForHardware().supportsHaptics` and `UserDefaults("hapticsEnabled")`. Unsupported devices and disabled haptics degrade to audio-only only when audio is allowed; if audio is muted or assets are unavailable, the result is silence.

## Technical Notes

Incidental event audio uses `AVAudioSession.Category.ambient` with `.mixWithOthers`, respecting the mute switch and other audio. Immersive Selah and Sacred Spaces use `.playback` only after explicit entry, with `.mixWithOthers` and `.duckOthers`, and they deactivate on suspension or interruption.

The audio engine starts lazily, stops on route/interruption changes, and deactivates the session on `suspend()`. Production implementation must add real crossfade automation and verified seamless loop scheduling before enabling the flag.

The Signature Selah Moment remains: UI fades, motion slows, notifications disappear, ambient sound enters gently, a real Bible page opens, then nothing happens. No AI, feed, prompts, streaks, or generated suggestions may be attached to this moment.

## Personal Spiritual Audio Anchors

Persistence shape:

| Field | Type | Notes |
|---|---|---|
| `userID` | String | Private owner. |
| `verseRef` | String | Canonical verse reference key. |
| `anchorToneID` | String | Stable subtle tone ID selected from approved anchor assets. |
| `updatedAt` | Timestamp | Maintenance only; not displayed as activity. |

Firestore path: `users/{uid}/selahAudioAnchors/{normalizedVerseRef}`.

Guardrails: no counts, streaks, badges, "anchor of the day", leaderboards, sharing prompts, or analytics optimized around anchor use. Anchors are memory aids only.

## Reverence Review

| Drift Risk | Guardrail |
|---|---|
| Anchor tones could become collectibles. | Private per-user mapping only; no counts, rarity, recommendations, or daily prompts. |
| Completion sounds could feel like alarms or achievement cues. | Single soft bell/chime/note, low LUFS, no sharp transient, no celebratory stack. |
| Time profiles could become personalization bait. | Profiles only reduce or soften density, EQ, timing, and gain; no novelty rotation. |
| Sabbath mode could become a themed event. | It only calms and reduces interruptions; no special rewards or visual campaign. |
| Deep-reflection decay could be used to measure session retention. | It is local shaping only; no analytics event and no UI callout. |
| Sacred Spaces could become entertainment content. | Framed as historically inspired contextual environments for Scripture, prayer, and study. |
| Page turns could become decorative UI feedback. | They remain restrained, swipe-synced, and haptic-paired; silence remains acceptable. |

## Build Readiness

Code is scaffolded and feature-flagged OFF. Do not flip `selah_sensory_layer_enabled` until assets are produced, loudness-normalized, accessibility reviewed, and loop/crossfade QA is complete. A human should add any new files to the Xcode project membership and run the canonical build.

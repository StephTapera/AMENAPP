# AIL_CONTRACTS.md — Phase 1 Contract Freeze + Reuse Inventory

Branch `feature/ail` · 2026-06-09 · **Contracts FROZEN (additive-only).**
Source of truth: `functions/ail/ail.contracts.ts`. Routing delta applied to `functions/router/amenRouting.config.js`.

## What was frozen
- **`functions/ail/ail.contracts.ts`** — `A11yTask` (12), `ReadingLevel`, `A11yProvenance` (+`toONEProvenanceClass` family map), `SensitivityTopic`, `CaptionStyle/CultureNote/CaptionTrack/CaptionCue/ImageDescription`, `A11yProfile` (+allowed-keys, defaults), `A11yTransformResult`, `FIRESTORE_PATHS`, `AIL_ROUTING_ADDITIONS`, `SpeechProvider`, `FEATURE_FLAGS` (reconciled), and enforcement helpers (`assertNoForbiddenProfileFields`, `assertClaudeOnly`, `assertNoUserFacingTierGate`, `failsOpen`).
- **`amenRouting.config.js`** — 10 new task routes (validated: 55 total routes, providers resolve, Claude-only tasks have no fallover, `explain_scripture` fail_closed, all others fail-open `degrade`).

## Decisions baked in (your four calls)
1. `describe_image` / `summarize_audio` are **new callModel tasks** (gemini/geminiPro), riding existing NeMo guards. No engines built.
2. **Reuse is mandatory** — the delta table below is the contract for Phase 2. Building any parallel accessibility component = failure.
3. Repo paths: contracts under `functions/ail/`; routes in real JS config; `ailTransform` callable goes **gen1 in `functions/index.js`**; `A11yProvenance` net-new but maps into the `ONEProvenanceClass` family.
4. Captions = **subcollection under the parent media doc** (`posts/{postId}/mediaMeta/{mediaId}/captions/{id}`), inheriting parent read perms; rules deny-by-default, server-write only.

---

## REUSE INVENTORY + DELTA (build ONLY the right column)

| Cap | Already shipped (EXTEND in place) | Delta to build |
|---|---|---|
| **C1 Translate** | `BereanContextualTranslationEngine`, `PostTranslationService`, `CommentTranslationBridge`, `PrayerRoomTranslationService`, `BereanLiveTranslationBar`, `LiquidGlassTranslationCapsule`, `TranslationModels/Service/UIComponents`, CF `translateMultilingualContent`, prefs `translationPreferences/{uid}` | `CultureNote` idiom/scripture-phrase tooltips; consistent under-text pill + provenance label + "View original"; reading-level handoff |
| **C2 Reading Level** | flag `readabilityLayerEnabled`; CF `transformContent.ts` (simplify/summarize/explain) | Level slider (Original/Simple/VerySimple/Summary) → `simplify` task; **scripture-lock** (never re-level verse); explanation-alongside panel labeled "Explanation — not Scripture" |
| **C3 Tone Hints** | `ToneCheckerSheet`, route `comment_coach` | `tone_hint` task; on-demand hedged "may read as…"; suppress on Guardian-flagged; flag `ailToneHintsEnabled` (NEW, default OFF) |
| **C4 Captions** | `LiveCaptionOverlay`, `AmenLiveCaptionsOverlay` (already honor Reduce Motion/Transparency), `AmenCaptionEditorView`, `PerMediaCaptionComposer`, `AmenSyncCaptionService`, CF `validateMediaCaptions`, `mediaMeta` storage | `CaptionStyle` controls (size/bg/contrast/speed/placement) → profile; **`SpeechProvider`** adapter (on-device live / server recorded); captions subcollection write; creator-edit → provenance flip |
| **C5 Image Desc/Alt** | route `media_alt_text`, `mediaMeta.altText`, `ChurchNotesPhotoOCR` | `describe_image` task (NEW route); generate-and-edit on upload + long-press "Describe"; identity/facial guardrail; provenance flip on edit |
| **C6 Audio/Video Summary** | routes `video_summary`/`quick_summary`, `WhisperVoiceService`, `transformContent` | `summarize_audio` task (NEW route); summary card (main point/action/tone); mount on video + voice surfaces |
| **C7 Voice Nav** | — (Berean voice is Q&A, not nav) | **Net-new**: command map (open comments/summarize/reply/save/translate); flag `ailVoiceNavEnabled` |
| **C8 Comment Intent** | `SmartCommentService` (quality only) | **Net-new** picker: Encourage/Ask/Pray/Support/Disagree-kindly/Save in comment composer |
| **C9 Larger Targets** | `AmenSimpleModeService.fontScale` (type only) | **Net-new**: `largerTouchTargets` setting + **on-device** calibration (no network); apply min tap target |
| **C10 Reply-with-Care** | `ThinkFirstGuardrailsService`, `comment_coach`, `ToneCheckerSheet` | `reply_care_check` task (NEW route); pre-send nudge, dismissible; **zero NeMo path** |
| **C11 Cooldown Assist** | `comment_coach`/`prayer_rewrite` | `cooldown_rewrite` task (NEW route); suggested rewrite, **never blocks** |
| **C12 Safety Filter** | — | **Net-new**: `sensitivity_classify` task; user-policy blur + tap-to-reveal; **crisis-help never blurred**; `sensitivityFilters` in profile |
| **C13 Calm Mode** | `AmenSimpleModeService` (Firestore-synced), `AmenSimpleModeView/SettingsSection`, `SelahCalmEnhancements`, flag `naturalModeEnabled` | **EXTEND SimpleMode** (do NOT rebuild): focus-card one-at-a-time, hide counts/badges/chrome, ensure Reduce Motion/Transparency |
| **C14 Re-entry** | `NotificationCoordinator` (no re-entry yet) | **Net-new**: `reentry_summary` task; qualitative, computed at read time; hook post-dismiss; **NO counts** |

**Spine (A2):** unified `ailTransform` callable (gen1, `functions/index.js`) wrapping existing `transformContent`/`refineTranslation`/`translateMultilingualContent` where possible — validates task, routes via `callModel`, enforces Claude-only, stamps provenance, caches to `transformCache` (DM skipped), honors crisis-bypass.
**Settings (A7):** `users/{uid}/settings/a11yProfile` + forbidden-field-denying rules; extends `AmenSimpleModeSettingsSection`.

## Phase 2 ownership (disjoint, extend-in-place)
- **A2** backend: `functions/ail/ailTransform.js` + `transformCache` + wire into `index.js`. *Forbidden:* UI, moderation, rules.
- **A3** language (C1/C2): extend translation stack + reading-level + scripture-explanation panel. *Forbidden:* Selah verse-render internals (mount via existing extension points).
- **A4** perception (C4/C5/C6): extend caption overlays/editor + alt-text flow + summary card + `SpeechProvider`. *Forbidden:* media pipeline internals, Storage rules.
- **A5** interaction (C7/C8/C9/C13): voice nav + intent picker + touch targets + **extend** SimpleMode for Calm. *Forbidden:* network writes of motor data, feed query logic.
- **A6** protection (C10/C11/C12/C14): care/cooldown nudges + safety filter + re-entry. *Forbidden:* NeMo/Guardian code, anything that blocks a send.
- **A7** settings: a11yProfile + setup flow + rules PR. *Forbidden:* other agents' dirs.

## Verification gates already enforced at contract layer
- ✅ Fail-open vs fail-closed encoded per task; `explain_scripture` is the sole fail-closed AIL route.
- ✅ Claude-only tasks have `chain:["claude"]` (validated, no fallover leak).
- ✅ Forbidden-profile-field denial + no-user-facing-tier-gate guards exported for A8 to call/grep.
- ✅ Captions rules contract + DM-never-cached constant frozen.

**Held for your checkpoint:** function deploy (`--project amen-5e359`). All build/wire/verify runs first.

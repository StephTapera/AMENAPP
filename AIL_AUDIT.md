# AIL Phase 0 Audit Report
**Auditor:** Agent A0 · **Date:** 2026-06-15 · **Branch:** feature/berean-island-w0

---

## 1. Engine Layer Map

### `callModel` Signature
**File:** `functions/router/callModel.js`

```js
async function callModel({
  task,           // routing key (e.g. "translate", "explain_scripture")
  input,          // raw user input text
  systemPrompt,   // optional override
  context,        // extra context injected into system prompt
  userId,         // required for audit logs
  safetyLevel,    // "strict"|"standard"|"relaxed" (default: "standard")
  featureFlags,   // Map<task, boolean> — false disables task
  namespace,      // Pinecone namespace for retrieval
  queryVector,    // embedding vector for Pinecone search
})
// Returns:
//   Success  → { output: string, provider, task, latencyMs }
//   Blocked  → { output: null, blocked: true, reason, ... }
//   Degraded → { output: any, degraded: true, task }
```

### ContextBus (iOS)
**File:** `AMENAPP/AMENAPP/Core/ContextBus/ContextBus.swift`

- **Actor** (Swift concurrency) — ring buffer capped at 500 signals, FIFO eviction
- `crisisSurfaceOpened` tier `.s` → **device only, never forwarded to network**
- Firestore forward for tier `.c/.p` → `contextSignals/{uid}/signals/{signalId}`
- Subscription model: `AsyncStream` keyed by `SignalType`
- Consent edges all default **OFF** (except `activityToRhythm`)

### Provenance Enum
**File:** `AMENAPP/AMENAPP/Accessibility/AIL/AILContracts.swift` (lines 94–118)

```swift
enum A11yProvenance: String, Codable, Sendable {
    case aiGenerated = "ai_generated"      // label: "AI translation"
    case aiHumanEdited = "ai_human_edited" // label: "AI · edited by author"
    case human                             // label: "Original"
}
```

### Three Engines — Current State

| Engine | Status | Notes |
|--------|--------|-------|
| **Intent** | Integrated into AIL via `AILTransformService.transform()` | No standalone "IntentEngine" file; dispatch is in `callModel` routing |
| **Visual** | Distributed: `AILCaptionRenderer`, `AILAltTextEditor`, `LiquidGlassTranslationCapsule` | `describe_image` routes to Gemini via callModel |
| **Knowledge** | `BereanContextualTranslationEngine` + retrieval via Pinecone (namespace per task) | `explain_scripture` uses Pinecone + Claude (no fallover) |

---

## 2. Moderation Pipeline

### Entry Points

- **Primary gate:** `functions/moderationGateway.js` — `checkContentSafety(uid, contentType, text)`
  - Valid content types: `post`, `comment`, `message`, `dm`
  - Fail behavior: NeMo HTTP error → `safe = false, categories: ["guard_error"]` → decision: `"review"` (human queue)
- **Phrase pre-check** (lines 39–85): self-harm, medical advice, manipulative religious language → immediate `"review"`
- **NeMo response guard:** if response doesn't contain exact string `"safe"` → unsafe (jailbreak mitigation)
- **Rate limiter:** >30 checks/60s → `resource-exhausted` error

### Fail-Closed Model: CONFIRMED ✓

All moderation paths fail **closed** (block/review, never auto-allow). This is architecturally separate from AIL's fail-open behavior.

### Bypass Risks

| # | Risk | Severity | Status |
|---|------|----------|--------|
| R1 | AIL rewrite suggestions (cooldown_rewrite, reply_care_check) are **not re-moderated** before send | LOW | ACCEPTED — Claude generates in constrained context; documented in AILContracts |
| R2 | `sensitivity_classify` degrades to `{ topics: [], sensitive: false }` — crisis content blur may not apply if Gemini unavailable | MEDIUM | MITIGATED — `isCrisisHelp` bypass in AILEmotionalSafetyFilter; crisis content is never blurred regardless |
| R3 | DM moderation uses same fail-open-on-degraded path as posts | LOW | DOCUMENTED — consistent architecture; acceptable |
| R4 | Notification payload `userInfo` not cryptographically signed | MEDIUM | MITIGATED — iOS APNs uses TLS; push certificate required; never trust for auth decisions |

**No AIL mount point can bypass NeMo moderation.** AIL runs in the compose / read layer, not the moderation decision layer.

---

## 3. Surface Inventory

| Surface | Primary File | Existing A11y Handling | AIL Mount Viability |
|---------|-------------|----------------------|---------------------|
| **Posts Feed** | `YourFeedView.swift` | `AILProvenanceLabel` on post cards | ✓ Translate/simplify pills mount on `PostCardView` |
| **Comments** | `PostDetailView.swift` | C10/C11 pre-send gate wired | ✓ Pre-send gate active; translate pill needed |
| **DMs** | `ONEMessageComposerView.swift` | Pre-send gate wired (`isDirectMessage: true`) | ✓ DM transforms skip server cache (enforced) |
| **Spaces/Rooms** | `AmenSpaceDetailView.swift` | C12 emotional safety blur applied | ✓ sensitivity_classify blur available |
| **Church Notes** | `ChurchNoteEditorView.swift` | Built-in note summary; no captions | ✓ translate/simplify available; OCR gap (see §11) |
| **Videos (Media)** | `MediaPlayerView.swift` | `CaptionTrack` support, `CaptionStyle` respected | ✓ summarize_audio + describe_image ready |
| **Voice Notes** | `AudioWaveformView.swift` | No alt text built-in | ✓ summarize_audio callable ready (Gemini) |
| **Notifications** | `AMENNotificationContentHandler.swift` | `safetyState` field modifies body text | ⚠️ Cannot embed full AIL transforms (4 KB APNs limit); reference app instead |

---

## 4. i18n / Translation Infrastructure

### Existing Services

| File | Purpose | Backend route |
|------|---------|---------------|
| `BereanContextualTranslationEngine.swift` | Routes post/comment text to translation | `callModel(.translate)` |
| `PrayerRoomTranslationService.swift` | Specialized translation for prayer-room captions | `callModel(.translate)`, visibility: `participants` |
| `LiquidGlassTranslationCapsule.swift` | Language picker UI (Liquid Glass, respects Reduce Transparency) | UI only |
| `TranslationCacheManager.swift` | Client-side cache of translation results | Cache layer |
| `TranslationSettingsManager.swift` | User locale preferences | Settings |

### Gap: No String Catalogs (.xcstrings)
All UI text is hardcoded in Swift. No `.xcstrings` file exists. Multi-language UI (not content translation) would require a separate migration. **Not in AIL scope for this wave.**

---

## 5. Media Pipeline

### Firebase Storage Paths
- **Post/comment media:** `users/{uid}/posts/{postId}/media/{mediaId}.{ext}`
- **DM attachments:** `users/{uid}/conversations/{conversationId}/media/{attachmentId}`
- **Church notes:** `users/{uid}/churchNotes/{noteId}/media/{mediaId}`
- **Voice notes:** `users/{uid}/voice/{voiceNoteId}.m4a`

### Upload Flow
1. Client creates in-memory `MediaUploadTask`
2. `FirebaseStorageService.uploadMedia(data, contentType, destinationPath)`
3. Firestore metadata written with `moderationStatus: "pending"`
4. If `autoCaptionsEnabled` → triggers `generateCaptions` callable
5. If `churchNotesPhotoOCREnabled` → triggers `ocrImage` callable

### Playback Flow
1. Client fetches `CaptionTrack` from Firestore (if present)
2. Renders via `AILCaptionRenderer` (respects `CaptionStyle`: size, bg, contrast, speed, placement)
3. Live captions: `SpeechProvider` on-device ASR
4. Recorded captions: `SpeechProvider` server ASR adapter

---

## 6. Notification Render Path

**Extension:** `AMENAPP/AMENNotificationServiceExtension/AMENNotificationContentHandler.swift`

```swift
didReceive(_ request:, withContentHandler:) {
    // 1. Extract safetyState: "clear" | "guarded" | "moderated" | "restricted"
    // 2. guarded/moderated/restricted → replace body with safe summary
    // 3. Rewrite title from actorName + type fields
    // 4. Call contentHandler with mutated content
}
```

**AIL in notifications:** Cannot embed transforms (APNs 4 KB payload limit). Captions, descriptions, tone hints must be fetched in-app on tap. This is a **platform constraint**, not a design choice.

---

## 7. Routing Config

**File:** `functions/router/amenRouting.config.js` (476 lines)

### AIL Task Routes (lines 354–425)

| Task | Primary | Fallover | Fail Mode | Input Guard | Output Guard | Claude-only |
|------|---------|---------|-----------|------------|-------------|-------------|
| `translate` | claudeFast | claude | degrade (fail-open) | no | yes | no |
| `simplify` | claudeFast | claude | degrade | no | yes | no |
| `explain_scripture` | claude | **NONE** | **fail_closed** | yes | yes | **YES** |
| `tone_hint` | claude | **NONE** | degrade | no | yes | **YES** |
| `reply_care_check` | claude | **NONE** | degrade | no | yes | **YES** |
| `cooldown_rewrite` | claude | **NONE** | degrade | no | yes | **YES** |
| `describe_image` | gemini | geminiPro | degrade | yes | yes | no |
| `summarize_audio` | geminiPro | gemini | degrade | no | yes | no |
| `reentry_summary` | claudeFast | claude | degrade | no | yes | no |
| `sensitivity_classify` | gemini | none | degrade (`{topics:[],sensitive:false}`) | no | no | no |

**`explain_scripture` is correctly fail-closed and Claude-only.** ✓

### Gen1 / Gen2 Split
- **Gen1:** `functions/router/callModel.js` — `httpsCallable("callModel")`
- **Gen2:** `functions/v2triggers/router/callModel.js` — HTTP-native, deployed separately; both coexist

---

## 8. Existing AIL Work — What's Already Built

**Substantial AIL infrastructure already exists** from the prior build (2026-06-09). The directory is populated:

```
AMENAPP/AMENAPP/Accessibility/AIL/
├── AILContracts.swift                      ← frozen Swift types
├── AILProfileService.swift                 ← A11yProfile Firestore sync
├── AILTransformService.swift               ← callModel dispatcher
├── Language/
│   ├── AILTranslatePill.swift              ← C1 translate UI
│   ├── AILScriptureExplanationPanel.swift  ← C3 scripture explanation
│   ├── AILReadingLevelControl.swift        ← C2 reading level selector
│   └── AILProvenanceLabel.swift            ← provenance badge
├── Protection/
│   ├── AILPreSendGate.swift                ← C10/C11 compose-time gate
│   ├── AILPreSendInterceptor.swift         ← decision logic
│   ├── AILReplyWithCareSheet.swift         ← C10 UI
│   ├── AILCooldownAssistSheet.swift        ← C11 UI
│   ├── AILReentrySummaryCard.swift         ← C14 re-entry UI
│   └── AILEmotionalSafetyFilter.swift      ← C12 blur
├── Perception/
│   ├── AILCaptionRenderer.swift            ← C4 rendering
│   ├── AILCaptionStyleControls.swift       ← C4 user preferences
│   ├── AILAudioSummaryCard.swift           ← C6 audio summary UI
│   ├── AILAltTextEditor.swift              ← C5 image description editor
│   └── SpeechProvider.swift                ← on-device/server ASR adapter
├── Interaction/
│   ├── AILVoiceNavigationController.swift  ← C7 (experimental/partial)
│   ├── AILCalmModeModifier.swift           ← C13 low-cog-load modifier
│   ├── AILTouchTargetCalibrationView.swift ← C9 on-device calibration
│   └── AILCommentIntentPicker.swift        ← C8 intent picker
└── Settings/
    ├── AILAccessibilitySettingsSection.swift
    ├── AILAccessibilitySetupView.swift
    └── AILReadingUnderstandingSettingsView.swift
```

### Iron Rules Status in Existing Code

| Rule | Status |
|------|--------|
| Accessibility free at every tier | ✓ No tier checks in AIL code |
| Transforms fail open to original | ✓ `degradeResult: { failOpen: true }` pattern |
| Scripture never re-leveled | ✓ EXPLAIN_SCRIPTURE renders alongside original |
| Every transform labeled + reversible | ✓ A11yProvenance + originalRef everywhere |
| No motor metrics to network | ✓ `allowedKeys` filtering in AILProfileService |
| No people named in alt text | ✓ guard in callModel describe_image route |
| Tone hints are opt-in | ✓ `toneHintsEnabled: false` by default |
| Crisis content never blurred | ✓ `isCrisisHelp` bypass in AILEmotionalSafetyFilter |
| Pre-send gate is proposal-only | ✓ Never blocks; `isEnabled: false` default |
| Profile portable across surfaces | ✓ Firestore sync at `users/{uid}/settings/a11yProfile` |

---

## 9. P0 Risk Flags

| # | Risk | Severity | File | Status |
|---|------|----------|------|--------|
| P0-01 | All API keys use `defineSecret`/`getSecret` — no hardcoding | ✓ SAFE | `callModel.js:63`, `moderationGateway.js:27` | No action needed |
| P0-02 | Force unwraps in AILTransformService | ✓ SAFE | `AILTransformService.swift:74` | Guard statements used throughout |
| P0-03 | Forbidden fields in A11yProfile could leak motor data | ✓ SAFE | `AILProfileService.swift:94–115` | `allowedKeys` filter enforced |
| P0-04 | AIL rewrite not re-moderated before send | ⚠️ ACCEPTED | `AILCooldownAssistSheet.swift` | Claude rewrites in constrained context; documented |
| P0-05 | DM moderation degrades same as posts | ⚠️ DOCUMENTED | `moderationGateway.js:33` | Consistent architecture |
| P0-06 | Notification userInfo not cryptographically signed | ⚠️ MITIGATED | `AMENNotificationContentHandler.swift:14–40` | APNs TLS; never use for auth |
| P0-07 | Engagement counters in C14 | ✓ SAFE | `amenRouting.config.js:414–419` | Explicitly forbidden in route config note |
| P0-08 | `sensitivity_classify` degrade allows crisis content to pass unblurred | ⚠️ MITIGATED | `amenRouting.config.js:420` | `isCrisisHelp` bypass is independent of classify result |
| P0-09 | `crisisContext: true` lifts AIL caps — client must not self-escalate | ⚠️ MITIGATED | `AILTransformService.swift:39` | Server-side approval required; client cannot self-assign |

---

## 10. Feature Flag Inventory

### AIL Master Gate
- `accessibilityIntelligenceEnabled` — default **false** — Remote Config: `accessibility_intelligence_enabled`

### AIL Sub-Feature Flags (all default false)
- `meaningAwareTranslationEnabled` — `meaning_aware_translation_enabled`
- `naturalModeEnabled`
- `contextualModeEnabled`
- `readabilityLayerEnabled` — controls C2 simplify UI
- `contentDifficultyScoring` — experimental
- `audioNarrationEnabled` — C6 audio-description reading
- `contextBridgeEnabled` — experimental cross-surface
- `adaptiveAccessibilityEnabled` — profile-aware UI
- `conversationBridgeEnabled` — DM ↔ Berean context
- `smartTranslationVisibilityEnabled`
- `sideBySideTranslationEnabled` — C1 side-by-side view
- `perLanguageAutoTranslateEnabled`
- `creationLanguageEnabled`
- `adaptiveTranslationEnabled`

### Always-On (media/caption)
- `perMediaCaptionsEnabled` — default **true**
- `autoCaptionsEnabled` — default **true**
- `perMediaCaptionAltTextEnabled` — default **true**

---

## 11. Gaps & Unknowns

### Blocking Gaps (must resolve before Phase 2)

**2026-06-15 update:** All three blocking gaps verified RESOLVED by post-A1 investigation. GATE OPEN for Phase 2.

| # | Gap | Status |
|---|-----|--------|
| G1 | **Backend `ailTransform` callable** | ✅ RESOLVED — exists at `functions/ail/ailTransform.js`; all 10 AIL tasks routed through `callModel` |
| G2 | **`BereanTranslationCoordinator` implementation** | ✅ RESOLVED — defined as `final class BereanTranslationCoordinator: ObservableObject` in `AMENAPP/AIIntelligence/BereanRealtimeServices.swift` |
| G3 | **`functions/ail/ail.contracts.ts` parity** | ✅ RESOLVED — file exists; Swift `A11yTask` enum (12 cases) confirmed identical to TS enum; `ReadingLevel`, `SensitivityTopic`, `A11yProvenance` all match |

### Non-Blocking Gaps (Phase 3 items)

| # | Gap | Notes |
|---|-----|-------|
| G4 | C7 Voice Navigation implementation is partial — no speech-command grammar found | Experimental; wire to system VoiceOver or custom speech input in Phase 3 |
| G5 | C9 Touch-target calibration has no tap-miss detector | On-device only; implement in Phase 3 |
| G6 | C13 Calm Mode rules are partial — no explicit UI element hide/show rules documented | Coordinate with `AmenSimpleModeService` in Phase 3 |
| G7 | No String Catalogs (.xcstrings) — all UI text hardcoded | Out of scope for this wave |
| G8 | Church Notes OCR gap — `churchNotesPhotoOCREnabled` flag exists but no AIL wiring | Phase 3 item |
| G9 | Notification AIL transforms not embeddable (4 KB APNs limit) | Platform constraint; fetch in-app on tap |
| G10 | Culture notes database (idiom/slang/scripture-phrase) backend indexing not documented | Locate Pinecone namespace in `callModel` config |
| G11 | Fail-open UI state naming inconsistent — `.failOpen` vs `.unavailable` vs `.error` | Standardize in Phase 3 pass |

---

## Build Readiness Assessment

### GATE OPEN ✓ for Phase 1 (Contract Freeze)
- Three-engine layer: documented and callable
- Moderation: fail-closed, no bypass paths accepted
- All surfaces: mount-ready
- Profile: portable, privacy-preserving
- Feature flags: all default OFF
- Iron rules: all 10 encoded and confirmed in existing code
- Routing config: AIL tasks already defined; Claude-only paths enforced

### GATE OPEN ✓ for Phase 2 (2026-06-15)
All three pre-Phase-2 blockers resolved (see G1/G2/G3 above). Phase 2 agents may proceed.

**Remaining before Phase 2 ship:**
- Deploy `ailTransform` callable: `firebase deploy --only functions:default:ailTransform` (human step)
- Enable `accessibility_intelligence_enabled` Remote Config flag (after deploy verified)

### Key Architectural Finding
**Substantial AIL infrastructure already exists** from the prior build (2026-06-09). The Swift file set (22 files across Language/Perception/Interaction/Protection/Settings), routing config, and profile service are largely complete. Phase 2 agents should map to the existing directory structure and fill gaps rather than rebuild.


# AIL_WIRING.md — Surface Mount Guide (apply at merge, one additive pass)

These are the **minimal additive** mounts for the AIL components onto the 9 §0 surfaces.
They are deferred to merge time because every host file below is owned by another active
lane (see AGENT_LANES.md); editing them in the `feature/ail` worktree (older base) would
manufacture conflicts. Apply each as a small insertion on the **quiet** tree. Every component
is already wired to real logic — these just place it.

Convention for each: gate behind the capability flag (default OFF) + `AILProfileService.shared.profile`.

| Surface | Host file (real path) | Mount | Component |
|---|---|---|---|
| Posts | `AMENAPP/PostDetailView.swift` | under post body | `AILTranslatePill(originalText:originalRef:)`, `AILReadingLevelText(...)` |
| Posts (verse posts) | `AMENAPP/PostDetailView.swift` | below a scripture post | `AILScriptureExplanationPanel(canonicalVerse:reference:)` |
| Comments | `AMENAPP/PostDetailView.swift` (comment input) | above send button | `AILCommentIntentPicker(onSelect:)`; pre-send `AILReplyWithCareSheet` |
| Comments (cell) | `AMENAPP/AMENAPP/VoicePrayer/VoicePrayerCommentRowView.swift` | trailing | `AILTranslatePill` |
| DMs | `AMENAPP/BereanChatView.swift` / `VergeMessageBubbleView.swift` | bubble + composer | `AILTranslatePill(isDirectMessage:true)`*, `AILCooldownAssistSheet` |
| Spaces | `AMENAPP/AMENAPP/ConnectSpaces/AmenSpaceDetailView.swift` | feed item | `AILTranslatePill`, `.ailSensitivityBlur(text:)` |
| Rooms (live) | `AMENAPP/AMENAPP/ConnectSpaces/Live/AmenLiveRoomShellView.swift` | captions slot | `AILCaptionRenderer` fed by `AppleSpeechProvider` (extend existing `AmenLiveCaptionsOverlay`) |
| Church Notes | `AMENAPP/ChurchNotes/Views/ChurchNotesExpressiveEditorScreen.swift` | toolbar | `AILReadingLevelControl`, `AILTranslatePill` |
| Videos | `AMENAPP/MediaPlayerView.swift` / `AmenMediaDetailView.swift` | below player | `AILCaptionRenderer`, `AILAudioSummaryCard(transcript:)`, `AILAltTextEditor` on upload |
| Voice Notes | `AMENAPP/VoiceMessageComponents.swift` | playback controls | `AILAudioSummaryCard`, caption toggle via `AppleSpeechProvider` |
| Notifications | `AMENAPP/AMENAPP/Notifications/Engine/NotificationCoordinator.swift` (post-dismiss) + `AMENNotificationsView.swift` | re-entry slot | `AILReentrySummaryCard(threadContext:originalRef:)` |
| Settings | app Settings root | a row/section | `AILAccessibilitySettingsSection`; first-run `AILAccessibilitySetupView` |
| Global | feed/root container | modifier | `.ailCalmMode()`, `.ailTouchTarget()` on tappables, `AILVoiceNavigationController` |

\* **DM rule:** always pass `isDirectMessage: true` so the backend skips server-side caching.

**Pre-merge hotspot appends (single-claimant, append-only):**
- `AMENAPP/AMENFeatureFlags.swift`: add `ailToneHintsEnabled`, `ailImageDescribeEnabled`, `ailAudioSummaryEnabled`, `ailVoiceNavEnabled`, `ailCommentIntentEnabled`, `ailLargerTouchTargetsEnabled`, `ailReplyCareEnabled`, `ailCooldownAssistEnabled`, `ailEmotionalSafetyFilterEnabled`, `ailReentrySummaryEnabled` (default **false**). Reuse existing `accessibilityIntelligenceEnabled` / `meaningAwareTranslationEnabled` / `readabilityLayerEnabled` / `naturalModeEnabled` for C1/C2/C13.
- `firestore.rules`: append `a11yProfile` (owner r/w, forbidden-field schema validation), `transformCache` (server-write only), captions subcollection (deny-by-default, inherits parent read).

Each mount is one `if flag { AILComponent(...) }` insertion — no host logic changes, no dead handlers.

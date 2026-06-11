# Music Content Layer — Total Control Wiring Certificate
# Branch: safety-hardening  |  Date: 2026-06-11  |  Gate: ff_music_content_layer (default OFF)

## Interactive Surfaces Inventory

| Surface | File | Interactions | Wired to? | Status |
|---|---|---|---|---|
| Attachment card play button | LiquidGlassAttachmentCard.swift | onPlay callback | Caller supplies | WIRED — caller-injectable ✓ |
| Attachment card save button | LiquidGlassAttachmentCard.swift | onSave callback | Caller supplies | WIRED — caller-injectable ✓ |
| Attachment card share button | LiquidGlassAttachmentCard.swift | onShare callback | Caller supplies | WIRED — caller-injectable ✓ |
| Music picker tab selection | MusicAttachmentPickerView.swift | selectedTab @State | Internal | WIRED — internal state ✓ |
| Music picker search | MusicAttachmentPickerView.swift | searchText onChange | Mock data filter | WIRED — mock filter ✓ |
| Music picker row select | MusicAttachmentPickerView.swift | onSelect callback | Caller supplied | WIRED — caller-injectable ✓ |
| Suggestion bar chip tap | SmartComposerIntentService.swift | onChipTap callback | Caller supplied | WIRED — callback ✓ |
| Intent pill (display only) | SmartComposerIntentService.swift | accessibility read | None | WIRED — read-only ✓ |
| Church note expand/collapse | ChurchNoteShareCard.swift | isExpanded @State | Internal | WIRED — internal state ✓ |
| Church note save | ChurchNoteShareCard.swift | Save button | Unimplemented | HONESTLY-DEFERRED — Stage-2: wire to PostService or ChurchNotesService |
| Church note share | ChurchNoteShareCard.swift | Share button | Unimplemented | HONESTLY-DEFERRED — Stage-2: wire to ShareService |
| Church note comment | ChurchNoteShareCard.swift | Comment button | Unimplemented | HONESTLY-DEFERRED — Stage-2: wire to CommentsView |
| Resource shelf filter chips | ProfileResourceShelf.swift | selectedCategory @State | Internal | WIRED — internal state ✓ |
| Resource shelf sort | ProfileResourceShelf.swift | @State sort selection | Internal | WIRED — internal state ✓ |
| Resource shelf Add Resource | ProfileResourceShelf.swift | onAddResource callback | Caller supplied | WIRED — gated isAdmin ✓ |
| Resource shelf item tap | ProfileResourceShelf.swift | Navigation / deeplink | Unimplemented | HONESTLY-DEFERRED — Stage-2: route to ContentDetailView |
| Profile tab bar selection | ProfileResourceTabBar.swift | selectedTab Binding | Caller's @State | WIRED — two-way binding ✓ |
| Comment composer submit | ContextAwareCommentComposer.swift | onSubmit callback | Caller supplied | WIRED — caller-injectable ✓ |
| Comment composer cancel | ContextAwareCommentComposer.swift | onDismiss callback | Caller supplied | WIRED — caller-injectable ✓ |
| Comment rewrite button | ContextAwareCommentComposer.swift | applyRewrite() | Internal @State | WIRED — replaces text ✓ |
| Faith graph loadRelated | FaithMusicGraphService.swift | loadRelated() async | In-memory seed | WIRED — session-only; HONESTLY-DEFERRED persistence → Stage-3 Firestore |
| Faith graph search | FaithMusicGraphService.swift | search() async | In-memory filter | WIRED — session-only ✓ |
| Faith graph node tap | FaithMusicRecommendationRow.swift | onNodeTap callback | Caller supplied | WIRED — callback ✓ |
| Rights access check | RightsMonetizationService.swift | checkAccess() | Policy strings | WIRED — synchronous ✓ |
| Music platform compliance | RightsMonetizationService.swift | checkMusicPlatformCompliance() | MusicPlatformRuling | WIRED — ruling constants ✓ |
| MonetizationStatusPill display | RightsMonetizationService.swift | visibilityBadge() | Policy string | WIRED — display only ✓ |
| ResourceAccessBadge display | RightsMonetizationService.swift | checkAccess() result | ContentAccessResult | WIRED — display only ✓ |
| Listening room join | ListeningDiscussionRoomView.swift | joinRoom() | Mock Firestore | HONESTLY-DEFERRED — mock sync; Stage-3: LiveKit wiring + Auth+AppCheck gate |
| Listening room leave | ListeningDiscussionRoomView.swift | leaveRoom() | Mock state clear | WIRED — clears state ✓ |
| Listening room send message | ListeningDiscussionRoomView.swift | sendMessage() | Local @Published | WIRED — local only; HONESTLY-DEFERRED real-time → Stage-3 |
| Listening room submit vote | ListeningDiscussionRoomView.swift | submitVote() | Local poll state | WIRED — local only ✓ |
| Listening room end (host) | ListeningDiscussionRoomView.swift | endRoom() | Mock state | WIRED — sets state; HONESTLY-DEFERRED backend → Stage-3 |
| Room card join/replay | ListeningDiscussionRoomView.swift | onJoin callback | Caller supplied | WIRED — callback ✓ |
| Pulse digest refresh | AmenPulseDigestService.swift | refreshDigest() | Mock data | HONESTLY-DEFERRED — Stage-3: call PulseService.fetchDigest() |
| Pulse digest mute source | AmenPulseDigestService.swift | muteSource() | In-memory Set | WIRED — session-only ✓ |
| Pulse digest save item | AmenPulseDigestService.swift | saveItem() | In-memory flag | WIRED — session-only ✓ |
| Pulse digest card expand | AmenPulseDigestCard.swift | @State isExpanded | Internal | WIRED — internal state ✓ |
| Pulse digest item tap | AmenPulseDigestCard.swift | deepLink URL open | URL(string:) guard | WIRED — guarded open ✓ |
| Pulse digest swipe mute | AmenPulseDigestCard.swift | .swipeActions | onMuteSource callback | WIRED — callback ✓ |
| Pulse personalization sheet dismiss | AmenPulseDigestCard.swift | isPresented Binding | Caller's @State | WIRED — binding ✓ |
| Pulse frequency picker | AmenPulseDigestCard.swift | @State frequency | Local only | HONESTLY-DEFERRED — Stage-3: persist to PulsePrefs via PulseService.updatePrefs() |
| Pulse notification toggles | AmenPulseDigestCard.swift | @State toggles | Local only | HONESTLY-DEFERRED — Stage-3: persist to PulsePrefs |
| Composer modifier attach button | MusicContentLayerEntryPoints.swift | showAttachmentPicker | @State toggle | WIRED — shows picker ✓ |
| Composer modifier remove attachment | MusicContentLayerEntryPoints.swift | pendingAttachment = nil | Internal | WIRED — clears state ✓ |
| Comment context banner dismiss | MusicContentLayerEntryPoints.swift | isDismissed = true | Internal | WIRED — one-shot dismiss ✓ |

## Honestly-Deferred Items (Stage-3 backlog)

| Item | Blocker | What's needed |
|---|---|---|
| FaithMusicGraphService persistence | No Firestore schema | `faithGraph/nodes` + `faithGraph/edges` collections; edge weights updated by Cloud Function on engagement events |
| ListeningRoom real-time sync | LiveKit not wired | LiveKit room join via `AmenLivekitLiveRoomProvider` (already in ConnectSpaces); Auth+AppCheck gate on room join callable |
| ListeningRoom auth/AppCheck gate | Room join is UI-only | Add CF `joinListeningRoom` with App Check enforcement; return LiveKit token |
| Pulse Stage-3 integration | PulseService not consumed | Call `PulseService.shared.fetchDigest()` + new CF `getMusicPulseItems` to augment base digest |
| Pulse prefs persistence | No backend write | Call `PulseService.shared.updatePrefs()` on frequency/notification changes |
| Church note save/share/comment | No PostService/CommentsView wiring | Pass through existing `PostService`, `ShareService`, or `CommentsView` |
| Profile resource shelf item tap | No deeplink router | Route to `ContentDetailView` or profile detail via AMEN deeplink system |

## Music Platform Rulings (standing, enforced by RightsMonetizationService)

| Platform | Policy | Enforced by |
|---|---|---|
| MusicKit (Apple Music) | PRIMARY — stream-only via MusicKit API | `MusicPlatformRuling.musicKitPolicy = "stream_only"` |
| Spotify | Unfurl-only (card shows artwork/title only, no audio) | `MusicPlatformRuling.spotifyPolicy = "unfurl_only"` |
| Lyrics | NEVER display, store, cache, or transmit | `MusicPlatformRuling.lyricsPolicy = "never_display"` |
| Licensed content | Display-only (artwork + title + artist + duration) | `MusicPlatformRuling.licensedDisplayPolicy = "display_only"` |
| Verified Clean preview | 30s preview via MusicKit only | `MusicPlatformRuling.verifiedCleanPreviewPolicy = "preview_30s_only"` |

## Feature Flag

- **Gate key:** `ff_music_content_layer`
- **Default:** OFF (false) in all environments
- **Read path:** `RemoteConfig.remoteConfig().configValue(forKey: "ff_music_content_layer").boolValue`
- **Debug override:** `UserDefaults.standard.set(true, forKey: "ff_music_content_layer_debug")`
- **AMENFeatureFlags.swift addition needed (HUMAN step):**
  Add to System 40 section:
  ```swift
  // MARK: - System 40: Music Content Layer
  /// Master gate for Liquid Glass music attachments, church discography shelves,
  /// smart composer intent, context-aware comments, faith+music graph,
  /// listening rooms, rights enforcement, and Pulse music digest.
  /// Default OFF until Stage-3 backend integrations are deployed.
  @Published private(set) var musicContentLayerEnabled: Bool = false
  ```
  And in applyRemoteConfig():
  ```swift
  musicContentLayerEnabled = config["ff_music_content_layer"].boolValue
  ```

## Build Status

- Branch: safety-hardening
- Build: GREEN (0 errors, 0 warnings from MusicContentLayer)
- Files: 14 Swift files in AMENAPP/MusicContentLayer/
- Tests: 26 @Test functions in AMENAPPTests/MusicContentLayer/MusicContentLayerTests.swift
- Docs: AMENAPP/MusicContentLayer/DECISIONS.md

## Dedup Status

No duplicate type definitions remain. Previous collisions (`ModerationWarningBanner`, `ContextPill`, duplicate group registration) were resolved. `RightsPolicy`, `VisibilityPolicy`, `PostIntentType` exist once each in MusicContentContracts.swift.

# Liquid Glass Pattern Map — 2026-05-29
## 8 iOS Reference Patterns → AMEN Call Sites

---

## HIGH-LEVERAGE SINGLE-FILE WINS (do these first)

| File | Change | Patterns covered | Impact |
|------|--------|-----------------|--------|
| `EmptyStateView.swift` | Add 3D glass icon slot + AMEN tint | P6 empty states | Propagates to ALL callers at once |
| `QuickShareSheet.swift` | Extract avatar chip row as reusable component | P7 share sheets | Already built — just propagate to 11 other share sites |
| `AmenContextMenuActionKind` enum + feature flag | Already defined — just apply dark glass styling | P1 context menus | Flag `messagingLiquidGlassContextMenuEnabled` already wired |
| `BereanModelPickerComponents.swift` | Refactor pill+menu into floating top chrome component | P8 chrome bar | Building blocks exist (pill:95, menu:131) |

---

## PATTERN 1 — Dark Glass Long-Press Context Menu
**Reference:** iMessage iOS 19 — dark semi-transparent glass card, icon+text rows, thin dividers

### P0
| File | Line | Current | Action |
|------|------|---------|--------|
| `UnifiedChatView.swift` | 5311 | `.contextMenu` exists (light) | Upgrade to dark glass; add Translate row |
| `PostCard.swift` | 2232, 3709 | Long-press → sheet (no context menu) | Replace sheet with dark glass menu: Save, Copy Link, Report, Delete, Share, Translate |

### P1
| File | Line | Current | Action |
|------|------|---------|--------|
| `PrayerView.swift` | 1402, 4369 | Long-press **disabled** (minimumDuration: .infinity) | Enable + dark glass: Reply, Copy, Report, Delete |
| `LiquidGlassMessagesView.swift` | 371, 431, 461, 483 | Long-press callback — **no menu** | Add dark glass: Reply, Copy, React, Edit (own <15min), Delete, Report |
| `NotificationsView.swift` | 1356, 1376 | `.contextMenu` (light) | Upgrade to dark glass |
| `ChurchNotesView.swift` | 1466, 3066, 5769 | `.contextMenu` (light) | Upgrade to dark glass |
| `BereanChatView.swift` | 1791, 3195 | Custom floating tray | Unify to dark glass pattern |
| `MessagesView.swift` | 1379, 1422, 1972 | `.contextMenu` (light) | Upgrade to dark glass |
| `ThreadDetailView.swift` (Spaces) | 407 | `.contextMenu` (light) | Upgrade to dark glass |
| `SpacesChatView.swift` | 268 | `.contextMenu` (light) | Upgrade to dark glass |

### P2
`DiscussionChannelRow.swift:95`, `TimestampedCommentRow.swift:65`, `QuotePostView.swift:151`, `SmartMediaCarouselView.swift:84`

**Key asset:** `AmenContextMenuActionKind` enum already defines all actions; feature flag `messagingLiquidGlassContextMenuEnabled` at `UnifiedChatView:2784` controls rollout.

---

## PATTERN 2 — Floating Liquid Glass Pill Toolbar
**Reference:** iOS 19 Photos/Files — pill with 3–4 grouped icons, isolated circular action button, floats above content

### P0 (media viewers)
| File | Lines | Current | Pill actions | Isolated |
|------|-------|---------|-------------|---------|
| `FullscreenMediaViewer.swift` | 156–231 | Top-bar chrome + bottom dots | delete, move, share | close |
| `ImmersiveMediaViewer.swift` | 194–248 | Right-edge action rail | amen, comment, share | more |
| `Media/AMENMediaViewer.swift` | 42–76 | Rail + sheet modal | like, comment, share, save | more |

### P1 (composer/editor toolbars)
| File | Lines | Pill actions | Isolated |
|------|-------|-------------|---------|
| `CreatePostView.swift` | 1061–1150 | drafts, media, format, schedule | post |
| `ChurchNotesEditor.swift` | 1571, 1919, 2010 | scripture, format, voice, save-draft | save/done |
| `LivingComposerView.swift` | 57 | note/reminder/prayer/church-note type selectors | create |

### P2
`ChurchNotesBottomActionCapsule.swift:1–37` — already pill-shaped; upgrade material to `LiquidGlassTokens.blurThin`

**Key assets already built:** `AmenLiquidGlassBottomBar`, `GlassTray`, `LiquidGlassComposerBar`, `CreatorBottomRail`

---

## PATTERN 3 — People Search with Avatar Chips + Typeahead
**Reference:** YouTube iOS search — avatar+name+handle rows, bold keyword highlight, link-out arrow

### P0
| File | Lines | Issue |
|------|-------|-------|
| `AmenDiscoverSearchCapsule.swift` | 91–144 | No typeahead at all; plain TextField only |
| `CreatePostView.swift` | 94–96 | `showMentionSuggestions` state + `mentionSuggestions: [AlgoliaUser]` exist — **UI layer entirely missing** |

### P1
| File | Lines | Issue |
|------|-------|-------|
| `DiscoverySearchResultsView.swift` | 309–410 | Avatar rows exist; missing typeahead suggestion layer above results |
| `TagPeopleSheet.swift` | 67–178 | Avatar chips exist (104–152); no typeahead dropdown |

### P2
`SuggestedFollowsSheet.swift:64–99`, `ShareToMessagesSheet.swift:108–126`, `ContactSearchView.swift:77–100`

**Key miss:** Bold keyword highlighting on matched text (e.g. searching "jo" → **Jo**hn) absent everywhere.

---

## PATTERN 4 — AI Feed Curation Bottom Sheet ("Dear algo")
**Reference:** Threads — icon + headline + subtitle + NL text input + CTA button

### P0
| File | Lines | Current | Fix |
|------|-------|---------|-----|
| `BereanPulseCurateSheet.swift` | 1–246 | Mode prioritization UI; **no NL input** | Add "Dear Berean…" TextField above savedPreferencesSection:52–67; wire to `HeyFeedNLPreferencesService` |
| `OpenTableView.swift` | 107 | `AmenFilterButton` → static dropdown | Add "Tune my feed" secondary action inside dropdown → present `BereanFeedCurateSheet` |

### P1
| File | Lines | Current | Fix |
|------|-------|---------|-----|
| `YourFeedView.swift` | 94–100, 476 | NL input exists in collapsed section | Promote to full-bleed hero card matching reference (icon + headline) |
| `PostFeedActions.swift` | 17–113 | "Adjust Feed Preferences" CTA | Add "Tell Berean what you want to see" NL shortcut path |

### P2
`AmenDiscoverView.swift:44–46` (topic rail — add "Tune for me" pill), `AMENNotificationsView.swift:686` (FocusModePill — add "Mute types…" Berean NL link)

**Key asset:** `HeyFeedNLPreferencesService` already exists. `HeyFeedControlsSheet.swift` appears dead code — candidate for deletion.

---

## PATTERN 5 — Voice / AI Settings Sheet
**Reference:** AI companion app — voice selector rail, personality chips, speed slider, audio source, mic rows, toggle

### P0
| File | Lines | Missing |
|------|-------|---------|
| `BereanLiveVoiceView.swift` | 1–395 | Everything: voice selector, personality chips, speed slider, audio source, mic rows |
| `SettingsDestinationViews.swift` (BereanAISettingsView) | ~1296–1380 | Only has "Allow voice input" toggle; needs full voice selector expansion |

### P1
| File | Fix |
|------|-----|
| `BereanChatView.swift` | Link from chat toolbar to voice settings sheet |
| `BereanCarPlayCoordinator.swift:1–85` | Sync voice settings from phone app (no CarPlay custom UI possible) |
| `BereanAIAssistantView.swift:102–137` | Add `voiceSettings` case to `ActiveModal` enum; wire `.sheet` binding |

**Key need:** Shared `BereanVoiceSettingsModel` `@Observable` class to back all 5 sites. Backing: `BereanRealtimeSessionManager` + `AmenAIModelRouter`.

---

## PATTERN 6 — 3D Liquid Glass Empty States
**Reference:** iOS 19 Files — full-bleed light-lavender page, centered 3D glass icon with glow shadow

### P0
| File | Lines | Current icon | Glass icon | Tint |
|------|-------|-------------|-----------|------|
| `PrayerView.swift` | 191–209 | Flat SF symbols `.secondary` | `hands.sparkles` / `hands.clap` / `checkmark.seal` glass | amenGold |

### P1
| File | Lines | Current | Glass icon | Tint |
|------|-------|---------|-----------|------|
| `AMENNotificationsView.swift` | 595–623 | Flat `bell.fill` in `.activityGlass` circle | `bell.fill` glass with halo | amenPurple |
| `NotificationsView.swift` | 983–1016 | Bare `bell.slash.fill` linear gradient, no material | `bell.slash.fill` glass | amenPurple |
| `BereanPulseEmptyStateView.swift` | 1–40 | `sparkles.rectangle.stack` 32pt, no background | same symbol glass | amenPurple |
| `BereanPulseErrorStateView.swift` | 1–41 | `exclamationmark.triangle` 30pt, no background | same symbol glass | amenGold |
| `AmenDiscoverView.swift` | 216–253 | `sparkles` 44pt `.secondary`, no material | `sparkles`/`star.circle` glass | amenGold |

### P2
`PrayerView.swift:3399` (Prayer Wall no-results), `PrayerTestimonyFeatures.swift:1179`, `BereanChatsListView.swift:378`, `SmartCommunitySearchErrorState.swift:1–39` (also leaks Apple blue — fix `Color.accentColor`)

**Highest-leverage change:** Upgrade `EmptyStateView.swift` (shared component) → propagates 3D glass to every caller automatically.

---

## PATTERN 7 — Share Sheet with Avatar Row + Action Grid
**Reference:** Threads — search bar + horizontal avatar scroll + action icon grid (Link, Share to, Story, Message…)

### P0
| File | Lines | Current |
|------|-------|---------|
| `TestimoniesView.swift` | 1252–1254, 1311–1312 | System `UIActivityViewController` |
| `PrayerView.swift` | 1440, 1513–1515, 1938 | System share sheet |
| `BereanShareSheet.swift` | 32–349 | Custom modal → `ShareService.presentSystemSheet()` |

### P1
`PostCard.swift:~3813`, `PostShareOptionsSheet.swift:59–145`, `TestimoniesView` category, `BereanPulseView.swift:75–104`

### P2
`CommentsView.swift:3496`, `UnifiedChatView.swift:2796–2800+`, `ScriptureDetailRoute.swift`

**Key asset:** `QuickShareSheet.swift:60–101` already implements horizontal avatar chip row with selection state — extract as `AmenShareContactRail` and reuse across all 11 other sites.

---

## PATTERN 8 — Floating Chrome Bar + Mode Pill Switcher
**Reference:** AI notes app — left: hamburger pill, center: tappable mode label pill, right: edit+overflow pill. Below: glass "Share Message" card.

### P0
| File | Lines | Current | Fix |
|------|-------|---------|-----|
| `BereanPulseView.swift` | 142–149 | Back chevron + horizontal `BereanPulseModePillRow` | Replace `topBar` with 3-pill floating chrome; center pill shows active mode label |
| `ChurchNotesSmartRecapView.swift` | 17–38 | Standard nav toolbar | Add floating chrome with "Smart Recap" mode pill + share card |
| `BereanChatView.swift` | (composer tray) | Model picker buried in composer | Move to floating top chrome: left=hamburger, center=model label (e.g. "Berean Deep"), right=edit+overflow |

### P1
`ChurchNoteSemanticEditorView.swift`, `ChurchNoteTranslationReviewView.swift`, `BereanContextPanelView.swift`

### P2
`BereanAIAssistantView.swift`, `BereanModesSheet.swift:74–100` (10 modes: standard, scripture, prayer, study, deep…), `BereanModelPickerComponents.swift:95–197`

**Key assets:** `BereanPulseModePillRow.swift` (mode pill pattern), `BereanModelPickerComponents` pill:95 + menu:131, `BereanModelStore` / `BereanModeStore` back the state.

---

## QUESTIONS FOR STEPH

1. **Feed curation scope:** Should the "Dear Berean" NL input in `BereanPulseCurateSheet` also write to `HeyFeedNLPreferencesService` (affecting OpenTable), or stay isolated to Pulse ranking?
2. **Empty state component:** Should 3D glass icons be a `ZStack` composition in each site, or a new `AmenGlass3DIcon(symbol:tint:)` added to `AmenLiquidGlassComponents.swift`?
3. **Voice settings model:** New `BereanVoiceSettingsModel` singleton, or persist voice config through `BereanRealtimeSessionManager`?
4. **Notifications legacy cleanup:** `NotificationsView.swift` and `AMENNotificationsView.swift` both implement the bell empty state. Which is live in the tab bar? The legacy one is a deletion candidate.
5. **Chrome bar scope:** `BereanChatView` model picker — does it stay in the composer tray for quick switching, or move fully to the floating top chrome?

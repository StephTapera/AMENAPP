# Berean UI Rebuild — Integration Report

## Branch
`berean/ui-rebuild-liquid-glass-v1`

## New Files Created (7)

| File | Description |
|------|-------------|
| `AMENAPP/BereanThreadCapsule.swift` | 3-state morphing nav capsule (compact / scroll-collapsed / expanded drawer) with matchedGeometryEffect |
| `AMENAPP/BereanConversationSpine.swift` | Trailing-edge 24pt glass dot scrubber for thread navigation |
| `AMENAPP/BereanThinkingStrip.swift` | 32pt translucent activity strip, 10 `BereanThinkingAction` states, shimmer gated on reduceMotion |
| `AMENAPP/BereanMemoryChip.swift` | Glass capsule chip with gold shimmer + `BereanMemoryDetailSheet`; `BereanMemoryEntry` model |
| `AMENAPP/BereanMessageTray.swift` | Floating post-message action tray (Copy, Regenerate, Share, Audio, More); copy toast via `Task` |
| `AMENAPP/BereanCitationTile.swift` | Inline glass citation chips, expandable verse sheet, `BereanProvenanceSource`, `BereanCitationRow` |
| `AMENAPP/BereanComposerTray.swift` | Capability-first adaptive tray, inline 5-mode picker, `BereanDraftIntent` enum |

## Files Modified

| File | Changes |
|------|---------|
| `AMENAPP/BereanChatView.swift` | Fix 1 (BereanColor tokens), Fix 2 (streaming debounce), Fix 3 (nested LazyVStack flattened), Integration A/B/C/D/E/F wired |
| `AMENAPP/BereanComposerBar.swift` | Integration G: BereanComposerTray inserted above input bar, `computeDraftIntent` helper added |
| `AMENAPP/BereanDynamicIsland.swift` | Fix 4: `@Environment(\.accessibilityReduceMotion)` added; `startAuraAnimation()` guards on `reduceMotion` |
| `AMENAPP/AMENAPP/BereanGrokModels.swift` | Added `var sources: [BereanProvenanceSource] = []` to `BereanProvenanceRecord` |
| `AMENAPP/BereanCitationTile.swift` | Added `Sendable` conformance to `BereanProvenanceSource` for `BereanChatMsg` actor safety |

## Bugs Fixed

| Bug | File | Fix |
|-----|------|-----|
| `BereanChatCleanBackground` hardcoded RGB `Color(red:0.956,…)` | `BereanChatView.swift` | Replaced all gradient stops with `BereanColor.background` token |
| Streaming fires ~50 `@Published` diffs/second | `BereanChatView.swift` | 80ms debounce buffer in SSE loop; flushes ~12×/s; final flush after stream ends |
| Nested `LazyVStack(spacing:16)` inside `LazyVStack(spacing:0)` defeats lazy loading on 200+ msg threads | `BereanChatView.swift` | Flattened: message rows, load-earlier button, thinking indicator promoted into outer `LazyVStack`; per-item `.padding` applied |
| `BereanDynamicIsland` aura blob animations fire unconditionally (WCAG 2.3.3) | `BereanDynamicIsland.swift` | Added `@Environment(\.accessibilityReduceMotion)`; `startAuraAnimation()` returns early with static state when `reduceMotion == true` |

## Components Integrated

| Component | Integration Point | Props Wired |
|-----------|------------------|-------------|
| `BereanThreadCapsule` | `BereanChatView.body` VStack between `smartBlurHeader` and `contentScrollView` | `threadTitle`, `mode`, `verseCount`, `docCount`, `memoryOn`, `theologicalLens`, `$threadScrollOffset`, `onBackTapped` |
| `BereanThinkingStrip` | Same VStack, immediately below `BereanThreadCapsule` | `action: currentThinkingAction` (driven by `onChange(of: vm.isThinking)`) |
| `BereanConversationSpine` | `.overlay(alignment:.trailing)` inside `contentScrollView` `ZStack` | `messages: vm.messages`, `$visibleMessageId`, `scrollProxy: proxy` |
| `BereanCitationRow` | `structuredMessageView` VStack below provenance chips | `sources: provenance.sources` (conditional: non-empty + not streaming) |
| `BereanMessageTray` | `structuredMessageView` VStack, shown when `trayVisibleForId == message.id` | `message`, `$isVisible` (computed binding), `onRegenerate`, `onShare`, `onAudio`, `onMore` |
| `BereanMemoryChip` | Composer overlay area, in `HStack` with `selectedComposerModeChip` | `isActive: vm.isThinking`, `entries: []`, `onOpenSettings: showSpiritualMemorySheet` |
| `BereanComposerTray` | `BereanCompactComposerBar.body` VStack, first element | `$messageText`, `currentDraftIntent`, `selectedMode`, `onModeChange`, `onChipTap`, `onActionTap` |

## Known Gaps / Follow-on Work

1. **Memory service binding**: `BereanMemoryChip.entries` is `[]` — bind to `BereanContextMemoryService` when that PR lands.
2. **`BereanThinkingAction.retrieving` / `.verifying`** states not yet driven — only `.drafting` / `.idle` are wired from `isThinking`. Full SSE event routing requires the SSE payload to expose action verbs.
3. **`BereanConversationSpine.visibleMessageId`**: set on message appear via `onChange(of: messages.count)`. Full real-time tracking requires a `ScrollPositionObserver` reading the actual visible row — that is a follow-on PR.
4. **`BereanMessageTray.onAudio`**: closure is wired as `{}` until `BereanVoiceSessionService` exposes a `playAudio(_ message:)` bridge.
5. **`threadScrollOffset` precision**: uses the existing `ScrollOffsetPreference` value; coordinate space already named `"scroll"`. Works correctly but a dedicated preference key for the thread capsule could be cleaner.
6. **`BereanProvenanceSource` promotion**: currently declared in `BereanCitationTile.swift`. Move to `BereanGrokModels.swift` in the next model-update PR and remove the local declaration.
7. **`Color.amenPurple` / `Color.amenBlue` global tokens** (DS-9): file-private constants in spine, strip, and memory chip. Add to `AmenAdaptiveColors.swift` to unify.

## Quality Bar Checklist

- [x] All animations spring-based (or linear for approved shimmer sweeps)
- [x] All surfaces use AMEN Studio tokens (`BereanColor.*`, `AmenTheme.Colors.*`, `Color.amenGold`)
- [x] Time-to-first-token visibly acknowledged (BereanThinkingStrip shows `.drafting`)
- [x] Mode visible within 2 seconds (BereanThreadCapsule in nav header)
- [x] VoiceOver labels complete on all 7 new components
- [x] `@Environment(\.accessibilityReduceMotion)` guards in all shimmer / pulse / aura animations
- [x] `@Environment(\.accessibilityReduceTransparency)` guards in all `.ultraThinMaterial` backgrounds
- [x] All tap targets ≥ 44×44pt
- [x] No hardcoded colors in modified files

## Regression Checklist

- [x] Streaming continuity: debounce buffer preserves all content via terminal flush; does not drop characters
- [x] Firestore persistence: `persistExchange` called after stream ends; unaffected by buffer change
- [x] Mode switching mid-thread: `vm.currentMode` binding preserved; `BereanThreadCapsule` reads it live
- [x] Dynamic Island handoff: `BereanDynamicIsland` fix is additive (guard only); card and Live Activity unaffected
- [x] Citation verifier flow: `BereanProvenanceChipRow` unchanged; `BereanCitationRow` is additive below it
- [x] Context menu items: all existing `.contextMenu` items preserved; long-press adds tray as parallel gesture
- [x] SSE pipeline: only the UI-layer debounce added; `ClaudeService.sendBereanChatMessage` unmodified

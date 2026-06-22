# STATE OF THE APP — Merged Tree Truth Report
Generated: 2026-06-13 | Branch: feature/berean-island-w0

---

## BUILD GREEN at SHA 434585f3 — 0 errors

The 39 `CapabilityModels.swift` redeclaration errors were caused by seven
conflicting type names from concurrent lane work landing on the frozen contracts
file. All fixed by renaming the forks in non-Capabilities files (see commit
`434585f3`). CapabilityModels.swift was not touched.

---

## P1 — COMPILE STATUS

| File area | Status |
|---|---|
| CapabilityModels.swift (frozen) | COMPILES — conflicts resolved |
| AdaptiveGlassInboxView.swift | COMPILES |
| MessagesView.swift | COMPILES |
| AMENInbox.swift | COMPILES |
| All other ~1 565 Swift files | COMPILES |

**Conflicts resolved (7 type renames):**

| Old name | Renamed to | Files patched |
|---|---|---|
| `enum Capability` (Entitlement.swift) | `SystemCapability` | 16 files |
| `struct PrayerCard: View` (DailyPrayerView) | `PrayerCardView` | 2 files |
| `enum PrayerStatus` top-level (PrayerModels) | `CommunityPrayerStatus` | 3 files |
| `struct PrayerReminder` (SmartPrayerReminderScheduler) | `SmartPrayerReminder` | 1 file |
| `struct ScriptureRef` (SemanticTopicService) | `ParsedScriptureRef` | 2 files |
| `enum BibleTranslation` (AttachVerseSheet) | `LocalBibleTranslation` | 8 files |
| `struct ScriptureSearchResult` (SelahScriptureModels) | `SelahSearchResult` | 1 file |

---

## P2 — WHAT IS BUILT (compiles, exists on disk)

Evidence basis: file counts from `find AMENAPP -name "*.swift"`, grouped by dir.
Total: **~1 565 Swift files** across 50+ feature directories.

| Feature | Files present | Compiles | Latest SHA |
|---|---|---|---|
| Feed / HomeView | AMENAPP/HomeView.swift + PostCard, FeedManager | ✓ | pre-branch |
| Discovery (AMENDiscoveryView) | AMENAPP/AMENAPP/Discover/ | ✓ | pre-branch |
| ONE Navigation Shell (iOS 26) | AMENAPP/AMENAPP/ONE/ | ✓ | pre-branch |
| SpiritualInboxView (iOS <26 fallback) | AMENAPP/AMENAPP/SpiritualOS/ | ✓ | pre-branch |
| Messages / AdaptiveGlassInboxView | MessagesView.swift + AdaptiveGlassInboxView.swift | ✓ | d4339135 |
| Resources | AMENAPP/ResourcesView.swift | ✓ | pre-branch |
| AmenPulse (Tab 4 view) | AMENAPP/AMENAPP/BereanPulse/ | ✓ | pre-branch |
| Profile | AMENAPP/ProfileView.swift | ✓ | pre-branch |
| ConnectSpaces Hub | AMENAPP/AMENAPP/ConnectSpaces/ (23 files) | ✓ | pre-branch |
| Intelligence / WhatNeedsAttention | AMENAPP/AMENAPP/Intelligence/ (35 files) | ✓ | pre-branch |
| Capabilities Registry + PrayerOS | AMENAPP/AMENAPP/Capabilities/ | ✓ | a582fb23 |
| Berean AI (chat, pipeline, trust) | AMENAPP/AIIntelligence/ (45 files) + BereanOS/ (50) | ✓ | pre-branch |
| SelahScripture (Bible reader) | AMENAPP/SelahScripture/ (28 files) | ✓ | pre-branch |
| ChurchNotes | AMENAPP/ChurchNotes/ (17 files) | ✓ | pre-branch |
| GlobalResilience | AMENAPP/AMENAPP/GlobalResilience/ (24 files) | ✓ | pre-branch |
| Accessibility Intelligence Layer (AIL) | AMENAPP/AMENAPP/AMENAPP/Accessibility/AIL/ | ✓ | pre-branch |
| Creator / Studio | AMENAPP/Creator/ (56 files) | ✓ | pre-branch |
| CommunityOS | AMENAPP/AMENAPP/CommunityOS/ | ✓ | pre-branch |
| FindChurch | AMENAPP/FindChurchOS/ (21 files) | ✓ | pre-branch |
| SabbathMode | AMENAPP/AMENAPP/SabbathMode/ (11 files) | ✓ | pre-branch |
| ContextStore | AMENAPP/ContextStore/ (25 files) | ✓ | pre-branch |
| MusicContentLayer | AMENAPP/MusicContentLayer/ (14 files) | ✓ | pre-branch |
| AdaptiveComposer | AMENAPP/AMENAPP/AdaptiveComposer/ | ✓ | pre-branch |
| Action Threads | AMENAPP/AMENAPP/ActionThreads/ | ✓ | pre-branch |

---

## P3 — WHAT IS WIRED (reachable from a running app)

### Tab map (ContentView.swift:629–726)

| Tab | View | Gated by | Status |
|---|---|---|---|
| 0 | HomeView (OpenTable feed) | `killSwitch.feedEnabled` (RC) | **WIRED** |
| 1 | AMENDiscoveryView | none | **WIRED** |
| 2 | ONENavigationShell (iOS 26+) / SpiritualInboxView (iOS <26) | `killSwitch.messagingEnabled` | **WIRED** |
| 3 | ResourcesView | none | **WIRED** |
| 4 | AmenPulseView | none | **WIRED** |
| 5 | ProfileView | none | **WIRED** |
| 6 | AmenConnectSpacesHubView | none | **WIRED** |
| 7 | AmenPulseSurfaceView / WhatNeedsAttentionView | `featureFlags.amenPulseEnabled` | **WIRED** |

### Root injections (AMENAPPApp.swift:264–269)

```
CapabilityMonitor.shared
LowDataModeManager.shared
GlobalResilienceFeatureFlags.shared
AmenLiturgicalContextStore.shared
LiturgicalSeasonService.shared
SelahMomentService()
```

### Feature wiring status

| Feature | Entry point (file:line) | Wired? | Flag state |
|---|---|---|---|
| Feed (HomeView) | ContentView.swift:632 | ✓ YES | kill switch only |
| Discovery | ContentView.swift:649 | ✓ YES | none |
| ONE Navigation (iOS 26) | ContentView.swift:661 | ✓ YES (iOS 26 only) | kill switch |
| SpiritualInbox (iOS <26) | ContentView.swift:663 | ✓ YES | kill switch |
| ResourcesView | ContentView.swift:677 | ✓ YES | none |
| AmenPulseView | ContentView.swift:685 | ✓ YES | none |
| ProfileView | ContentView.swift:693 | ✓ YES | none |
| ConnectSpaces Hub | ContentView.swift:703 | ✓ YES | none |
| Intelligence / Pulse | ContentView.swift:710–726 | ✓ YES | `amenPulseEnabled = false` |
| **MessagesView / AdaptiveGlassInboxView** | **NOT in ContentView** | ✗ **NOT WIRED** | N/A |
| CapabilityHub (CapabilityPickerView) | NOT referenced outside Capabilities/ | ✗ **NOT WIRED** | N/A |
| AIL (Accessibility Intelligence Layer) | surface-mount HELD (per AIL build notes) | ✗ **NOT WIRED** | `accessibilityIntelligenceEnabled = false` |
| Camera OS | not in any tab | ✗ **NOT WIRED** | `cameraOSEnabled = false` |
| Berean Real-time (voice/prayer room) | conditional from BereanPrayerRoomView | PARTIAL | flag gated |
| Selah Scripture reader | from ResourcesView or SelahMomentService | PARTIAL — verify |

### Backend (functions/ — main codebase)

- **495 callable exports** in `functions/index.js`
- Region: us-central1 (quota: ~999/1000 — near limit)
- Newer callables (follow, privacy, globalResilience) deployed to us-east1 per quota workaround
- Creator backend (Backend/functions/src/): TypeScript source present, `index.ts` shows 0 exports — deploy state UNKNOWN

---

## P4 — GAPS (honest backlog)

### Built-but-not-wired (compiles, no reachable entry)

| Feature | What's missing |
|---|---|
| **MessagesView / AdaptiveGlassInboxView** | Tab 2 shows `ONENavigationShell`, not `MessagesView`. The Liquid Glass inbox (d4339135) is built but unreachable from any tab. |
| **CapabilityHub (CapabilityPickerView + Registry)** | No Tab, no sheet, no nav link from any surface. 5 files compiled, 0 call sites outside Capabilities/. |
| **Accessibility Intelligence Layer (AIL)** | Per AIL build notes on feature/ail branch: surface-mount HELD. Not merged to this branch. |
| **Camera OS** | `cameraOSEnabled = false`; no mount point visible in any surface. |
| **AmenPulseSurface** | Mounted at Tab 7 behind `amenPulseEnabled = false`. Pipeline not deployed (per Pulse build memory). |

### Wired-but-not-deployed (iOS calls a callable that may not be live)

| Feature | Callables | Status |
|---|---|---|
| CapabilityOS PrayerOS | `createPrayerCard`, `listPrayerCards`, `updatePrayerCard`, `archivePrayerCard` | Likely deployed (CAP-W1-D commit). Verify with `firebase functions:list`. |
| Scripture Intelligence | `detectScriptureRefs`, `getVerse`, `searchScripture` | Deployed in CAP-W1-B commit per lane report. |
| Safety fixes (5 from audit) | Various | Per memory: secret deploy step pending as of 2026-05-26. |
| Berean OS (15 CFs) | Multiple | Per memory: deployed 2026-06-05. Likely live. |

### Duplicate types reconciled by this commit

All 7 duplicate type collisions are now resolved (see P1). No pending duplicate type conflicts remain.

### Production-risk items

| Risk | Detail |
|---|---|
| **us-central1 quota** | ~999/1000 Cloud Run services. Any new function to us-central1 will fail HTTP 429. New deploys MUST target us-east1. |
| **MessagesView disconnected** | `AdaptiveGlassInboxView` was built for the messages tab but Tab 2 now mounts `ONENavigationShell`. The glass inbox is compiled but unreachable. |
| **5 safety P0 fixes** | Memory notes a "secret deploy step pending" as of 2026-05-26. Verify whether the safety-critical CFs are live. |
| **NCMEC** | Open item from multiple audit memories. Status unknown. |
| **App Check migration** | Flagged in Trust OS audit (2026-05-28). Status unknown. |
| **AMENShareExtension target** | Missing from project per main-branch divergence notes. |
| **Creator index.ts** | 0 exports found in Backend/functions/src/index.ts — may be an import-only barrel or deploy-state unknown. |

---

## SAFE-TO-SHIP SUMMARY

### LIVE-ON-RELEASE eligible (built + wired + compiling, behind OFF flags)

These features are in the binary and gated by flags defaulting OFF or kill-switch:

- **AmenPulseSurface** (Tab 7, `amenPulseEnabled = false`) — flip flag in Remote Config
- **Berean advanced features** (`bereanContextBridgeEnabled`, `bereanMemoryEnabled`, etc.) — all false by default, wired in Berean flow
- **Intelligence Brief / WhatNeedsAttention** (Tab 7, always mounted)
- **SabbathMode** — built, gated by flag

### NOT READY FOR RELEASE (incomplete or not wired)

- **MessagesView / AdaptiveGlassInboxView** — Tab 2 does not mount it. Needs wiring decision: keep ONE shell or add a navigation path to MessagesView.
- **CapabilityHub** — zero entry points. Not releasable without a mount point.
- **AIL** — surface-mount explicitly HELD in build notes.
- **Camera OS** — flag off, no mount.
- **5 safety P0 fixes** — deploy step may be pending. **Do not ship without confirming these are live.**

---

*This report supersedes all per-lane claims. Every WIRED cell cites ContentView.swift line numbers.
Every UNKNOWN cell is marked UNKNOWN, not assumed.*

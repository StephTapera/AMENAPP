# Build Currency Audit — 2026-06-10 (claude · Action Intelligence lane)

Read-only audit per Ruling 4. No Xcode required. Steps 1–2 only (tree currency +
feature wiring table). Stage 3 may build on this.

---

## Step 1 — Tree Currency

**Branch:** `feature/connected-intelligence-20260609-r2`
**Divergence from `main`:** `0` behind, `9` ahead → branch is **current with main** (no rebase needed); carries 9 unmerged commits.

### 9 commits ahead of main
| Commit | Subject |
|---|---|
| `91af1a44` | chore: junk-duplicate dedup — record tracked storekit dup deletion |
| `8ebbc140` | chore: junk-duplicate dedup (build-blocking) |
| `4f113c24` | docs(ail): stage ailTransform into consolidated Stage-3 deploy package |
| `4b40d006` | feat(ail): land Accessibility Intelligence Layer onto -r2 (path-scoped, clean) |
| `37129fb3` | feat(connected-intelligence): connectorFetch read-CF (consent-gated, discard, fail-closed) |
| `7695189b` | feat(connected-intelligence): corrected-contract lane (Phases 0-3) + wiring |
| `0aa1205c` | rescue: add git-discipline header + ConnectSpaces prepared-ground tests |
| `12f8839f` | rescue: durable snapshot to harden against repeated git-clean wipes |
| `cc9cd5d3` | Checkpoint before FirebaseAI linkage cleanup |

### Working-tree shape (HOT — multi-lane uncommitted state)
| Class | Count | Notes |
|---|---|---|
| Modified (unstaged) | 168 | spans many lanes |
| Deleted (unstaged) | 51 | mostly root scripts/logs/JSX prototypes (`deploy-berean*.sh`, `*.py` cleanup, `church_notes_*.txt`, `Berean*.jsx`) — looks like deliberate root declutter |
| Untracked | 32 | see hazards below |
| Staged (index) | 7 | **NOT this lane's** — see hazard |

### ⚠️ Currency hazards (must inform Stage 3 / the FirebaseAI commit)
1. **The index is pre-loaded with another lane's staged work (7 files).** A naive
   `git commit` would sweep all of it up:
   - `AMENAPP/AMENAPP/Accessibility/AIL/Settings/AILReadingUnderstandingSettingsView.swift` (A) — AIL lane
   - `AMENAPP/AMENBuildInfo.swift` (A) — build-info lane (pairs with the pbxproj membership-exception line)
   - `AMENAPP/DesignSystem/Ambient/{AUDIT.md,VERIFY.md,Components/AdaptiveColorsSetting.swift}` (A), `AmbientContract.swift` (M), `Components/AdaptiveGlassContainer.swift` (M) — ambient-UI lane
2. **`project.pbxproj` carries uncommitted Info.plist / usage-description rewrites + `AMENBuildInfo.swift` membership + Live Activities keys** from another lane. The FirebaseAI unlink commit must stage **only** the FirebaseAI hunks.
3. **Junk-duplicates have REGENERATED post-dedup.** New ` 2`/` 3`/` 4` files since `8ebbc140`/`91af1a44`: `AGENT_LANES 2.md`, `RULES_INDEX_AUDIT 2.md`, `demo_note_pill 3.html`/`4.html` (+ viewer/share variants), `Backend/functions/src/{actionIntelligence,noteShare,userSettings,agents/agentIdentity,agents/agentOutcomes} 2.ts`, `connectedIntelligence.{config,contracts} 2.ts`, `noteShare.test 2.ts`, `noteShareAccess.rules.test 2.js`, `actionIntelligenceRules.test 2.js`. A process is still duplicating files — the dedup is not converged.
4. **Genuinely new untracked source** (real work, needs target membership + commit): `AMENAPP/LiquidGlassActionCapsule.swift`, `AMENAPP/firestore.deploy.rules`, `Backend/functions/src/agents/agentOutcomes.ts`, `Backend/functions/src/prayer/createPrayerRequest.ts`, `Backend/rules-tests/{action-intelligence,minor-safe-dm,note-share-security-closers}.rules.test.ts`, `functions/test/actionIntelligenceFunctions.test.js`, plus `handoffs/` (this lane).

---

## Step 2 — Feature Wiring Table (file:line evidence)

Authoritative mount point is `AMENAPP/ContentView.swift`. Tabs live in
`allTabsZStack` (`ContentView.swift:616-696`); chrome/overlays in
`mainContentWithOverlays` (`:784-957`); gates in the root `body` (`:152-544`).

### Primary navigation — 8 tabs (`allTabsZStack`)
| Tab | Surface | Mount (file:line) |
|---|---|---|
| 0 Home | `HomeView` | `ContentView.swift:619` |
| 1 Discovery | `AMENDiscoveryView` | `ContentView.swift:633` |
| 2 Hub | `ONENavigationShell` (iOS 26+) / `SpiritualInboxView` (fallback) | `ContentView.swift:643` / `:645` |
| 3 Resources | `ResourcesView` (Church Notes + Find Church) | `ContentView.swift:656` |
| 4 Pulse | `AmenPulseView` (notifications) | `ContentView.swift:664` |
| 5 Profile | `ProfileView` (+ Settings) | `ContentView.swift:672` |
| 6 Spaces | `AmenConnectSpacesHubView` | `ContentView.swift:682` |
| 7 Intelligence | `WhatNeedsAttentionView` (def `AMENAPP/AMENAPP/Intelligence/WhatNeedsAttentionView.swift:15`) | `ContentView.swift:690` |

### OS-layer features & overlays
| Feature | Mount (file:line) | Notes |
|---|---|---|
| Accessibility Intelligence Layer (AIL) | `.ailCalmMode()` + `.ailTouchTarget()` on `selectedTabView` — `ContentView.swift:723-724` | global; no-op unless a11y profile enables |
| Simple Mode (a11y home) | `AmenSimpleModeView` — `ContentView.swift:286` | full-screen, bypasses feed/tabs |
| Sabbath Mode | `SabbathWindowView` / `SabbathBanner` — `ContentView.swift:576` / `:595`; service `:45` | additive gate, precedes Shabbat |
| Sunday Church Focus (Shabbat) | `SundayChurchFocusGateView` — `ContentView.swift:605` | tab allow-list `:709-715` |
| Spiritual OS Assistant Bar | `AmenAssistantBarOverlay(coordinator:)` — `ContentView.swift:831` | coordinator init `:145`; contextManager env `:956`; hidden on Resources |
| Camera OS | `AmenCameraOSHubView` fullScreenCover — `ContentView.swift:888`; tab-bar hook `:810` | |
| Berean Dynamic Island | `BereanDynamicIsland(vm: BereanIslandViewModel.shared)` — `ContentView.swift:940` | |
| Berean Daily Formation | `BereanDailyFormationView` fullScreenCover — `ContentView.swift:1082` | |
| Berean Conversion Menu | `AmenBereanConversionMenu` — `ContentView.swift:904` | |
| Creator Kit | `AmenCreatorKitHome` — `ContentView.swift:911` | |
| Audience-First Composer | `AmenAudienceFirstPickerView` → `CreatePostView` via `.glassContextualSheet` — `ContentView.swift:919` / `:936` | |
| Note Share Viewer (deep link) | `NoteShareViewerView` fullScreenCover `:534`, router `handleNoteShareURL` `:546` | flag `feature_note_share_viewer` OFF (per AGENT_LANES) |
| Wellness Guardian | `WellnessBreakReminderView:495`, `WellnessRiskOverlay:518`, session track `:489-491` | |
| Adaptive Accessibility banner | `AccessibilitySuggestionBanner` — `ContentView.swift:840` | flag `adaptiveAccessibilityEnabled` |
| Audio narration mini-player | `AudioMiniPlayerBar` — `ContentView.swift:826` | flag `audioNarrationEnabled` |
| Moderation toast / in-app banner | `.moderationToast()` `:780`, `.inAppNotificationBanner()` `:781` | |

### Auth / account gates (root `body`, in order)
| Gate | Mount (file:line) |
|---|---|
| 2FA verification | `TwoFactorVerificationGateView` — `ContentView.swift:158` |
| Unauthed splash/landing | `AMENAuthLandingView` — `ContentView.swift:169` (+ `AutoLoginSplashView:177`, `SmartAccountResumeView:197`) |
| Deactivated | `ReactivationPromptView` — `ContentView.swift:231` |
| Age gate (D-01) | `AgeGateContainerView` — `ContentView.swift:242` |
| Username selection | `UsernameSelectionView` — `ContentView.swift:251` |
| Onboarding | `OnboardingView` — `ContentView.swift:265` |
| Email verification | `EmailVerificationGateView` — `ContentView.swift:277` |
| Account status (suspended) | `AccountStatusGateView` wraps `mainContent` — `ContentView.swift:295` |

### Action Intelligence (this lane) — wiring reality
| Item | Evidence | State |
|---|---|---|
| Capsule UI in church-note comments | `ChurchNoteCommentsView.swift:143` `AmenActionIntelligenceCapsule(analysis:)`; analyze `ActionIntelligenceEngine.shared.analyze` `:159`; execute `ActionIntelligenceService.shared.execute` `:193` | **WIRED** end-to-end |
| Execute from chat | `UnifiedChatView.swift:3398` `ActionIntelligenceService.shared.execute(...)`; payload builder `actionIntelligenceSource(for:analysis:)` `:3410` | **WIRED** |
| Generic `NotePill` component | def `CommunicationOSGlassKit.swift:642` | **NOT rendered** — zero `NotePill(` call sites outside its def file. Component exists, unused in live app. |

### Connected Intelligence surfaces — NOT mounted in iOS
No Swift surfaces found for `ConnectorsHub` / `NotebookView` / `ScheduledActions` /
`ConnectedIntelligence`. Confirms the connected-intelligence build is React/TS (per
project memory); the **`ConnectorsHubScreen` iOS mount gap is real** — there is no
SwiftUI mount point. `WhatNeedsAttentionView` (tab 7) is the only "intelligence brief"
surface present in the app.

---

## Carry-forward for Stage 3
- FirebaseAI unlink: **handed to human** (agent pbxproj edits blocked by Xcode-open crash-safety hook). Exact 6-site edit posted to chat 2026-06-10. Verified safe (no app-target source imports FirebaseAI/FirebaseAILogic).
- Dirty index + dirty pbxproj → the FirebaseAI commit must stage **only** FirebaseAI hunks.
- Junk-duplicate regeneration is **not converged** — a process is still spawning ` 2/3/4` files.
- iOS ConnectorsHub mount + Action Intelligence `NotePill` render are open wiring gaps.

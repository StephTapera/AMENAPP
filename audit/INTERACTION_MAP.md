# AMEN — Interaction Map (Phase A)

**Status:** Phase A inventory artifact. Read-only audit; no app code changed in this pass.
**Date:** 2026-06-21
**Scope:** The 11 §13 product surfaces — Feed, Comments, Profile, Onboarding, Settings, Amen Connect, Spaces/Communities, Berean, Selah/Media, Resources, Find a Church. Audited from canonical views, tracing into referenced row/cell/menu/component files.
**Method:** 6 parallel read-only audit agents, each homing in on the canonical view(s) per surface and assessing PRIMARY interactive elements against the §3 schema. This is the source of truth for Phases B–F.

> Convention in tables: "Missing states" lists only the states that are *actually* absent. **Status** = `OK` (complete) · `PARTIAL` (wired but missing states/a11y) · `DUP` (duplicate control) · `DEAD` (stub / no real action) · `BROKEN` (wired but wrong).

---

## 0. Cross-cutting synthesis (the patterns that repeat everywhere)

These themes recur across most surfaces and should drive the Phase B foundation and Phase C repairs:

1. **Dead / stub controls that look live.** Empty closures, `print`-only handlers, and placeholder/`sample*` data back many visible affordances — several even carry VoiceOver "Open X" labels while doing nothing. Worst offenders: `CreatorProfileView` hero actions (`break`), the whole Berean Scripture-reader action surface, `AmenSpaceModerationDashboard` data loaders, `FeedUtilityDrawer`, `ResourcesContentView` rails, resource "Preview bundle".
2. **Non-idempotent backend writes.** Join / RSVP / like / save / visit-plan paths optimistically mutate and `increment(+1)` with no transaction, no in-flight guard, and `try?`-swallowed errors → count drift and duplicate records. Visit-plan and calendar paths write fresh `UUID()`/auto-ID docs on every tap.
3. **Paywall fragmentation.** ≥4–5 distinct upgrade/paywall surfaces gate Spaces/Connect alone (`AmenAccountPaywallView`, inline `PaywallOverlay`, `AmenSubscriptionPaywall`, `AmenFeatureGateView`, SignUp `TierCard`). Directly motivates a single `PaywallCoordinator`.
4. **Silent failures.** `try?` / `catch { dlog }` / `errorMessage` set-but-never-rendered across comments, privacy settings, Selah/AskSelah streams, photo upload, follow. Users get false confidence (e.g., a failed block shows nothing; a failed save looks saved).
5. **Missing VoiceOver labels on icon-only controls** — including the single most important action on a surface (comment **Send**), profile toolbar follow/message/share, and many `+`/search/clear glyphs.
6. **Sub-44pt tap targets** — pervasive on pills, chips, composer glyphs, and nested card buttons.
7. **Misleading success signals.** Calendar "Added" toast on permission denial; Connect SignUp "You're in!" on purchase *cancel*.

### Highest-severity items (CRITICAL/HIGH rollup)

| # | Severity | Surface | File:line | Problem |
|---|---|---|---|---|
| 1 | **CRITICAL** | Berean | `BereanSmartPillSystem.swift:301` | Crisis "Find immediate help" pill routes back into the AI instead of `CrisisResourceOverlayView`/988 — safety + Companion-Boundary breach |
| 2 | **CRITICAL** | Spaces | `SpacesViewModel.swift:77` | Join not idempotent/transactional; optimistic insert + unconditional `increment(+1)`, all writes `try?` → member-count drift |
| 3 | **CRITICAL** | Spaces | `AmenSpaceModerationDashboardView.swift:631` | All moderator data loaders are stubs returning `[]` — moderation effectively non-functional |
| 4 | **CRITICAL** | Find a Church | `FindChurchView.swift:1216/1689/2351` | Denied-location dead end: "Search Manually" + text search + MKLocalSearch all re-guard on GPS; typed city/zip never returns results |
| 5 | **CRITICAL** | Resources | `AMENResourceDetailView.swift:332` | Media Save/bookmark is ephemeral `@State` — never persisted or loaded; user saves silently lost |
| 6 | **CRITICAL** | Profile | `CreatorProfileView.swift:237` | Hero follow/message/support/share all `break` (no-op) — every primary CTA dead |
| 7 | **HIGH** | Settings | `SettingsView.swift:235` | "Delete Account" alert confirm button body empty (dead duplicate of working nav row at :170) |
| 8 | **HIGH** | Settings | `SettingsView.swift:604` | Every `SDToggleRow` uses `.tint(.white)` → "on" state invisible on light bg; toggles look permanently off |
| 9 | **HIGH** | Berean | `BereanScriptureReaderView.swift:51–169` | Entire verse-card/context-menu action surface is stub (Share button body empty; Highlight/Note/Save empty; AI actions `print`-only, no loading, no re-tap guard) |
| 10 | **HIGH** | Onboarding | `OnboardingFlowView.swift:128` | `finish()` sets `hasCompletedOnboarding=true` + dismisses with fire-and-forget `setData`; failed write leaves server flags unset |
| 11 | **HIGH** | Onboarding | `OnboardingFlowView.swift:1107` | "Enable Notifications" advances regardless; previously-denied users get no prompt + no feedback |
| 12 | **HIGH** | Connect | paywall ×5 | Paywall fragmentation (see #3 above) |
| 13 | **HIGH** | Spaces | `CommunityGroupsView.swift:400` | CreateGroup sets `isCreating=true` before `guard uid` → button permanently stuck disabled on nil uid; errors swallowed |
| 14 | **HIGH** | Spaces | `AmenConnectSpacesHubView.swift:320` | Live card NavigationLink fabricates `memberIds: Array(repeating:"",count:)` — passes fake data to real detail view |
| 15 | **HIGH** | Resources | `ResourceGlassHomeView.swift:592` | Bundle "Preview" → `previewItem` hardcoded `nil`; every bundle tap is a no-op |
| 16 | **HIGH** | Resources | `ResourcesContentView.swift:102` | ~16 rail cards look tappable, only "Find a Church" is wired |
| 17 | **HIGH** | Find a Church | `FindChurchView.swift:2516` | `kCLLocationAccuracyBest` requests exact GPS though only city-radius search is needed |
| 18 | **HIGH** | Find a Church | `ChurchCommunityProfileView.swift:255` | Calendar shows "Added" success toast even on EventKit denial; re-tap duplicates events |
| 19 | **HIGH** | Berean | `BereanStudyHubView.swift:173` | Home `handleChip` empty TODO; `submitInput` `print`-only with no constitutional/UGC gate |
| 20 | **HIGH** | Connect | `AmenConnectV2View.swift:168/533/693` | Workspace presence button, 8 section tiles, and "See all" all dead (some with actionable a11y labels) |

---

## 1. Feed + Comments

Files: `ActivityFeedView.swift`, `YourFeedView.swift`, `MediaOnlyFeedView.swift`, `FeedUtilityDrawer.swift`, `CommentsView.swift`, `CommentsViews.swift`, `TimestampedCommentsView.swift`, `LiquidGlassButtons.swift`, `MediaTileView.swift`.

| Element | File:line | Action/Destination | Missing states | A11y | Dedup/Idempotency | Status | Issue → Fix |
|---|---|---|---|---|---|---|---|
| Global/Community tab pills | ActivityFeedView.swift:124 | switch `selectedTab` | none | no label; ~34pt | none | PARTIAL | <44pt; no `.isSelected` → add label/trait, minHeight 44 |
| Retry (error) | ActivityFeedView.swift:355 | `retryGlobalFeed()` | none | OK | none | OK | — |
| Avatar buttons (participants) | CommentsView.swift:257 | open profile sheet | failure (nil userId) | label missing; 48pt | shared sheet OK | PARTIAL | add `accessibilityLabel("View \(name)")` |
| Close (X) | CommentsView.swift:397 | dismiss | none | labeled; 36pt | none | PARTIAL | 36pt → bump to 44 |
| Cancel-reply (X) | CommentsView.swift:788 | `replyingTo=nil` | none | labeled; ~16pt | none | PARTIAL | enlarge hit area |
| Smart-reply chips | CommentsView.swift:819 | fill text | none | text only; ~30pt | none | PARTIAL | min height/label |
| Emoji button | CommentsView.swift:1103 | show picker | none | "Add emoji"; 24×24 | none | PARTIAL | pad to 44 |
| Photo button | CommentsView.swift:1116 | moderate+attach | none | label OK; 24×24 | re-pick re-runs | PARTIAL | pad to 44 |
| Berean rewrite-assist | CommentsView.swift:1150 | `requestBereanRewrite()` | failure (silent) | labeled; 28pt | disabled while loading OK | PARTIAL | surface failure; enlarge |
| **Send (GlassCircularButton)** | CommentsView.swift:1198 / LiquidGlassButtons.swift:67 | `submitComment()` | none | **no a11y label**; 44pt | `isDisabled` guard good | PARTIAL | add `accessibilityLabel("Send comment")` |
| Composer submit logic | CommentsView.swift:1508 | addComment/Reply optimistic | offline | n/a | strong: in-flight guard + temp-id rollback | OK | (exemplar) |
| Comment Amen/heart | CommentsView.swift:2433 | `toggleAmen` optimistic | none | toggles | **no in-flight guard** → double-fire | PARTIAL | add per-comment lock |
| Own-comment ellipsis | CommentsView.swift:2510 | confirmationDialog→Delete | none | "Comment options"; ~20pt | **DUP of contextMenu Delete** | DUP | consolidate |
| ContextMenu (own) Copy/Reply/Delete | CommentsView.swift:2586 | … | none | labeled | Delete duplicated | DUP | keep one canonical |
| ContextMenu (other) Restrict/Block/Mute/Report | CommentsView.swift:2614 | safety actions | failure (block/mute silent) | labeled | none | PARTIAL | add failure toast |
| Report Comment | CommentsView.swift:2656 | report sheet | none | labeled | none | OK | — |
| Long-press soft reactions | CommentsView.swift:2558 | SoftReactionSheet | none | emojis no labels | maps to same toggle | PARTIAL | add labels |
| CommentReportSheet reasons | CommentsView.swift:3071 | `submitReport` | none | labeled; ≥44 | `isSubmitting` guard | OK | (exemplar) |
| YourFeed topic chip (tap/long-press) | YourFeedView.swift:912 | pin / suppress | none | no dual-gesture label; ~30pt | none | PARTIAL | label+hint+VO custom action |
| Reset all feed tuning | YourFeedView.swift:630 | `removeAll()` | failure | labeled | **no confirm (destructive)** | PARTIAL | add confirmationDialog |
| FeedUtilityDrawer feed-mode rows | FeedUtilityDrawer.swift:242 | set local state | n/a | text | none | **DEAD** | no feed re-query; sample data → wire or gate off |
| Drawer community rows | FeedUtilityDrawer.swift:302 | generic browse | n/a | text | hardcoded `sampleOwned/Joined` | DEAD | back with real VM |
| MediaOnlyFeed grid tile | MediaOnlyFeedView.swift:133 | fullScreenCover | all covered | labeled + `.isButton` | none | OK | (exemplar state machine) |
| CommentCard Amen | CommentsViews.swift:106 | local count only | failure | label OK | guard good | **DEAD** | "not supported server-side" → wire or hide |
| GIFPicker tiles | CommentsViews.swift:912 | hardcoded Giphy URL | n/a | no label | none | DEAD | 4 static URLs, search non-functional → wire API or remove |
| FullCommentsView submit | CommentsViews.swift:606 | optimistic + `try?` persist | failure (no rollback) | n/a | guard good | PARTIAL | roll back + error toast on failure |
| TimestampedComments submit | TimestampedCommentsView.swift:161 | callable | failure (silent; text already cleared) | no send label | disabled guard | PARTIAL | restore text + error toast |

**Top issues:** (HIGH) Send button no a11y label; FeedUtilityDrawer dead/sample-backed; comment-level Amen stubbed; GIFPicker hardcoded. (MED) duplicate Delete paths; silent block/mute failure; no debounce on comment heart; FullComments/Timestamped swallow write failures; destructive reset no confirm. (LOW) sub-44pt emoji/photo/Berean/tab/topic controls; topic-chip long-press invisible to VoiceOver.
**Exemplars to reuse:** `CommentReportSheet` (full state machine), `submitComment` (optimistic+rollback), MediaOnlyFeed grid.

---

## 2. Profile + Onboarding + Settings

Files: `ProfileView.swift`, `UserProfileView.swift`, `CreatorProfileView.swift`, `ProfilePhotoEditView.swift`, `OnboardingFlowView.swift`, `AMENAccountTypeOnboardingView.swift`, `OnboardingQuizView.swift`, `SettingsView.swift`, `AMENSettingsSystem.swift`, `PrivacyControlsSettingsView.swift`, `SettingsDestinationViews.swift`.

| Element | File:line | Action | Missing states | A11y | Dedup/Idempotency | Status | Issue → Fix |
|---|---|---|---|---|---|---|---|
| Follow/Following (header) | UserProfileView.swift:2406 | toggleFollow | none | label+hint; ≥44 | `FollowOperationGuard` actor | OK | (exemplar) |
| Toolbar Follow/Message/Share/⋯ (scrolled) | UserProfileView.swift:2042–2070 | actions | none | **icon-only, no labels** | guard shared | PARTIAL | add labels |
| Avatar (other) | UserProfileView.swift:2255 | full-screen avatar | none | no label; 86pt | low | PARTIAL | "View profile photo" |
| Edit/Share profile (own) | ProfileView.swift:2054/2079 | sheet / share | none | no label; ~38pt | single-sheet OK | PARTIAL | 44pt + labels |
| Own ⋯ menu | ProfileView.swift:579 | settings/QR/history/share/signout | none | no label on ellipsis | OK | PARTIAL | add label |
| Sign Out (own) | ProfileView.swift:423 | signOut | none | destructive + confirm | confirm-gated | OK | — |
| Photo Save/Remove | ProfilePhotoEditView.swift:280/581 | upload/delete | **failure haptic-only** | role OK | disabled/confirm | PARTIAL | error banner + retry |
| Onboarding Continue/age/terms/privacy | OnboardingFlowView.swift:95–807 | `advance()` | none | traits; 56pt | idempotent via `min` | OK | (exemplar) |
| Enable Notifications | OnboardingFlowView.swift:1107 | request perm → advance | **denied no-ops then advances** | label; 56pt | system | PARTIAL | detect `.denied`→Settings |
| Username Continue | OnboardingFlowView.swift:1279 | advance gated | offline (banner) | states good | debounced 500ms | OK | (exemplar) |
| Slide5 Follow toggle | OnboardingFlowView.swift:1673 | optimistic | **failure (`try?` swallow)** | label; ~34pt | **no in-flight lock** | PARTIAL | 44pt; revert/error |
| Finish "Go to Feed" | OnboardingFlowView.swift:1452 | finish→save+dismiss | **save failure unhandled** | ≥56pt | flag set even if write fails | PARTIAL | await write/handle failure |
| Account-type cards | AMENAccountTypeOnboardingView.swift:193 | selectType | none | no combined label/`.isSelected` | idempotent | PARTIAL | add label+trait |
| Account-type Get Started | AMENAccountTypeOnboardingView.swift:219 | DOB gate / complete | loading; COPPA gate | disabled+submitting; 54pt | guard | OK | (exemplar COPPA fail-closed) |
| Settings Sign Out | SettingsView.swift:163 | confirm→signOut | none | confirm | gated | OK | — |
| **Settings Delete Account (alert btn)** | SettingsView.swift:235 | **empty closure** | n/a | destructive | n/a | **DEAD** | dead dup of nav row :170 → remove or route |
| Settings Delete Account (nav row) | SettingsView.swift:170 | DeleteAccountView | none | nav | — | OK | working path |
| **SDToggleRow (all toggles)** | SettingsView.swift:604 | binding set | none | label bound | reflects state | PARTIAL | `.tint(.white)` invisible on light bg → brand tint |
| Privacy DM/Comment/Mention pickers | PrivacyControlsSettingsView.swift:41/120/165 | trust update | **failure (optimistic, no revert)** | labels | per-change write | PARTIAL | revert on failure + toast |
| **CreatorProfile hero actions** | CreatorProfileView.swift:237 | **`break` no-op** | all | — | n/a | **DEAD** | follow/message/support/share dead → wire or hide; add `creatorProfilesEnabled` flag |
| CreatorProfile error banner | CreatorProfileView.swift:195 | shows on fail | no retry | label | — | PARTIAL | copy promises pull-to-refresh but no `.refreshable` |

**Top issues:** (CRITICAL) CreatorProfile hero CTAs dead. (HIGH) Delete-Account alert dead-dup; SDToggleRow invisible "on"; onboarding finish fire-and-forget save; notifications advance-on-denied. (MED) slide5 follow swallow+no-lock; photo upload/delete silent failure; privacy pickers optimistic-no-revert; profile toolbar/avatar/edit icon-only no labels. (LOW) CreatorProfile refreshable copy mismatch; account-type cards no selected trait.
**Exemplars:** `FollowOperationGuard`, idempotent `advance()`, COPPA-gated account-type confirm, confirmation-gated sign-out.

---

## 3. Amen Connect + Spaces / Communities

Files: `AmenConnectV2View.swift`, `AmenConnectSpacesHubView.swift`, `AMENConnectSignUpView.swift`, `SpacesDiscoveryView.swift`, `SpaceDashboardView.swift`, `AmenSpaceDetailView.swift`, `CommunityGroupsView.swift`, `ConnectForumView.swift`, `SpacesViewModel.swift`, `SpaceCardView.swift`, `AmenSpaceModerationDashboardView.swift`, `SpaceRoleActionBar.swift`.

| Element | File:line | Action | Missing states | A11y | Dedup/Idempotency | Status | Issue → Fix |
|---|---|---|---|---|---|---|---|
| Workspace presence button | AmenConnectV2View.swift:168 | `TODO(wiring)` | all | label; 30pt | none | **DEAD** | wire or remove (context-menu items also empty) |
| Section bar pills | AmenConnectV2View.swift:285 | set section | none | label+`.isSelected`; 44 | none | OK | — |
| Section grid tiles (8) | AmenConnectV2View.swift:533 | decorative | no tap | "Open X" label but no Button | none | **DEAD** | announces actionable, does nothing → wrap/drop label |
| Discover "See all" | AmenConnectV2View.swift:693/712 | empty `{}` | all | text | none | **DEAD** | wire or remove |
| Discover filter pills | AmenConnectV2View.swift:657 | set filter | doesn't filter rails | no label/trait | none | PARTIAL | cosmetic; wire to data |
| Hub top tabs | AmenConnectSpacesHubView.swift:202 | set tab | none | label+`.isSelected`; ~36pt | none | PARTIAL | minHeight 44 |
| Live space card (NavLink) | AmenConnectSpacesHubView.swift:320 | →detail | none | label | **fabricates memberIds array** | PARTIAL | pass real doc |
| Spaces load error | AmenConnectSpacesHubView.swift:278 | "pull to retry" | **no `.refreshable`** | text | none | PARTIAL | add refreshable |
| SpaceCard Join | SpaceCardView.swift:123 | `onJoin` | no in-flight/failure | no label; ~30pt | **no guard, `try?`** | PARTIAL | guard+toast+44pt |
| **vm.toggleJoin** | SpacesViewModel.swift:77 | Firestore write | failure swallowed | n/a | **non-idempotent: optimistic+`increment(+1)`, no txn** | **BROKEN** | transactional CF; re-entrancy guard |
| Discovery filter pills / FAB / clear | SpacesDiscoveryView.swift:135/263/107 | filter/create/clear | none | **no labels** | none | PARTIAL | add labels/traits |
| EventRow RSVP | SpaceDashboardView.swift:242 | rsvp CF | **binary only, not Going/Maybe/Not; silent revert** | no label; 30pt | in-flight guard | PARTIAL | 3-state + label + error |
| VolunteerNeed "Help" | SpaceDashboardView.swift:296 | static URL alert | n/a | no label; 30pt | none | **DEAD** | wire to signup |
| SpaceRoleActionBar | SpaceRoleActionBar.swift:124 | role closures | disabled OK | label+hint; 44 | none | OK | but onMembers/onAnalytics passed empty `{}` from dashboard |
| SpaceDetail Hero "Join" | AmenSpaceDetailView.swift:316 | server entitlement | no loading; silent failure | hero a11y | fail-closed | PARTIAL | loading+error |
| ModDashboard Review/Action/Approve/Deny/Remove | AmenSpaceModerationDashboardView.swift:104–550 | CF actions | loading/error vary | labels | **no confirm on destructive** | PARTIAL | confirm destructive + audit log |
| **ModDashboard data loaders** | AmenSpaceModerationDashboardView.swift:631 | `sleep` then `=[]` | — | n/a | n/a | **DEAD** | stubs → wire Firestore |
| CommunityGroups Join | CommunityGroupsView.swift:315 | confirm→joinGroup | no failure surface | no label; ~30pt | **`increment(+1)` double-count risk** | PARTIAL | CF txn + toast |
| **CreateGroup "Create"** | CommunityGroupsView.swift:400 | setData | **no failure; `isCreating` stuck** | Form | guard-fail leaves disabled | **BROKEN** | reset on all paths; surface error |
| Forum reply send | ConnectForumView.swift:360 | optimistic | no failure; `try?` | no send label | **double-append on double-tap** | PARTIAL | disable while sending; toast |
| SignUp "Join Pro" | AMENConnectSignUpView.swift:288 | upgrade | loading; disabled | text only | guard | PARTIAL | **shows "You're in!" on purchase cancel** → branch on outcome |

**Top issues:** (CRITICAL) `toggleJoin` non-idempotent; moderation data loaders stubbed. (HIGH) destructive mod actions no confirm/audit; paywall fragmentation ×4–5; CreateGroup stuck-disabled; live-card fake memberIds. (MED) dead section tiles/"See all"/presence; RSVP binary+silent; volunteer "Help" dead; optimistic Join/reply no in-flight; SignUp false success. (LOW) filter/category pills missing labels/traits, cosmetic filters.

---

## 4. Berean

Files: `BereanStudyHubView.swift`, `BereanStudyHomeView.swift`, `BereanScriptureReaderView.swift`, `BereanChatView.swift`, `BereanLandingView.swift`, `BereanSmartPillSystem.swift`, `BereanFloatingActionTray.swift`, `ScriptureActionRow.swift`, `SmartActionPills.swift`.

| Element | File:line | Action | Missing states | A11y | Dedup | Status | Issue → Fix |
|---|---|---|---|---|---|---|---|
| Home quick-action chip | BereanStudyHubView.swift:104 | `handleChip` empty TODO | all | hint; <44 | none | **DEAD** | route through `BereanContextActionEngine` |
| Home input send | BereanStudyHubView.swift:50 | `submitInput` print-only | loading/success/failure | input bar | none | **DEAD** | engine + constitutional/UGC gate |
| Home mic | BereanStudyHubView.swift:55 | "W3" empty | all | none | none | **DEAD** | wire or hide |
| "Continue studying" card | BereanStudyHubView.swift:89 | none | — | hint "tap" but not Button | none | **DEAD** | make Button or drop hint |
| Study passage submit arrow | BereanStudyHomeView.swift:273 | `onStudyPassage` | failure/empty | **no label**; ~28pt | none | PARTIAL | label + 44pt |
| Quick-prompt chip (chat) | BereanStudyHomeView.swift:219 | `onNewChat` discards text | — | no label | none | PARTIAL | pass prompt into chat |
| Leader rows (Pastor/Mentor/Counselor) | BereanStudyHomeView.swift:399 | none | all | chevron implies tappable | none | **DEAD** | wire or remove chevron |
| Recent-chat rows | BereanStudyHomeView.swift:481 | none | — | not Button | none | **DEAD** | wire to session open |
| Reader contextMenu Highlight/Note | BereanScriptureReaderView.swift:82 | empty `{}` | all | menu label | none | **DEAD** | wire to stores |
| Reader Cross-Ref/Original-Lang/Ask | BereanScriptureReaderView.swift:85–93 | `handleAction` print-only | all AI states | menu label | **no guard → re-fire** | PARTIAL | engine + loading + guard |
| ScriptureActionRow Save | ScriptureActionRow.swift:62 | `handleSave` TODO | success/failure | label; 44pt | none | **DEAD** | wire bookmarks |
| ScriptureActionRow Share | ScriptureActionRow.swift:63 | alert→Share btn **empty** | success/failure | label; 44pt | none | **DEAD** | wire Guard + share sheet |
| ScriptureActionRow Pray/Explain | ScriptureActionRow.swift:64 | `handleAction` print-only | all AI states | label; 44pt | re-tap | PARTIAL | wire + loading |
| Chat Send/Stop (compact) | BereanChatView.swift:1877 | `send()`/`cancelStreaming()` | handled in vm | dynamic label; 32pt | `!isThinking` guard | PARTIAL | enlarge to 44pt |
| Chat Send/Stop (adaptive) | BereanChatView.swift:969 | onSend/onStop | — | composer bar | guard | OK | stop wired correctly |
| Voice/mic + Plus/attach | BereanChatView.swift:1864/1831 | voice sheet / `dlog` | all | mic no label; attach labeled | none | PARTIAL/DEAD | label+size; attach is dead `dlog` |
| **Crisis pill "Find immediate help"** | BereanSmartPillSystem.swift:301 | `onAskFollowUp("show crisis resources")` | — | label | none | **BROKEN** | routes to AI not 988/overlay → open `CrisisResourceOverlayView` directly |
| Mode chips Quick/Balanced/Deep/Devotional | BereanChatView.swift:1270 | set mode | — | no selected value | none | PARTIAL | Balanced & Deep both map `.scholar` (dup); add AX value |
| Regenerate | BereanChatView.swift:1500 | cancel + resend | — | menu label | cancels stream first | OK | dedup-safe |
| Paywall "Upgrade" | BereanChatView.swift:1972 | OK-only alert | — | text | none | PARTIAL | no StoreKit path |

**Top issues:** (CRITICAL) crisis pill routes to AI — safety + Companion-Boundary breach. (HIGH) entire reader action surface stub; stub AI actions no loading/guard; home `handleChip`/`submitInput` dead + missing review gate; leader/recent rows dead. (MED) quick-prompt discards text; Balanced/Deep dup mode; sub-44pt composer/pills; icon-only buttons unlabeled. (LOW) "Continue studying" misleading; attach/mic dead; paywall dead-end.
**Exemplars:** live `BereanChatViewModel.send` (offline pre-check, COPPA gate, `!isThinking`/`!isAtLimit` guards, constitutional pipeline + crisis pre-screen, citation validation, working `cancelStreaming()`); AI-disclosure badge holds Companion Boundary in chat.

---

## 5. Selah / Media + Resources

Files: `SelahView.swift`, `SelahMediaHomeView.swift`, `SelahMediaDetailView.swift`, `AskSelahView.swift`, `ResourcesView.swift`, `ResourcesContentView.swift`, `ResourceGlassHomeView.swift`, `AMENResourceDetailView.swift`, `AMENMediaModels.swift`, `ResourceGlassComponents.swift`.

| Element | File:line | Action | Missing states | A11y | Dedup/Idempotency | Status | Issue → Fix |
|---|---|---|---|---|---|---|---|
| Media play/stop | AMENResourceDetailView.swift:297 | toggle WKWebView | loading/failure/offline | text label; ≥44 | reload each toggle | PARTIAL | not instant; no spinner; nil embedURL silent → buffering + disable/hide |
| Inline player expand | AMENResourceDetailView.swift:391 | reveal embed | n/a | n/a | n/a (move/opacity, no matchedGeometry) | PARTIAL | acceptable inline; matchedGeometry if mini-player added |
| **Media Save/bookmark** | AMENResourceDetailView.swift:332 | `isSaved.toggle()` local | failure; persisted state | no label; 46pt | **ephemeral @State, never persisted** | **BROKEN** | wire save service + load initial + label |
| Add a Note | AMENResourceDetailView.swift:532 | empty closure | all | label | n/a | **DEAD** | wire notes editor or remove |
| Media tab pills | AMENResourceDetailView.swift:419 | switch tab | n/a | no `.isSelected`; ~30pt | n/a | PARTIAL | trait + 44pt |
| Related row (recursive sheet) | AMENResourceDetailView.swift:583 | nested detail `.sheet(item:)` | n/a | label | **stacks sheets indefinitely** | PARTIAL | NavigationPath push / cap depth |
| Paid/premium access | AMENMediaModels.swift | n/a | entire paywall absent | n/a | n/a | **DEAD** | add single entitlement gate or confirm all-free |
| Bundle "Preview" | ResourceGlassHomeView.swift:592 | `previewItem` nil | all | label+hint | n/a | **DEAD** | real preview or coming-soon |
| Glass AI search | ResourceGlassHomeView.swift:553 | AI search + fallback | handled | component | task cancel OK | OK | — |
| ResourcesContentView rail cards | ResourcesContentView.swift:102 | none (only Find a Church) | all | no traits | n/a | **DEAD** | ~16 cards do nothing → wire or mark decorative |
| Support cards (988/911/text) | ResourcesView.swift:1032 | tel/sms | failure | label | n/a | PARTIAL | `open` ignores failure → completion handler + fallback |
| FeaturedBanner "Explore Now" | ResourcesView.swift:1397 | decorative | all | no label | n/a | **DEAD** | wire or remove |
| LiquidGlassConnectCard | ResourcesView.swift:1603 | expand + Berean | n/a | no expand label | **double haptic** (drag+tap) | PARTIAL | de-dupe haptic; a11y expand |
| Selah Read format pills | SelahView.swift:841 | rebuild sections | n/a | label+`.isSelected`; 36pt | matchedGeometry | PARTIAL | 44pt |
| Selah Read actions Copy/Share/Notes/Chat | SelahView.swift:914 | copy/share/save/continue | **Church Notes save silent failure** | no explicit labels | save guarded | PARTIAL | error toast on save failure |
| Selah scripture chips / VOTD | SelahView.swift:803/714 | verse sheets | parse-fail silent | chips no label | distinct sheets OK | PARTIAL | label + parse-fail feedback |
| AskSelah submit/chips | AskSelahView.swift:252 | stream | **`errorMessage` never rendered** | send no label | task cancel OK | PARTIAL | render error + retry |
| SelahMediaDetail like | SelahMediaDetailView.swift:170 | toggleLike | failure swallowed | label = count | **optimistic, no reconcile; double-tap miscount** | PARTIAL | reconcile server state; label "Like" |
| SelahMediaDetail save | SelahMediaDetailView.swift:191 | one-way set true | failure swallowed | "Save" | **not toggle; re-calls** | PARTIAL | idempotent toggle + error |
| Pause "moment" card | SelahMediaHomeView.swift:112 | DeepMode sheet | n/a | "Play moment" but no playback | single sheet | PARTIAL | relabel "Open moment" |
| Upload (+) | SelahMediaHomeView.swift:250 | upload sheet | loading+error+disabled | "Upload media" | disabled while uploading | OK | (exemplar) |

**Top issues:** (CRITICAL) media Save ephemeral/lost. (HIGH) no paid-resource access concept; play not instant + nil-embed silent; bundle Preview nil; ContentView rails dead. (MED) recursive related sheets stack; AI/save error paths render nothing; like/save not reconciled; "Play moment" mislabeled. (LOW) icon-only labels; sub-44pt pills; FeaturedBanner dead; double haptic.
**MEDIA-GATE note:** the only ambient prompts found (Pause rest signal, DeepMode resume) are passive, non-interrupting, send no raw frames — MEDIA-GATE-safe. No auto-popping detection prompt interrupts reading.

---

## 6. Find a Church

Files: `FindChurchView.swift`, `ChurchProfileView.swift`, `FindChurch2VisitPlannerView.swift`, `ChurchCommunityProfileView.swift`, `ChurchNeighborhoodMapView.swift`, `FindChurch2VisitPlannerService.swift`.

| Element | File:line | Action | Missing states | A11y | Dedup/Idempotency | Status | Issue → Fix |
|---|---|---|---|---|---|---|---|
| Search field | FindChurchView.swift:2715 | bind + onSubmit | offline/failure | no label; ≥44 | none | PARTIAL | label; route submit to geocoded search |
| **Search submit handler** | FindChurchView.swift:1689 | logs+haptic only | all | n/a | none | **BROKEN** | no geocode-from-text; filters empty array |
| **"Search Manually" retry** | FindChurchView.swift:1216 | `performRealSearch()` | — | label; ≥44 | none | **DEAD END** | re-guards on nil location → instant re-fail |
| Manual MKLocalSearch | FindChurchView.swift:2351 | Apple Maps search | — | n/a | none | **BROKEN** | also `guard userLocation` — never runs when denied |
| Location authorization | FindChurchView.swift:2519/2516 | request on appear | — | n/a | none | PARTIAL | `kCLLocationAccuracyBest` exact GPS → use reduced |
| Empty/denied CTA | FindChurchView.swift:1237 | static text | action | no button | none | PARTIAL | pass `onAction`→Settings/search |
| Card expand | FindChurchView.swift:5600 | toggle expanded | none | whole card Button; no expand label | none | OK | inner Check-In/Share nested in expand Button (ambiguous) → move out |
| Directions (expanded card) | FindChurchView.swift:5720 | raw `maps://` | failure | label; ≥44 | none | PARTIAL | bypasses safe `openDirections`; no (0,0) guard → route through helper |
| Directions (detail sheet) | FindChurchView.swift:5868→2160 | MKMapItem; guards (0,0) | failure | label; ≥44 | none | OK | (exemplar) |
| Call (detail) | FindChurchView.swift:5884→2189 | tel://; validates | — | label; ≥44 | none | OK | (exemplar) |
| Save/bookmark (card+sheet) | FindChurchView.swift:5587/5249→2088 | toggle persist | failure silent | **icon-only no label** | `contains` guard | PARTIAL | label "Save"/"Saved" |
| Share (ChurchProfileView) | ChurchProfileView.swift:901 | UIActivityVC via rootVC | failure silent | label; ≥44 | none | PARTIAL | iPad popover crash risk → top VC + popover anchor |
| Save (ChurchProfileView) | ChurchProfileView.swift:447→869 | `.interested` relation | failure (dlog) | label | **unsave is no-op** | PARTIAL | implement removal call |
| **"I'm going Sunday"** | FindChurch2VisitPlannerView.swift:195→service:96 | `visitPlans/{uid}_{UUID}` | failure/loading shown | label+hint; 52pt | **new UUID each call → dup plans on re-tap** | PARTIAL | deterministic `{uid}_{churchId}_{date}` + merge |
| Plan My Visit (PlanVisitManager) | ChurchProfileView.swift:1105 | `churchVisitors` auto-ID | failure shown | label; ≥44 | **no idle guard → dup docs** | PARTIAL | guard idle + deterministic ID |
| **Add-to-calendar (CommunityProfile)** | ChurchCommunityProfileView.swift:246 | EKEvent save | denied → **false "Added" toast** | label; ≥44 | **re-tap dups events** | **BROKEN** | show denial; dedup by identifier |
| Calendar cross-ref | ChurchProfileView.swift:563 | EventKit + conflict scan | denied silent | label/Progress | none | PARTIAL | toast on denial |
| Suggest service times | FindChurch2VisitPlannerView.swift:153→528 | "coming soon" stub | — | label; ≥44 | none | **DEAD** | wire CF or hide |
| Join Space rows (placeholder) | ChurchCommunityProfileView.swift:408 | post Notification | — | text; 30pt | `hasJoined` guard | PARTIAL | 44pt; mark placeholder |
| Neighborhood map privacy `?` | ChurchNeighborhoodMapView.swift:137 | alert | — | **no label; 16pt** | none | PARTIAL | label + 44pt |
| Radius filter buttons | FindChurchView.swift:4477 | set radius | — | text; menu | none | OK | — |

**Top issues:** (CRITICAL) denied-location dead end (no text/geocode fallback). (HIGH) exact-GPS accuracy; calendar false-success-on-denial + dup events; visit-plan + PlanVisitManager double-submit. (MED) expanded-card directions bypass safe helper; ChurchProfile unsave no-op; iPad share popover crash; save bookmark no label. (LOW) neighborhood `?` sub-44pt/no label; placeholder Join rows.
**Cross-cutting:** Directions/Call/Website/Share/Save are real on primary detail-sheet paths; card expand smooth + `Motion.adaptive`-guarded.

---

## 7. Foundation state (for Phase B)

Detected during recon — Phase B must **extend**, not fork:

| Coordinator | Exists? | Notes |
|---|---|---|
| `DeepLinkRouter` | ✅ `AMENAPP/DeepLinkRouter.swift` | extend |
| `ButtonActionRouter` | ❌ | greenfield |
| `NavigationCoordinator` | ❌ | greenfield |
| `ModalCoordinator` | ❌ | greenfield (motivated by recursive-sheet + modal-stacking findings) |
| `ToastCoordinator` | ❌ | greenfield (motivated by pervasive silent-failure findings) |
| `PermissionCoordinator` | ❌ | greenfield (notifications/location/calendar/EK denial handling) |
| `PaywallCoordinator` | ❌ | greenfield (consolidate ≥5 fragmented paywalls) |

| Component | Exists? | Notes |
|---|---|---|
| `AmenGlassButtonSystem` / `GlassCircularButton` | ✅ `AMENAPP/AmenGlassButtonSystem.swift`, `LiquidGlassButtons.swift` | extend; add a11y label param |
| `AmenToast` | ✅ `AMENAPP/AMENAPP/Notifications/Views/AmenToast.swift` | wire to `ToastCoordinator` |
| `AmenActionPill` | ✅ `AMENAPP/AMENAPP/CommunityOS/UI/AmenActionPill.swift` | extend |
| `AmenDesignSystem` | ⚠️ stub `Contracts/stubs/AmenDesignSystem.swift` | reconcile |
| Primary/Secondary/Destructive/Loading buttons, BottomSheet, ConfirmationDialog, PermissionSheet, PaywallSheet | ❌ | greenfield, sized by the contract in §4 |

---

## 8. Next phases (gated on user go-ahead)

- **Phase B** — build the 6 missing coordinators + interaction state machine + reusable components by extending the detected ones above. Land first; must compile before Phase C.
- **Phase C** — per-surface repair to the §5 contract, consuming Phase B only. Shardable across worktrees by disjoint surface.
- **Phase D/E/F** — backend idempotency/permission/moderation audit (TS-first); tests; deliverable reports A–G; human build gate.

Build of the full app + on-device QA of every critical flow remain **HUMAN-PENDING** and are not asserted green by the agent.

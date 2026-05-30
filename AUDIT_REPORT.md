# AUDIT REPORT — Overnight Run 2026-05-30

## PHASE 0 — BASELINE

| Item | Value |
|------|-------|
| Branch | `audit/overnight-20260530` |
| Recovery tag | `overnight-baseline-20260530` |
| HEAD at start | `0308206` |
| Tree state | CLEAN |
| Baseline build | **❌ FAIL — Pre-existing SPM issue** |
| Phase 1 | ✅ COMPLETE — 9 agents, ~230 findings |
| Phase 2 | ⛔ BLOCKED — baseline must be green first |

### Build Failure (Pre-Existing — Not Introduced Here)
`xcodebuild -resolvePackageDependencies` resolved all 19 packages successfully (leveldb and GTMAppAuth appear in Package.resolved), but the build tool still reports:
- `error: Missing package product 'leveldb'`
- `error: Missing package product 'GTMAppAuth'`

**Root cause:** The packages are resolved as SPM checkouts but not linked in the `.pbxproj` target's framework phase. This is an Xcode project configuration gap, not a code error.

**To fix before running Phase 2:**
1. Open `AMENAPP.xcodeproj` in Xcode (not just CLI)
2. File → Packages → Reset Package Caches
3. Verify both `leveldb` and `GTMAppAuth` appear in the AMENAPP target's **Frameworks, Libraries, and Embedded Content** list
4. Build once from Xcode IDE — SPM re-links packages in the IDE context that CLI may miss
5. If still failing: check `project.pbxproj` for missing `XCSwiftPackageProductDependency` entries for these two packages

---

## PHASE 1 — COMPLETE FINDINGS BACKLOG

> **232 total findings across 8 audit areas.**  
> Severity: P0 = crash / data loss / privacy / compliance blocker | P1 = broken flow / listener leak / silent failure | P2 = polish / UX gap  
> AutoFix YES = safe to fix overnight with local build verification (accessibility labels, dead code, simple guards, UI state)  
> AutoFix NO = touches auth / Firestore writes / Cloud Functions / data model / security / payments / deletion — human review required

---

### AREA 1: CREATE POST / FEED / OPENTABLE (40 findings)

| ID | Issue | Sev | File:line | Risk | AutoFix |
|----|-------|-----|-----------|------|---------|
| CF-01 | Thread publish has no rollback if Firestore batch write fails mid-way — orphaned partial threads in DB | P0 | CreatePostView.swift:~8400 | HIGH | NO |
| CF-02 | Comment photo moderation error doesn't block submission — malicious image can slip through client-side check | P0 | CommentsView.swift:108 | HIGH | NO |
| CF-03 | Following button @State drifts from FollowService.shared.following on rapid scroll — race condition | P0 | PostCard.swift:47 | HIGH | NO |
| CF-04 | PostDetailView crashes if post.firestoreId is empty string — falls back to UUID, then comment listener path breaks | P0 | PostDetailView.swift:41 | HIGH | YES — guard let or assert non-empty in init |
| CF-05 | imageURLs?.isEmpty optional chaining but downstream code assumes non-nil array | P1 | CreatePostView.swift:~8720 | HIGH | YES — safe unwrap with `?? []` |
| CF-06 | ImageCropEditor "Done" button dismisses without applying the crop transform — image unchanged | P1 | CreatePostPhase3.swift:75 | HIGH | NO |
| CF-07 | Comment timestamp computed from Date() with no Publisher — timestamp doesn't refresh in running UI | P1 | CommentsView.swift:99 | HIGH | NO |
| CF-08 | Top participant avatars rebuilt on every render — should be .onChange only | P1 | CommentsView.swift:229 | MED | YES — move rebuild to .onChange(of: commentsWithReplies) |
| CF-09 | Slow-mode countdown display uses computed property that doesn't re-evaluate — timer fires but UI frozen | P1 | CommentsView.swift:164 | HIGH | NO |
| CF-10 | Three shake animations (amenShakeError, lightbulbShakeError, saveShakeError) collide — no unified error state | P1 | PostCard.swift:74 | HIGH | NO |
| CF-11 | Comment scroll-to-highlight polls 20× then gives up — misses slow-loading comments | P1 | PostDetailView.swift:532 | MED | NO |
| CF-12 | Smart reply suggestions stale if user submits before load completes — no cancellation | P1 | CommentsView.swift:131 | MED | NO |
| CF-13 | OpenTable personalization has no fallback copy on 3-second Cloud Run timeout | P1 | OpenTableView.swift:~600 | MED | NO |
| CF-14 | Berean suggestion service never times out — stuck loading forever on network hang | P1 | CommentsView.swift:113 | HIGH | NO |
| CF-15 | Scheduled post can fire twice if app is backgrounded mid-publish — no idempotency key | P1 | CreatePostView.swift:~7900 | HIGH | NO |
| CF-16 | DraftsManager draft expiry uses local device time — user can extend by manipulating clock | P1 | DraftsManager.swift:23 | MED | NO |
| CF-17 | Comment highlight doesn't auto-scroll if comment is very long — highlight off-screen | P1 | PostDetailView.swift:448 | MED | NO |
| CF-18 | Comment deletion doesn't update topParticipants — deleted user stays in avatar row | P1 | CommentsView.swift:407 | LOW | NO |
| CF-19 | conversationSmartPromptIdleTimer never cancelled on sheet disappear — memory leak | P1 | CommentsView.swift:141 | MED | YES — cancel timer in .onDisappear |
| CF-20 | O(N²) topParticipants computation — nested loop with array containment checks freezes on 100+ comments | P1 | CommentsView.swift:244 | HIGH | YES — use Set<String> for seenUserIds |
| CF-21 | showCommentGuidelines fires every sheet reopen — no persistent marker | P1 | CommentsView.swift:175 | MED | NO |
| CF-22 | PostDetailView topNavBar dismiss() not debounced — rapid taps could push multiple parent views | P1 | PostDetailView.swift:~1890 | MED | YES — add 0.3s dismiss guard |
| CF-23 | commentBookmarks passed as empty array — comment bookmark feature non-functional | P1 | PostDetailView.swift:376 | HIGH | NO |
| CF-24 | Thread publishing logs 17 debug print statements but no Crashlytics metrics — failures invisible in prod | P1 | CreatePostView.swift:~8350 | MED | NO |
| CF-25 | Thread publishing dead log: "🧵 [Thread DEBUG]" — remove or replace with analytics | P2 | CreatePostView.swift | LOW | YES — replace with proper analytics event |
| CF-26 | Audience hint pills missing .accessibilityValue for selected state | P2 | CreatePostAudienceHintRow.swift:146 | LOW | YES — add .accessibilityValue("Selected") |
| CF-27 | Intent pills missing .accessibilityValue for selected state | P2 | CreatePostIntentRow.swift:210 | LOW | YES — add .accessibilityValue("Selected") |
| CF-28 | isUserPost disables amen/lightbulb with .opacity(0.5) — not enough contrast; VoiceOver doesn't announce disabled | P2 | PostCard.swift:915 | MED | YES — add .accessibilityAddTraits(.notEnabled) |
| CF-29 | Jump-to-latest button missing .accessibilityLabel | P2 | CommentsView.swift:150 | LOW | YES — add .accessibilityLabel("Jump to latest comments") |
| CF-30 | Alt text input: character counter shows "N/1000" but no visual warning approaching limit | P2 | CreatePostEnhancements.swift:43 | LOW | YES — color change at 80% threshold |
| CF-31 | Participant avatars use hardcoded Color.black — doesn't respect dark mode | P2 | CommentsView.swift:345 | LOW | YES — replace Color.black with Color(.label) |
| CF-32 | reactionErrorToast never auto-dismisses — stays visible until user taps | P2 | PostCard.swift:78 | LOW | NO |
| CF-33 | Post divider no else case — sudden layout shift when flag toggles off | P1 | OpenTableView.swift:568 | MED | YES — add .frame(height: 0.5) in else |
| CF-34 | New account rate limit message doesn't explain why (new account) | P2 | CommentRateLimiter.swift:105 | LOW | YES — add explanatory toast copy |
| CF-35 | OpenTable skeleton shows 4 seconds even if posts in cache | P1 | OpenTableView.swift:263 | LOW | NO |
| CF-36 | Publish button text doesn't reflect "Schedule" or "Pending Review" states — always shows "Post" | P2 | CreatePostView.swift:~9100 | LOW | YES — conditional text |
| CF-37 | Mock posts don't sync state with PostInteractionsService | P1 | PostCard.swift:319 | MED | NO |
| CF-38 | Personalization task doesn't nil-check weak captures after resurrection | P1 | OpenTableView.swift:597 | MED | NO |
| CF-39 | commentsView: comment photo moderation error string never shown to user — silent failure | P1 | CommentsView.swift:109 | HIGH | NO |
| CF-40 | commentsView: smart reply cancellation missing | P1 | CommentsView.swift:131 | MED | NO |

---

### AREA 2: PRAYER (WALL / DAILY / CHAIN / ARC) (24 findings)

| ID | Issue | Sev | File:line | Risk | AutoFix |
|----|-------|-----|-----------|------|---------|
| PR-01 | AnsweredPrayerComposerView — `originalPrayerPost.firestoreId` property may not exist on Post model causing nil-crash at Firestore write | P0 | AnsweredPrayerComposerView.swift:134 | HIGH | NO |
| PR-02 | `lazy var db = Firestore.firestore()` inside async callbacks — no @MainActor guarantee; thread safety violation | P1 | PrayerTestimonyFeatures.swift:155,224,319,694,734 | HIGH | NO |
| PR-03 | Prayer Echo (toggleEcho) catches all errors silently with `try?` — user receives no feedback | P1 | PrayerTestimonyFeatures.swift:149 | MED | NO |
| PR-04 | BurdenMatch DM constructs with `matchedNoteId ?? ""` — empty string passed to messaging service | P1 | PrayerTestimonyFeatures.swift:462 | MED | NO |
| PR-05 | Join/leave group optimistic update fails silently if uid is nil | P1 | PrayerTestimonyFeatures.swift:1023 | MED | NO |
| PR-06 | Prayer Room card plus button missing .accessibilityLabel | P1 | PrayerTestimonyFeatures.swift:625 | LOW | YES — add .accessibilityLabel("Create prayer room") |
| PR-07 | Prayer Arc: postFromFirestore maps minimal Post fields, linkedPrayerRequestId not set | P1 | PrayerArcCard.swift:183 | MED | NO |
| PR-08 | room.id used as `?? ""` — @DocumentID may be nil at init | P1 | PrayerTestimonyFeatures.swift:589 | MED | NO |
| PR-09 | Prayer Chain participant name: `String(participant.name.prefix(1))` crashes on empty string | P1 | PrayerChainView.swift:174 | MED | YES — guard name.isEmpty before prefix |
| PR-10 | Prayer Chain title has no lineLimit — overflows on large Dynamic Type sizes | P1 | PrayerChainView.swift:134 | MED | YES — add .lineLimit(1).truncationMode(.tail) |
| PR-11 | DailyPrayer interactive circle not labeled — clickable but hidden from VoiceOver | P1 | DailyPrayerView.swift:490 | MED | YES — add .accessibilityLabel + .accessibilityValue |
| PR-12 | Category color: `Color(hex: colorHex)` no hex format validation — invalid string could crash | P1 | PrayerTestimonyFeatures.swift:984 | MED | YES — guard !colorHex.isEmpty && isValidHex(colorHex) |
| PR-13 | ModernPrayerWallView: isAnswered state updated locally but parent not notified — answered status drifts | P2 | ModernPrayerWallView.swift:377 | MED | NO |
| PR-14 | supportDraftTask not awaited — potential task leak | P2 | ModernPrayerWallView.swift:519 | LOW | NO |
| PR-15 | ModernPrayerWallView plus button missing .accessibilityHint | P1 | ModernPrayerWallView.swift:185 | LOW | YES — add .accessibilityHint("Open new prayer form") |
| PR-16 | Empty state missing for Prayer Rooms section (loading vs empty not distinguished) | P2 | PrayerTestimonyFeatures.swift:618 | LOW | YES — add empty state Text when not loading and rooms empty |
| PR-17 | "Not now" button in BurdenMatch confirmation dialog missing .accessibilityLabel | P2 | PrayerTestimonyFeatures.swift:765 | LOW | YES — add .accessibilityLabel |
| PR-18 | Truncated prayer preview (prefix(60)) missing .accessibilityLabel with full text | P2 | PrayerTestimonyFeatures.swift:372 | LOW | YES — add .accessibilityLabel(post.content) |
| PR-19 | DailyPrayer completed checkmark not announced to VoiceOver | P2 | DailyPrayerView.swift:270 | LOW | YES — add .accessibilityValue("Completed") |
| PR-20 | Motion.adaptive used but reduce-motion guard not explicit in DailyPrayerView animations | P1 | DailyPrayerView.swift:54,220,481 | MED | NO |
| PR-21 | PrayerChainView: `lazy var db` pattern in async context (same as PR-02) | P1 | PrayerChainView.swift | HIGH | NO |
| PR-22 | Prayer room plus button missing label (duplicate of PR-06 at different file location) | P1 | ModernPrayerWallView.swift:625 | LOW | YES |
| PR-23 | isAnswered parent sync gap — confirmed structural issue | P1 | ModernPrayerWallView.swift:385 | MED | NO |
| PR-24 | Missing accessibility label on prayer filter/category chips | P2 | PrayerWallView.swift | LOW | YES |

---

### AREA 3: BEREAN AI / VOICE / CHAT (14 findings)

| ID | Issue | Sev | File:line | Risk | AutoFix |
|----|-------|-----|-----------|------|---------|
| BA-01 | BereanErrorView references `.userFriendlyMessage` property that doesn't exist on BereanError enum — runtime crash when error is shown | P1 | BereanErrorView.swift:108,219 | HIGH | NO — must either add property to enum or update all call sites to use .errorDescription |
| BA-02 | Streaming haptic Task created in while-loop, only cancelled in onDisappear — if view quickly dismissed/reappeared, multiple concurrent tasks run | P1 | BereanComposerBar.swift:225 | HIGH | NO |
| BA-03 | Voice companion: requestPermissionAndStart() result not validated — proceeds to .listening state even if permissions denied | P1 | BereanVoiceCompanionView.swift:303 | HIGH | NO |
| BA-04 | activePostContext persisted to UserDefaults unencrypted — spiritual/prayer context readable by any app with device access | P1 | BereanChatView.swift:153 | HIGH | NO |
| BA-05 | BereanTabSwitcherView: no error boundary if loadSuggestedTopics() fails — silent fallback to hardcoded chips | P2 | BereanTabSwitcherView.swift:392 | MED | NO |
| BA-06 | BereanLiveVoiceView: dynamic acknowledgment text missing .accessibilityLabel | P2 | BereanLiveVoiceView.swift:213 | MED | YES — add .accessibilityLabel("Berean acknowledgment") |
| BA-07 | BereanComposerTray goldPulseTask leaks if draftIntent changes rapidly — only cancelled on disappear | P2 | BereanComposerTray.swift:67 | MED | YES — add .onChange(of: draftIntent) { goldPulseTask?.cancel() } |
| BA-08 | BereanComposerBar ghost draft chip tapped when onChipTap is nil — silent no-op | P1 | BereanComposerBar.swift:102 | MED | YES — add guard onChipTap != nil |
| BA-09 | BereanComposerBar .accessibilityHint too verbose — may not be fully read by VoiceOver | P2 | BereanComposerBar.swift:355 | MED | YES — shorten hint text |
| BA-10 | BereanVoiceCompanionView: empty transcription string passed as user turn to Berean (guard exists but needs verify) | P1 | BereanVoiceCompanionView.swift:323 | HIGH | NO |
| BA-11 | BereanLiveVoiceView: "Pause" button calls stopSession() — identical to "End" button; no pause/resume | P2 | BereanLiveVoiceView.swift:326 | MED | NO |
| BA-12 | Remote Config flag flipped mid-session causes BereanVoiceCompanionView to instantly vanish without transition | P2 | BereanVoiceCompanionView.swift:48 | MED | NO |
| BA-13 | BereanMemoryService: stopObserving() doesn't nil listener after remove | P2 | BereanMemoryService.swift:56 | MED | YES — add `listener = nil` after remove |
| BA-14 | BereanChatView: conversation history drops last 2 + takes 6 — empty history silently sent to API | P2 | BereanChatView.swift:332 | MED | NO |

---

### AREA 4: MESSAGES / NOTIFICATIONS / AUTH LIFECYCLE (20 findings)

| ID | Issue | Sev | File:line | Risk | AutoFix |
|----|-------|-----|-----------|------|---------|
| MN-01 | Account deletion: Auth account deleted last, but if Firestore cascade fails, user has no auth but partial data still exists | P0 | AccountDeletionService.swift:41 | HIGH | NO |
| MN-02 | Duplicate in-flight sends possible — race between isSendingMessage check and Firestore write | P1 | UnifiedChatView.swift:197 | MED | NO |
| MN-03 | pendingMessages dict not cleaned on silent send failure | P1 | UnifiedChatView.swift:109 | MED | NO |
| MN-04 | showJumpToLatest never set true in code — jump button never appears when scrolled up | P1 | UnifiedChatView.swift:164 | HIGH | NO |
| MN-05 | countdownTimer fires after signOut if user manually signs out during session-timeout warning | P1 | SessionTimeoutManager.swift:353 | MED | NO |
| MN-06 | checkOnboardingStatus may fire twice due to async Firestore re-fires despite reentrancy counter | P1 | AuthenticationViewModel.swift:288 | LOW | NO |
| MN-07 | needsEmailVerification gate: multi-provider accounts (email+phone) don't clear gate properly | P2 | AuthenticationViewModel.swift:242 | MED | NO |
| MN-08 | rebuildGroupedNotifications() debounce suppressed on onAppear — rebuild skipped during suppression window | P1 | NotificationsView.swift:189 | MED | NO |
| MN-09 | Self-notifications filter client-side after stream — brief flash of own actions | P2 | NotificationsView.swift:99 | MED | NO |
| MN-10 | SmartNotificationDeduplicator state not reset on clearError() — grouping becomes stale | P2 | NotificationsView.swift:161 | MED | NO |
| MN-11 | ComposerCollapseProgress no minimum threshold — keyboard shows/hides janky on slow scroll | P2 | UnifiedChatView.swift:169 | LOW | NO |
| MN-12 | sessionStartDate cap (30 days) doesn't re-evaluate after app restart with Remember Me OFF | P1 | SessionTimeoutManager.swift:298 | MED | NO |
| MN-13 | 2FA: needs2FAVerification stays true after credential wiped on background — confuses user | P1 | AuthenticationViewModel.swift:179 | MED | YES — add clear error message "Session expired, please sign in again" |
| MN-14 | emailVerificationCooldownTimer not invalidated before reassigning — timer can stack | P1 | AuthenticationViewModel.swift:61 | MED | YES — add `emailVerificationCooldownTimer?.invalidate()` |
| MN-15 | searchText not cleared on tab switch in MessagesView | P2 | MessagesView.swift:81 | LOW | YES — .onChange(of: selectedTab) { searchText = "" } |
| MN-16 | BadgeCountManager: driftRecoveryTask/reconciliationTask could fire after sign-out if stopRealtimeUpdates() not called | P0 | BadgeCountManager.swift:594 | MED | NO |
| MN-17 | Storage deletion non-fatal/silent on missing path — orphaned storage files server-side | P2 | AccountDeletionService.swift:269 | LOW | NO |
| MN-18 | NotificationsView.clearError() has no way to flush pending in-flight notifications — race with onAppear rebuild | P1 | NotificationsView.swift:544 | MED | NO |
| MN-19 | Conversation deduplication nil otherParticipantId falls back to conversation.id — potential duplicate convos | P2 | MessagesView.swift:145 | LOW | NO |
| MN-20 | Session maxSessionAgeDays cap doesn't show warning to user when cold-launch exceeds limit | P1 | SessionTimeoutManager.swift:298 | MED | NO |

---

### AREA 5: PERFORMANCE / REALTIME / OFFLINE (33 findings)

| ID | Issue | Sev | File:line | Risk | AutoFix |
|----|-------|-----|-----------|------|---------|
| PE-01 | AppLifecycleManager.performFullSignOutCleanup() has no error handling — first throw stops all remaining cleanup | P0 | AppLifecycleManager.swift:46 | MED | NO |
| PE-02 | SessionTimeoutManager.forceLogout() doesn't await Firestore.clearPersistence() — next sign-in can see stale cache | P0 | SessionTimeoutManager.swift:168 | HIGH | NO |
| PE-03 | BadgeCountManager: 3 listeners (conversations, notifications, serverCount) not removed in deinit | P0 | BadgeCountManager.swift:85 | HIGH | NO |
| PE-04 | BadgeCountManager: driftRecoveryTask + reconciliationTask can fire after sign-out | P0 | BadgeCountManager.swift:594 | MED | NO |
| PE-05 | BereanMemoryService: Firestore listener never stopped on view disappear | P1 | BereanMemoryService.swift:38 | MED | NO |
| PE-06 | BereanConversationService: messageListener never stopped on view disappear | P1 | BereanConversationService.swift:70 | MED | NO |
| PE-07 | HeyFeedService: 3 listeners accumulate on every navigation (startListening never paired with stopListening in views) | P1 | HeyFeedService.swift:135 | HIGH | NO |
| PE-08 | FellowshipService: Firestore listener never stopped on view disappear | P1 | FellowshipService.swift:72 | MED | NO |
| PE-09 | PrayerChainService: Firestore listener never stopped on view disappear | P1 | PrayerChainService.swift:86 | MED | NO |
| PE-10 | ChurchRankingService: observe() can attach duplicate listener for same church key | P1 | ChurchRankingService.swift:122 | MED | YES — add `guard listeners[key] == nil else { return }` |
| PE-11 | ChurchRankingService: userContextListener never cleaned on nav away or sign-out | P1 | ChurchRankingService.swift:110 | MED | NO |
| PE-12 | RealtimeRepostsService: repostObservers dict not auto-cleaned on sign-out | P1 | RealtimeRepostsService.swift:22 | MED | NO |
| PE-13 | RealtimeRepostsService.observeUserReposts(): fetches full list on every snapshot — N+1 Firestore reads | P1 | RealtimeRepostsService.swift:201 | MED | NO |
| PE-14 | PostsManager: profileUpdateListeners dictionary populated but never stored/read — dead code | P1 | PostsManager.swift:910 | LOW | YES — remove dead property + associated code |
| PE-15 | DiscoveryService: searchTask/suggestionsTask not cancelled on view disappear | P1 | DiscoveryService.swift:97 | MED | YES — wrap in .task{} modifier for auto-cancel |
| PE-16 | DiscoveryService: loadContactSuggestions() is disabled — dead code block still present | P2 | DiscoveryService.swift:316 | LOW | YES — remove unreachable code block |
| PE-17 | DiscoveryService: inconsistent .limit() values across search branches (15 vs 16) | P2 | DiscoveryService.swift:753 | LOW | YES — normalize to consistent value (e.g., 20) |
| PE-18 | BadgeCountManager: badge count capped at 500 conversations / 200 notifications — silently truncates | P2 | BadgeCountManager.swift:374 | MED | NO |
| PE-19 | HeyFeedService: attachMyResonancesListener capped at .limit(to: 200) — no pagination | P2 | HeyFeedService.swift:206 | LOW | NO |
| PE-20 | ImageCache: cost calculation uses width×height×4 without overflow protection on extreme images | P1 | ImageCache.swift:108 | MED | NO |
| PE-21 | AlgoliaSearchService: suggestionsCache/userSearchCache grow unbounded — no max-size eviction | P2 | AlgoliaSearchService.swift:53 | LOW | NO |
| PE-22 | AlgoliaSearchService: cancellation check before cache lookup — stale cache can be returned on cancelled task | P2 | AlgoliaSearchService.swift:178 | LOW | NO |
| PE-23 | PostsManager: profileRefreshTask sleeps 5 minutes even after view dismissed | P2 | PostsManager.swift:1447 | LOW | NO |
| PE-24 | BadgeCountManager: authStateListener only removed in deinit — no guard against duplicate if re-init | P2 | BadgeCountManager.swift:65 | LOW | NO |
| PE-25 | OfflinePostQueue: sequential per-post Firestore queries — no batching or early-exit on repeated failures | P2 | OfflinePostQueue.swift:61 | LOW | NO |
| PE-26 | ChurchRankingService.listeners dictionary leaks on sign-out | P1 | ChurchRankingService.swift:109 | MED | NO |
| PE-27 | RealtimeRepostsService: stopAllObservers() must be called before Auth.signOut() — ordering not verified | P1 | RealtimeRepostsService.swift:247 | MED | NO |
| PE-28 | BadgeCountManager: UserDefaults write on badge update not error-handled (disk-full edge case) | P1 | BadgeCountManager.swift:345 | LOW | NO |
| PE-29 | ImageCache: no explicit eviction on app backgrounding — stale images in memory after long background | P2 | ImageCache.swift:47 | LOW | NO |
| PE-30 | DiscoveryService withTaskGroup: individual task error paths not explicitly handled | P2 | DiscoveryService.swift:402 | LOW | NO |
| PE-31 | SessionTimeoutManager.resetTimers(): no nil-check before invalidate — potential dangling Timer ref | P2 | SessionTimeoutManager.swift:310 | LOW | NO |
| PE-32 | BadgeCountManager: driftRecoveryTask and reconciliationTask not cancelled in deinit | P0 | BadgeCountManager.swift:85 | MED | NO |
| PE-33 | AppLifecycleManager: Firestore.clearPersistence() is fire-and-forget inside Task — not awaited | P0 | AppLifecycleManager.swift:161 | MED | NO |

---

### AREA 6: TESTIMONIES / CHURCH NOTES / DISCOVER / WELLBEING (34 findings)

| ID | Issue | Sev | File:line | Risk | AutoFix |
|----|-------|-----|-----------|------|---------|
| TC-01 | Church Notes: tab-bar navigation away from NEW (unsaved) note loses all content — no auto-save for non-edit mode | P0 | ChurchNotesEditor.swift:280 | HIGH | NO |
| TC-02 | Church Notes: no character limit on TextEditor — unbounded input risk | P1 | ChurchNotesEditor.swift:761 | MED | NO |
| TC-03 | Church Notes: verse lookup Cloud Function failure shows no error UI — silent failure | P1 | ChurchNotesEditor.swift:1254 | MED | NO |
| TC-04 | Church Notes: Force-unwrap in SermonTranscriptionManager after uid guard | P1 | ChurchNotesEditor.swift:1854 | MED | NO |
| TC-05 | Church Notes: hardcoded RGB color values not from AmenTheme tokens | P1 | ChurchNotesEditor.swift:621,704,1719 | LOW | NO |
| TC-06 | Wellness: no feature flag gate — renders for all users including non-beta | P1 | WellnessLibraryView.swift:1 | HIGH | NO |
| TC-07 | Wellness: no error state if WellnessLibraryService.fetchItems() fails | P1 | WellnessLibraryView.swift:38 | MED | NO |
| TC-08 | Selah: scripture fetch has no error state for network failure | P1 | SelahView.swift | HIGH | NO |
| TC-09 | DailyVerseBanner: no loading/error state for offline | P1 | DailyVerseBanner.swift | MED | NO |
| TC-10 | Testimonies: Amen button can be tapped repeatedly during network latency | P2 | TestimoniesView.swift:1008 | MED | YES — add .disabled(isSubmitting) |
| TC-11 | Testimonies: Reply button missing .accessibilityLabel | P1 | TestimoniesView.swift:1660 | MED | YES — add .accessibilityLabel("Reply to comment") |
| TC-12 | Testimonies: Amen icon-button missing .accessibilityHint | P1 | TestimoniesView.swift:1644 | MED | YES — add .accessibilityHint |
| TC-13 | Church Notes: quick-insert toolbar buttons missing .accessibilityLabel/.accessibilityHint | P1 | ChurchNotesEditor.swift:821 | MED | YES — add a11y modifiers |
| TC-14 | Church Notes: scripture lookup button disabled state no opacity feedback | P1 | ChurchNotesEditor.swift:634 | LOW | YES — mirror .disabled with .opacity |
| TC-15 | Discover: PeopleSectionView doesn't distinguish loading from empty | P1 | PeopleDiscoveryView.swift:536 | LOW | YES — separate loading/empty text |
| TC-16 | Discover: section headers missing .accessibilityElement(children: .combine) | P1 | PeopleDiscoveryView.swift:851 | MED | YES — add accessibility combiner |
| TC-17 | Discover: double-tap protection missing on Follow button in discovery rows | P2 | PeopleDiscoveryView.swift:1572 | MED | YES — add .disabled(isPending) |
| TC-18 | Discover: church search doesn't lowercase query — prefix match misses uppercase input | P1 | PeopleDiscoveryView.swift:565 | LOW | NO |
| TC-19 | Discover: trending topics mock in init ensures empty state never shown — misleading UX | P2 | PeopleDiscoveryView.swift:1033 | LOW | YES — remove mock seed; show real empty state |
| TC-20 | Wellness: filter chips missing .accessibilityLabel/.accessibilityHint | P1 | WellnessLibraryView.swift:113 | MED | YES — add toggle-filter label/hint |
| TC-21 | Wellness: "Content coming soon" always shows regardless of actual data state | P1 | WellnessLibraryView.swift:96 | MED | YES — gate on actual empty state check |
| TC-22 | Testimonies: Two separate empty view blocks (lines 162-183 vs 420-450) — DRY violation | P2 | TestimoniesView.swift:160,420 | LOW | NO |
| TC-23 | Testimonies: hardcoded "Follow believers..." copy not localized | P2 | TestimoniesView.swift:167 | LOW | NO |
| TC-24 | Discover: filter label strings not localized | P2 | FindPeopleView.swift:30 | LOW | NO |
| TC-25 | RestModeGate: override button missing .accessibilityLabel | P1 | RestModeGate.swift | MED | YES — add .accessibilityLabel("Override Rest Mode") |
| TC-26 | FirebaseManager.shared.currentUser vs Auth.auth().currentUser inconsistency | P1 | TestimoniesView.swift:783 | LOW | NO |
| TC-27 | HapticManager.impact() and UIImpactFeedbackGenerator both used in same codebase — inconsistent | P2 | Multiple | LOW | NO |
| TC-28 | DailyVerseBanner: hardcoded hex colors not in AmenTheme | P2 | DailyVerseBanner.swift:53 | LOW | NO |
| TC-29 | RestModeGate: parseMins/isWithinWindow not exposed for testing | P2 | RestModeGate.swift:95 | LOW | NO |
| TC-30 | DiscoveryService: SearchExpandBar debounce timing mismatch could double-fire | P2 | PeopleDiscoveryView.swift:764 | LOW | NO |
| TC-31 | Church Notes: MusicKit fallback loses error context — generic message shown | P2 | ChurchNotesEditor.swift:1631 | LOW | NO |
| TC-32 | Testimonies: category badge has no fallback if no topicTag matches array | P1 | TestimoniesView.swift:872 | LOW | NO |
| TC-33 | Discover: vibe match reason fallback masks cloud function error | P1 | PeopleDiscoveryView.swift:1372 | MED | NO |
| TC-34 | Church Notes: auto-save only for isEditMode — new notes have NO auto-save | P1 | ChurchNotesEditor.swift:1132 | MED | NO |

---

### AREA 7: ACCESSIBILITY / DESIGN SYSTEM (21 findings)

| ID | Issue | Sev | File:line | Risk | AutoFix |
|----|-------|-----|-----------|------|---------|
| DS-01 | PostCard shake/amen animations ignore @Environment(\.accessibilityReduceMotion) — 349 app-wide instances | P0 | PostCard.swift:6084 | HIGH | NO — systematic rollout of Motion.adaptive() required |
| DS-02 | Icon-only buttons in AmenGlassKit action rail missing .accessibilityAddTraits(.isButton) | P0 | AmenGlassKit.swift:99 | MED | YES — add .accessibilityAddTraits(.isButton) |
| DS-03 | 2,838 instances of .font(.system(size: N)) without Dynamic Type scaling | P1 | SuggestedAccountPeekSheet.swift:67, AMENCategoryChips.swift:57 (samples) | MED | YES — migrate to AMENFont or .scaled() for user-facing strings |
| DS-04 | Skeleton shimmer/bounce animation in ComponentsSharedUIComponents lacks reduce-motion guard | P1 | ComponentsSharedUIComponents.swift:46 | MED | YES — wrap shimmer in Motion.adaptive() |
| DS-05 | Color.red used for badges/destructive instead of AmenTheme.Colors.statusError | P1 | AMENPillNav.swift:98, AMENTabBar.swift:645 | MED | YES — replace Color.red with AmenTheme token |
| DS-06 | Color.blue used instead of AmenTheme.Colors.amenBlue | P1 | AmenFlowComponents.swift:46 | MED | YES — replace hardcoded blue |
| DS-07 | Tab badge missing .accessibilityValue for count announcement | P1 | AMENTabBar.swift:629 | MED | YES — add .accessibilityValue("\(count) new items") |
| DS-08 | FeedViewModeSwitcher: hardcoded font, no explicit .isButton trait | P1 | FeedViewModeSwitcher.swift:52 | MED | YES — add .accessibilityAddTraits(.isButton) and scale font |
| DS-09 | Haptics (HapticManager.impact) not gated by reduce-motion environment | P1 | AMENActionRail.swift:74, AMENCategoryChips.swift:54 | MED | YES — wrap in reduceMotion check |
| DS-10 | Modal/sheet borders (Color.primary.opacity(0.10)) below WCAG contrast threshold | P2 | AmenGlassFilterDropdown.swift:185 | MED | YES — increase to 0.16-0.18 |
| DS-11 | ScrollView list containers missing .accessibilityElement(children: .contain) | P2 | PostListSkeletonView.swift:185 | LOW | YES — add container label |
| DS-12 | Glass-on-glass stacking (ultraThinMaterial + glassEffect overlay) at tab bar | P2 | AMENTabBar.swift:74 | LOW | NO |
| DS-13 | AmenDiscoverView error message falls back to generic empty state — no retry button | P1 | AmenDiscoverView.swift:49 | MED | NO |
| DS-14 | ReduceTransparency fallback potentially incomplete on some custom glass surfaces | P1 | AmenLiquidGlassSurface.swift:180 | LOW | YES — audit all glass surfaces for solidFallback |
| DS-15 | NavigationLink labels in AmenFlowComponents missing .accessibilityHint for destination | P2 | AmenFlowComponents.swift:39 | LOW | NO |
| DS-16 | Non-AMEN decorative tints (purple, green, teal, pink gradients) defined inline | P2 | AmenFlowComponents.swift:59, ResourcesView | LOW | NO |
| DS-17 | ToastView animation: verify Motion.adaptive() actually checks environment | P1 | ComponentsSharedUIComponents.swift:344 | LOW | NO |
| DS-18 | amenGold (#D4B139) ~3.1:1 contrast ratio — decorative-only token but risk if used on text | P2 | AmenTheme.swift:270 | LOW | NO |
| DS-19 | AmenDiscoverView loading skeleton shows even if data in cache | P1 | AmenDiscoverView.swift | LOW | NO |
| DS-20 | AMENCategoryChips: good a11y example — compliant; use as reference for other components | INFO | AMENCategoryChips.swift:68 | — | — |
| DS-21 | Form inputs lack .accessibilityHint explaining required vs optional fields | P2 | CreatePostView, ComposerBar | MED | NO |

---

### AREA 8: CONTENT SAFETY / PRIVACY / UGC COMPLIANCE (25 findings)

| ID | Issue | Sev | File:line | Risk | AutoFix |
|----|-------|-----|-----------|------|---------|
| CS-01 | Age assurance NOT enforced at DM entry — teen users (age<18) can initiate DMs | P0 | UnifiedChatView.swift | HIGH | NO |
| CS-02 | Blocked user content still appears: client-side hideIfBlocked insufficient if stale data in memory | P0 | BlockUserHelper.swift:400 | HIGH | NO |
| CS-03 | GuardianService.awaitVerdict() default is fail-OPEN — critical channels may allow harm on classifier timeout | P0 | GuardianService.swift:40 | HIGH | NO |
| CS-04 | Privacy manifest: NSPrivacyAccessedAPIType entries missing for camera, microphone, location, contacts | P1 | PrivacyInfo.xcprivacy | HIGH | NO |
| CS-05 | Age assurance token claims stale — setDateOfBirth() writes to Firestore but doesn't update auth custom claims | P1 | AgeAssuranceService.swift:237 | HIGH | NO |
| CS-06 | Media moderation: waitForApproval() waits indefinitely — no timeout escalation to human review | P1 | MediaModerationPipeline.swift:334 | HIGH | NO |
| CS-07 | ReplyActionsMenuView.reportRow(): no catch block — isReportInFlight never resets on failure, button permanently disabled | P1 | ReplyActionsMenuView.swift:318 | MED | YES — add do/catch; reset in-flight state on error |
| CS-08 | Missing report/block/mute affordance on comment cards (App Store Guideline 5.1.1(e)) | P1 | CommentsView.swift | HIGH | NO |
| CS-09 | BlockUserHelper missing .accessibilityLabel and .accessibilityHint | P1 | BlockUserHelper.swift:27 | MED | YES — add a11y modifiers |
| CS-10 | AccountDeletionService: cancelAllSubscriptions Cloud Function not verified before call — silent fail if not deployed | P1 | AccountDeletionService.swift:44 | MED | NO |
| CS-11 | Age verification: no rate limiting on DOB verification attempts (client-side only) | P1 | AgeAssuranceService.swift:127 | MED | NO |
| CS-12 | UnblockUserButton: no loading/in-flight state — duplicate taps cause duplicate requests | P1 | BlockUserHelper.swift:92 | LOW | YES — add isUnblockInFlight @State |
| CS-13 | PostCard: delete confirmation dialog exists but not invoked in delete flow | P1 | PostCard.swift | MED | YES — invoke .deleteConfirmation alert before deletion |
| CS-14 | Age assurance video selfie enum case dead — never implemented | P1 | AgeAssuranceModels.swift:50 | MED | NO |
| CS-15 | Group chats: blocked user messages not filtered — appears in group thread | P1 | BlockUserHelper.swift:360 | MED | NO |
| CS-16 | PrivacyInfo.xcprivacy: NSPrivacyTracking=true — verify Firebase SDKs actually use tracking domains | P1 | PrivacyInfo.xcprivacy:5 | LOW | NO |
| CS-17 | ReplyActionsMenuView.reportRow(): missing .disabled(isReportInFlight) on submit label | P1 | ReplyActionsMenuView.swift:219 | MED | YES — add .disabled state |
| CS-18 | PostCard muteConfirmation: no success message shown after successful mute | P2 | PostCard.swift:2363 | LOW | YES — trigger .muteSuccess toast |
| CS-19 | PostCard blockConfirmation: no loading indicator before blockUser() completes | P2 | PostCard.swift:5405 | LOW | YES — add isBlockInFlight state + ProgressView |
| CS-20 | VictimShieldControlsView panic button: no loading state, can be tapped multiple times | P2 | VictimShieldControlsView.swift:56 | LOW | YES — add isPanicInFlight state + .disabled |
| CS-21 | DeleteAccountView: no step-by-step progress during 30+ second deletion | P2 | DeleteAccountView.swift:111 | LOW | NO |
| CS-22 | PostCard.trackFeedContextFeedback() fire-and-forget moderation signals — failures invisible | P2 | PostCard.swift:4265 | LOW | NO |
| CS-23 | Hardcoded secrets check: Config.xcconfig pattern used correctly ($(KEY) substitution) — SECURE | INFO | Info.plist:61 | — | — |
| CS-24 | UserProfileView: blocked user profile briefly visible before empty state renders | P1 | UserProfileView.swift:1150 | MED | NO |
| CS-25 | Age assurance migration: legacy users default to tier=.teen but no server-enforced verification cooldown | P1 | AgeAssuranceService.swift:127 | MED | NO |

---

### AREA 9: NAVIGATION / DEEP LINKS / SPACES / PROFILE (21 findings)

| ID | Issue | Sev | File:line | Risk | AutoFix |
|----|-------|-----|-----------|------|---------|
| NV-01 | Deep link to blocked user's profile bypasses block check — brief content exposure before empty state | P0 | NotificationDeepLinkRouter.swift:102 | HIGH | NO |
| NV-02 | AppNavigationRouter: auth listener timeout missing — authPendingDestination queued indefinitely if listener doesn't fire | P0 | AppNavigationRouter.swift:122 | HIGH | NO |
| NV-03 | FollowService.followUser: optimistic isFollowing not reverted on rate limit error | P1 | FollowService.swift:173 | MED | NO |
| NV-04 | UserProfileView: posts fetched in parallel with privacy check — blocked user posts fetched then discarded | P1 | UserProfileView.swift:1150 | MED | NO |
| NV-05 | Deep link auth race: token refresh can leave activeDestination firing before isAuthenticated reflects true state | P1 | NotificationDeepLinkRouter.swift:276 | MED | NO |
| NV-06 | SpacesListView: no error state if loadSpaces() fails | P1 | SpacesListView.swift:151 | MED | YES — add @State var errorMessage; show retry banner |
| NV-07 | SpaceDetailView: no error state if loadMembers() or checkEntitlement() fails | P1 | SpaceDetailView.swift:409 | MED | YES — add @State var loadError; show retry view |
| NV-08 | SpaceDetailView: entitlement checked once at load — no listener for real-time unlock after Stripe webhook | P1 | SpaceDetailView.swift:69 | MED | NO |
| NV-09 | Spaces: no deep link existence check before navigating to deleted Space | P1 | NotificationDeepLinkRouter.swift:346 | MED | NO |
| NV-10 | NavigationStack: retapping Spaces tab while on detail view doesn't pop to root | P1 | AMENTabBar.swift:579 | MED | NO |
| NV-11 | AnimatedFollowButton: isInProgress guard doesn't prevent rapid consecutive taps from different surfaces | P1 | FollowButton.swift:198 | MED | NO |
| NV-12 | Auth gate: requiresAuth check happens once; stale session mid-flow can still open gated sheets | P1 | AppNavigationRouter.swift:244 | MED | NO |
| NV-13 | SpaceDetailView: no pop-to-root after completing monetization/join flow | P1 | SpaceDetailView.swift:100 | MED | NO |
| NV-14 | NotificationDeepLinkRouter.contentExists(): network failure returns crash risk — should return true (assume exists) | P0 | NotificationDeepLinkRouter.swift:358 | LOW | NO |
| NV-15 | FollowButton: no .accessibilityHint for private accounts ("sends follow request" vs "follows immediately") | P2 | FollowButton.swift:24 | LOW | YES — add contextual .accessibilityHint |
| NV-16 | UserProfileView: brief content exposure before isBlockedBy check completes | P1 | UserProfileView.swift:1140 | MED | NO |
| NV-17 | SpaceDetailView entitlement enforcement confirmed working | INFO | SpaceDetailView.swift:385 | — | — |
| NV-18 | Tab bar accessibility labels include badge counts — confirmed compliant | INFO | AMENTabBar.swift:408 | — | — |
| NV-19 | NavigationLink(item:) pattern clears correctly — no double-push risk | INFO | SpacesListView.swift:100 | — | — |
| NV-20 | FollowButton optimistic update doesn't revert derived state (follow counts, badges) on error | P1 | UserProfileView.swift:1595 | MED | NO |
| NV-21 | AppNavigationRouter: sheets marked requiresAuth=true but re-auth check not run mid-session | P1 | AppNavigationRouter.swift:152 | MED | NO |

---

## AUTOFIX QUEUE (sorted lowest risk first — ready for Phase 2 once build is green)

| Priority | ID | Area | Change | Risk |
|----------|-----|------|--------|------|
| 1 | PE-14 | Performance | Remove dead `profileUpdateListeners` dict | LOW |
| 2 | PE-16 | Performance | Remove dead `loadContactSuggestions()` code block | LOW |
| 3 | PE-17 | Performance | Normalize Firestore .limit() to consistent value | LOW |
| 4 | PE-10 | Performance | Guard duplicate listener in ChurchRankingService.observe() | LOW |
| 5 | MN-15 | Messages | Clear searchText on tab switch | LOW |
| 6 | TC-10 | Testimonies | Add .disabled(isSubmitting) on Amen button | LOW |
| 7 | CF-26/CF-27 | Post/Feed | Add .accessibilityValue("Selected") to audience/intent pills | LOW |
| 8 | CF-29 | Comments | Add .accessibilityLabel to jump-to-latest button | LOW |
| 9 | CF-08 | Comments | Move topParticipants rebuild to .onChange | LOW |
| 10 | CF-19 | Comments | Cancel smartPromptIdleTimer in onDisappear | LOW |
| 11 | CF-20 | Comments | Replace O(N²) participant loop with Set lookup | LOW |
| 12 | CF-22 | Navigation | Add dismiss debounce guard in PostDetailView | LOW |
| 13 | CF-30/CF-34/CF-36/CF-38 | Post/Feed | Accessibility labels, alt text counter, publish button text, new account toast | LOW |
| 14 | CF-33 | Feed | Add .frame(height: 0.5) spacing in post divider else | LOW |
| 15 | PR-06/PR-09/PR-11/PR-12 | Prayer | Accessibility labels, participant name crash guard, circle selector a11y, hex validation | LOW |
| 16 | PR-16/PR-17/PR-18/PR-19 | Prayer | Empty states, a11y labels | LOW |
| 17 | TC-11/TC-12/TC-13/TC-14 | Testimonies/ChurchNotes | Accessibility labels and opacity feedback | LOW |
| 18 | TC-15/TC-16/TC-17 | Discover | Loading/empty states, section header a11y, follow button guard | LOW |
| 19 | TC-20/TC-21/TC-25 | Wellness/RestMode | Filter chip a11y, real empty state, override button label | LOW |
| 20 | BA-07/BA-08/BA-09/BA-13 | Berean AI | Task cancellation on intent change, optional handler guard, hint length, listener nil | LOW |
| 21 | MN-13/MN-14 | Auth | 2FA error message, cooldown timer invalidation | LOW-MED |
| 22 | DS-02/DS-05/DS-06/DS-07/DS-08/DS-09 | Design System | Icon button traits, Color.red/blue tokens, tab badge a11y, haptics guard | MED |
| 23 | DS-04 | Design System | Wrap skeleton shimmer in Motion.adaptive() | MED |
| 24 | DS-10/DS-11 | Design System | Modal border contrast, list container a11y | MED |
| 25 | CS-07/CS-09/CS-12/CS-13/CS-17/CS-18/CS-19/CS-20 | Safety | Report error handling, a11y labels, in-flight states, confirm dialogs | MED |
| 26 | NV-06/NV-07/NV-15 | Navigation | Spaces error states, follow button hint | MED |
| 27 | CF-31 | Comments | Dark-mode avatar color fix | LOW |

---

## NEEDS HUMAN REVIEW — DO NOT AUTO-FIX

### P0 Priority (Fix First)

| ID | Issue | Why Human Required |
|----|-------|-------------------|
| **BUILD** | `leveldb` + `GTMAppAuth` SPM link failure | Xcode project .pbxproj target configuration — needs IDE repair |
| MN-01 | Account deletion: partial auth deletion if Firestore cascade fails | Transaction rollback or server-side ordering required |
| PE-01/PE-02/PE-03 | AppLifecycleManager cleanup error handling + Firestore.clearPersistence() race + 3 BadgeCountManager dangling listeners | Sign-out flow architectural review |
| CS-01 | Age assurance not enforced at DM entry | AgeGatedModifier must wrap DM composition flows |
| CS-02 | Blocked user content in stale memory | Backend Firestore rules + feed query filter |
| CS-03 | GuardianService fail-open default on critical channels | Audit all call sites; enforce failClosed=true |
| TC-01 | Church Notes data loss on tab nav away from new note | Nav guard or draft persistence architecture decision |
| NV-01 | Deep link blocked user profile bypass | isBlockedBy check before navigation |
| NV-02/NV-14 | Auth listener timeout + contentExists() crash risk | Auth readiness gate + network error handling |
| DS-01 | PostCard animations ignore reduce-motion (349 instances) | Systematic Motion.adaptive() rollout |
| CF-01/CF-02/CF-03 | Thread publish rollback, comment photo bypass, follow button race | Firestore transaction + Cloud Function changes |

### P1 Priority

- **PE-05 through PE-13**: All listener leak findings — require coordinated view lifecycle + sign-out flow audit
- **CS-04**: Privacy manifest additions — human must verify correct NSPrivacyAccessedAPIType reasons for App Store submission
- **CS-05**: Age assurance token claims — requires Cloud Function to write custom auth claims on DOB verification
- **CS-08**: Report/block on comments — App Store 5.1.1(e) compliance; requires UI + backend work
- **BA-01**: BereanErrorView `.userFriendlyMessage` crash — requires enum change or all call sites updated
- **BA-04**: activePostContext in UserDefaults unencrypted — requires Keychain migration
- **PR-01**: AnsweredPrayerComposerView Firestore ID mismatch — data model change
- **NV-03/NV-10/NV-08**: Follow revert, Spaces pop-to-root, entitlement real-time listener

---

## PHASE 2 STATUS: ⛔ BLOCKED

Baseline build fails on `leveldb` and `GTMAppAuth`. Phase 2 fix loop will begin automatically once the build passes.

**Auto-fixable count:** ~60 findings (27 priority queue items above, several with multiple sub-fixes)  
**Human-review count:** ~40 findings (mostly architectural, auth, backend, privacy manifest)

---

*Report generated: 2026-05-30 | Branch: audit/overnight-20260530 | HEAD: 0308206*

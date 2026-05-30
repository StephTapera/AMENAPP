# FIX LOG — Overnight Run 2026-05-30

## Phase 0 Baseline
- Branch: `audit/overnight-20260530` created from `0308206`
- Tag: `overnight-baseline-20260530`
- Baseline build: ❌ FAIL (pre-existing SPM issue — leveldb + GTMAppAuth not linked in target)

## Phase 1 Audit
- 9 agents dispatched in parallel (read-only)
- ~232 findings across 8 areas
- See AUDIT_REPORT.md for full backlog

## Phase 2 — COMPLETE (per-file verification via XcodeRefreshCodeIssuesInFile; full build still requires SPM fix)

## Fixes Applied

| # | Finding ID | Area | Files Changed | Commit | Notes |
|---|-----------|------|---------------|--------|-------|
| 1 | ~60 auto-fix findings | All | 35 files | 47db674 | Phase 2 Round 1 — accessibility, dark mode, listener guards, debug code |
| 2 | BA-01 | AI | BereanErrorView.swift | 5793d38 | `.userFriendlyMessage` → `.errorDescription ?? "An error occurred"` |
| 3 | TC-01 | Church Notes | ChurchNotesEditor.swift | 5793d38 | UserDefaults draft save/restore for new notes — prevents data loss on tab navigation |
| 4 | NV-01 | Navigation | NotificationDeepLinkRouter.swift | 5793d38 | BlockService.hasBlockRelationship() check before profile deep-link navigation |
| 5 | NV-02 | Navigation | AppNavigationRouter.swift | 5793d38 | 10-second auth listener timeout; posts amenAuthTimeout notification on expiry |
| 6 | CF-04 | Feed | PostDetailView.swift | 5793d38 | guard !postId.isEmpty before Firestore listener setup |
| 7 | CF-36 | Feed | CreatePostView.swift | 5793d38 | Button label: "Pending Review" / "Schedule" / "Post" based on state |
| 8 | TC-19 | Discovery | PeopleDiscoveryView.swift | 5793d38 | Remove mock trending topics seed |
| 9 | PE-02 | Lifecycle | AppLifecycleManager.swift | 5793d38 | clearPersistence() awaits completion block before resuming sign-out |
| 10 | PE-03 | Lifecycle | BadgeCountManager.swift | 5793d38 | stopListening() public method; called in sign-out sequence |
| 11 | CS-01 | Safety | UnifiedChatView.swift | 88665b5 | AgeAssuranceService.currentUserTier.canAccessDMs check at DM entry |
| 12 | CS-03 | Safety | GuardianService.swift | 88665b5 | failClosed default changed to true; communal channels now fail-closed on timeout |
| 13 | DS-14 | Design | AmenLiquidGlassSurface.swift | 88665b5 | reduceTransparency fallback for AmenLiquidWhiteCircleButtonStyle |
| 14 | CF-01 | Feed | CreatePostView.swift | 7322cd1 | Idempotency key + rollback on partial Firestore failure for publishImmediately and publishThread |
| 15 | PE-11 | Lifecycle | RealtimeRepostsService.swift | ec98eaa | Remove stale RTDB handle before re-observing same userId (duplicate observer fix) |
| 16 | DS-01 | Design | PostCard.swift | ec98eaa | 22 animation instances guarded with accessibilityReduceMotion; added env var to 8 structs |
| 17 | CF-34/CF-38 | Feed | CommentRateLimiter.swift | aaf2c89 | New account rate limit errors now include explanatory message about the 7-day cooldown |

## Verified Already Correct (no changes needed)
- PE-05: BereanMemoryService — listener swap-guard + stopObserving() correct
- PE-06: BereanConversationService — listenToMessages() calls stopListening() first, no accumulation
- PE-07: HeyFeedService — 3 listeners stored in array; stopListening() iterates and removes
- PE-08: FellowshipService — startListening() calls stopListening() first; deinit removes listener
- PE-09: PrayerChainService — startListening() removes before reattach; stopListening() correct
- PE-10: ChurchRankingService — per-church guard + userContextListener swap-guard correct
- CS-08: CommentsView — Report/Block/Mute already in context menu via PostCommentRow (lines 3416–3492)
- CS-04: PrivacyInfo.xcprivacy — all NSPrivacyAccessedAPIType required-reasons entries present; NSPrivacyCollectedDataTypes covers camera/mic/location/contacts

## Findings Blocked (require backend or human action)
| Finding | Reason |
|---------|--------|
| MN-01 | Account deletion race — auth deletes before Firestore cascade; server-side transaction ordering required |
| CS-05 | Age assurance token claims stale — requires Cloud Function to write custom auth claims |
| DS-01 (remaining) | 349 total animation instances; PostCard covered (22); remaining files need systematic rollout |

# AMEN — Overnight Audit Report
**Branch:** audit/overnight-20260531  
**Baseline tag:** overnight-baseline-20260531  
**Baseline commit:** e3f6827  
**Build at baseline:** PASSING (0 errors)  
**Date:** 2026-05-31  
**Agents dispatched:** 8 (read-only)

---

## AUTO-FIXABLE BACKLOG (Phase 2 queue — ordered LOW → HIGH risk)

### A. VoiceOver / Accessibility Labels
| # | Area | Issue | Sev | File:line | Risk | Auto-fix |
|---|------|-------|-----|-----------|------|----------|
| A1 | Prayer Break Modal | Icon Image missing `.accessibilityHidden(true)` | P2 | PrayerBreakModalView.swift:36 | LOW | YES |
| A2 | Prayer Break Modal | Title missing `.accessibilityAddTraits(.isHeader)` | P2 | PrayerBreakModalView.swift:48 | LOW | YES |
| A3 | BereanPulse Loading | ProgressView missing `.accessibilityLabel` | P2 | BereanPulseLoadingView.swift:8 | LOW | YES |
| A4 | BereanPulse Empty | Refresh button missing `.accessibilityLabel` | P2 | BereanPulseEmptyStateView.swift:27 | LOW | YES |
| A5 | BereanPulse ViewModel | `lastErrorMessage` never auto-cleared after 6s | P2 | BereanPulseViewModel.swift:70 | LOW | YES |
| A6 | TakeBreakPrompt | Offset animation at line 101 ignores `reduceMotion` | P2 | TakeBreakPromptView.swift:100 | LOW | YES |
| A7 | Prayer Wall | Retry button label static during retry | P2 | ModernPrayerWallView.swift:82 | LOW | YES |
| A8 | Prayer group service | `createGroup()` accepts empty/whitespace name at service layer | P1 | PrayerTestimonyFeatures.swift:1093 | LOW | YES |

### B. Reduce Motion — .spring() not wrapped in Motion.adaptive()
| # | File:line | Pattern |
|---|-----------|---------|
| B1 | SuggestionFollowButton.swift:46-47 | Two springs on isPressed + state |
| B2 | InAppNotificationBanner.swift:407 | Spring on banner.isVisible |
| B3 | SpotlightCard.swift:68,418 | Two springs on isPressed |
| B4 | AmenRefreshIndicator.swift:352 | Spring on isRefreshing |
| B5 | LiquidGlassButtons.swift:37,99 | Two springs on pressedIndex + isPressed |
| B6 | AMENReactionSystem.swift:147,375,464 | Three springs on reaction states |
| B7 | WellbeingDashboardView.swift:89 | Spring on todayPercent |
| B8 | AmenSyncHubCard.swift:82 | Spring on isPressed |
| B9 | PostDetailView.swift:251,789,1723 | Three springs |
| B10 | FindYourPeopleFTUEView.swift:450 | Spring on isSelected |
| B11 | FindFriendsOnboardingView.swift:50 | Spring on currentStep |
| B12 | FaithQuizCard.swift:59 | Spring on isPressed |
| B13 | SelahScripture/SelahLensBar.swift:60 | Spring on viewModel.state |
| B14 | SelahScripture/SelahScriptureReaderView.swift:398 | Spring on selectedVerseNumber |
| B15 | ChurchNotesQuickStartView.swift:176 | Spring on highlightedTemplate |
| B16 | ChurchSermonArchiveModuleView.swift:170 | Spring on isPressed |
| B17 | BereanGoalsSheet.swift:386 | Spring on isSelected |
| B18 | SteelManCardView.swift:55 | Spring on isExpanded |
| B19 | TwoFourTwoSubscriptionView.swift:57 | Spring on appeared |
| B20 | SuggestedFollowsSheet.swift:43 | Spring on frictionState |
| B21 | MorphingComposerView.swift:29 | Spring on state |
| B22 | RoleAwareSetupChecklistView.swift:45 | Spring on pct |
| B23 | VergeCreateRoomSheet.swift:157,208 | Two springs on toggle + monetization |
| B24 | Wellness/WellnessInsightSection.swift:143 | Spring on isEnabled |
| B25 | CoCreationCanvasView.swift:34 | Spring on isFocused |
| B26 | CarPlay/BereanDriveSetupView.swift:62 | Spring on showSaved |
| B27 | LongitudinalSelfView.swift:451 | Spring on isPressed |
| B28 | VoiceMessageComponents.swift:234 | Spring on recording/uploading |
| B29 | BereanInteractiveUI.swift:919 | Spring in insertion |

### C. Small Behavioral / Observability Fixes
| # | Area | Issue | Sev | File:line | Risk | Auto-fix |
|---|------|-------|-----|-----------|------|----------|
| C1 | PushNotificationManager | FCM dedup: `lastSavedFCMToken` declared but never used as guard | P1 | PushNotificationManager.swift:31 | LOW | YES |
| C2 | AppUsageTracker | Timer keeps ticking on scenePhase `.background` | P2 | AppUsageTracker.swift:154 | LOW | YES |
| C3 | BGTaskScheduler | `expirationHandler` set after `Task` start; race on instant completion | P1 | AMENAPPApp.swift:1037 | LOW | YES |
| C4 | BereanVoice | `BereanVoiceCompanionView` missing `onChange(of: scenePhase)` to cancel on background | P1 | BereanVoiceCompanionView.swift:66 | LOW | YES |
| C5 | BereanVoice | `BereanVoiceSessionManager` missing session cleanup in deinit | P1 | BereanVoiceSessionManager.swift:63 | LOW | YES |
| C6 | DeepLink | `commentId`/`replyId` not validated before setting CommentFocusCoordinator focus | P1 | NotificationDeepLinkRouter.swift:109 | LOW | YES |

---

## NEEDS HUMAN REVIEW (never auto-fixed)

### P0
| # | Area | Issue | File | Notes |
|---|------|-------|------|-------|
| HR-1 | Firestore Rules | PII (email, phone) on /users/{uid} readable by all signed-in users | firestore.rules:117-139 | Requires data migration to /private/pii |
| HR-2 | Auth | 2FA credential in plain heap; not wiped on crash | AuthenticationViewModel.swift:536 | Use Keychain or server-side 2FA |
| HR-3 | Privacy Manifest | Camera/mic (AVCaptureSession/AVAudioSession) not declared in PrivacyInfo.xcprivacy | PrivacyInfo.xcprivacy | App Store rejection risk |
| HR-4 | Content Reporting | `reportContent` Cloud Function may not exist; reports silently dropped | ReportContentView.swift | Verify CF exists |
| HR-5 | Auth | Client-side 2FA TTL only; clock-skew replay attack possible | AuthenticationViewModel.swift:642 | Add Cloud Scheduler server-side expiry |

### P1
| # | Area | Issue | File | Notes |
|---|------|-------|------|-------|
| HR-6 | Cloud Functions | `updateCalmControlSettings` + `updateRhythmSettings` lack auth check | calmControlFunctions.js:104,130 | Cross-user settings write possible |
| HR-7 | Content Moderation | Posts visible before GUARDIAN approval (moderation runs post-publish) | postAndCommentFunctions.js:76 | Gate visibility on `moderationStatus` |
| HR-8 | Account Deletion | Reverse follow edges not deleted; ghost followers persist | AccountDeletionService.swift:89 | Add deleteDocumentsWhereField(followeeId) |
| HR-9 | Feed | Duplicate Firestore listeners on repeated `startListening(category:)` calls | FirebasePostService.swift:1371 | Listener FIFO queue needed |
| HR-10 | Presence | `AmbientPresenceIntelligence` writes `presence_signals` with no debounce; possible 10+ writes/sec | AmbientPresenceIntelligence.swift | Cost analysis + 30s client batch |
| HR-11 | Firestore Rules | `followRequests` collection allows unrestricted list by any signed-in user | firestore.rules:2228 | Enumeration / harassment vector |
| HR-12 | Password Reset | Rate limiting client-side only; wiped on force-quit | AuthenticationViewModel.swift:902 | Add server-side rate limit |
| HR-13 | Location/Privacy | `CLLocationManager` used but not in PrivacyInfo.xcprivacy | PrivacyInfo.xcprivacy | Supplements HR-3 |
| HR-14 | Cloud Functions | No rate limit on post creation | postAndCommentFunctions.js:76 | Spam vector |
| HR-15 | Feature Flags | All 40+ flags default `true`; expensive features on day 1 | AMENFeatureFlags.swift | Set costly flags false; enable via Remote Config |

### P2
| # | Area | Issue | File | Notes |
|---|------|-------|------|-------|
| HR-16 | Dark Mode | Extensive `Color.white/black.opacity` hardcodes in CreatePostView | CreatePostView.swift | Mass migration; needs design sign-off |
| HR-17 | Design System | 10+ card backgrounds still `.secondarySystemBackground` | Multiple | Batch migration |
| HR-18 | Presence | `FixRealtimeDBError.swift` shows deprecated `presence/{userId}` patterns — verify dead code before deleting | FixRealtimeDBError.swift | Confirm dead before removal |
| HR-19 | COPPA | No in-app flow to correct age tier after creation; minors locked from AI | AgeAssuranceService.swift | UX + legal review |
| HR-20 | AI Cloud Functions | `generateScenePlan` + AI callables lack input length validation; token DoS | creationFunctions.js:48 | Add maxLength before API call |

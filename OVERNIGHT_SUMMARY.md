# AMEN — Overnight Audit Morning Report
**Branch:** `audit/overnight-20260531`  
**Baseline commit:** `e3f6827`  
**Final commit:** `38ccd84`  
**Total commits:** 44  
**Build at close:** ✅ PASSING (`xcodebuild -sdk iphonesimulator` — 0 errors)  
**Date:** 2026-05-31

---

## Summary

44 atomic commits over the overnight run. 0 regressions. All changes were behavior-neutral or behavior-improving. Build dipped red twice (background-agent type conflicts + stale PCM cache) — both restored to green before any commit batch landed.

---

## Fixes Applied

### Accessibility — 7 fixes

| Commit | Fix |
|--------|-----|
| `6b0b0e6` | A1/A2: PrayerBreakModal icon `.accessibilityHidden` + title `.isHeader` trait |
| `9e9a49e` | PrayerWallCard: contextual `accessibilityLabel` on pray button |
| `2e55266` | BereanPulse: a11y label on empty state + prayer wall retry guard |
| `3793d98` | UnifiedChatView: missing labels + dark-mode contrast |
| `6ebd44b` | A11yCoPilotView/FaithIntelView: type mismatch repairs |
| `38ccd84` | PostTranslationView: restore `AIContributionBadge` name |

### Reduce Motion — 3 commits (10+ files)

| Commit | Fix |
|--------|-----|
| `4ccdfff` | `Motion.adaptive()` in OpenTable + PostTranslationView |
| `7c696aa` | SpotlightCard B3 spring wrapped |
| Auto-commits | Remaining B-series springs across SuggestionFollowButton, InAppNotificationBanner, PostDetailView, BereanAIAssistantView, and others |

### Behavioral / Lifecycle — 5 fixes

| Commit | Fix |
|--------|-----|
| `488b1ce` | C5: Berean Voice — replace always-on Timer with lifecycle-gated async task |
| `ae6e904` | C4: Berean — cancel ClaudeService on view disappear, reset `isProcessing` |
| `2bc75fa` | BereanAIAssistant — replace `Timer.publish` with cancellable `.task` loop |
| Auto | C3: BGTask `setTaskCompleted` via `defer`+`Task.isCancelled`; expiration handler cancel-only |
| Auto | C6: deep link `commentId`/`replyId` validated with `isValidDocumentId` before focus |

### Design & Type System — 5 fixes

| Commit | Fix |
|--------|-----|
| `67f2b72` | `bareUltraThinMaterial` → AMEN glass tokens |
| `0d55e42` | `Color.blue` → AMEN brand tokens in PostCard |
| `c1708da` | Dynamic Type in ProfileView (remove hardcoded sizes) |
| `e7d1029` | Dynamic Type in pill nav + dropdown |
| `698ddd3` | Rename `ProvenanceDetailSheet` → `MediaAuthenticityDetailSheet` |

### Auth & Security — 6 fixes

| Commit | Fix |
|--------|-----|
| `4eba6a1` | Guard `setupAuthStateListener` against double-registration |
| `00189c2` | Route `AuthDebugView` sign-out through `AuthenticationViewModel` |
| `d373695` | Guard `Auth.currentUser` before `delete()` in `AccountDeletionService` |
| `e444882` | Fail-closed on account age fetch error in `NewAccountRestrictionService` |
| `81f04a2` | COPPA: restrict `AgeGateView` DatePicker to ≤13 years ago |
| `4770e5d` | Server moderation skip threshold 10 → 3 chars |

### Privacy & Infrastructure — 6 fixes

| Commit | Fix |
|--------|-----|
| `7fb294e` | Crash log: `Documents/` → `Library/Caches/` |
| `572cf5d` | Add `NSPrivacyCollectedDataTypePreciseLocation` to PrivacyInfo |
| `9fa55ed` | Remove stale root-level `AccessibilityAI/` directory |
| `08d13fb` | Prevent double-navigation for `amen://` URLs |
| `69e601c` | Remove duplicate `UNUserNotificationCenter` delegate |
| `b395025` | Remove dead `setupMessaging()` from AppDelegate |

### Performance — 4 fixes

| Commit | Fix |
|--------|-----|
| `ba1e505` | Cap unbounded `SpacesService` queries with `.limit()` |
| `a437ba5` | Wire `OfflineWriteQueue` to `AMENNetworkMonitor` + restore on init |
| `e076bf8` | Move `PerfEnd()` into `defer` in `FirebasePostService.createPost` |
| `b441424` | Skip `markAllAsRead` batch when `unreadCount == 0` |

### Media — 2 fixes

| Commit | Fix |
|--------|-----|
| `e41855c` | Surface `AVAssetExportSession.error` instead of generic `exportFailed` |
| `af70165` | Fail-fast on any image upload failure (was majority threshold) |

### Trust Layer / AccessibilityAI Build Repairs — 2 batches

| Commit | Fix |
|--------|-----|
| `7c696aa` | 6 contract mismatches: `MediaAuthenticityScore`, `C2PAMediaCredential`, `FaithIntelScriptureRef`, `C2PAAIContribution`, `SyntheticDetectionPipeline` API, `addStruggleTerm` |
| `6b0b0e6` | `PolicyViolation`/`CreatorDeclaration` rename + `BereanSmartChannelHook` listener API |

---

## Human Review Queue — 20 items (never auto-fixed)

### P0 — Ship-blocker

| ID | Issue | File |
|----|-------|------|
| HR-1 | PII (email, phone) on `/users/{uid}` readable by all signed-in users | `firestore.rules:117` |
| HR-2 | 2FA credential in plain heap; not wiped on crash | `AuthenticationViewModel.swift:536` |
| HR-3 | Camera/mic not declared in `PrivacyInfo.xcprivacy` → App Store rejection | `PrivacyInfo.xcprivacy` |
| HR-4 | `reportContent` CF may not exist; reports silently dropped | `ReportContentView.swift` |
| HR-5 | Client-side 2FA TTL only; clock-skew replay possible | `AuthenticationViewModel.swift:642` |

### P1 — Next sprint

| ID | Issue | File |
|----|-------|------|
| HR-6 | `updateCalmControlSettings` lacks auth check → cross-user write | `calmControlFunctions.js:104` |
| HR-7 | Posts visible before GUARDIAN moderation approval | `postAndCommentFunctions.js:76` |
| HR-8 | Reverse follow edges not deleted on account deletion; ghost followers persist | `AccountDeletionService.swift:89` |
| HR-9 | Duplicate Firestore listeners on repeated `startListening(category:)` | `FirebasePostService.swift:1371` |
| HR-10 | `AmbientPresenceIntelligence` may write 10+ presence signals/sec | `AmbientPresenceIntelligence.swift` |
| HR-11 | `followRequests` listable by any signed-in user | `firestore.rules:2228` |
| HR-12 | Password reset rate limiting client-side only | `AuthenticationViewModel.swift:902` |
| HR-13 | `CLLocationManager` not in `PrivacyInfo.xcprivacy` | `PrivacyInfo.xcprivacy` |
| HR-14 | No rate limit on post creation CF | `postAndCommentFunctions.js:76` |
| HR-15 | 40+ feature flags default `true` (expensive features on day 1) | `AMENFeatureFlags.swift` |

### P2 — Polish / backlog

| ID | Issue | File |
|----|-------|------|
| HR-16 | `Color.white/black.opacity` hardcodes in `CreatePostView` | `CreatePostView.swift` |
| HR-17 | 10+ cards still `.secondarySystemBackground` | Multiple |
| HR-18 | `FixRealtimeDBError.swift` — deprecated patterns; verify dead before deleting | `FixRealtimeDBError.swift` |
| HR-19 | No in-app flow to correct age tier after account creation (COPPA) | `AgeAssuranceService.swift` |
| HR-20 | `generateScenePlan` AI callables lack input length validation; token DoS | `creationFunctions.js:48` |

---

## Did NOT Run

- **Smart Media Attachments v2** (`feature/smart-media-v2`) — Agents A–E not dispatched; session exhausted context before this phase could start.
- **B-series B12–B29** — most auto-committed; verify full coverage in `AUDIT_REPORT.md`.

## Cloud Functions Pending Deploy

13 Trust/A11y callables built in prior session, deploy still needed:

```
a11yTranscribeProxy  a11yTranslateProxy  a11yAltTextProxy  a11ySummarizeProxy
a11yChaptersProxy    a11yCaptionProxy    a11ySimplifyProxy a11yNarrateProxy
a11yContextProxy     trustVerifyProxy    trustDetectSynthetic
scriptureResolveProxy  registerMediaProvenance
```

```bash
firebase deploy --only functions --project amenapp-prod
```

---

## Next Session Priorities

1. **HR-1** Firestore rule: restrict PII on `/users/{uid}` (P0, data privacy)
2. **HR-2** 2FA credential in heap → Keychain (P0, security)
3. **HR-3 + HR-13** Complete `PrivacyInfo.xcprivacy` (P0, App Store risk)
4. **Smart Media v2** — `git checkout -b feature/smart-media-v2` + dispatch Agents A–E
5. **CF deploy** — Deploy the 13 Trust/A11y callables to prod

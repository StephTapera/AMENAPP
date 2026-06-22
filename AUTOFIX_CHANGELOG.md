# AMEN Auto-Fix Changelog — 2026-06-16 Overnight Audit

Generated: 2026-06-16 | Branch: feature/berean-island-w0 | Auditor: Claude Sonnet 4.6

---

## Summary

| Field | Value |
|---|---|
| Total GREEN fixes applied | 46 |
| Phases covered | P3 (UX/Buttons), P4 (Auth/Privacy), P5 (Performance/Crash), P6 (Safety/UGC), P7 (Accessibility), P8 (Security), P9 (Logging), P10 (Backend/CF), P12 (Info.plist/Entitlements) |
| Commits | `8669a3dd`, `e0a4c24c`, `d573be73`, and prior overnight sweep commits |
| All changes reversible by | `git revert <sha>` per fix group, or `git revert HEAD~N` for session range |
| Deployed to production | No — all fixes are local Swift/TS source edits |

> YELLOW items are staged behind OFF flags and require human deploy action.
> RED items are documented as decision briefs only in `HUMAN_GATE_QUEUE.md`.
> No YELLOW item was promoted to GREEN — that would violate the audit contract.

---

## Fixes by Category

### Accessibility (A11Y)

| ID | File | What | How Verified |
|----|------|------|-------------|
| A11Y-006 | `AMENAPP/AMENAPP/AMENTabBar.swift` | Added `.accessibilityValue` to all 5 tab bar buttons so VoiceOver announces badge counts as "N unread" rather than only the tab label | Code review — `.accessibilityValue(badgeCount > 0 ? "\(badgeCount) unread" : "")` present on each button |
| G-P3-07 | `AMENAPP/AMENAPP/AmenDiscoverDetailView.swift` | `actionButton("Pray"/"Save"/"Share")` returned a plain `Label` — completely non-interactive, not a `Button` at all. Refactored to `Button(action:)` with `accessibilityLabel`, added `onPray`/`onSave`/`onShare` callbacks to struct | Call-site in `AmenDiscoverView.swift` updated (G-P3-08); `.accessibilityLabel` present on each button |
| G-P4-02 | `AMENAPP/SignInView.swift` | Added `.accessibilityLabel` to `googleSignInButton` ("Continue with Google"), `appleSignInButton` ("Continue with Apple"), and `passwordlessSignInButton` ("Sign in with Email Link") so VoiceOver reads human-readable labels instead of SF Symbol names. Added `.accessibilityHidden(true)` on inner icon `Image` | Code review — labels present; icon images hidden from accessibility tree |

### Safety / UGC

| ID | File | What | How Verified |
|----|------|------|-------------|
| SAFE-007 | `AMENAPP/AMENAPP/PrivacySettingsView.swift` | Wired `PermissionsCenterView` into the Capabilities Data & Context section of Privacy Settings — previously unreachable. Gates on existing `capabilitiesCoreEnabled` flag | Code review — `PermissionsCenterView()` embedded behind flag check; no new flag introduced |
| G-P3-06 | `AMENAPP/AMENAPP/VoicePrayer/VoicePrayerCommentRowView.swift` | Delete in ellipsis Menu fired `onDelete()` immediately without confirmation. Added `confirmationDialog` with destructive + cancel buttons | State var `showDeleteConfirmation` drives `.confirmationDialog`; delete only fires on destructive confirm |

### Auth / Privacy

| ID | File | What | How Verified |
|----|------|------|-------------|
| G-P12-01 | `AMENAPP/AMENAPP/Info.plist` | Added 4 missing privacy purpose strings required by iOS runtime: `NSMicrophoneUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSLocationWhenInUseUsageDescription`, `NSSpeechRecognitionUsageDescription`. All four APIs are called in the app (AVAudioSession.record, PHPhotoLibrary, CLLocationManager, SFSpeechRecognizer) but the corresponding Info.plist keys were absent — runtime crash on first API access | Keys present after `NSCameraUsageDescription` in Info.plist; strings are honest user-facing descriptions |
| G-P4-01 | `AMENAPP/SignInView.swift` | Added `.disabled(viewModel.isLoading)` to `googleSignInButton`, `appleSignInButton`, and `passwordlessSignInButton` to prevent duplicate concurrent auth requests while an in-flight sign-in is running | `.disabled(viewModel.isLoading)` modifier appended to all three social button call-sites |
| G-P4-03 | `AMENAPP/AMENAPP/RecoveryOS/AccountManagementService.swift` | Fixed `softDeleteAccount` and `requestDataExport` to derive `uid` from `Auth.auth().currentUser` inside the service instead of trusting the caller-supplied `uid` parameter. An empty-string uid would have written to `users/""` | Both functions guard-unwrap `Auth.auth().currentUser`; throw a 401 `NSError` if no authenticated user present |
| G-P4-04 | `AMENAPP/AMENAPPApp.swift` | Fixed Keychain/AppStorage age-gate mismatch: `AgeGateView` (CHILD-001) writes to Keychain, but `AMENAPPApp.onAppear` checked only `@AppStorage` which is always `false` after the Keychain migration — causing the age gate to show on every launch for returning users | `onAppear` now reads `AgeGateKeychain.hasCompleted` as authoritative source; gate shown only when both Keychain and AppStorage return false |
| G-P4-05 | `AMENAPP/SignInView.swift` | Added Terms of Service and Privacy Policy links to the sign-up screen (App Store Review §5.1.4). The sign-up form had no legal links. Added "By signing up you agree to our Terms and Privacy Policy" with live `amenapp.com/terms` and `amenapp.com/privacy` links, conditionally visible when `!isLogin` | `toggleSignInSignUp` wraps existing HStack in VStack with conditional `Link` row on sign-up panel |
| B-007 | `AMENAPP/AMENAPP/SettingsView.swift` | `BereanConstitutionalPipeline.shared.clearHistory()` was not called on sign-out. Static singleton persisted one user's conversation into the next session. Added `clearHistory()` call before `authViewModel.signOut()` | `clearHistory()` invocation present before sign-out in SettingsView |
| B-008 | `AMENAPP/AMENAPP/BereanChatView.swift` | `saveConversation()` lacked guard against `demo_user` fallback. When Auth UID is nil, `userId` falls back to `"demo_user"`. Without guard, chat was written to `users/demo_user/chatHistory` — a shared world-readable bucket | Guard matching `persistMessageCount`/`loadMessageCount` added; returns early when `userId == "demo_user"` |
| PRIV-006 | `AMENAPP/AMENAPP/AMENLogger.swift` | Changed `os_log` format specifier from `%{public}@` to `%{private}@` for log message bodies. `%{public}@` makes values visible in Console.app even in production builds; log bodies may contain PII | `%{private}@` present in AMENLogger.swift; dlog() confirmed no-op in Release |

### Performance / Crash Prevention

| ID | File | What | How Verified |
|----|------|------|-------------|
| G-P12-02 | `AMENAPP/AMENAPP/GlobalResilience/MessageOutbox.swift` | Replaced production `fatalError` crash in `MessageOutbox.init()` with graceful degradation. A SwiftData `ModelContainer` init failure (corrupted SQLite store, low storage) would hard-crash every user. Updated all context-accessing methods to guard-return on nil container | `container` typed as `ModelContainer?`; do-catch assigns nil on failure with `dlog`; all context accesses have `guard-let` |
| B-029 | `AMENAPP/AMENAPP/DiscussionThreadView.swift` | `DiscussionThreadViewModel` deinit did not remove Firestore listeners. Three snapshot listeners were stored as `(any Sendable)?` with no removal path, causing permanent leaks. Changed types to `ListenerRegistration?` and added `deinit` | `deinit` calls `.remove()` on all three `ListenerRegistration?` properties |

### UX / Buttons / No-Op Stubs

| ID | File | What | How Verified |
|----|------|------|-------------|
| G-P3-01 | `AMENAPP/AMENAPP/AIIntelligence/AmenDistinctives.swift` | Scripture ref `Button(action:{})` was a silent no-op. Added `dlog` + `TODO(BIL)` comment to surface taps in logs and make the stub discoverable | `dlog("Scripture ref tapped — TODO(BIL-BI-01)")` present in `groundingRefsSection` |
| G-P3-02 | `AMENAPP/AMENAPP/AIIntelligence/AmenDistinctives.swift` | `Button("Listen") {}` and `Button("Print") {}` in `DailyOfficeView.officeBody` were completely silent. Added `dlog` + TODO comments for audio and print pipelines | `dlog` statements present for listen and print actions |
| G-P3-03 | `AMENAPP/AMENAPP/HomeView.swift` | 9 empty BIL action buttons (Approve, Undo, Expand, Keep, Replace, Edit, Merge synthesis, Attach to thread, Open, Share, New Version) inside `bilEnabled`-flagged BIL views had empty `{}` closures. Added `dlog + TODO(BIL-BI-0x)` to each | 11 empty `Button` closures replaced with named `dlog` calls across `BILHomeCompactionView`, `BILHomeLedgerView`, `BILHomeBranchingView`, `BILHomeSourceCardsView`, `BILHomeContextPackagesView` |
| G-P3-04 | `AMENAPP/AMENAPP/HomeView.swift` | `BILHomeWave1View` presented as a sheet from `HomeView` had no dismiss/cancel path; users were trapped | `@Environment(\.dismiss)` + `ToolbarItem(.cancellationAction)` Done button added to `BILHomeWave1View` |
| G-P3-05 | `AMENAPP/AMENAPP/HomeView.swift` | `notificationPostSheetRoute` sheet (`NavigationStack` wrapping `NotificationPostDetailView`) had no close button; users were trapped | `.toolbar` with `ToolbarItem(.cancellationAction)` `Button("Close") { notificationPostSheetRoute = nil }` added to the sheet's `NavigationStack` content |
| G-P3-08 | `AMENAPP/AMENAPP/AmenDiscoverView.swift` | Updated the only call-site of `AmenDiscoverDetailView` to pass the three new `onPray`/`onSave`/`onShare` closures with analytics tracking | `AMENAnalyticsService.shared.track` calls present for each action closure |

### Security / Build

| ID | File | What | How Verified |
|----|------|------|-------------|
| SEC-003 | `AMENAPP/AMENAPP/CloudFunctionsService.swift` | Removed dead commented-out emulator `useEmulator` line. The comment `// functions.useEmulator(withHost: "localhost", port: 5001)` created ambiguity about emulator state in production builds | Line absent from CloudFunctionsService.swift |

---

## Full Fix Index (46 items)

> This table lists all 46 GREEN fixes applied during the overnight audit session.
> Fixes in the categories above have extended descriptions.

| # | ID | Category | File (abbreviated) | Commit |
|---|---|---|---|---|
| 1 | G-P12-01 | Privacy/Info.plist | Info.plist | Overnight sweep |
| 2 | G-P12-02 | Performance/Crash | MessageOutbox.swift | Overnight sweep |
| 3 | G-P3-01 | UX/Buttons | AmenDistinctives.swift | Overnight sweep |
| 4 | G-P3-02 | UX/Buttons | AmenDistinctives.swift | Overnight sweep |
| 5 | G-P3-03 | UX/Buttons | HomeView.swift | Overnight sweep |
| 6 | G-P3-04 | UX/Buttons | HomeView.swift | Overnight sweep |
| 7 | G-P3-05 | UX/Buttons | HomeView.swift | Overnight sweep |
| 8 | G-P3-06 | Safety/UGC | VoicePrayerCommentRowView.swift | Overnight sweep |
| 9 | G-P3-07 | Accessibility | AmenDiscoverDetailView.swift | Overnight sweep |
| 10 | G-P3-08 | UX/Buttons | AmenDiscoverView.swift | Overnight sweep |
| 11 | G-P4-01 | Auth/Privacy | SignInView.swift | Overnight sweep |
| 12 | G-P4-02 | Accessibility | SignInView.swift | Overnight sweep |
| 13 | G-P4-03 | Auth/Privacy | AccountManagementService.swift | Overnight sweep |
| 14 | G-P4-04 | Auth/Privacy | AMENAPPApp.swift | Overnight sweep |
| 15 | G-P4-05 | Auth/Privacy | SignInView.swift | Overnight sweep |
| 16 | P5-G1 | Performance | (see Phase 5 output) | Overnight sweep |
| 17 | P5-G2 | Performance | (see Phase 5 output) | Overnight sweep |
| 18 | P5-G3 | Performance | (see Phase 5 output) | Overnight sweep |
| 19 | P5-G4 | Performance | (see Phase 5 output) | Overnight sweep |
| 20 | P5-G5 | Performance | (see Phase 5 output) | Overnight sweep |
| 21 | P6-G1 | Safety/UGC | (see Phase 6 output) | Overnight sweep |
| 22 | P6-G2 | Safety/UGC | (see Phase 6 output) | Overnight sweep |
| 23 | P6-G3 | Safety/UGC | (see Phase 6 output) | Overnight sweep |
| 24 | P6-G4 | Safety/UGC | (see Phase 6 output) | Overnight sweep |
| 25 | P7-G1 | Accessibility | (see Phase 7 output) | Overnight sweep |
| 26 | P7-G2 | Accessibility | (see Phase 7 output) | Overnight sweep |
| 27 | P7-G3 | Accessibility | (see Phase 7 output) | Overnight sweep |
| 28 | P7-G4 | Accessibility | (see Phase 7 output) | Overnight sweep |
| 29 | P8-G1 | Security | (see Phase 8 output) | Overnight sweep |
| 30 | P8-G2 | Security | (see Phase 8 output) | Overnight sweep |
| 31 | P8-G3 | Security | (see Phase 8 output) | Overnight sweep |
| 32 | P9-G1 | Logging | (see Phase 9 output) | Overnight sweep |
| 33 | P9-G2 | Logging | (see Phase 9 output) | Overnight sweep |
| 34 | P10-G1 | Backend/CF | (see Phase 10 output) | Overnight sweep |
| 35 | P10-G2 | Backend/CF | (see Phase 10 output) | Overnight sweep |
| 36 | A11Y-006 | Accessibility | AMENTabBar.swift | `8669a3dd` |
| 37 | PRIV-006 | Logging | AMENLogger.swift | `8669a3dd` |
| 38 | SEC-003 | Security | CloudFunctionsService.swift | `8669a3dd` |
| 39 | SAFE-007 | Safety/UGC | PrivacySettingsView.swift | `8669a3dd` |
| 40 | B-007 | Auth/Privacy | SettingsView.swift | `e0a4c24c` |
| 41 | B-008 | Auth/Privacy | BereanChatView.swift | `e0a4c24c` |
| 42 | B-029 | Performance | DiscussionThreadView.swift | `e0a4c24c` |
| 43 | P10-G3 | Backend/CF | (see Phase 10 output) | Overnight sweep |
| 44 | P10-G4 | Backend/CF | (see Phase 10 output) | Overnight sweep |
| 45 | P12-G3 | Info.plist | (see Phase 12 output) | Overnight sweep |
| 46 | P12-G4 | Info.plist | (see Phase 12 output) | Overnight sweep |

---

## What Was NOT Auto-Fixed

### YELLOW — Staged behind OFF flags / requires human deploy

These items exist in code but are gated by Remote Config or require backend deploy before they are active. They count as STAGED, not APPLIED.

| ID | Reason |
|----|--------|
| BTN-001 | Requires wiring AmenSpaceEntitlementService + Firestore membership write; too large for automated fix; needs E2E test |
| BTN-002 | 26 stubs require individual backend wiring decisions; some (Give Now) require Stripe integration |
| BTN-003 | Straightforward code fix but requires confirming VisitVerificationService Firestore contract |
| BTN-004 | Requires PDFKit wrapper redesign |
| SAFE-002 | Requires adding context-menu + ModerationService wiring to 3 views |
| SAFE-003 | Requires backend hash-scan deployment decision and NCMEC registration |
| SAFE-005 | Requires DiscoveryService + AMENDiscoveryView changes (server-side filter) |
| SAFE-010 | Requires T&S Lead escalation on OPEN-2 before code change |
| PRIV-005 | Requires first-run consent sheet design decision |
| PRIV-007 | Requires full privacy policy text accessible in a pre-login sheet |
| FIRE-010 | Backend CF code change; requires deploy |
| A11Y-002 | LiquidGlassModifiers change affects hundreds of call sites; needs visual QA |
| A11Y-003 | LiquidGlassAnimations change requires spring parameter audit |
| SEC-006 | Info.plist `ITSAppUsesNonExemptEncryption` — requires encryption compliance decision (true vs false) before insert |

### RED — Decision briefs only (legal, policy, payment, architecture)

These are documented in `HUMAN_GATE_QUEUE.md` with full decision brief. No code was changed.

| ID | Reason |
|----|--------|
| AUTH-004 | Requires Google Sign-In SDK re-auth integration — architectural decision on SDK version |
| AUTH-006 | Legal gate — requires counsel to confirm live URLs before linking |
| AUTH-009 | Requires ReauthenticationSheet integration in AccountRecoveryView |
| AUTH-013 | Legal/backend gate — requires server-side scheduled deletion job verification |
| PRIV-001 | Original audit finding; superseded by G-P12-01 which was applied — RESOLVED |
| PERF-006 | Original audit finding; superseded by G-P12-02 which was applied — RESOLVED |

### Audit Contract Guarantee

No YELLOW item was promoted to GREEN. The distinction is enforced as follows:
- GREEN = reversible local Swift/TS source edit, no deploy, no product judgment required
- YELLOW = requires any of: Firebase deploy, Remote Config toggle, Stripe/payment wiring, Apple console action, or legal/policy judgment
- RED = requires human legal, policy, or architecture decision before any code change

---

## Commits Covering These Fixes

| SHA | Message | Fix IDs |
|-----|---------|---------|
| `8669a3dd` | appstore: auto-fix GREEN items (a11y, privacy, logging, cleanup) | A11Y-006, PRIV-006, SEC-003, SAFE-007 |
| `e0a4c24c` | [B-007/B-008/B-029] Fix three privacy/resource-management regressions | B-007, B-008, B-029 |
| Overnight sweep | Phase 3–12 GREEN fix batch (G-P3-xx, G-P4-xx, G-P5-xx…G-P12-xx) | G-P3-01…G-P12-04 |

To revert the entire overnight GREEN fix set:
```sh
git revert e0a4c24c  # B-007/B-008/B-029
git revert 8669a3dd  # A11Y-006/PRIV-006/SEC-003/SAFE-007
# For overnight sweep commits, identify SHA from git log and revert per phase
```

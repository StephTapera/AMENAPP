# AMEN App — Pre-Ship Production Readiness Audit
**Audit Date:** March 2026
**Scope:** Full product sweep — Principal iOS Engineer + QA Lead + Trust & Safety
**Status:** Patches applied. Deploy checklist at bottom.

---

## Section 1 — Missed Issues List (Top Findings)

### P0 — Critical (Ship Blockers)

| # | Issue | File | Status |
|---|-------|------|--------|
| 1 | **Live API keys committed to git** — OpenAI, Anthropic, YouVersion, Google Vision keys were in `Config.xcconfig` in git history | `Config.xcconfig` | ✅ **FIXED** — Keys scrubbed, file untracked from git. **Rotate all 4 keys externally immediately.** |
| 2 | **Posts permission denied at create time** — Firestore create rule blocked `amenCount`, `lightbulbCount`, `commentCount`, `repostCount` entirely; iOS SDK always writes these as `0` | `AMENAPP/firestore 18.rules` | ✅ **FIXED** — Changed to `== 0` checks for counter fields |
| 3 | **Lightbulb notification update denied** — Notifications update rule only checked `userId`, blocking actor's lightbulb update which carries `actorId` | `AMENAPP/firestore 18.rules` | ✅ **Confirmed fixed** — actorId allowed in update rule |

### P1 — High Severity

| # | Issue | File | Status |
|---|-------|------|--------|
| 4 | **Production logging of userId + shadow ban status** — 13 `print()` calls in `AdvancedModerationService` ran in Release builds, logging user IDs and enforcement decisions to device console | `AdvancedModerationService.swift` | ✅ **FIXED** — All wrapped in `#if DEBUG` |
| 5 | **Reply interaction polling every 60 seconds** — ProfileView timer fired `fetchAllCommentInteractions` 20+ times/session causing excessive Firestore reads | `ProfileView.swift:1359` | ✅ **FIXED** — Changed to 300s (5 min) |
| 6 | **Force-unwrap `URL(string: bioURL)!` crash** — User-entered bio URLs can contain invalid characters, crashing on `URL(string:)!` force unwrap in both ProfileView and UserProfileView | `ProfileView.swift:1702`, `UserProfileView.swift:1814` | ✅ **FIXED** — Wrapped in `if let` binding |
| 7 | **Force-unwrap phone URL in FindChurchView** — `tel://\(church.phone...)!` would crash if phone data contains unusual formatting that breaks URL parsing | `FindChurchView.swift:3533` | ✅ **FIXED** — Wrapped in `if let` |
| 8 | **Force-unwrap Vertex AI URL** — Interpolated config values (region, projectId, endpoint) could produce invalid URLs | `VertexAIPersonalizationService.swift:203` | ✅ **FIXED** — Changed to `guard let` with thrown error |
| 9 | **FindChurchView multiple `.sheet()` warnings** — 3 chained sheet modifiers caused "only one sheet at a time" SwiftUI warnings; sheets could silently fail to present | `FindChurchView.swift` | ✅ **FIXED** — Consolidated to single `sheet(item: $activeSheet)` |

### P1 — Configuration / Deploy Blockers

| # | Issue | File | Status |
|---|-------|------|--------|
| 10 | **Firestore rules not deployed** — Fixed rules in `AMENAPP/firestore 18.rules` are local only until `firebase deploy --only firestore:rules` is run | — | ⚠️ **ACTION REQUIRED** — Deploy to Firebase |
| 11 | **`MessagesAPIService` uses placeholder domain** — `baseURL = "https://api.yourdomain.com/v1"` means all REST message API calls will 404 in production | `MessagesAPIService.swift` | ⚠️ **ACTION REQUIRED** — Set real domain or verify this path is unused |
| 12 | **`Config.xcconfig` keys must be rotated** — Keys were in git history before being scrubbed. Even after removal from future commits, any clones of the repo before this commit still have the keys | External | ⚠️ **IMMEDIATE ACTION** — Rotate all 4 API keys |

### P2 — Polish / Consistency

| # | Issue | File | Status |
|---|-------|------|--------|
| 13 | `UIScreen.main` deprecated in iOS 26 | `ChurchProfileView.swift:37` | Pre-existing warning, not introduced by this audit |
| 14 | `AIBibleStudyView` uses `http://localhost:3400/bibleChat` — this is a local dev URL that will fail silently in production if Berean backend is not deployed | `AIBibleStudyView.swift:628` | Review — should be Remote Config or xcconfig URL |
| 15 | `LegacyPost` mock data returned from `ServicesPostService` — force-unwrap URLs inside commented-out stubs, plus the service returns mock data only | `ServicesPostService.swift` | Low risk — commented-out code, but verify this class is unused |
| 16 | `MessagingSystemValidation.swift` has test URL force-unwrap | `MessagingSystemValidation.swift:72` | Low risk — validation/testing code |

---

## Section 2 — UX Coherence Findings

### Confirmed Working
- **Auth state machine** (`ContentView.swift`) — 5-state machine (loading → 2FA → unauthenticated → onboarding → main) is well-structured with 2s max deadline polling loop
- **Tab bar navigation** — State is preserved across tabs via `@StateObject` in ContentView
- **Duplicate post prevention** — `isPublishing` guard + `inFlightPostHash` in `CreatePostView` prevents double-submit
- **Follow request flow** — Private account gating enforced at Firestore rules level AND in `FollowService`
- **Onboarding completeness** — `FTUEManager` gates each step; `CommunityGuidelinesPrompt` shown on first post; `ProfilePicturePicker` required before proceeding

### Findings
- **17 sheet/fullScreenCover modifiers** in `ContentView.swift` — spread across nested subviews (acceptable since each is on a different view instance), but should be audited if the "only one sheet" warning appears during QA
- **ProfileView polling timer** — Now set to 5 minutes. Realtime database listeners handle live updates; timer is a fallback only — consider removing entirely and relying on listeners
- **HeyFeed preferences** — Muted authors and hidden posts are filtered in `HomeFeedAlgorithm`, but the preference sync across devices depends on Firestore working (no offline fallback for mute state)

---

## Section 3 — Performance Findings

### Confirmed Optimized
- **URLCache** — Sized 64MB RAM / 256MB disk in `AMENAPPApp.swift`
- **`dlog()`** — All debug logging via `dlog()` is `#if DEBUG` only (no-op in Release)
- **Feed rendering** — `FeedAPIService` uses Cloud Run with local `HomeFeedAlgorithm` fallback; pagination via `startAfter` cursor
- **Image caching** — `CachedAsyncImage` + `NotificationImageCache` provide two-tier caching
- **Notification listeners** — `NotificationService` correctly cleans up both listeners on `deinit`/`stopListening()`
- **`ProfileView` listener cleanup** — Comprehensive cleanup in `removeListeners()` covers 8+ listener references

### Remaining Concerns
- **`AdvancedModerationService` parallel AI calls** — Makes 3 concurrent API calls (Google NL, OpenAI, FaithML) per content submission. If all 3 have network timeouts (default 60s), a post submit could hang for 60s. Ensure there's a timeout override on `URLRequest`.
- **Shadow ban list loaded on demand** — `loadShadowBannedUsers()` fetches from Firestore every time `lastShadowBanSync` is >5 minutes old. Under heavy load this could fire frequently. Consider a background refresh interval.

---

## Section 4 — Safety & Compliance Findings

### Confirmed Present
- **Age gating** (`AgeAssuranceService`) — Tier system: blocked (<13), tierB (13-15), tierC (16-17), tierD (18+). COPPA/UK Children's Code/App Store 4+ design.
- **Content moderation pipeline** — `AdvancedModerationService` + `ContentModerationService` + `LocalContentGuard` + `ThinkFirstGuardrailsService`
- **Shadow banning** — Soft enforcement via `AdvancedModerationService`; hard enforcement via `EnforcementLadderService`
- **Crisis resources** — `EnhancedCrisisSupportService` present; `CrisisSupportCard` renders in-app
- **Block/mute/restrict** — `BlockService`, `SmartMuteService`, `RestrictService` all present
- **Reporting flow** — `SafetyReportingService` + `ModerationAuditLog` confirmed
- **Phone verification** — Rate limited server-side via `phoneAuthRateLimit.js`
- **2FA** — Full 2FA flow with session signing off immediately on 2FA detection before granting access
- **Firebase Storage rules** — MIME allowlist (no SVG/script injection), ownership enforcement on all paths, resized variants write-blocked to client

### Remaining Concerns
- **API keys exposed in git history** — Even after scrubbing `Config.xcconfig`, the keys exist in git history commits. Any team members who cloned before this patch have the keys. **Rotate all keys immediately.**
- **`posts/images/{fileName}` Storage path** — No per-user ownership (legacy path). Client deletes are blocked; writes are open to any authenticated user. Documented in rules with P1 note — acceptable if this path is being deprecated in favor of `post_media/{authorUserId}/{postId}/{fileName}`.
- **Shadow ban enforcement only on `AdvancedModerationService`** — If content is submitted through a path that bypasses `AdvancedModerationService.analyzeContent()`, shadow banned users can still post. Ensure all content creation paths go through this service.

---

## Section 5 — Release Gate Checklist

### Security
- [ ] **Rotate OpenAI API key** — https://platform.openai.com/api-keys
- [ ] **Rotate Anthropic API key** — https://console.anthropic.com/settings/keys
- [ ] **Rotate YouVersion API key** — https://scripture.api.bible
- [ ] **Rotate Google Vision/Vertex AI API key** — https://console.cloud.google.com/apis/credentials
- [ ] Create `Config.local.xcconfig` with new keys (git-ignored)
- [ ] Verify `Config.xcconfig` no longer has any API key values (empty `KEY =`)
- [ ] Confirm no other `.xcconfig` files contain keys

### Firebase Deploy
- [ ] Run `firebase deploy --only firestore:rules` to push `AMENAPP/firestore 18.rules`
- [ ] Run `firebase deploy --only storage` to push `AMENAPP/storage.rules`
- [ ] Verify posts can be created in TestFlight after rules deploy
- [ ] Verify lightbulb notifications are delivered after rules deploy

### Build / App Store
- [ ] Archive with Release scheme (not Debug) — `dlog()` calls silent, `#if DEBUG` blocks excluded
- [ ] Confirm no simulator-only code paths reach App Store binary
- [ ] Verify `http://localhost:3400/bibleChat` in `AIBibleStudyView` is unreachable in production (or replace with production URL)
- [ ] Set real `MessagesAPIService.baseURL` or confirm the REST path is unused in production

### QA Smoke Tests
- [ ] Sign up new account → onboarding → first post (no permission denied)
- [ ] Give lightbulb on a post → author receives notification
- [ ] Tap a profile bio URL with a malformed URL → no crash
- [ ] Open church detail → share church → deep link opens correctly
- [ ] Find Church → tap phone number on comparison view → no crash
- [ ] Shadow ban a user via admin → confirm content is blocked

### Monitoring
- [ ] Firebase Crashlytics enabled for Release builds
- [ ] Confirm no personal data (email, phone, userId) appears in production device logs
- [ ] Confirm `AdvancedModerationService` logs do not appear in Xcode Organizer for Release builds

---

## Section 6 — Final Patch Summary

All patches applied in this audit session:

| File | Change |
|------|--------|
| `Config.xcconfig` | Scrubbed all API keys; added rotation instructions |
| `.gitignore` already had `Config.xcconfig` | `git rm --cached Config.xcconfig` run to untrack the file |
| `AMENAPP/AdvancedModerationService.swift` | Wrapped all 13 `print()` calls in `#if DEBUG` |
| `AMENAPP/ProfileView.swift` | Fixed `URL(string: bioURL)!` → `if let` binding |
| `AMENAPP/UserProfileView.swift` | Fixed `URL(string: bioURL)!` → `if let` binding |
| `AMENAPP/FindChurchView.swift` | Fixed `URL(string: "tel://...")!` → `if let` binding; previously fixed 3→1 sheet modifiers |
| `AMENAPP/AboutAmenView.swift` | Fixed `URL(string: url)!` in `LicenseRow` → `if let` binding |
| `AMENAPP/ChurchModels.swift` | Changed `ChurchDeepLink.url: URL` → `URL?` (non-crashing) |
| `AMENAPP/ChurchProfileView.swift` | Updated `deepLink.url.absoluteString` → `deepLink.url?.absoluteString ?? fallback` |
| `AMENAPP/VertexAIPersonalizationService.swift` | Fixed force-unwrap Vertex AI URL → `guard let` with thrown error |
| `AMENAPP/AuthenticationViewModel.swift` | Fixed `URL(string: "https://www.google.com")!` → `guard let`; confirmed all PII prints already `#if DEBUG` |
| `AMENAPP/ProfileView.swift` | Polling timer: 60s → 300s |
| `AMENAPP/firestore 18.rules` | Posts create: counter fields now `== 0` check instead of blanket `hasAny` block |

**All modified files pass `XcodeRefreshCodeIssuesInFile` with zero errors.**

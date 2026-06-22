# AMEN — Frozen FLOW CONTRACT (Wave 0)

**Date:** 2026-06-17 · **Status:** FROZEN — nothing downstream (Waves 1–3) may edit this file.
**Source:** Read-only code analysis of `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP`. No app run.

> Reading rule for explorers/verifiers: a flow correctly **blocked by a safety, age, auth,
> or moderation control is PASSING (EXPECTED)** — never file it as a bug, never weaken the
> control to make it "pass." Such outcomes are tagged **[EXPECTED-BLOCK]** below.

---

## 1. Cold start / launch
- **Entry:** `AMENAPPApp.swift` (@main init/onAppear), `AppDelegate.swift` (Firebase + FCM).
- **Gates:** COPPA age gate (`AgeGateKeychain`, `AMENAPPApp.swift:~312`) → blocks all access until verified **[EXPECTED-BLOCK]**; `ContentView.swift:~169` → no user shows `AMENAuthLandingView`; `:~160` 2FA needed → `TwoFactorVerificationGateView`; `:~207` cached user → `AutoLoginSplashView`.
- **Expected success:** age-verified returning user → tabs visible; first-timer → auth landing.
- **Expected error:** network timeout → offline banner + retry; invalid app version → mandatory-update alert (kill switch).

## 2. Sign up (email/password, phone, Apple, Google)
- **Entry:** `SignInView.swift` (isLogin=false); SSO on `AMENAuthLandingView.swift`.
- **Controls:** email (regex validate), password (strength meter), display name (required), username (async availability), "Sign Up" → `createAccountWithDOB()/createAccountWithPassword()`; DOB collection via `DateOfBirthCollectionView`; phone OTP (60s resend cooldown, 3-try cap).
- **Expected success:** `isAuthenticated=true` → onboarding for new user; email-verify gate if unverified.
- **Expected error:** email-in-use, username taken (red feedback), weak password, network error, OTP attempts exceeded → cooldown **[EXPECTED-BLOCK]**.
- **Age below minimum → blocked [EXPECTED-BLOCK].**

## 3. Email verification
- **Entry:** `EmailVerificationGateView.swift` when `needsEmailVerification=true`.
- **Controls:** "Check Verification Status", "Resend" (60s cooldown), "Sign Out". Deep-link verify via `Auth.auth().canHandle(url)` in `AMENAPPApp.swift:~436`.
- **Expected success:** link tapped / status refresh → gate dismisses.
- **Expected error:** expired link → resend; gate persists until verified or sign-out **[EXPECTED-BLOCK]**.

## 4. Sign in
- **Entry:** `SignInView.swift` (isLogin=true).
- **Controls:** email, password (show/hide), "Sign In" → `signIn(email:password:)`, "Forgot Password?", passwordless toggle, phone toggle, Google/Apple.
- **Expected success:** valid creds → 2FA gate if enabled → email-verify gate if unverified → main app.
- **Expected error:** invalid creds, no internet; 2FA credential wiped on backgrounding mid-wait (`AuthenticationViewModel.swift:~185`) **[EXPECTED-BLOCK]**.

## 5. Sign out
- **Entry:** `SettingsView.swift` → `signOut()`.
- **Clears:** Firestore listeners + persistence cache, FCM token deactivation, identity hints, `AMENEncryptionService.wipeAllKeys()`, badge, 2FA/phone state.
- **Expected:** routed to `AMENAuthLandingView`; no further push for signed-out user.

## 6. Onboarding (9 slides + skip/back/next)
- **Entry:** `OnboardingFlowView.swift` when `hasCompletedOnboarding=false` post-signup.
- **Slides:** intro → age (DOB) → ToS agree → privacy ack → interests (multi-select) → faith stage → notifications toggle (+Skip) → username (availability) → suggested users (Follow).
- **State:** Firestore `users/{uid}`: `hasCompletedOnboarding/onboardingCompleted/onboardingComplete=true`, `onboardingCompletedAt`, plus field data.
- **Expected success:** `finish()` → main app, tab bar shows.
- **Expected edge:** early dismiss/swipe-back → state lost, re-shown next launch; skip notifications → flag saved, deferred.

## 7. Permission prompts
- **Manager:** `AMENPermissionsManager.swift` (context pre-education sheet before native prompt).
- **Mic:** Berean voice / prayer note / testimony. **Camera:** profile photo / instant post photo. **Photos:** post image / avatar.
- **Expected allow:** feature unlocks. **Expected deny:** feature disabled + link to Settings (graceful, no crash).

## 8. Primary navigation
- **Root:** `ContentView.swift:~156` + `AMENTabBar.swift:~128`. 5 visible tabs: Home(0, `HomeView`/OpenTable), Search(1, `DiscoveryView`), Messages(2, `MessagingView`), Resources(3, `AMENResourcesHubView`), Profile(4, `ProfileView`). Floating compose button → `CreatePostView` modal. Deep-link-only: Spaces, Notifications, Brief.
- **Expected:** tab tap → view switches; compose button → composer sheet.

## 9. Post composer
- **Entry:** `CreatePostView.swift` via floating button / deep link.
- **Controls:** text (draft auto-save 3–5s), category, images (≤4 via PhotosPicker), hashtag suggest, link preview, comment permission, scripture verse picker, visibility/audience, schedule date, **Post**, **Cancel** (→ "Save draft?").
- **Expected success:** publish → `FirebasePostService` write → optimistic feed insert → "Posted!"; scheduled → queued via cloud function.
- **Expected error:** validation fail → alert; network fail → draft saved; **content flagged by safety engine → held for review [EXPECTED-BLOCK]**; rate limit → "try again" **[EXPECTED-BLOCK]**.

## 10. Feed actions
- **View:** `PostCard.swift`.
- **Like/"Amen"** (`PostInteractionsService`) → optimistic fill + haptic; backend fail → shake + rollback.
- **Comment** → `PostDetailView` thread; empty reply rejected.
- **Share** → `AMENShareCardSystem` share sheet.
- **Lightbulb/insight**, **Repost** (confirm dialog), **Save** (`RealtimeSavedPostsService`).
- **Report** (three-dot → `ModerationService`) → reason form → safety queue → "Thanks for your feedback"; **content may be downranked/removed [EXPECTED-BLOCK]**. Three-dot also: Edit/Delete (author), Block/Mute, "Why this post".

## 11. Profile edit
- **Entry:** `ProfileView.swift` → Settings → Edit Profile.
- **Controls:** display name, bio (char limit), profile image (camera/library), church affiliation, ≤3 links, **Save** → Firestore `users/{uid}`.
- **Expected error:** network fail → "not saved"; oversize image → compress/error; bio over limit → warning.

## 12. Settings toggles
- **Entry:** `SettingsView.swift` via Profile.
- **Sections:** Edit Profile, Account (email/username/password/2FA), Notifications (push/categories/quiet hours), Messaging, Privacy (account type/block/mute), Appearance, Advanced (cache/export), **Sign Out**, **Delete Account** (`AccountDeactivationView` → password confirm → `AccountDeletionService`).
- **Expected:** toggle → Firestore/UserDefaults write → UI refresh. Delete-account password confirm is **[EXPECTED-BLOCK]** if wrong password.

## 13. Berean entry — READ-ONLY SMOKE ONLY
- **Entry:** Brief tab (sparkles) → `BereanLandingView`; floating AI action; deep link `amen://intelligence`.
- **Smoke pass criteria:** UI loads without crash/layout break; entry reachable. **Do NOT run expensive AI query loops.** Moderation on responses is **[EXPECTED-BLOCK]** when triggered.

## 14. Notifications / Live Activity
- **Push:** `CompositeNotificationDelegate.swift`; tap routing via `NotificationOpenCoordinator` (`AMENAPPApp.swift:~449`) → `NotificationDeepLinkRouter`.
- **Routes:** follow→profile, comment/reply→post(+highlight), prayerRequest→prayer, churchNote→note, message→conversation, likeAmen→post, groupInvite→join.
- **Live Activity:** `LiveActivityManager.swift`; restored on relaunch; Dynamic Island tap → deep link.
- **Expected:** tap → launch + navigate to target; silent → badge update only.

## 15. Deep links
- **Handlers:** `DeepLinkRouter.swift` (`amen://`), `NotificationDeepLinkRouter.swift` (`amenapp://`); dispatch in `AMENAPPApp.swift:~431` (Firebase Auth → Google → notification coord → legacy).
- **Routes:** post/{id}(+comment), user/{id}, church/{id}, conversation/{id}, category/{name}, search?q=, settings/{section}, email-link sign-in (`https://amen.app/__/auth/action`), notes/{id}, intelligence, share-extension resume.
- **Expected valid:** parse → navigate, context preserved. **Expected invalid:** unrecognized/malformed → logged warning, **no navigation, no crash**.

---

## Verification severity scale (for Wave 1 tickets)
`crash` > `broken-flow` > `visual`. A **[EXPECTED-BLOCK]** outcome is never a ticket — log it as EXPECTED in evidence and move on.

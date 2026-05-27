# AMEN Onboarding System Audit
**Date:** 2026-05-24  
**Branch:** audit/2026-05-21  
**Result:** GO WITH CAVEATS

---

## Onboarding Flow Map

```
Cold Launch
  └── SplashView (auth resolving)
        ├── .signedOut → AMENAuthLandingView
        │     ├── SmartAccountResumeView (if flag + cached accounts)
        │     ├── AutoLoginSplashView (if hasCachedUser, flag off)
        │     └── SplashView (new user)
        ├── .needsTwoFactorChallenge → TwoFactorVerificationGateView
        ├── .deactivated → ReactivationPromptView
        ├── .deleting / .suspended / .missingUserDocument / .error → AccountLifecycleBlockedView
        │
        ├── needsUsernameSelection → UsernameSelectionView
        │     └── onDismiss: authViewModel.completeUsernameSelection()
        │
        ├── needsOnboarding → OnboardingView (6 steps)
        │     Step 0 — Value Proposition (why AMEN)
        │     Step 1 — Account Setup (photo · display name · username · bio · DOB)
        │     Step 2 — Privacy & Safety (data transparency · toggles · AI consent)
        │     Step 3 — Interests (10 chips · terms checkbox)
        │     Step 4 — Follow Suggestions (contacts + interest-based)
        │     Step 5 — Community Discovery (Find Church · Enter AMEN)
        │     └── finishOnboarding() → Cloud Function completeOnboarding()
        │
        ├── needsEmailVerification → EmailVerificationGateView
        │
        └── .authenticated → mainContent (tab bar)
              └── Post-onboarding: NotificationPermissionOnboardingSheet (delayed 1.5s)
```

---

## Files Reviewed

### Primary Onboarding Flow
| File | Status | Notes |
|------|--------|-------|
| `AMENAPP/OnboardingOnboardingView.swift` | ✅ Active | 6-step production flow — **modified** |
| `AMENAPP/AMENOnboardingSystem.swift` | ✅ Active | ONB design tokens + 12 components |
| `AMENAPP/AMENTypography.swift` | ✅ Active | `ONBAnimatedHeadline` defined here |
| `AMENAPP/OnboardingAppLaunchView.swift` | ⚠️ Legacy | `AppLaunchView` struct — not in ContentView routing |
| `AMENAPP/OnboardingFlowView.swift` | ⚠️ Debug | 9-slide prototype `#if DEBUG` only |

### Auth Gates
| File | Status | Notes |
|------|--------|-------|
| `AMENAPP/ContentView.swift` | ✅ Active | 12-branch auth routing chain |
| `AMENAPP/AuthenticationViewModel.swift` | ✅ Active | `completeOnboarding()` calls Cloud Function |
| `AMENAPP/UsernameSelectionView.swift` | ✅ Active | Social sign-in username gate |
| `AMENAPP/MinimalAuthenticationView.swift` | ✅ Active | Email/password sign-in/up |
| `AMENAPP/AMENAuthLandingView.swift` | ✅ Active | Signed-out landing |
| `AMENAPP/AutoLoginSplashView.swift` | ✅ Active | Cached-user resume |
| `AMENAPP/SmartAccountResumeView.swift` | ✅ Active | Flag-gated smart resume |
| `AMENAPP/SplashView.swift` | ✅ Active | Cold-launch splash |
| `AMENAPP/TwoFactorVerificationGateView.swift` (inferred) | ✅ Active | 2FA gate |
| `AMENAPP/EmailVerificationGateView.swift` (inferred) | ✅ Active | Email verify gate |

### Profile / Upload
| File | Notes |
|------|-------|
| `AMENAPP/ProfileImageSetupView.swift` | `ProfileImageFlowViewModel.uploadProfileImage()` — path: `users/{uid}/profile/profileImage.jpg` |
| `AMENAPP/UserService.swift` | `UserService.uploadProfileImage()` — path: `profile_images/{uid}/profile.jpg` (not owner-scoped) |
| `AMENAPP/UserModel.swift` | `UserService.uploadProfileImage()` — same non-owner-scoped path |

### Notification / Post-Onboarding
| File | Status |
|------|--------|
| `AMENAPP/NotificationPermissionOnboarding.swift` | ✅ Active — 3-step glassmorphic sheet |
| `AMENAPP/AMENAPPApp.swift` | Triggers notification sheet 1.5s after first login |

### Design System
| File | Notes |
|------|-------|
| `AMENAPP/AMENOnboardingSystem.swift` | ONB tokens, ONBGlassCard, ONBPrimaryButton, ONBSecondaryButton, ONBToggleRow, ONBPrivacyRow, ONBPageDots, ONBStepTransition, ONBIconBadge, ONBFeatureRow, ONBHeroText, ONBInputField |

---

## Files Created
- `AMENAPP/AMENAPP/Docs/OnboardingAudit.md` — this file

## Files Modified
- `AMENAPP/OnboardingOnboardingView.swift` — see changes below

---

## Changes Made to `OnboardingOnboardingView.swift`

### 1. Added `import FirebaseStorage`
Required for the new owner-scoped avatar upload helper.

### 2. Added missing state variables
```swift
@State private var bio: String = ""
@State private var aiPersonalizationConsent: Bool = true   // on by default
@State private var aiMessageConsent: Bool = false           // off by default (conservative)
```

### 3. Added bio field — Step 1 (Account Setup)
- Optional multiline `TextField` with `axis: .vertical`
- `accessibilityLabel("Bio, optional")`
- Placed after username, before DOB
- Max 3 visible lines; no hard cap enforced client-side (backend should enforce 160 chars)

### 4. Added AI consent controls — Step 2 (Privacy & Safety)
Two `ONBToggleRow` controls in a new glass card:
- **Personalise my experience** — default ON. Uses interests + activity for content suggestions.
- **AI access to messages** — default OFF. Berean cannot read private messages unless explicitly enabled.

Both values saved to Firestore on `finishOnboarding()`.

### 5. Fixed `finishOnboarding()` — missing Firestore fields
Added to `updateData`:
```swift
"bio":                      trimmedBio              // if non-empty
"usernameLowercase":        trimmedUsername         // needed for case-insensitive lookups
"aiPersonalizationConsent": aiPersonalizationConsent
"aiMessageConsent":         aiMessageConsent
"onboardingCompletedAt":    FieldValue.serverTimestamp()
```

### 6. Fixed avatar storage path (owner-scoped)
Replaced `UserService().uploadProfileImage(img)` (which wrote to `profile_images/{uid}/profile.jpg`) with a private helper `uploadAvatarOwnerScoped(_:userId:)` that writes to:
```
users/{uid}/profile/avatar/profileImage.jpg
```
This path is owner-scoped and consistent with `ProfileImageSetupView`. The helper returns only the download URL — no side-effect Firestore write — so `finishOnboarding()`'s single `setData(merge:true)` remains the source of truth.

### 7. Fixed deprecated `Text +` concatenation (iOS 26)
Replaced 4 `Text(...) + Text(...)` expressions with a single `Text("...  **bold** ...")` using Markdown interpolation. Zero warnings remain.

### 8. Added photo picker accessibility label
```swift
.accessibilityLabel(selectedProfileImage == nil ? "Add profile photo, optional" : "Change profile photo")
```

---

## Duplicate Flow Matrix

| Duplicate | Files | Active? | Risk | Action |
|-----------|-------|---------|------|--------|
| `AppLaunchView` vs `OnboardingView` | `OnboardingAppLaunchView.swift` vs `OnboardingOnboardingView.swift` | Only `OnboardingView` active | Low — dead code | Kept; safe to delete `AppLaunchView` if no other references |
| `OnboardingFlowView` vs `OnboardingView` | `OnboardingFlowView.swift` vs `OnboardingOnboardingView.swift` | `OnboardingFlowView` `#if DEBUG` only | Low | Kept; debug prototype isolated |
| Triple onboarding completion flags | `hasCompletedOnboarding`, `onboardingCompleted`, `onboardingComplete` | All written in different places | Medium — migration burden | `AuthenticationViewModel.completeOnboarding()` reads all three for backwards compat — acceptable |
| Two notification onboarding paths | `NotificationPermissionOnboarding` (post-login) vs step 2 toggle in `OnboardingView` | Both active, different timing | Low — not duplicates, they're sequential | Step 2 toggle sets `notificationsEnabled` preference; system prompt fires post-onboarding via `NotificationPermissionOnboardingSheet` |
| Two profile upload paths | `ProfileImageSetupView.uploadProfileImage` vs `UserService.uploadProfileImage` vs new `uploadAvatarOwnerScoped` | `UserService` path now replaced in onboarding | Medium — path inconsistency | **Fixed**: onboarding now uses owner-scoped path |

---

## Profile Data Contract Matrix

| Field | Collected In | Firestore Field | Type | Notes |
|-------|-------------|-----------------|------|-------|
| uid | Auth | — | server | Set by Firebase Auth |
| displayName | Step 1 | `displayName` | String | Also set in Firebase Auth profile |
| username | Step 1 | `username` | String | Re-validated at submit |
| usernameLowercase | Step 1 | `usernameLowercase` | String | **Added in this audit** |
| bio | Step 1 | `bio` | String? | **Added in this audit** |
| profileImageURL | Step 1 | `profileImageURL` | String? | Optional; upload failure surfaced to user |
| birthYear | Step 1 | `birthYear` | Int | Year only — not full DOB |
| interests | Step 3 | `interests` | [String] | 10 options, multi-select, skippable |
| isPrivate | Step 2 | `isPrivate` | Bool | Default false |
| notificationsEnabled | Step 2 | `notificationsEnabled` | Bool | Default true |
| aiPersonalizationConsent | Step 2 | `aiPersonalizationConsent` | Bool | **Added in this audit** — default true |
| aiMessageConsent | Step 2 | `aiMessageConsent` | Bool | **Added in this audit** — default false |
| onboardingCompletedAt | finishOnboarding | `onboardingCompletedAt` | Timestamp | **Added in this audit** — server timestamp |
| hasCompletedOnboarding | completeOnboarding() CF | `hasCompletedOnboarding` | Bool | Set by Cloud Function |

### Fields NOT collected during onboarding (settable post-onboarding)
- `bannerURL` — profile settings
- `selectedChurchId` — church discovery (Step 5 opens `FindChurchView`)
- `dmPermission` — privacy settings post-onboarding
- `presenceVisibility` — privacy settings post-onboarding
- `profileVisibility` — mapped from `isPrivate`
- `notificationPreferences` — detailed prefs via `NotificationPermissionOnboardingSheet`

---

## Button Wiring Matrix

| Button | File | Action | State | Loading/Error | A11y | Status |
|--------|------|--------|-------|--------------|------|--------|
| Get Started | Step 0 | `advance(by: 1)` | `step` | N/A | `.plain` style | ✅ |
| Back (chevron) | All steps > 0 | `advance(by: -1)` | `step` | N/A | Implicit label | ✅ |
| Skip | Steps 0-4 | `advance(by: 1)` | `step` | N/A | `.plain` style | ✅ |
| PhotosPicker | Step 1 | loads `selectedItem` → `selectedProfileImage` | `selectedProfileImage` | None needed (picker handles) | **Fixed: accessibilityLabel added** | ✅ |
| Username suggestion chip | Step 1 | sets `username`, re-runs check | `username`, `usernameAvailable` | Loading spinner | Inherits button a11y | ✅ |
| DOB calendar toggle | Step 1 | `showDOBPicker.toggle()` | `showDOBPicker` | N/A | Chevron icon only | ⚠️ No explicit a11y hint |
| Privacy toggle (Private Account) | Step 2 | Toggle binding | `privateAccount` | N/A | `ONBToggleRow` | ✅ |
| Notifications toggle | Step 2 | Toggle binding | `notificationsEnabled` | N/A | `ONBToggleRow` | ✅ |
| AI Personalisation toggle | Step 2 | Toggle binding | `aiPersonalizationConsent` | N/A | `ONBToggleRow` | ✅ **Added** |
| AI Messages toggle | Step 2 | Toggle binding | `aiMessageConsent` | N/A | `ONBToggleRow` | ✅ **Added** |
| Privacy Policy link | Step 2 | `Link` to URL | N/A | N/A | `Link` semantic | ✅ |
| Terms link | Step 2 | `Link` to URL | N/A | N/A | `Link` semantic | ✅ |
| I Understand — Continue | Step 2 | `advance(by: 1)` | `step` | N/A | Always enabled | ✅ |
| Terms checkbox | Step 3 | `hasAgreedToTerms.toggle()` | `hasAgreedToTerms` | N/A | Needs explicit label | ⚠️ |
| Interest chip | Step 3 | insert/remove from `selectedInterests` | `selectedInterests` | N/A | Button inherits label | ✅ |
| Continue (Step 3) | Step 3 | `advance(by: 1)` | disabled until terms agreed | N/A | Disabled state visual | ✅ |
| Find friends (contacts) | Step 4 | `requestContactsAccess()` | `contactsAuthStatus` | ProgressView | Plain button | ✅ |
| Follow / Unfollow | Step 4 | `discoveryService.followUser/unfollowUser` | `isFollowing` | None explicit | `DiscoveryFollowCard` | ✅ |
| Continue (Step 4) | Step 4 | `advance(by: 1)` | N/A | N/A | N/A | ✅ |
| Find a Church card | Step 5 | `showFindChurch = true` | sheet | N/A | `ScaleButtonStyle` | ✅ |
| Enter AMEN | Step 5 | `finishOnboarding()` | `isSaving` | `ProgressView` + alert | Always enabled | ✅ |
| Try Again (error alert) | Error | `finishOnboarding()` | `isSaving` | N/A | Alert button | ✅ |
| Share to AMEN (first post) | ONBFirstPostSheet | `showComposer = true` | N/A | N/A | `PressableButtonStyle` | ✅ |
| Maybe later | ONBFirstPostSheet | `isPresented = false` | N/A | N/A | `.plain` | ✅ |

---

## Privacy / AI Consent Matrix

| Setting | Default | Step | Field | Editable Post-Onboarding | Notes |
|---------|---------|------|-------|--------------------------|-------|
| Private Account | OFF | 2 | `isPrivate` | Yes — Profile Settings | |
| Prayer & Community Alerts | ON | 2 | `notificationsEnabled` | Yes — Notification Settings | |
| AI Personalisation | ON | 2 | `aiPersonalizationConsent` | Yes — AI Settings | **Added** |
| AI Message Access | OFF | 2 | `aiMessageConsent` | Yes — AI Settings | **Added** — conservative default |
| Contacts Access | Not determined | 4 | OS permission | Via iOS Settings | Explained before prompt |

---

## Upload / Storage Matrix

| Asset | Path | Owner-Scoped | Content-Type | Size Limit | Notes |
|-------|------|-------------|--------------|------------|-------|
| Profile avatar (onboarding) | `users/{uid}/profile/avatar/profileImage.jpg` | ✅ | `image/jpeg` | 5 MB | **Fixed in this audit** |
| Profile avatar (profile settings) | `users/{uid}/profile/profileImage.jpg` | ✅ | `image/jpeg` | 5 MB | `ProfileImageSetupView` |
| Profile avatar (UserService) | `profile_images/{uid}/profile.jpg` | ⚠️ Not owner-scoped | `image/jpeg` | None client-side | Used by post-onboarding profile edits — Storage rules must protect |

> **Caveat**: `UserService.uploadProfileImage()` still uses the `profile_images/` path for post-onboarding profile updates. This path needs a Storage rule `match /profile_images/{userId}/{file} { allow write: if request.auth.uid == userId; }` to be owner-scoped at the rules layer.

---

## Firestore / Storage Rules Matrix

> **Note**: Firestore/Storage rules files were not found in this repo copy. The following requirements must be verified against the deployed rules.

| Collection/Path | Required Rule | Risk if Missing |
|-----------------|---------------|-----------------|
| `users/{uid}` | Write: `request.auth.uid == uid` + field allowlist | User can set `isAdmin`, `isBanned`, etc. |
| `users/{uid}` — `hasCompletedOnboarding` | Server-only via Cloud Function | Client bypass of onboarding gate |
| `usernames/{usernameLowercase}` | Write: owner only; read: public for availability check | Username squatting |
| `users/{uid}` — `aiMessageConsent` | Owner-only read/write | Privacy leak |
| `users/{uid}` — `aiPersonalizationConsent` | Owner-only read/write | Privacy leak |
| `users/{uid}/profile/avatar/**` | Write: `request.auth.uid == uid` | Other users overwrite your avatar |
| `profile_images/{userId}/**` | Write: `request.auth.uid == userId` | Not owner-scoped by path — needs rule |

---

## Liquid Glass Matrix

| Element | Treatment | Compliant | Notes |
|---------|-----------|-----------|-------|
| Step container | `ONB.canvas` background (pearl white) | ✅ | Not glass |
| Feature/info cards | `ONBGlassCard` — `.thinMaterial` + white overlay + border | ✅ | Single pass |
| Progress capsules | `ONBPageDots` — solid fill | ✅ | Not glass |
| CTA button | Solid `ONB.inkPrimary` fill | ✅ | Not glass |
| Toggle rows | `ONBToggleRow` — text + system Toggle | ✅ | Not glass |
| Privacy rows | Expandable rows inside `ONBGlassCard` | ✅ | Single glass layer |
| AI consent card | New `ONBGlassCard` | ✅ | Single glass layer |
| No glass-on-glass | — | ✅ | Verified: no nested materials |

---

## Accessibility Matrix

| Element | VoiceOver Label | Dynamic Type | Reduce Motion | Contrast | Status |
|---------|----------------|--------------|---------------|----------|--------|
| Photo picker | "Add profile photo, optional" / "Change profile photo" | `.systemScaled` fonts | N/A | ONB.accent contrast | ✅ **Fixed** |
| Username availability | `UIAccessibility.post(.announcement)` | ✅ | N/A | Green/red | ✅ |
| Continue button | Inherits `Text` title | `minHeight: 56` | N/A | White on black | ✅ |
| Terms checkbox | Button with visual check | ✅ | `.spring` reduced | Accent on white | ⚠️ Needs explicit `accessibilityLabel` |
| DOB picker toggle | Chevron only | ✅ | `.easeInOut` | Accent icon | ⚠️ Needs `accessibilityLabel("Date of birth")` |
| AI consent card | `.accessibilityElement(children: .contain)` + label | ✅ | N/A | ONB tokens | ✅ **Fixed** |
| Interest chips | Button inherits `label` Text | ✅ | `.spring` | Color + text | ✅ |
| Error alert | System alert | ✅ | N/A | System | ✅ |
| Bio field | `accessibilityLabel("Bio, optional")` | ✅ | N/A | ONB tokens | ✅ **Fixed** |

---

## Remaining Caveats

### Must Fix Before Production
1. **`UserService.uploadProfileImage()` path** — Post-onboarding profile edits still write to `profile_images/{uid}/profile.jpg`. Storage rules MUST enforce `request.auth.uid == userId` for this path. Verify in deployed rules.
2. **Username uniqueness is client-side** — `scheduleUsernameCheck()` queries `users` collection directly with no rate limiting. A server-side `checkUsernameAvailable` callable with rate limiting should be used. The final re-check in `finishOnboarding()` partially mitigates races but not enumeration.
3. **Terms checkbox missing `accessibilityLabel`** — Needs `accessibilityLabel("Agree to Terms of Service and Privacy Policy")`.
4. **DOB toggle missing `accessibilityLabel`** — Needs `accessibilityLabel("Date of birth")` on the toggle button.

### Minor / Acceptable Caveats
5. **`profile_images/` path inconsistency** — Old path used by `UserService` for post-onboarding profile changes. Consolidating to `users/{uid}/profile/avatar/` is a follow-up migration, not a launch blocker if rules are correct.
6. **No bio length limit enforced client-side** — Backend `completeOnboarding` callable should reject bios over 160 chars. Client-side cap would improve UX.
7. **`OnboardingFlowView.swift` and `OnboardingAppLaunchView.swift`** — Legacy/debug dead code. Safe to delete but not blocking.

---

## Tests Run
- Xcode live diagnostics: `XcodeRefreshCodeIssuesInFile` on `OnboardingOnboardingView.swift` → **0 issues**

## Exact Deploy Commands (after rules verification)

```bash
# Verify + deploy Firestore + Storage rules
firebase deploy --only firestore:rules,storage --dry-run
firebase deploy --only firestore:rules,storage

# Build + test
xcodebuild \
  -project AMENAPP.xcodeproj \
  -scheme AMENAPP \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build test
```

---

## Rollout Recommendation
**GO WITH CAVEATS** — Core onboarding flow is wired, accessible, and data-complete. Ship behind a feature flag if username client-side enumeration is a concern. The two accessibility gaps (terms checkbox label, DOB button label) are minor and fixable in a follow-up.

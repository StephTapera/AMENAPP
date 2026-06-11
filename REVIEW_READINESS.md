# App Store Review Readiness
**App:** AMEN v1.0 (build 5)
**Bundle ID:** tapera.AMENAPP
**Prepared by:** Agent 5, Launch Readiness Swarm
**Date:** 2026-06-11

---

## Guideline 1.2 — User-Generated Content Compliance

### Moderation Evidence

| Requirement | Implementation | Source file(s) | Screenshot needed? |
|---|---|---|---|
| Report mechanism — posts | Three-dot menu → Report → category selector | `PostCard.swift` | YES — Station 10 in WALKTHROUGH_SCRIPT.md |
| Report mechanism — profiles | Profile view → Report User | `UserProfileView.swift` | YES — Station 12 |
| Report mechanism — comments | Long-press / swipe action on comment | `CommentsView.swift` | YES — Station 11 |
| Report mechanism — DMs | Report button in chat | `UnifiedChatView.swift` | YES |
| Report backend | `submitSafetyReport` CF (auth + AppCheck + rate-limited) | `functions/submitSafetyReport.js` | No (server-side) |
| Block user | Profile → Block (enforced in rules + backend) | `UserProfileView.swift`, Firestore rules | YES — Station 12 |
| Mute user | Feed → Mute (hides from feed) | `PostCard.swift` | YES |
| Automated text moderation | NeMo Guard CF — all posts/comments pre-publication | `functions/mediaModerationPipeline.ts` | No (server-side) |
| Automated image moderation | Google Vision API — media quarantine path | `functions/mediaModerationPipeline.ts` | No (server-side) |
| Human review queue | `adminReviewPost` CF — escalated reports | `functions/adminReviewPost.js` | No (server-side) |
| Minor protection — DM | Adult-to-minor DM gate (fail-closed) | `AmenChildSafetyService.swift`, `ageTier.js` | No |
| Minor protection — search | Minor search exclusion in feed/search rules | `functions/ageTier.js`, Firestore rules | No |

---

## Guideline 4.8 — Sign-in Options

Apple requires Sign in with Apple when ANY third-party social login is offered.

| Sign-in method | Status | Source |
|---|---|---|
| Sign in with Apple | **YES — IMPLEMENTED** | `com.apple.developer.applesignin` entitlement present in both `.entitlements` files; `Default` capability added |
| Sign in with Google | YES | `GoogleSignIn` SDK — URL scheme `com.googleusercontent.apps.78278013543-...` in `Info.plist` |
| Email / Password | YES | Firebase Auth |
| Biometric (Face ID / Touch ID) | YES | `BiometricAuthService.swift`, `BiometricOnboardingPage.swift` |

Sign in with Apple is confirmed present. No action needed on this point.

---

## Guideline 5.1 — Privacy

### Privacy Policy
- **Action required (HUMAN):** Confirm Privacy Policy URL is set in App Store Connect → App Information.
- **Action required (HUMAN):** Confirm Privacy Policy URL is accessible from within the app (sign-in screen or Settings).
- Privacy domains match `NSPrivacyTrackingDomains` in `PrivacyInfo.xcprivacy`.

### App Tracking Transparency
- ATT prompt is triggered in `AppDelegate.swift` via `ATTrackingManager.requestTrackingAuthorization`.
- `NSPrivacyTracking = true` declared in `PrivacyInfo.xcprivacy`.
- `NSUserTrackingUsageDescription` key set in build settings.
- No action needed — ATT is correctly implemented.

### Account Deletion
- **Action required (HUMAN):** Verify delete-account flow is accessible from Settings in the production build and that it works end-to-end (deletes Firebase Auth user, Firestore documents, Storage media).
- Apple requires in-app account deletion for any app with user accounts (Guideline 5.1.1).

### Data Minimization
- Contacts: `ChurchChemistryService.swift` reads contacts on-device only; PrivacyInfo.xcprivacy declares `linked = false`.
- Health: PrivacyInfo.xcprivacy declares `linked = false`; no health data stored on servers per usage description.
- Location: PrivacyInfo.xcprivacy declares `linked = false`; only used for church discovery.

---

## Guideline 2.3 — Accurate Metadata

### Features that must be visible to reviewers

| Feature | How to access | Notes |
|---|---|---|
| Home feed | Launch app → sign in with demo account | Posts pre-populated |
| Create post | Tap compose (pencil) button | Goes through NeMo Guard |
| Church Notes | Notes tab | Create note, add scripture |
| Find a Church | Discover tab → Church search | Location permission required |
| Prayer Wall | Feed → Prayer tab | View and add prayer requests |
| Berean AI | Berean icon / assistant bar | AI scripture questions |
| Profile + block/report | Tap any user avatar | Report, block, mute options |
| Settings + account deletion | Profile → Settings | Account deletion must be visible |

### Features that are gated OFF by default (Remote Config)

These features are built and tested but disabled by default via Remote Config flags. Reviewers will NOT encounter them unless flags are enabled:

- Connect V2 redesign (`connect_layout_v2_enabled = false`)
- Spaces features (`spaces_*` flags = false)
- ONE relay (`one_relay_enabled = false`)
- Amen Pulse (`amen_pulse_enabled = false`)
- Music Content Layer (`music_content_layer_enabled = false`)
- Connected Intelligence (`connected_intelligence_enabled = false`)

**Do not flip any of these flags ON before submission unless those features have been fully tested end-to-end.**

---

## Demo Account

Apple Review requires a demo account with pre-populated content so reviewers can see the app working without signing up.

```
Email:    review@amen-appstore-demo.com   ← HUMAN MUST CREATE
Password: [human sets a strong password]
```

**HUMAN ACTION — populate this account before submission:**
1. Post 3+ feed items (text, one with a photo, one with scripture)
2. Add 2+ prayer requests
3. Create 1 church note with a scripture reference
4. Follow 2+ other accounts
5. Save 1+ churches in Find a Church
6. Do NOT use any real users' personal information in this account

---

## Review Notes Draft

Copy and paste the following into App Store Connect → Version Information → Notes for Reviewer:

---

```
AMEN is a faith community app for Christians to share posts, prayer requests, and church notes.

SIGN-IN INSTRUCTIONS
Email:    review@amen-appstore-demo.com
Password: [FILL IN PASSWORD BEFORE SUBMITTING]

KEY FEATURES TO REVIEW

1. Home feed — posts and prayer requests from the community. Tap the three-dot menu on any post to access Report and Hide options.

2. Create Post — tap the compose (pencil) button. All posts pass through automated content moderation before appearing in the feed.

3. Church Notes — tap the Notes tab. Create a note, and the app will auto-detect scripture references. Notes are private by default.

4. Find a Church — Discover tab → Search churches. Location permission is requested when entering this feature (When In Use only).

5. Prayer Wall — feed → Prayer section. Post prayer requests; community members can add "Praying" reactions.

6. Berean AI — the assistant bar at the top of the Berean tab. Ask Bible questions; all responses include scripture citations.

7. Report / Block — tap any user avatar → Profile → three-dot menu → Report or Block. Report categories include CSAM, harassment, self-harm, and other safety categories.

8. Account Deletion — Profile → Settings → Account → Delete Account.

MINOR SAFETY NOTE
If a reviewer creates a test account with a birth date indicating a minor (under 18), certain direct messaging and public discovery features will be restricted. This is intentional age-tier safety behavior. The demo account above is an adult account and has full access.

CONTENT MODERATION
All user-generated content passes through automated text and image moderation before being publicly visible. Safety reports are routed to human moderators. Moderation contact: moderation@amen.app [HUMAN: CONFIRM THIS EMAIL]

SIGN IN WITH APPLE
Sign in with Apple is supported alongside Sign in with Google and email/password.

IN-APP PURCHASES
Amen+, AmenPro, CreatorPro, and ChurchPro subscriptions are available. These are standard auto-renewable subscriptions managed by App Store.

ENCRYPTION
AMEN uses only standard iOS/Apple encryption (HTTPS/TLS). No custom encryption algorithms are implemented. Answer "No" to the encryption export compliance question.
```

---

## Remaining Blockers Before Submission

### Must-fix before submitting

| Item | Owner | Ref |
|---|---|---|
| Create demo account with populated content | HUMAN | Section: Demo Account |
| Set Privacy Policy URL in App Store Connect | HUMAN | Guideline 5.1 |
| Verify account deletion works end-to-end | HUMAN | Guideline 5.1.1 |
| Document moderation SLA + publish moderation contact | HUMAN | Guideline 1.2 |
| Answer age rating questionnaire in App Store Connect | HUMAN | AGE_RATING_WORKSHEET.md |
| Answer privacy labels in App Store Connect | HUMAN | APP_PRIVACY_LABELS.md |
| Enter release notes in App Store Connect | HUMAN | RELEASE_NOTES.md |
| Capture screenshots per CAPTURE_PLAN.md | HUMAN | CAPTURE_PLAN.md |
| NCMEC registration complete (for CSAM reporting CF) | HUMAN (legal) | A-01 in DECISION_DOC_SAFETY |
| Deploy backend (10 steps in STAGE3_DEPLOY_PACKAGE) | HUMAN | STATUS_BOARD.md |

### Confirm-and-close (likely fine, verify before submitting)

| Item | Status | Verified by |
|---|---|---|
| Sign in with Apple entitlement | Confirmed present in both entitlements files | Agent 5 |
| ATT prompt implemented | Confirmed in AppDelegate.swift | Agent 5 |
| aps-environment = production | Confirmed in AMENAPP.entitlements | Agent 5 |
| App Attest environment = production | Confirmed in AMENAPP.entitlements | Agent 5 |
| Background modes declared in Info.plist | Confirmed (remote-notification, fetch, processing) | Agent 5 |

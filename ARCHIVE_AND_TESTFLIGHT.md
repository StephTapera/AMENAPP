# Archive, Upload, and TestFlight — Step-by-Step
**App:** AMEN v1.0 (build 5)
**Bundle ID:** tapera.AMENAPP
**Prepared by:** Agent 5, Launch Readiness Swarm
**Date:** 2026-06-11

---

## Prerequisites — Complete Before Archiving

- [ ] All 10 backend deploy steps in `STAGE3_DEPLOY_PACKAGE_2026-06-11.md` completed
- [ ] `RUN_ME.sh` completed with no errors
- [ ] Demo account `review@amen-appstore-demo.com` created with pre-populated content (see `REVIEW_READINESS.md`)
- [ ] Privacy labels answered in App Store Connect (use `APP_PRIVACY_LABELS.md`)
- [ ] Age rating answered in App Store Connect (use `AGE_RATING_WORKSHEET.md`)
- [ ] App Store metadata (description, keywords, subtitle) entered (use `RELEASE_NOTES.md`)
- [ ] Screenshots captured per `CAPTURE_PLAN.md`
- [ ] Privacy policy URL set in App Store Connect
- [ ] Support URL set in App Store Connect

---

## Step 1 — Verify Scheme, Destination, and Configuration

1. Open `AMENAPP.xcodeproj` in Xcode
2. Product → Scheme → **AMENAPP** (not AMENNotificationServiceExtension or AMENWidgetExtension)
3. Set run destination: **Any iOS Device (arm64)**
   - Do NOT archive to a simulator — App Store requires a device build
4. Confirm active configuration: **Release**
   - Product → Scheme → Edit Scheme → Archive → Build Configuration = Release

---

## Step 2 — Verify Feature Flag Defaults

Before archiving, confirm that all Remote Config flags default to `false` in the source. Remote Config overrides are applied at runtime after the binary ships — they are NOT compiled in.

Key files to check:
- `AMENAPP/AMENFeatureFlags.swift` — all flag properties should default `false`
- `Config.xcconfig` — confirm no production secrets are embedded
- `Config.local.xcconfig` — if this file exists, it must NOT be included in the Archive build (it is developer-only)

**Confirm:** No feature flag is hardcoded `true` in source for the production Archive.

---

## Step 3 — Confirm Entitlements (Release vs Debug)

The project uses two entitlements files:

| File | Used for | aps-environment |
|---|---|---|
| `AMENAPP/AMENAPP.entitlements` | Debug + Release (primary) | `production` |
| `AMENAPP/AMENAPP.release.entitlements` | Release only (secondary/override) | `production` |

Both files have:
- `aps-environment = production` ✓
- `com.apple.developer.devicecheck.appattest-environment = production` ✓ (debug file only — confirm release build uses correct entitlements in Build Settings)
- `com.apple.developer.applesignin` ✓

**Action:** In Xcode → Target AMENAPP → Build Settings → Code Signing Entitlements — confirm the Release configuration points to `AMENAPP.release.entitlements` (or `AMENAPP.entitlements` if that is the intended release file).

---

## Step 4 — Archive

1. Product → **Archive**
2. Wait for archive to complete (typically 5–15 minutes for a clean build)
3. Xcode Organizer opens automatically when archive completes
4. Verify: the archive shows the correct version `1.0 (5)` and bundle ID `tapera.AMENAPP`

If the archive fails:
- Check for any compile errors in the build log (Product → Show Build Log)
- The most common issue is missing SPM packages — run Package → Resolve Package Versions first
- If binary SPM packages (abseil, grpc, WebRTC) cause issues, see the Camera OS build notes in project memory

---

## Step 5 — Validate Before Upload

1. In Organizer: select the archive → **Distribute App**
2. Select: **App Store Connect**
3. Select: **Upload** (not Export)
4. Distribution options — check all that apply:
   - [x] **Strip Swift symbols** — reduces binary size
   - [x] **Upload symbols** — enables symbolicated crash reports in Crashlytics
   - [ ] Include bitcode — leave unchecked (bitcode is deprecated in Xcode 14+)
5. **Export Compliance:**
   - AMEN uses standard HTTPS/TLS only
   - No custom encryption algorithms
   - No VPN, messaging end-to-end encryption, or custom crypto
   - **Select: "No, the app does not use encryption other than Apple's standard encryption"**
6. Click **Validate** and wait for validation to complete
7. Fix any validation errors before proceeding to upload

### Common validation errors and fixes

| Error | Fix |
|---|---|
| "Missing compliance" | Answer export compliance as described above |
| "Invalid bundle — missing Push Notification entitlement" | Confirm aps-environment = production in entitlements; confirm APN certificate/key is configured in Apple Developer Portal |
| "The app references non-public selectors" | Check for any private API usage introduced by new code |
| "Missing privacy manifest" | `PrivacyInfo.xcprivacy` exists — confirm it is in the AMENAPP target membership |
| "Invalid icon" | App icon must not include alpha channel; use Xcode asset catalog with correct sizes |

---

## Step 6 — Upload

1. After validation passes: click **Upload**
2. Upload typically takes 2–10 minutes depending on binary size
3. When complete, Xcode shows a success confirmation
4. The build will appear in **App Store Connect → TestFlight** within approximately 30 minutes
5. It will first be in "Processing" status — wait for it to complete processing before adding to groups

---

## Step 7 — TestFlight Internal Testing

1. App Store Connect → Your App → **TestFlight**
2. Select the processed build → Add to **Internal Testing** group
3. Add internal testers (up to 100 users with TestFlight access via App Store Connect team roles)
4. Testers receive an invitation email / TestFlight notification
5. Testers install via TestFlight app on a physical device

### TestFlight Acceptance Checklist

Run through `WALKTHROUGH_SCRIPT.md` on a **real iPhone** (not simulator) using the internal TestFlight build. Document pass/fail for each station.

| Station | Feature | Expected | Pass/Fail |
|---|---|---|---|
| 1 | App launch + onboarding | Smooth launch, onboarding shown on first install | |
| 2 | Sign in with Apple | OAuth sheet → account created | |
| 3 | Sign in with Google | OAuth sheet → account created | |
| 4 | Email / password sign-up | Verification email sent | |
| 5 | Age verification | Age gate shown; minor gets restricted experience | |
| 6 | Home feed | Posts load; pull to refresh works | |
| 7 | Create post | Compose → post visible in feed after moderation | |
| 8 | Photo post | Camera permission prompt → photo added | |
| 9 | Church Notes | Note created; scripture auto-detected | |
| 10 | Report post | Three-dot → Report → category → submitted | |
| 11 | Report comment | Long-press → Report → submitted | |
| 12 | Block user | Profile → Block → user no longer visible | |
| 13 | Find a Church | Location permission → churches listed nearby | |
| 14 | Prayer Wall | Prayer posted; community praying reaction | |
| 15 | Berean AI | Question answered with scripture citation | |
| 16 | Push notifications | Test notification delivered on real device | |
| 17 | Account deletion | Settings → Delete Account → account removed | |
| 18 | ATT prompt | Tracking permission dialog shown at first launch | |
| 19 | Sign out | Signs out cleanly; no stale session | |

---

## Step 8 — External TestFlight (Optional, Recommended)

For broader pre-launch testing (up to 10,000 external testers):

1. App Store Connect → TestFlight → External Testing → **New Group**
2. Submit for **TestFlight App Review** (faster than full App Store review — typically 1-2 business days)
3. Share the TestFlight link with beta testers
4. Collect feedback before full App Store submission

---

## Step 9 — Submit for Full App Store Review

**Do not submit until ALL of the following are complete:**

- [ ] All TestFlight stations pass on a real device
- [ ] All 10 backend deploy steps complete
- [ ] GROUP A safety decisions answered (DECISION_DOC_SAFETY — A-01 through A-08)
- [ ] NCMEC registration complete (A-01 gate)
- [ ] Demo account created with content
- [ ] Privacy labels answered in App Store Connect
- [ ] Age rating answered in App Store Connect
- [ ] App Store metadata (description, keywords, screenshots) complete
- [ ] Privacy policy URL set
- [ ] Support URL set
- [ ] Review notes pasted (from `REVIEW_READINESS.md`)
- [ ] Moderation SLA documented; moderation contact email published

**Submit:** App Store Connect → Your App → Prepare for Submission → **Submit for Review**

---

## Export Compliance — Final Answers

Apple asks about encryption during distribution. Use these answers:

| Question | Answer |
|---|---|
| Does your app use encryption? | YES — standard HTTPS/TLS (Apple's built-in) |
| Does your app implement any encryption beyond Apple's standard? | **NO** |
| Is your app a "mass market" crypto product? | NO |
| Exemption category | HTTPS/TLS — qualifies for EAR exemption 5D002 |
| Do you need an ERN (Encryption Registration Number)? | NO — HTTPS-only apps are exempt |

Select **"No"** when Xcode asks "Does your app use encryption other than Apple's built-in standard encryption?" This is the correct answer for HTTPS-only apps.

---

## Post-Submission Checklist

- [ ] App Store Connect shows "Waiting for Review" status
- [ ] Team notified of submission timestamp
- [ ] Moderation team on standby for App Review period (reviewers may send questions)
- [ ] App Review response contact confirmed in App Store Connect
- [ ] If rejected: review rejection reason carefully before resubmitting; do not rush a resubmit

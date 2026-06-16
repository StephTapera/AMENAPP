# AMEN — Human Gate Queue

**Generated:** 2026-06-16 Overnight Audit
**Your morning**: Work through P0 -> P1 -> P2 -> P3. All P0 blocking items must be resolved before App Store submission.

## Legend

- 🔴 P0 = App Store BLOCKER — must fix before submission
- 🟠 P1 = High severity — fix before beta
- 🟡 P2 = Medium — fix before launch
- ⚪ P3 = Low — fix when convenient

- 🟡 lane = YELLOW lane (code staged, you activate)
- 🔴 lane = RED lane (decision brief, you decide + implement)
- ⏱ = Estimated time

**Total items:** 30 yellow + 17 red = 47
**P0 count:** 6 | **P1 count:** 5

---

## P0 BLOCKERS — Must clear before any submission

---

### 🔴 P0-1 — [P5-Y1] DM message .report action not wired to ReportContentSheet

**Lane:** YELLOW (code ready to write)
**Why gated:** Apple Guideline 1.2 requires a functioning in-app report mechanism for all UGC surfaces. MessageActionCluster always appends .report to its actions grid, but the onAction(.report) callback fires into a no-op closure — no sheet is presented. The button is visible and interactive but does nothing.
**⏱ Estimated:** 45 min

**Exact action:**

1. Open `ONEThreadView.swift`
2. Add `@State private var reportingMessage: AppMessage? = nil`
3. Mount `MessageActionCluster` with:
   ```swift
   onAction: { action in
       if action == .report { reportingMessage = msg }
   }
   ```
4. Add:
   ```swift
   .sheet(item: $reportingMessage) { msg in
       ReportContentSheet(
           targetType: .message,
           targetId: msg.id,
           onSubmitted: { _ in },
           onDismiss: { reportingMessage = nil }
       )
   }
   ```
5. Mirror the same pattern in `AmenMinistryRoomChatView.swift`

**Affected files:**
- `AMENAPP/AMENAPP/ONE/People/Views/ONEThreadView.swift`
- `AMENAPP/AMENAPP/ConnectSpaces/Spaces/AmenMinistryRoomChatView.swift`
- `AMENAPP/AMENAPP/AMENAPP/CommunicationOS/MessageActionCluster.swift`

---

### 🔴 P0-2 — [P5-Y2] NCMEC CyberTipline not wired — LEGAL GATE

**Lane:** RED (legal decision required before any code change)
**Why gated:** 18 USC 2258A mandates electronic service providers report CSAM within 24 hours of actual knowledge. `mediaModerationPipeline.ts` blocks content on hash match but does not submit an NCMEC CyberTip. `securityLaunchReadiness.test.ts` will fail due to missing fields: `ncmecReadiness`, `requiresEvidencePreservation`, `dualApprovalRequired`, `automatedCyberTipSubmitted`, etc.
**⏱ Estimated:** 120 min (after legal gate clears)

**Decision required:** Legal must sign off before any deploy. Do not merge or deploy this path without legal written approval.

**Engineering steps (post legal approval):**

1. Register as an Electronic Service Provider at https://www.missingkids.org/gethelpnow/cybertipline
2. Obtain NCMEC API credentials; store as `NCMEC_API_KEY` and `NCMEC_ENDPOINT` in Cloud Secret Manager (never in source)
3. In `mediaModerationPipeline.ts`, after `hashCheck.matched === true` / `action === block`, call:
   ```ts
   await submitNCMECCyberTip(postId, userId, mediaUrl, hashCheck.hashValue)
   ```
4. Add the following fields to `submitReport.ts` to satisfy the launch readiness test:
   - `ncmecReadiness`
   - `automatedCyberTipSubmitted: false`
   - `evidenceVault`
   - `moderationCases`
   - `dualApprovalRequired`
   - `breakGlassRequiredForPrivateContent`
   - `needs_trained_reviewer_assessment`
5. Deploy only after legal review and sign-off

**Affected files:**
- `Backend/functions/src/submitReport.ts`
- `Backend/functions/src/mediaModerationPipeline.ts`
- `Backend/functions/src/securityLaunchReadiness.test.ts`

---

### 🟡 P0-3 — [Y-P4-01] Account deletion hard-delete Cloud Function not deployed

**Lane:** YELLOW (code exists, deployment pending)
**Why gated:** App Store Guideline 5.1.1 mandates a working hard-delete path. `AccountManagementService.hardDeleteAccount()` calls `functions.httpsCallable('deleteUserAccount')`. Without this CF deployed, tapping "Delete Immediately (No Recovery)" in `DeleteAccountView` will fail at runtime with a not-found error.
**⏱ Estimated:** 60 min

**Exact action (run from repo root only):**

```sh
# Step 1 — Verify CF source exists
ls Backend/functions/src/ | grep deleteUserAccount

# Step 2 — Deploy to us-east1 (us-central1 is at quota)
firebase deploy --only functions:default:deleteUserAccount

# Step 3 — Add to Interim Region Table in docs/FUNCTION_INVENTORY.md:
# | deleteUserAccount | us-east1 | default | 2026-06-16 | account hard-delete per Guideline 5.1.1 |

# Step 4 — Smoke-test with a sandboxed test account before flipping live traffic
```

**Affected files:**
- `AMENAPP/AMENAPP/RecoveryOS/AccountManagementService.swift`
- `AMENAPP/DeleteAccountView.swift`
- `Backend/functions/src/` (verify deleteUserAccount.ts exists)
- `docs/FUNCTION_INVENTORY.md` (add region table entry)

---

### 🟡 P0-4 — [Y-P4-02] No reviewer demo-credential path for App Store submission

**Lane:** YELLOW (no code yet, must add before archiving)
**Why gated:** Apple reviewers cannot access the app without pre-provisioned credentials. App Review will reject if they cannot exercise core features from cold launch. Vague "contact us" notes are insufficient.
**⏱ Estimated:** 45 min

**Exact action:**

1. Create Firebase Auth account `reviewer@amenapp.com` with a strong known password (store in 1Password under "App Store Review Credentials")
2. Set in Firestore: `users/{uid}/hasCompletedOnboarding = true`
3. Add to `SignInView.swift`:
   ```swift
   #if APPSTORE_REVIEW_BUILD
   Button("Use Demo Account") {
       email = "reviewer@amenapp.com"
       password = "ReviewerPass1!"
   }
   .font(.caption)
   .foregroundColor(.secondary)
   #endif
   ```
4. Add `APPSTORE_REVIEW_BUILD` to Swift Active Compilation Conditions in a dedicated Xcode scheme named "AMENAPP (Review)"
5. Archive using the Review scheme only for App Store Connect uploads — never use this scheme for production builds
6. Paste credentials into the "Notes for Reviewers" field in App Store Connect before submitting

**Affected files:**
- `AMENAPP/SignInView.swift`
- Xcode project scheme settings (manual Xcode step)

---

### 🔴 P0-5 — [R-P12-01] Restore Purchases button missing from all paywall screens

**Lane:** RED (UX decision required before engineering)
**Why gated:** Apple App Store Review Guideline 3.1.1 requires every paywall screen to include a "Restore Purchases" button. Five screens are missing it: `TwoFourTwoSubscriptionView`, `CreatorSubscriptionGateView`, `MentorshipPlanSheet`, `StudioPaywallView`, `AMENConnectMembership`.

**Decision required (product/design must choose one option before engineering starts):**

| Option | Description | Tradeoffs |
|--------|-------------|-----------|
| A | Standalone "Restore Purchases" text link below primary CTA on each of the 5 views, calling `AppStore.sync()` | Quickest path; most consistent with App Store guidelines |
| B | Shared `RestorePurchasesButton` component embedded in a reusable `SubscriptionFooterView` | Cleaner architecture; slightly more setup |
| C | Link from Settings > Account > Subscriptions only | Apple still requires it on the paywall itself per Guideline 3.1.1 — DO NOT choose this option |

**Engineering notes (after decision):** Wrap `AppStore.sync()` in a loading/error state. Handle `StoreKitError.userCancelled` silently; surface other errors as an alert.

---

### 🔴 P0-6 — [R-P12-02] Stripe used for in-app digital subscriptions — potential Guideline 3.1.1 violation

**Lane:** RED (legal + product decision required before any code change)
**Why gated:** `MentorshipService` and `StudioPaymentService` call Stripe Cloud Functions (`stripeCreatePaymentIntent`, `mentorship-createPaidRelationship`) to charge users $19–$39/month for mentorship and creator studio features inside the app. Apple Guideline 3.1.1 prohibits third-party payment processors for digital content or services delivered inside the app.

**Decision required (legal + product must align on one option):**

| Option | Description | Risk level |
|--------|-------------|------------|
| A | Classify mentorship as "external human-delivered service": add Apple-compliant disclaimer that payment is processed externally; remove any in-app entitlement grant triggered by Stripe result | Medium — Apple may still challenge if entitlement is granted in-app |
| B | Classify as digital content: migrate all subscription products to StoreKit 2; remove Stripe from the iOS payment path entirely | Higher engineering cost; eliminates rejection risk |
| C | Seek formal Apple pre-submission review for the mentorship model to get written guidance before committing | Safest; adds 2–4 weeks; written guidance protects submission |

**Recommendation:** Option C if timeline allows. Option B if submission date is fixed and cannot slip.

---

## P1 HIGH SEVERITY — Fix before beta

---

### 🟡 P1-1 — [Y-P12-01] Add AI disclosure copy to Berean surfaces

**Lane:** YELLOW (copy decision needed, then 30-min engineering task)
**Why gated:** EU AI Act and Apple reviewer practice require disclosure when AI generates user-facing content. Berean surfaces show AI-generated responses with no attribution or disclaimer.
**⏱ Estimated:** 30 min

**Exact action (after product/legal approves copy):**

1. Agree on disclosure copy. Suggested text: "Berean responses are generated by AI and may contain errors. Always verify with Scripture."
2. Add as a small footnote `Text` view to:
   - `AMENAPP/BereanMenuSheet.swift` — below the response card
   - `AMENAPP/AMENAPP/BereanAgent/` entry view — in the system header
3. Gate display behind existing Remote Config flag `berean_ai_disclosure_enabled`
4. To go live: set `berean_ai_disclosure_enabled = true` in Firebase Remote Config console after copy is approved

**Affected files:**
- `AMENAPP/BereanMenuSheet.swift`
- `AMENAPP/AMENAPP/BereanAgent/` (entry view file)

---

### 🟡 P1-2 — [Y-P3-03] AmenDiscoverDetailView Pray/Save/Share closures are log-only

**Lane:** YELLOW (closures exist, need real wiring)
**Why gated:** Pray/Save/Share are core app actions on the Discover surface. All three currently log analytics only and perform no actual operation. A user tapping Pray or Save sees no result and no feedback.
**⏱ Estimated:** 90 min

**Exact action:**

1. In `AmenDiscoverView.swift`, update `onPray`:
   ```swift
   onPray: {
       guard FeatureFlags.prayerOSEnabled else { return }
       Task { await PrayerOSService.shared.submit(for: item.id) }
   }
   ```
2. Update `onSave`:
   ```swift
   onSave: {
       guard FeatureFlags.saveFeatureEnabled else { return }
       Task { await BookmarkService.shared.save(item) }
   }
   ```
3. Update `onShare`:
   ```swift
   onShare: {
       let av = UIActivityViewController(activityItems: [item.shareURL], applicationActivities: nil)
       UIApplication.shared.topViewController?.present(av, animated: true)
   }
   ```
4. No feature flag needed for Share (system UI, always safe)

**Affected files:**
- `AMENAPP/AMENAPP/AmenDiscoverView.swift`
- `AMENAPP/AMENAPP/AmenDiscoverDetailView.swift`

---

### 🟡 P1-3 — [P5-Y3] Ministry Room chat has no post-send report affordance

**Lane:** YELLOW (pre-send Aegis guard exists; post-send reporting missing)
**Why gated:** Apple Guideline 1.2 requires all UGC chat surfaces to expose a report mechanism. `AmenMinistryRoomChatView.swift` has a pre-send Aegis guard but no long-press or context-menu report action on sent messages.
**⏱ Estimated:** 45 min (coordinate with P0-1 — the Ministry Room wiring is part of the same pass)

**Exact action:** When completing P0-1, verify that the mounted `MessageActionCluster` also appears on received messages in the Ministry Room. If the Room uses a different message row component, add `.contextMenu` with a "Report" option presenting `ReportContentSheet`.

**Affected files:**
- `AMENAPP/AMENAPP/ConnectSpaces/Spaces/AmenMinistryRoomChatView.swift`

---

### 🟡 P1-4 — [Y-P12-02] NSUserTrackingUsageDescription too vague for ATT approval

**Lane:** YELLOW (15-min Info.plist edit, no deploy)
**Why gated:** Apple has rejected vague ATT purpose strings in review. The current string does not name specific tracking domains or data types collected.
**⏱ Estimated:** 15 min

**Exact action:**

1. Open `AMENAPP/Info.plist`
2. Find key `NSUserTrackingUsageDescription`
3. Replace the current value with:
   ```
   AMEN uses the advertising identifier to measure app installs and engagement via Firebase Analytics (app-measurement.com) and Crashlytics crash attribution. This data is used only for product improvement and is not sold to third parties.
   ```
4. No Firebase deploy needed — change takes effect in the next Xcode archive/upload

**Affected files:**
- `AMENAPP/Info.plist`

---

### 🔴 P1-5 — [R-P3-01] VoicePrayerCommentRowView: hard-delete vs soft-delete policy undefined

**Lane:** RED (product policy decision required)
**Why gated:** The confirmation dialog prevents accidental taps, but `onDelete()` makes an immediate hard Firestore delete of user-generated audio content with no recovery path. Policy has not been defined.

**Decision required (product must choose before beta):**

| Option | Description | Engineering cost |
|--------|-------------|-----------------|
| A | Immediate hard-delete (current behavior) | Zero — already implemented |
| B | 24-hour soft-delete: add `deletedAt` timestamp; Cloud Function purges after 24h; user sees an undo affordance within the window | Medium — data model change + new CF + UI undo affordance |

**Recommendation:** If soft-delete (B) is chosen, the data model change must be made before any real user audio is collected in production. A migration after launch is significantly more expensive.

---

## P2 MEDIUM SEVERITY — Fix before launch

---

### 🔴 P2-1 — [R-P3-02] CovenantRoomDetailView context-menu delete fires without confirmation

**Lane:** RED (UX pattern decision + small engineering task)
**Why gated:** Long-press "Delete" on a message in `AmenCovenantRoomDetailView` fires an immediate Firestore delete with no confirmation dialog or undo path. Accidental destructive action with no recovery.

**Decision required:** Choose the UX pattern (confirmation alert or undo toast), then engineering can implement in approximately 20 min.

---

### 🟡 P2-2 — [Y-P3-01] BIL action button contracts not yet wired (11 stubs)

**Lane:** YELLOW (stubs exist; contracts pending BIL Wave 2)
**Why gated:** 11 buttons across BIL views (`BILHomeCompactionView`, `LedgerView`, `BranchingView`, `SourceCardsView`, `ContextPackagesView`) have `dlog` stubs. All are behind the `bilEnabled` feature flag — safe to ship gated OFF.
**⏱ Estimated:** 180 min (BIL Wave 2 work, not a pre-submission blocker)

**When BIL Wave 2 contracts land:**
```sh
grep -r "TODO(BIL-BI-0" AMENAPP/
```
Wire each stub per its Wave 2 contract definition.

**Affected files:**
- `AMENAPP/AMENAPP/HomeView.swift` (and all BIL view files)

---

### 🟡 P2-3 — [Y-P3-02] DailyOffice Listen and Print pipelines not wired

**Lane:** YELLOW (blocked on BIL audio pipeline landing)
**Why gated:** "Listen" button needs `DailyOffice.audioAssetRef` wired to AVPlayer. "Print" button needs `UIActivityViewController`. Both are blocked behind BIL audio pipeline work.
**⏱ Estimated:** 60 min (post-BIL-audio-pipeline)

**When BIL audio pipeline lands:**
```sh
grep -r "TODO(BIL-audio)\|TODO(BIL-print)" AMENAPP/
```

**Affected files:**
- `AMENAPP/AMENAPP/AIIntelligence/AmenDistinctives.swift`

---

## P3 LOW / NICE-TO-HAVE

*All items below are gated OFF by feature flags and do not block submission. Address when convenient.*

---

### ⚪ P3-1 — Remaining RED-lane decision items (lower priority)

The following RED items require product or legal decisions but are not App Store blockers for the initial submission. Schedule a product review session to work through them.

| ID | Title | Owner | Estimated eng time post-decision |
|----|-------|-------|----------------------------------|
| R-P3-02 | CovenantRoomDetailView delete confirmation pattern (see P2-1) | Product/Engineering | 0.5 hrs |
| R-P3-01 | VoicePrayer soft-delete policy (see P1-5) | Product/Engineering | 0–6 hrs |

---

## Special Non-Negotiable Gates

---

### Child Safety — P0 BLOCKING

**Item:** P0-2 above (NCMEC CyberTipline)

This gate will NOT open without all four of the following:

1. Written legal sign-off on 18 USC 2258A compliance
2. NCMEC ESP registration confirmation in writing
3. `NCMEC_API_KEY` and `NCMEC_ENDPOINT` stored in Cloud Secret Manager — never in source code
4. Deploy reviewed by at least one non-engineering team member before any production traffic

Do not deploy `mediaModerationPipeline.ts` hash-match changes to production without completing all four steps. A missed CyberTip after actual knowledge of CSAM is a federal reporting violation.

---

### Credential Rotation — P0 BLOCKING if secrets found

**Status from overnight audit:** No new hardcoded secrets found in this audit wave. The CLAUDE_API_KEY rotation was completed 2026-06-05.

**Standing rule:** Before every archive/upload, run a secrets scan:

```sh
git secrets --scan
# or manually:
grep -r "AIza\|sk-\|NCMEC_API_KEY\|STRIPE_SECRET" \
  --include="*.swift" --include="*.ts" \
  AMENAPP/ Backend/
```

Any hit is a P0 blocker. Rotate the secret via Cloud Secret Manager, invalidate the old key, and re-run the scan before proceeding.

---

### Production Deploy Runbook

**Region rule (CRITICAL — us-central1 at 999/1000):**

- All new Cloud Functions MUST deploy to `us-east1`
- Every deploy must add a row to `docs/FUNCTION_INVENTORY.md` Interim Region Table
- Silent region choices are forbidden (per CLAUDE.md)
- Creating a new us-central1 function will fail with HTTP 429

**Pending CF deploys from this audit:**

| Function | Codebase | Target region | Why needed |
|----------|----------|---------------|------------|
| deleteUserAccount | default | us-east1 | P0-3: Guideline 5.1.1 hard-delete |
| submitNCMECCyberTip | default | us-east1 | P0-2: CSAM CyberTip (LEGAL GATE) |

**Deploy command pattern (run from repo root only):**

```sh
firebase deploy --only functions:default:FUNCTION_NAME
```

See `docs/deploy-topology.md` for full topology, codebase map, and KnownDrift list.

---

### Decisions Required — RED Lane Summary

All RED-lane items require a human decision before any engineering work begins. Decisions can be made async; tag the engineering lead when ready to unblock.

| ID | Priority | Title | Decision needed | Est. eng time post-decision |
|----|----------|-------|-----------------|------------------------------|
| P0-5 / R-P12-01 | P0 | Restore Purchases placement on 5 paywall screens | UX pattern choice (Option A or B) | 2 hrs |
| P0-6 / R-P12-02 | P0 | Stripe IAP classification — internal vs external service | Legal + product (Option A, B, or C) | 8–40 hrs depending on option |
| P0-2 / P5-Y2 | P0 | NCMEC CyberTip wiring | Legal written sign-off | 2 hrs post-legal |
| P1-5 / R-P3-01 | P1 | VoicePrayer hard-delete vs soft-delete policy | Product decision | 0–6 hrs |
| P2-1 / R-P3-02 | P2 | CovenantRoom delete: confirmation alert vs undo toast | UX pattern choice | 0.5 hrs |

---

## Item Count Summary

| Severity | Item count | Blocks App Store submission |
|----------|------------|----------------------------|
| P0 | 6 | Yes — all 6 must be resolved |
| P1 | 5 | No — but must be resolved before beta |
| P2 | 3 | No |
| P3 | 1 (group) | No |
| **Total** | **47 source items** | |

**App Store submission verdict: NO-GO until all 6 P0 items are resolved.**

The two legal gates (P0-2 NCMEC, P0-6 Stripe IAP) are on the critical path and cannot be parallelized with engineering — the engineering path depends on the legal decision. Start legal review today.

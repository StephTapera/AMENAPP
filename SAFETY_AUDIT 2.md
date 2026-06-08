# AMEN Safety Audit
**Date:** 2026-06-02  
**Branch:** safety-hardening (fixes to follow after this report is reviewed)  
**Auditor:** Claude Code  
**Scope:** Firestore/Storage rules, all Cloud Functions, iOS auth + DM + moderation flows, secrets management, abuse vectors  

---

## Executive Summary

AMEN has a **maturing safety architecture** — multi-tier age gating, three-layer message scanning, fail-closed moderation, and proper secrets management are all present. However, **nine issues rated Critical or High** must be fixed before any minor users are admitted to the app. The most severe: CSAM detection exists in code but the mandatory NCMEC reporting pipeline is never called; Stripe webhook events are accepted without signature verification; and large content surfaces (Sanctuaries, prayer requests, DMs) are auto-moderated only if the client explicitly calls a callable — a server-side trigger does not enforce it.

---

## Findings

### CRITICAL

---

#### C-01 — No Automated NCMEC CyberTipline Reporting
**Files:** `AMENAPP/SexualContentPolicy.swift`, `AMENAPP/MinorSafetyService.swift`, `functions/moderatePost.js`, `functions/imageModeration.js`  
**Why it's a risk:**  
US law (18 U.S.C. § 2258A) requires electronic service providers to report apparent CSAM to NCMEC. The code defines `requiresMandatoryReport`, `emergencyFreezeAndReport`, `reportToNCMEC` enum cases, and the moderator console surfaces a "Report to NCMEC" action — but **no Cloud Function or background task actually submits a CyberTipline report**. Automated detection can flag CSAM; the reporting step is missing. Moderators must manually remember to file; that is not reliable.  
**Fix:**  
1. Create `functions/ncmecReporter.js` — a callable/scheduled function that POSTs to the NCMEC CyberTipline API (or, if the API is not yet provisioned, emails the mandatory-reporting address and creates a `ncmecPendingReports` Firestore document).  
2. Call it automatically whenever `mediaModerationPipeline.js` confirms a CSAM hash match or when a tier-1 user report is accepted.  
3. Add a `ncmecReports` collection for tamper-evident evidence preservation with legal hold semantics (deny all client writes, deny all client reads, deny admin deletes).  
4. Add an open-question item in `SAFETY_RUNBOOK.md` for legal counsel to confirm jurisdiction and API credentials.

---

#### C-02 — Stripe Webhook Handler Absent / No Signature Verification
**Files:** `functions/covenantFunctions.js` (references a webhook handler in comments), `functions/stripeFunctions.js` (no handler found)  
**Why it's a risk:**  
Stripe sends events for payment completion, subscription changes, and Connect payouts. Without a handler that calls `stripe.webhooks.constructEvent(rawBody, sig, secret)`, any attacker can POST a forged `payment_intent.succeeded` event and trigger entitlement grants or payout releases. This is a standard Stripe security requirement.  
**Fix:**  
Create an `onRequest` function that reads the raw body, verifies the `stripe-signature` header using `defineSecret("STRIPE_WEBHOOK_SECRET")`, and dispatches to the correct business logic. Never re-parse the body as JSON before verification — use the raw buffer.

---

#### C-03 — Server-Side Auto-Moderation Does Not Cover Sanctuaries, Prayer Requests, or DMs
**Files:** `functions/moderatePost.js` (document path: `posts/{postId}` only), `functions/contentModeration.js`  
**Why it's a risk:**  
The Firestore trigger in `moderatePost.js` only fires on `posts/{postId}` creation. Sanctuary group messages, prayer request text, DM content, and replies are moderated **only if the iOS client explicitly calls the `moderateContent()` callable**. A jailbroken app or a client bug can skip this call entirely. Content in those collections publishes un-reviewed.  
**Fix:**  
Add `onDocumentCreated` triggers for:  
- `sanctuaries/{sid}/messages/{mid}`  
- `prayers/{pid}`  
- `conversations/{cid}/messages/{mid}` (DMs — route through existing `safeMessageGateway` or NeMo Guard)  
- `replies/{rid}` / `posts/{pid}/replies/{rid}` (whichever path is in use)  

Each trigger should call the same NeMo Guard + fail-closed pipeline already used for posts.

---

#### C-04 — Appeals Mechanism Announced But Not Implemented
**Files:** `functions/contentModeration.js` (returns `appealable: true`), no `appeals` collection exists  
**Why it's a risk:**  
The moderation decision object tells clients content is appealable and the iOS UI surfaces this. But there is no `submitAppeal` callable, no `appeals` Firestore collection, and no admin review path. Users whose content is incorrectly removed have no recourse. This violates App Store guidelines and creates legal exposure in jurisdictions with content-hosting liability reform.  
**Fix:**  
1. Create `functions/appeals.js` with a `submitAppeal(contentId, reason, evidence)` callable (auth required, rate-limited to 3 appeals per user per 24 hours).  
2. Create `appeals/{appealId}` collection (client create only, client cannot update status).  
3. Add an admin `reviewAppeal(appealId, decision)` callable.  
4. Send user a notification on resolution.

---

### HIGH

---

#### H-01 — Testimony `isPublic` Defaults to PUBLIC
**File:** `AMENAPP/firestore 18.rules` line ~1275  
**Why it's a risk:**  
```
allow read: if isAuthenticated()
  && (resource.data.authorId == request.auth.uid
      || resource.data.get('isPublic', true) == true);  // ← default TRUE
```
Prayer requests correctly default to `false`. Testimonies, which contain personal spiritual narratives about addiction, trauma, and abuse, default to **world-readable by all authenticated users** if the client omits the field. One client-side bug or API misuse exposes sensitive content.  
**Fix:** Change the default to `false`.

---

#### H-02 — No Persistent Moderator Audit Trail
**Files:** `functions/moderatePost.js` lines 170, 194 (console.log only)  
**Why it's a risk:**  
`adminReviewPost()` logs to stdout (`console.log("✅ Admin ${uid} approved post...")`). Cloud Functions stdout is ephemeral and not queryable. There is no Firestore `moderation_audit_log` collection recording who reviewed what and when. CSAM escalation cases require legally defensible audit logs. If a report is ever filed with authorities, there is no proof of when the content was removed or by whom.  
**Fix:**  
After every admin action (approve, reject, escalate), write to `moderation_audit_log/{entryId}`:  
```
{ adminId, action, contentRef, decision, timestamp, categories, notesLength }
```  
Deny all client reads and writes in Firestore rules. Expose a paginated callable for admin dashboard queries only.

---

#### H-03 — Ban Evasion via Phone Re-Registration
**Files:** `functions/phoneAuthRateLimit.js`, `AMENAPP/AgeAssuranceService.swift`  
**Why it's a risk:**  
A banned user can create a new Firebase Auth account with the same phone number (Firebase Auth allows this after deletion). The `isBanned` / `accountStatus` check in `safeMessagingGateway.js` is on the user document, which is new and clean. There is no cross-check of the phone number against a `bannedPhones` list.  
**Fix:**  
1. On user ban, write the normalized E.164 phone number to `bannedPhones/{hash}` (hash with SHA-256 to avoid storing PII in plaintext).  
2. In the `createUser` / phone-linkage flow, check `bannedPhones` before allowing account completion.  
3. For repeat CSAM or child safety violations, add a `permanentBanPhones` sub-collection with a higher evidence threshold to remove from it.

---

#### H-04 — Missing Rate Limits on Post Creation, Invites, and Account Creation
**Files:** `functions/rateLimiter.js` (exists but not applied to all surfaces)  
**Why it's a risk:**  
`rateLimiter.js` has a working rolling-window implementation, but grep finds no explicit limit applied to post creation (only Firestore auth rules), sanctuary invites, or account creation beyond phone OTP (3 per 15 min per phone, 10 per IP per 15 min). A single actor with multiple phone numbers can spam the public feed.  
**Fix:**  
Apply `checkRateLimit(uid, "post_create", 20, 3600)` (20 posts/hour) and `checkRateLimit(uid, "invite_send", 30, 86400)` (30 invites/day) at the top of the relevant callables or triggers.

---

#### H-05 — Adult→Minor DM Consent Path is Dead Code
**Files:** `AMENAPP/MinorSafetyService.swift` lines ~240–248  
**Why it's a risk:**  
```swift
if recipient.ageVerificationStatus == .parentalConsent && hasMutualFollow {
    return MinorSafetyPolicy(canSendDM: true, ...)
}
```
The `.parentalConsent` status has no UI, no enrollment, and no verification backend. It is dead code. If it is ever reachable (e.g., via a data migration bug or future code change), an adult can DM a minor after a simple mutual-follow — with no parent having actually consented.  
**Fix:**  
Remove the dead-code bypass entirely. If parental consent DMs are ever a real product feature, implement it from scratch with actual parent verification before allowing any cross-age DMs.

---

#### H-06 — Minors Can Message Adults (Minor→Adult Not Blocked)
**Files:** `AMENAPP/MinorSafetyService.swift`  
**Why it's a risk:**  
The policy hard-blocks adult→minor DMs but does not explicitly block minor→adult unsolicited DMs. A minor can initiate a conversation with any adult. Groomers can create accounts that appear adult (age is not independently verified beyond declared birthdate) and wait for minors to message them.  
**Fix:**  
For tier B/C users (13–17), require that the adult recipient has `followsMinor == true` (mutual follow) before allowing the DM. Absent that, block the DM and surface the report button.

---

### MEDIUM

---

#### M-01 — No Retry / Backoff in Moderation Functions
**Files:** `functions/moderatePost.js`, `functions/imageModeration.js`, `functions/contentModeration.js`, `functions/aiModeration.js`  
**Why it's a risk:**  
All moderation functions have a single try/catch with no internal retry. Firebase Cloud Firestore triggers do retry on function-level failure, but API-level errors (HTTP 429, 503) are caught by the try/catch and treated as final, not retried. A brief NVIDIA NIM or Vision API outage floods the moderation queue with false "pending" items.  
**Fix:**  
Add a `withRetry(fn, maxAttempts=3, baseDelayMs=500)` helper using exponential backoff with jitter. Apply it to each external API call.

---

#### M-02 — Age Downgrade Path Unguarded
**File:** `AMENAPP/AgeAssuranceService.swift` `requestAgeChange()` function  
**Why it's a risk:**  
The function requires verification only when a user is trying to upgrade from teen→adult. An adult can declare as a minor with no verification, gaining access to minor-specific trust flows while knowing they are an adult.  
**Fix:**  
Block adult→teen age changes client-side and server-side. If a user genuinely needs a correction, require moderator review with government ID.

---

#### M-03 — Sensitive Content Level Not Auto-Restricted for Minors
**File:** `AMENAPP/PrivacySettingsView.swift` (sensitiveContentLevel defaults to "standard")  
**Why it's a risk:**  
Adult users can post content flagged as "sensitive." Minors see it at the "standard" filter level, which may allow borderline content through.  
**Fix:**  
On account creation and on each session for tier B/C users, enforce `sensitiveContentLevel = "restricted"` server-side. Do not allow the user to change it if `ageTier != "tierD"`.

---

#### M-04 — Parental Consent Config Disabled But Architecture Exists
**File:** `AMENAPP/AgeAssuranceModels.swift` line ~246: `requireParentalConsentUnder16 = false`  
**Why it's a risk:**  
The data model has `parentalSupervisionEnabled` and `parentUserId` fields. The config hardcodes consent to `false`. If this is ever flipped without building the actual enrollment flow, minors under 16 will be missing the oversight the architecture promises.  
**Fix (open question):** Decide whether to build parental supervision or remove the dead architecture. If building it, the minimum viable flow is: minor enters parent email at signup → parent receives verification email → parent approves from a dedicated web URL → server sets `parentalSupervisionEnabled = true`. Add to `SAFETY_RUNBOOK.md` as an open question pending legal review.

---

#### M-05 — No TTL on `moderationQueue`, `fcmQueue`, or `temp/` Storage
**Files:** `functions/moderatePost.js`, `AMENAPP/firestore 18.rules` lines ~1402, `AMENAPP/storage.rules` lines ~185  
**Why it's a risk:**  
Queue collections and temp uploads accumulate indefinitely. At scale, this inflates Firestore read costs and makes moderation queue searches slower.  
**Fix:**  
Add an `expireAt` timestamp field (now + 30 days for resolved queue items, now + 7 days for temp uploads). Enable Firestore TTL on `expireAt` in the Firebase Console.

---

#### M-06 — No SLA / Escalation for Aged Moderation Queue Items
**Files:** `functions/moderatePost.js`  
**Why it's a risk:**  
Posts flagged as "pending" can sit in the queue indefinitely. CSAM or child-safety items that auto-moderation couldn't classify must be reviewed by a human — but there is no escalation timer to ensure it happens.  
**Fix:**  
Add a scheduled function (`functions/moderationSweep.js`, runs every 4 hours) that queries `moderationQueue` for items where `status == "pending"` and `createdAt < now - 24h`. It should alert the admin team (email/Slack) and, for tier-1 categories, auto-escalate to a `criticalReviewQueue`.

---

### LOW

---

#### L-01 — Username Enumeration by Authenticated Users
**Files:** `AMENAPP/firestore 18.rules` line ~165  
**Why it's a risk:**  
Unauthenticated enumeration is correctly blocked. However, any authenticated user can query `usernameLookup` with sorted/paginated queries, effectively enumerating all usernames. This leaks the user graph to scraping attacks.  
**Fix:**  
Restrict `usernameLookup` list queries to exact-match only (reject queries without a `where` clause on the username field). Allow only single-document reads by exact username.

---

#### L-02 — Admin Custom Claim Has No Audit Trail or Expiry
**Files:** `functions/adminClaims.js`  
**Why it's a risk:**  
Custom claims are set via `auth.setCustomUserClaims()` but there is no Firestore record of when a claim was granted, by whom, or an expiry policy. A compromised admin account with a stale claim remains admin indefinitely.  
**Fix:**  
Log every claim grant/revoke to `adminClaimLog/{entryId}`. Add an `adminClaimExpiry` field (now + 90 days). A scheduled function should warn the operator 7 days before expiry and revoke automatically at expiry.

---

#### L-03 — Testimony `isPublic` Mismatch Is Also a Client-Trust Issue
**File:** same as H-01  
Already covered under H-01. Tracking separately because it also requires a client-side default check in the iOS composer to prevent the null field from being submitted.

---

## Open Questions (Human Decision Required)

| # | Question | Who decides |
|---|----------|-------------|
| OQ-1 | NCMEC CyberTipline API credentials — has Amen applied for access? | Legal / ops |
| OQ-2 | Is parental supervision a launch requirement, or can minors 13–15 use the app without it pending a future release? | Product / legal |
| OQ-3 | What is the SLA commitment for human review of moderation queue items? | Ops |
| OQ-4 | Which law enforcement agencies should receive escalation for non-CSAM threats (e.g., credible violence)? | Legal |
| OQ-5 | COPPA: Does Amen intend to admit users under 13 ever? If not, add an explicit age-block server-side, not just client-side. | Product / legal |
| OQ-6 | Does Amen need to register as a "covered platform" under KOSA or similar state laws? | Legal |
| OQ-7 | Does `GoogleService-Info.plist` contain any keys that should be restricted (e.g., API key HTTP restrictions)? | Infra |

---

## Items That Are Well-Implemented (Do Not Break)

- **Fail-closed moderation** — all four moderation functions (NeMo Guard, Vision, NLU, Gemini) fail to "pending", not "approved"  
- **`visible` / `moderation.status` cannot be written by clients** — confirmed in Firestore rules and post update allowedKeys list  
- **Age-tier DM gating** — tier A/B users hard-blocked from DMs in both Firestore rules and `MinorSafetyService`  
- **Layer 0 hard signals** — CSAM / grooming / trafficking regexes always block, pre-NLU-scoring  
- **App Check enforcement** — 249+ callable functions require App Check; `AppDelegate` configures it before `FirebaseApp.configure()`  
- **Phone auth rate limiting** — 3 OTPs per phone per 15 min; IP-based limit at 10 per 15 min  
- **No hardcoded secrets** — NVIDIA key, Stripe keys, CSAM lookup token all use `defineSecret()`  
- **Evidence preservation on freeze** — frozen accounts cannot delete messages; Firestore rules enforce `canDeleteMessages: false`  
- **Crisis resource links** — 988, NCMEC, StopItNow surfaced in `VictimShieldControlsView`  

---

## Proposed Fix Order

**Wave 1 — Critical (before any minors onboard):**  
C-01 NCMEC reporting pipeline → C-02 Stripe webhook → C-03 server-side triggers for Sanctuaries/prayers/DMs → C-04 Appeals backend  

**Wave 2 — High:**  
H-01 Testimony privacy default → H-02 Moderator audit log → H-03 Ban evasion / phone blacklist → H-04 Rate limits → H-05 Remove dead adult→minor consent bypass → H-06 Block minor→adult unsolicited DMs  

**Wave 3 — Medium:**  
M-01 Retry backoff → M-02 Age downgrade guard → M-03 Sensitive content restriction for minors → M-05 TTL policies → M-06 Moderation SLA sweep  

**Wave 4 — Low:**  
L-01 Username enumeration → L-02 Admin claim audit + expiry  

---

*This document is the pre-fix audit. No code has been changed. Fixes will be committed on branch `safety-hardening` after this report is reviewed.*

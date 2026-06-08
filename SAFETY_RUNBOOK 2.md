# AMEN Safety Runbook
**Branch:** safety-hardening  
**Date:** 2026-06-02  
**Owner:** Engineering + Trust & Safety team  

This runbook describes how moderation, escalation, and CSAM reporting work end-to-end after the `safety-hardening` fixes are deployed. It also lists every open question that requires a human (legal, product, or ops) decision before Amen admits minor users to the platform.

---

## 1. Content Moderation Flow

### 1a. New post / Sanctuary message / prayer request / DM created

```
User submits content
       │
       ▼
Firestore trigger fires (moderatePost / moderateSanctuaryMessage /
moderatePrayerRequest / moderateDMMessage)
       │
       ▼
NeMo Guard (NVIDIA NIM) called with withRetry(3, 500ms + jitter)
       │
       ├─ Response: SAFE     → visible: true, moderation.status: "approved"
       │
       ├─ Response: UNSAFE   → visible: false, removed: true,
       │                        moderation.status: "blocked",
       │                        written to moderationQueue (expireAt +90d)
       │
       └─ API error / timeout → FAIL CLOSED: visible: false,
                                 moderation.status: "pending",
                                 written to moderationQueue (expireAt +90d)
```

### 1b. Image / video upload

```
Storage object finalized
       │
       ▼
moderateUploadedImage trigger
       │
       ├─ CSAM hash check (PhotoDNA/PDQ) with withRetry
       │       └─ MATCH → fileNCMECReport() called immediately
       │                   file deleted, post hidden, ncmecSubmissionQueue written
       │
       ├─ Cloud Vision SafeSearch with withRetry
       │       └─ adult≥3 or racy≥3 or violence≥4 → BLOCK (delete + hide)
       │       └─ borderline scores → REVIEW (hide, queue for admin)
       │
       └─ NVIDIA Vision LLM with withRetry (faith context override)
               └─ Can promote REVIEW→APPROVED or APPROVED→BLOCKED
```

---

## 2. Moderation Queue

Collection: `moderationQueue/{id}`  
Fields: `postRef | contentRef`, `contentType`, `authorId`, `preview (280 chars)`, `status`, `categories`, `createdAt`, `expireAt (+90d)`, `resolvedBy?`, `resolvedAt?`

**Admin actions (via `adminReviewPost` callable):**  
- `decision: "approved"` → sets `visible: true`, strips blocked media URLs, marks queue item `resolved`, writes `moderationAuditLog` entry  
- `decision: "rejected"` → sets `visible: false, removed: true`, marks queue item `rejected`, writes `moderationAuditLog` entry  

**SLA sweep** (`moderationSweep` — runs every 4 hours):  
- Items pending > 24h → writes `moderatorAlerts` "pending_review_aged"  
- Items with categories `csam | grooming | trafficking | child_safety | minor_safety` pending > 2h → escalated to `criticalReviewQueue` + "critical" alert  

---

## 3. CSAM Escalation Pipeline

This pipeline is **non-negotiable** under 18 U.S.C. § 2258A (PROTECT Our Children Act).

### Detection paths that trigger `fileNCMECReport()`:

| Source | Trigger |
|--------|---------|
| `imageModeration.js` | CSAM hash match confirmed |
| `moderatePrayerRequest` | NeMo Guard returns category `csam` or `child_safety` |
| `moderateDMMessage` | NeMo Guard returns `csam` or `grooming` category |
| User report (tier-1) | `commentModerationEnforcement` — `escalationTier === 1` |

### What `fileNCMECReport()` does:

1. Writes `ncmecReports/{reportId}` — tamper-evident, `legalHold: true`. **Never delete these documents.**
2. Writes `ncmecSubmissionQueue/{entryId}` — triggers `onCSAMDetected`.
3. `onCSAMDetected` trigger:
   - Sends FCM push to all `users.isAdmin == true` accounts (title: "CSAM Report Queued")
   - Writes `moderatorAlerts/{id}` with `urgency: "critical"`

### What the on-call admin must do (within 1 hour of alert):

1. Open Admin Center → Critical Review Queue
2. Review the flagged content (do NOT view CSAM directly — use hash/metadata only)
3. Confirm or dismiss. If confirmed:
   - Click "Submit NCMEC Report" (this currently queues it in `ncmecSubmissionQueue` — see Open Question OQ-1 for actual API wiring)
   - Update `ncmecReports/{reportId}.status = "submitted"` and record the NCMEC report ID
4. The user account is automatically frozen (evidence preservation active — they cannot delete messages)
5. If content involves a specific victim, contact NCMEC hotline directly: 1-800-843-5678

### Evidence Preservation

When a CSAM report is filed:
- The flagged Storage object is **deleted immediately** (no visible URL)
- The Firestore content document is preserved with `removed: true, legalHold: true`
- The user cannot delete their messages while `evidencePreservationActive: true` (enforced in Firestore rules)
- The `ncmecReports` collection has `allow write: if false` (no client or admin writes after creation)

---

## 4. Appeals Flow

Collection: `appeals/{appealId}`  
Fields: `contentId`, `contentType`, `contentRef`, `authorId`, `reason (≤500)`, `evidence (≤1000)`, `status: pending|approved|rejected`, `createdAt`, `reviewedAt?`, `reviewedBy?`, `adminNotes?`

**User submits:** `submitAppeal` callable  
- Rate limited: 3 appeals per user per 24 hours  
- Content must be currently removed  
- Caller must be the author  

**Admin reviews:** `reviewAppeal` callable  
- Approved: content visibility restored (`visible: true`)  
- Rejected: content stays removed  
- Both outcomes write a `moderationAuditLog` entry  

**SLA (recommended):** Appeal decisions within 5 business days per App Store guidelines.

---

## 5. Moderator Audit Log

Collection: `moderationAuditLog/{id}`  
Fields: `adminId`, `action`, `postId | contentId | appealId`, `decision`, `categories`, `reviewedAt`, `contentType`, `source`  

**Cannot be modified or deleted by any client or admin via the SDK** (Firestore rules: deny all client writes).  
Queryable by admin via `reviewAppeal` callback or custom dashboard query.  

Actions recorded: `review_post` (approve/reject), `review_appeal` (approve/reject).

---

## 6. Ban Evasion Prevention

When an admin bans a user:
1. Call `banUserPhone({ userId })` callable — this reads the user's E.164 phone from Firebase Auth, SHA-256 hashes it, and writes to `bannedPhones/{hash}`.
2. On new account creation, `onUserDocCreated` checks `bannedPhones` before allowing the document to persist.
3. If the phone is banned: Firebase Auth account is disabled and the Firestore user document is deleted.

**TODO (wiring):** The `accountSuspension.js` auto-ban flow should call `banUserPhone` automatically on permanent bans. Currently it must be called manually from the Admin Center.

---

## 7. Stripe Webhook Security

Webhook endpoint: `stripeWebhook` (deployed as an HTTP function)  
Verification: `stripe.webhooks.constructEvent(req.rawBody, sig, STRIPE_WEBHOOK_SECRET)` — any failure returns HTTP 400, no processing occurs.

**Setup steps (one-time):**
1. `firebase functions:secrets:set STRIPE_WEBHOOK_SECRET`
2. `firebase deploy --only functions:stripeWebhook`
3. Register the deployed URL in Stripe Dashboard → Developers → Webhooks
4. Select events: `payment_intent.succeeded`, `customer.subscription.updated`, `customer.subscription.deleted`, `account.updated`

---

## 8. Deploy Checklist

Run these commands after merging `safety-hardening`:

```bash
# 1. Deploy all new/modified functions
firebase deploy --only \
  functions:onCSAMDetected,\
  functions:stripeWebhook,\
  functions:moderateSanctuaryMessage,\
  functions:moderatePrayerRequest,\
  functions:moderateDMMessage,\
  functions:submitAppeal,\
  functions:reviewAppeal,\
  functions:adminReviewPost,\
  functions:moderatePost,\
  functions:moderateUploadedImage,\
  functions:banUserPhone,\
  functions:updateBirthYear,\
  functions:moderationSweep \
  --project amen-5e359

# 2. Deploy updated Firestore rules
firebase deploy --only firestore:rules --project amen-5e359

# 3. Set secrets if not already set
firebase functions:secrets:set STRIPE_WEBHOOK_SECRET --project amen-5e359

# 4. Register Stripe webhook URL (manual step — Stripe Dashboard)

# 5. Enable Firestore TTL on moderationQueue.expireAt (Firebase Console → Firestore → Indexes → TTL)

# 6. Enable Firestore TTL on ncmecSubmissionQueue (never expires — leave unset)
```

---

## 9. Open Questions (Require Human Decision Before Minor Users Are Admitted)

| # | Question | Owner | Urgency |
|---|----------|-------|---------|
| OQ-1 | **NCMEC CyberTipline API** — Has Amen applied for an Electronic Service Provider agreement with NCMEC? Until credentials are issued, reports are queued for manual submission. | Legal + Ops | CRITICAL — must be resolved before launch |
| OQ-2 | **Parental supervision** — Is the `parentalSupervisionEnabled` architecture a launch requirement for users 13–15, or is it deferred? Currently the feature is dead code. Either build it or remove it. | Product + Legal | HIGH |
| OQ-3 | **COPPA posture** — Does Amen intend to admit users under 13 ever? If not, add a server-side age block (not just client-side) and document this clearly in the Privacy Policy. | Legal | HIGH |
| OQ-4 | **Moderation SLA** — What is the committed SLA for human review of pending queue items? The sweep function alerts at 24h but the threshold is configurable. | Ops | HIGH |
| OQ-5 | **Law enforcement escalation beyond NCMEC** — Which authority should receive escalation for non-CSAM threats (credible violence, trafficking)? FBI IC3? Local PD? Document the decision tree. | Legal | MEDIUM |
| OQ-6 | **KOSA / state law registration** — Does Amen need to register as a "covered platform" under the Kids Online Safety Act or any state minor-protection law? | Legal | MEDIUM |
| OQ-7 | **Google API key restrictions** — Is the API key in `GoogleService-Info.plist` restricted to the Amen bundle ID in the Firebase Console? Unrestricted keys can be abused from other apps. | Infra | MEDIUM |
| OQ-8 | **Stripe webhook URL registration** — The `stripeWebhook` function must be registered manually in the Stripe Dashboard after deploy. Has this been done? | Eng | HIGH — deploy blocker |

---

## 10. What Was NOT Changed (Controls to Preserve)

- Fail-closed behavior on all four moderation systems (NeMo Guard, Vision, NLU, Gemini)
- `visible` / `moderation.status` client-write protection in Firestore rules
- Age-tier DM gating (tier A/B hard-blocked from DMs in rules + MinorSafetyService)
- Layer 0 hard regex signals (CSAM/grooming/trafficking always block pre-NLU)
- App Check enforcement on all callables
- Phone auth OTP rate limiting (3/phone/15min, 10/IP/15min)
- `defineSecret` usage — no hardcoded keys anywhere
- Evidence preservation on frozen accounts (Firestore rules enforce `canDeleteMessages: false`)

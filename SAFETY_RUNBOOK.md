# SAFETY RUNBOOK — Amen App

> WARNING: NCMEC CyberTipline reporting is NOT yet wired. See Section 7 before handling any child exploitation report.

**Version:** 2026-06-11
**Branch:** safety-hardening
**Status:** DRAFT — requires Legal, Trust & Safety Lead, and Engineering sign-off before launch
**Owner:** T&S Lead (role currently unassigned — see Section 16)

---

## 1. Amen Safety Principles

The following principles are non-negotiable and override product, performance, or UX considerations.

**Fail-closed.** When any safety service is unavailable, content defaults to `pending` — never to `approved`. Silent `try?` failures in `AmenChildSafetyService`, `AmenModerationService`, and `AntiHarassmentEngine` must be replaced with explicit error paths that land the item in the dead-letter queue. No content may be silently dropped or silently approved.

**Server-authoritative.** No trust decision — age tier, role, ban status, guardian approval, entitlement — may originate from the client. The client creates a request; the server makes every decision. Client-supplied fields in Firestore writes are treated as untrusted input and must be validated or overwritten by Cloud Functions before taking effect.

**Minor-first.** In any ambiguous case involving a user whose age is unknown, the system treats that user as a minor until verified otherwise. The I-8 invariant (`ageTier` cannot be downgraded from a minor tier to an adult tier without an age re-verification event) must hold at every write path. No Cloud Function may trust the client-supplied `ageTier` field.

**No client trust.** The iOS app is not a trusted principal. App Check reduces abuse surface but does not grant the client elevated trust. Firestore security rules and Cloud Function authorization checks must hold independently of whether App Check tokens are present.

**Moderation-first.** All user-generated content passes through the moderation pipeline before becoming visible to other users. The content states defined in Section 2 are the only permitted states. Content that skips moderation because of a CF timeout, quota exhaustion, or missing trigger is a P0 incident.

**Audit-ready.** Every moderation decision — approve, block, escalate, remove, appeal outcome — must produce an immutable record in `moderationAuditLog`. No moderation action is valid unless logged. Legal hold creation is irrevocable and must log the creating principal.

---

## 2. Content Moderation Lifecycle

### States

```
draft (client-side only, never written to Firestore)
  |
  v
pending (server-side initial state; visible only to author)
  |
  +-- automated ML safe    --> approved  (visible to eligible audience)
  |
  +-- automated ML unsafe  --> blocked   (visible only to author with "under review" copy)
  |
  +-- CSAM signal          --> escalated --> (Section 7 protocol)
  |
  +-- manual moderator     --> removed   (visible only to author with removal reason)
  |
  +-- user appeal          --> appealed  --> safety re-check --> approved | removed
```

### Permitted transitions

| From | To | Who may trigger |
|---|---|---|
| (new write) | pending | Client (only state a client may create) |
| pending | approved | Automated CF (ml safe) or moderator role |
| pending | blocked | Automated CF (ml unsafe) |
| pending | escalated | Automated CF (CSAM signal) or safetyLead |
| pending/approved/blocked | removed | moderator, safetyLead, admin |
| blocked | appealed | Author only, via `submitAppeal` CF |
| removed | appealed | Author only, via `submitAppeal` CF |
| appealed | approved | `decideAppeal` CF after passing safety re-check |
| appealed | removed | `decideAppeal` CF or legalReviewer |
| any | escalated | safetyLead or legalReviewer only |

**Invariants:**
- A client write may only produce `pending` state. Any other initial state must be rejected by Firestore rules.
- `escalated` content must not be moved to any non-`escalated` state without a `legalReviewer` sign-off logged in `moderationAuditLog`.
- `removed` content metadata is retained per Section 15 (the document is soft-deleted; media is quarantined, not deleted, until legal hold check passes).

---

## 3. Moderator Operations

### Reading the moderation queue

The `moderationQueue` collection is write-restricted to the Admin SDK only (`allow create: if isAdminSDK()`). Moderators access content via the internal admin web UI or Firebase Console with an account that holds the `moderator` custom claim.

**Step-by-step: process a pending item**

1. Navigate to Firebase Console > Firestore > `moderationQueue`. Filter `status == "pending"`.
2. Select an item. Record the `postId` / `messageId` / `commentId` and `contentType`.
3. Review the content and any automated scoring fields (`mlScore`, `flaggedCategories`).
4. Choose an action:
   - **Approve:** Call `approveModerationItem({queueId})` via the Admin callable or set `status: "approved"` via Admin SDK. The CF writes through to the content document and logs to `moderationAuditLog`.
   - **Remove:** Call `removeContent({queueId, reason})`. Supply a `reason` string from the canonical list (see below). The CF sets `visible: false`, writes the removal reason, and logs.
   - **Escalate to Safety Lead:** Call `escalateToSafetyLead({queueId, notes})`. The item moves to `escalated` state and sends a PagerDuty/Slack alert (configure via `SAFETY_ALERT_WEBHOOK` secret).
5. Do not directly edit Firestore documents for moderation decisions. All transitions must go through CFs to ensure `moderationAuditLog` is written.

**Canonical removal reasons:**
- `hate_speech`
- `harassment`
- `sexual_content`
- `violence`
- `csam` (immediately triggers Section 7 protocol)
- `spam`
- `misinformation`
- `self_harm`
- `other` (requires free-text notes field)

### Dead-letter queue

Items that fail automated processing land in `moderationDeadLetter`. These must be reviewed manually within 24 hours. Check `moderationDeadLetter` as part of every moderator shift start.

**Open question (OQ-20):** Is there a Firestore TTL policy actually enabled on `moderationQueue.expireAt` and `moderationDeadLetter` in the Firebase Console? The code sets `expireAt` fields but the TTL policy must be manually enabled in the Firebase Console under Firestore > Indexes > TTL. Confirm before launch.

---

## 4. Minor Protection Model

### Age tier definitions

| Tier | Age range | Label in code |
|---|---|---|
| Tier A | Under 13 | `under13` |
| Tier B | 13-15 | `13_15` |
| Tier C | 16-17 | `16_17` |
| Tier D | 18+ | `adult` |

`ageTier` is written to the `/users/{uid}` document by the age verification Cloud Function only. No client write to `ageTier` is permitted (Firestore rule: `allow update: if false` for that field from clients). Note: Firebase Console and Admin SDK bypass Firestore rules — see Section 16, OQ-27.

### I-8 Invariant

`ageTier` may never be downgraded from a minor tier (A, B, C) to adult tier (D) without a confirmed age re-verification event. This invariant is enforced in the CF but not in Firestore rules (enforcement is only possible server-side). Any CF that touches `ageTier` must check for downgrade and reject or log an anomaly.

### Discovery restrictions

- Tier A users must not appear in any search index. The `shouldExcludeFromPeopleIndex()` function must be called on every Algolia sync path — bulk and incremental. See OQ-24 regarding whether incremental sync paths all call this function.
- Tier B and C users do not appear in the public "People" search by default. They may appear in church/space member lists only to members of that same church/space.
- No user's `ageTier` field is visible to other users in any API response.

### DM rules

- Tier A users cannot initiate or receive DMs from any user outside their guardian-approved contact list.
- Tier B users cannot receive DMs from adult (Tier D) accounts they have not explicitly followed or accepted a connection from.
- Tier C users follow the same rules as Tier B with a relaxed threshold for church-context contacts (space members in a shared church space may DM, subject to the adult-minor detection signals in Section 5).
- `isGuardianApprovedContact()` in `AmenChildSafetyService.swift` currently returns `true` when the guardian approval document does not exist. This is a confirmed bug (OPEN-2). Until fixed, the guardian-approval DM gate is non-functional. Do not represent guardian-gated DMs as a live safety control in any external communication until OPEN-2 is resolved.

### Sanctuary rules

Content posted by Tier A users is visible only to:
- The user themselves
- Their guardian-approved contacts
- Moderators and safetyLeads

Content posted by Tier B/C users follows the standard moderation pipeline but is additionally age-gated: it will not appear in any feed delivered to Tier D users unless the Tier D user is a verified church leader in a shared space.

---

## 5. Adult-Minor Interaction Detection

### Signal list

The following signals trigger an elevated review flag on any adult-minor interaction:

1. An adult (Tier D) user sends a DM to a minor within 24 hours of first contact (account age signal)
2. Message contains terms from the grooming lexicon (maintained in `groomingKeywords` Firestore document — access restricted to safetyLead+)
3. Adult user has sent DMs to 3 or more distinct minors within any 7-day window
4. Minor reports a conversation
5. Sentiment score on a DM thread between an adult and a minor drops below the threshold defined in `HARASSMENT_SENTIMENT_THRESHOLD` secret
6. An adult requests a minor's phone number, address, or location in a message
7. A conversation transitions from a shared space context to a private DM context within 1 hour

### Automated response

When any signal fires:
1. The conversation is flagged in `moderationQueue` with `contentType: "dm_conversation"` and `triggerSignal: <signal_id>`.
2. The adult user's DM capability to that minor is suspended pending review (not a global ban — scoped to that conversation).
3. The minor receives no notification that a review has been triggered (reporter privacy).
4. A `safetyAlert` document is created in `safetyAlerts/{alertId}` with TTL of 90 days.

### Manual review escalation

If a safetyLead confirms a grooming pattern:
1. Call `escalateToLegalReview({alertId, notes})`.
2. Freeze the adult account (read-only mode, no new messages, no content deletion).
3. Preserve all conversation media per Section 8 (legal hold).
4. If CSAM is detected in the conversation, immediately follow Section 7.

---

## 6. Report Handling

### User-facing report flow

1. User taps the report button on a post, comment, space message, or DM.
2. The iOS client calls the `submitReport` CF with `{contentId, contentType, reportCategory, reporterUid}`.
3. The CF creates a document in `reports/{reportId}` with:
   - `reporterUid` (stored server-side only — never returned to other users)
   - `contentId`, `contentType`, `reportCategory`
   - `status: "pending_triage"`
   - `createdAt` server timestamp
4. The CF does NOT modify the reported content's visibility at this stage.
5. The reporter receives an in-app confirmation. The reporter's identity is never disclosed to the reported user.

**Open question (OQ-26):** Is there a report/flag button present on every surface where minors can see content or be contacted? Confirm DMs, space messages, and comments on public posts all have accessible report triggers before launch.

### Triage steps

Moderators triage `reports` collection filtered by `status == "pending_triage"`:

1. Review the reported content in its original context.
2. Assign a severity:
   - **P0:** CSAM, credible violence threat, imminent self-harm — follow Section 7 immediately
   - **P1:** Harassment of a minor, grooming signals — follow Section 5 escalation
   - **P2:** Hate speech, harassment (adult) — standard moderation pipeline
   - **P3:** Spam, off-topic — expedited review
3. Update `reports/{reportId}` with `{triageBy, triageSeverity, status: "in_review"}` via the `triageReport` Admin callable.
4. Take content action (see Section 3).
5. Close report with `{status: "closed", resolution, closedBy, closedAt}`.

### Reporter privacy protection

- The `reporterUid` field in `reports/{reportId}` is accessible only to the `moderator` role and above. Firestore rules must enforce: `allow read: if hasRole("moderator") || hasRole("safetyLead") || hasRole("legalReviewer") || hasRole("admin")`.
- No report notification, email, or in-app message to a reported user may include the reporter's identity.
- If a reported user sends a DM to someone who recently reported them, the system should flag this for review (potential retaliation detection — not yet implemented; track as post-launch enhancement).

---

## 7. CSAM / Child Exploitation Escalation

> WARNING — CRITICAL: Do NOT call `reportToNcmec()` in production until legal/compliance approves. The `NCMEC_SUBMISSION_ENABLED` environment variable must only be set to `true` after the ESP agreement is signed and the API key is valid. See OQ-10 and OQ-31 below.

### Step 1 — Immediate content hiding (within 60 seconds of detection)

- Set `visible: false` on the content document via Admin SDK.
- Set `status: "escalated"` in `moderationQueue`.
- Do NOT delete the content. Do NOT move media files. Do NOT notify the account owner.
- Record the system timestamp of detection in `csam_escalations/{escalationId}.detectedAt`.

### Step 2 — Create legal hold (before any other action)

Call `createLegalHold({contentId, contentType, detectedBy, escalationId})`. This CF:
- Creates a document in `legalHolds/{holdId}` (see Section 8 for structure).
- Sets `legalHold: true` on the content document.
- Writes an irrevocable entry to `moderationAuditLog`.
- Prevents any user-initiated delete, account deletion, or media purge from clearing the held content.

### Step 3 — Assign to legalReviewer role

- In the admin UI, assign the `csam_escalations/{escalationId}` to an account with the `legalReviewer` custom claim.
- The legalReviewer must acknowledge the assignment within 2 hours (SLA — see OQ-21 for the unresolved SLA definition).
- If no legalReviewer is available, escalate to the designated on-call legal contact via the out-of-band emergency channel (phone/Signal — define and document this contact before launch).

### Step 4 — NCMEC CyberTipline (MANUAL until wire-up is approved)

Until `reportToNcmec()` is approved and `NCMEC_SUBMISSION_ENABLED=true`:

1. Navigate to https://www.missingkids.org/gethelpnow/cybertipline
2. Complete the CyberTipline report form manually.
3. Record the CyberTipline report number in `csam_escalations/{escalationId}.ncmecReportNumber`.
4. Record the submitting staff member and timestamp.
5. 18 U.S.C. 2258A requires reporting "as soon as reasonably possible." Do not delay this step pending internal review.

### Step 5 — Do not restore or notify

- The escalated content must not be restored, republished, or made visible again without explicit written sign-off from both the legalReviewer and the T&S Lead.
- The account owner must not be notified that a CSAM escalation has been filed. Account suspension (if warranted) is handled separately by the T&S Lead with legal guidance.
- No staff member other than legalReviewer and the T&S Lead may view the flagged media after escalation. Access is logged.

### Automated detection status

**Open question (OQ-25):** Is the CSAM detection pipeline (hash-matching or ML scan) actually deployed and producing `detectionSource` values of `ios_hash_match` or `cf_vision_scan`? The `prepareCSAMEscalation()` method exists but its callers were not confirmed in this audit. This must be verified before launch.

---

## 8. Legal Hold Process

### `legalHolds` collection structure

```
legalHolds/{holdId}
  holdId: string (auto-generated)
  contentId: string
  contentType: enum [post, comment, dm, dm_conversation, media_file, user_account]
  contentPath: string (full Firestore path)
  mediaPaths: string[] (Storage paths of all associated media)
  createdAt: Timestamp (server-set, immutable)
  createdBy: string (UID of the CF or staff account that created the hold)
  reason: enum [csam, grooming, violence_threat, court_order, regulatory_inquiry, internal_investigation]
  status: enum [active, pending_legal_review, released_by_legal, expired_by_court]
  releaseApprovedBy: string | null
  releaseApprovedAt: Timestamp | null
  retentionUntil: Timestamp (minimum 90 days from creation; extended by legal team as needed)
  ncmecReportNumber: string | null
  notes: string (legalReviewer-only free text)
```

### Access

- `allow read, write: if hasRole("legalReviewer") || hasRole("admin")` — Firestore rule must be enforced.
- `moderator` and `safetyLead` roles: read-only, no field mutations.
- No client access of any kind.

**Open question (OQ-3):** Is the `legalReviewer` custom claim defined anywhere in the Cloud Functions auth layer? The `legalHolds` collection gap requires both a Firestore rule and a custom claim definition in the CF token-minting flow. Confirm before launch.

### What user delete flows must NOT clear

When a user requests account deletion or content deletion:

1. Check `legalHold: true` on the content document before any delete operation.
2. If `legalHold: true`, the delete request must be queued and blocked. The user receives the message: "This content is currently under review and cannot be deleted at this time."
3. Account deletion requests while any active `legalHolds` reference the account must be blocked. The account may be anonymized (display name, profile photo cleared) but the underlying data must be retained.
4. Media files in Storage with a corresponding active `legalHolds` entry must not be deleted by any automated purge job.
5. Log all blocked deletion attempts to `moderationAuditLog`.

### Retention

- Active legal holds: indefinite until `status` transitions to `released_by_legal` or `expired_by_court`.
- After release: retain hold metadata for minimum 7 years (subject to legal team guidance).
- NCMEC-linked holds: retain per NCMEC and 18 U.S.C. 2258A requirements.

---

## 9. Moderator Roles & Access Matrix

### Role definitions

| Role | Custom claim value | Description |
|---|---|---|
| `moderator` | `"moderator"` | Front-line content review; no legal hold access |
| `safetyLead` | `"safetyLead"` | Oversees moderation team; can escalate to legal |
| `legalReviewer` | `"legalReviewer"` | Legal/compliance team; exclusive CSAM and legal hold access |
| `supportAgent` | `"supportAgent"` | User-facing support; no content moderation powers |
| `admin` | `"admin"` | Engineering/ops; full access; must not handle CSAM directly |

### Access matrix

| Capability | moderator | safetyLead | legalReviewer | supportAgent | admin |
|---|---|---|---|---|---|
| Read `moderationQueue` | YES | YES | YES | NO | YES |
| Approve content | YES | YES | NO | NO | YES (break-glass) |
| Remove content | YES | YES | NO | NO | YES (break-glass) |
| Escalate to safetyLead | YES | YES | NO | NO | YES |
| Escalate to legalReview | NO | YES | YES | NO | NO |
| Read `reports` (reporter identity) | YES | YES | YES | NO | YES |
| Read `legalHolds` | Read-only | Read-only | Full | NO | Full |
| Write `legalHolds` | NO | NO | YES | NO | YES (break-glass) |
| Issue account suspension | NO | YES | NO | NO | YES |
| Issue account ban | NO | NO | NO | NO | YES |
| View flagged CSAM media | NO | NO | YES | NO | NO |
| Submit NCMEC report | NO | NO | YES | NO | NO |
| Read `moderationAuditLog` | Read-only | Read-only | Read-only | NO | Full |
| Modify `moderationAuditLog` | NO | NO | NO | NO | NO |
| Grant/revoke roles | NO | NO | NO | NO | YES |
| Read user `ageTier` | YES (masked) | YES | YES | NO | YES |
| Process account deletion requests | NO | YES | YES | YES | YES |
| Access billing/payment data | NO | NO | NO | YES | YES |

**Notes:**
- Admin "break-glass" actions must be justified and logged. All admin Firestore writes are audited.
- No role may view another user's `ageTier` value via a client API. Role-based reads are Admin SDK only.
- The `legalReviewer` role is the only role permitted to view CSAM-escalated media. Engineering (`admin`) must not access CSAM media under any circumstances.

---

## 10. Audit Log Policy

### `moderationAuditLog` collection

Every moderation action writes an immutable document to `moderationAuditLog/{logId}`:

```
moderationAuditLog/{logId}
  logId: string (auto-generated)
  action: string (approve | block | remove | escalate | appeal_submitted | appeal_decided |
                  legal_hold_created | ncmec_submitted | account_suspended | account_banned |
                  deletion_blocked)
  contentId: string
  contentType: string
  actorUid: string (moderator/CF service account UID)
  actorRole: string
  previousState: string
  newState: string
  reason: string | null
  notes: string | null
  timestamp: Timestamp (server-set)
  ipAddress: string | null (for human actors)
  cfName: string | null (for automated CF actors)
```

### Immutability

Firestore rule: `allow create: if isAdminSDK(); allow read: if hasRole("moderator") || ...; allow update, delete: if false`.

No principal — including admin — may update or delete an audit log entry. Deletion attempts must alert the on-call engineering team.

### Retention

Minimum 7 years for all audit log entries. CSAM-related entries: indefinite, co-located with the associated `legalHolds` document lifecycle.

### Who can read

- `moderator`, `safetyLead`, `legalReviewer`, `admin` roles: read access via Admin SDK-backed API endpoints.
- No direct Firestore client access.
- Legal team: read access via the `legalReviewer` role for litigation discovery.

---

## 11. Appeal Process

### User-facing flow

1. User views their `blocked` or `removed` content and sees the "Appeal this decision" option.
2. User submits a reason via the in-app appeal form.
3. The iOS client calls `submitAppeal({contentId, contentType, appealReason})`.
4. The CF:
   - Validates the content is in `blocked` or `removed` state.
   - Validates the calling user is the content author.
   - Creates an entry in `appeals/{appealId}` with `status: "pending"`.
   - Writes to `moderationAuditLog` with `action: "appeal_submitted"`.
   - Returns the `appealId` to the client.
5. User receives in-app confirmation. SLA: review within 48 hours (target; not yet contractually defined).

### Moderator review

1. Moderator sees `appeals` collection filtered by `status == "pending"` in the admin UI.
2. Moderator reviews the original content, the removal reason, and the user's appeal statement.
3. Moderator calls `decideAppeal({appealId, decision: "approve" | "deny", notes})`.

### If decision is "approve"

1. The `decideAppeal` CF re-runs the automated safety check on the content.
2. If the safety check passes: content state transitions to `approved`, `visible: true` is set.
3. If the safety check fails: the appeal is denied regardless of moderator decision. The moderator is notified.
4. A `moderationAuditLog` entry is written with `action: "appeal_decided"`, the decision, and the safety check result.

### If decision is "deny"

1. Content remains in `removed` or `blocked` state.
2. User receives in-app notification with the denial reason (no detailed internal notes are exposed).
3. `moderationAuditLog` entry written.

**Invariant:** Content that triggered an escalation (CSAM or grooming signal) is not eligible for appeal. The `submitAppeal` CF must reject calls where the content has `status: "escalated"` or `legalHold: true`.

---

## 12. Stripe / Payment Trust Boundaries

### Client never controls entitlements

The iOS client must never write to any document that controls paid features, tier upgrades, or moderation bypass. Entitlement documents (`users/{uid}/entitlements`, `orgs/{orgId}/subscription`) are written exclusively by the Stripe webhook Cloud Function.

### Webhook signature verification

Every request to the Stripe webhook endpoint must be verified using `stripe.webhooks.constructEvent(rawBody, sig, STRIPE_WEBHOOK_SECRET)`. Unverified requests must be rejected with HTTP 400. The raw body must be passed — parsed JSON bodies will fail signature verification.

**Open question (OQ-29):** Is the legacy `stripeWebhook.js` (root-level) actually exported and deployed to production, or has it been superseded by `stripe/stripeWebhook.js`? The `stripeFunctions.js` import chain needs to be traced to confirm which file is live before launch.

### Idempotency via event IDs

The webhook handler must check whether `stripeEvents/{event.id}` already exists before processing. If it exists, return HTTP 200 immediately without re-processing. This prevents duplicate entitlement grants from Stripe retry attempts.

### Paid status does not equal trusted or verified status

The following are explicitly prohibited:
- Paid users do not bypass content moderation.
- Paid organizations do not receive reduced scrutiny on UGC.
- Church/org verification status is independent of payment status.
- A lapsed subscription must immediately revoke entitlements — it must never leave a user in an elevated-trust state.

### Payment data isolation

- Stripe customer IDs and payment method tokens are stored only in Firestore documents accessible to the billing CF and `admin` role.
- Payment data must never appear in `moderationQueue`, `reports`, or `moderationAuditLog`.
- `supportAgent` role can read a user's subscription tier (not payment method details) to assist with billing inquiries.

---

## 13. Firebase Secrets Management

### defineSecret pattern

All sensitive values must be declared via `defineSecret()` in the Cloud Function source using `firebase-functions/params`:

```javascript
const { defineSecret } = require("firebase-functions/params");
const ncmecApiKey = defineSecret("NCMEC_API_KEY");
// Usage in function:
exports.myFunction = onCall({ secrets: [ncmecApiKey] }, async (req) => {
  const key = ncmecApiKey.value();
});
```

Secrets accessed via `process.env.SECRET_NAME` directly (without `defineSecret`) are not version-controlled or rotation-tracked. Migrate all such patterns before launch.

### Known secrets inventory

| Secret name | Purpose | Current location | Rotation policy |
|---|---|---|---|
| `NCMEC_API_KEY` | CyberTipline submission | Placeholder (`TODO_ESP_API_KEY`) | On ESP registration |
| `STRIPE_WEBHOOK_SECRET` | Stripe webhook verification | `defineSecret` (confirm) | On compromise or annually |
| `CLAUDE_API_KEY` | Berean AI / moderation ML | Rotated 2026-06-05 | On compromise or 90 days |
| `NIM_API_KEY` | NVIDIA NIM ML moderation | Confirm in CF env | On compromise or 90 days |
| `SAFETY_ALERT_WEBHOOK` | PagerDuty/Slack alert endpoint | Confirm in CF env | On compromise |
| `ALGOLIA_ADMIN_KEY` | Algolia sync (server-side) | Confirm in CF env | On compromise or annually |
| `NCMEC_ESP_ID` | CyberTipline ESP identifier | Placeholder (`TODO_ESP_ID`) | On ESP registration |
| `FIREBASE_WEB_API_KEY` | Client SDK initialization | Confirm deploy status | On compromise |

### How to rotate a secret

1. Generate the new value from the provider (Stripe dashboard, NCMEC portal, Anthropic console, etc.).
2. Run: `firebase functions:secrets:set SECRET_NAME` and paste the new value.
3. Redeploy all Cloud Functions that reference the secret: `firebase deploy --only functions`.
4. Verify the new value is active by checking the Cloud Function logs for the first invocation.
5. Revoke the old value at the provider.
6. Record the rotation event in a secure rotation log (maintain separately from UGC Firestore collections).

---

## 14. AI Model Provider Failover

### NIM API failure behavior

When the NVIDIA NIM API is unavailable or returns a non-200 response:

1. Content must remain in `pending` state — never auto-approved.
2. The failed item must be moved to `moderationDeadLetter` with `failureReason: "nim_api_unavailable"` and a timestamp.
3. A `safetyAlert` must be created if the NIM API has been unavailable for more than 5 consecutive minutes (alert threshold configurable via `NIM_OUTAGE_ALERT_THRESHOLD_MINUTES` Remote Config).
4. The moderator on-call must be notified via `SAFETY_ALERT_WEBHOOK`.

### `moderationDeadLetter` structure

```
moderationDeadLetter/{deadLetterId}
  originalQueueId: string
  contentId: string
  contentType: string
  failureReason: string
  failureTimestamp: Timestamp
  retryCount: number
  lastRetryAt: Timestamp | null
  status: enum [awaiting_retry, pending_manual_review, resolved]
```

### Manual review queue

During a provider outage, moderators should process `moderationDeadLetter` items directly. Priority order:
1. DMs involving minors
2. Comments on minor users' posts
3. Space messages in faith communities with minor members
4. General public posts

### Claude / Berean AI failover

When the Anthropic API is unavailable:
- Berean AI features must degrade gracefully (offline message shown to user).
- Content moderation that depends on Claude (if any) must fall back to the NIM pipeline or dead-letter queue.
- No content may be auto-approved because an AI provider is down.

### Fallback pattern audit required

**Open question (OQ-15):** The audit identified a `!/unsafe/i.test` regex fallback pattern in at least one moderation CF. If the AI moderation call fails and the fallback is a simple regex test, this is an inadequate safety control. All fallback paths must land content in the dead-letter queue, not auto-approve it. Audit all CFs that use this pattern before launch.

---

## 15. Data Retention

| Data type | Retention period | Notes |
|---|---|---|
| User posts (approved) | Until user deletion, subject to legal hold | Soft-delete on user request; hard-delete after legal hold check |
| User posts (removed/blocked) | 2 years minimum | Required for appeals and pattern analysis |
| DM messages | 1 year after conversation last active | Legal hold blocks deletion |
| `moderationQueue` items | 90 days via TTL policy (pending OQ-20 confirmation) | Dead-letter items: 1 year |
| `reports` collection | 3 years | Reporter identity protected throughout |
| `moderationAuditLog` | 7 years minimum | Immutable; CSAM entries indefinite |
| `legalHolds` metadata | Indefinite while active; 7 years after release | NCMEC-linked: indefinite |
| CSAM-escalated media | Indefinite under legal hold | Stored in quarantine Storage bucket |
| `safetyAlerts` | 90 days via TTL | Extended manually if investigation ongoing |
| User account data (deleted accounts) | 30 days soft-delete window, then purged | Legal hold blocks purge |
| Payment/billing data | 7 years (financial record-keeping requirement) | Stored in billing-isolated Firestore collection |
| `moderationDeadLetter` | 1 year | Resolved items may be purged after 90 days |
| Algolia search index (user records) | Until account deletion or index exclusion event | Minor records must never be indexed |
| Cloud Function logs | 30 days (Google Cloud default) | Extend to 1 year for safety-critical functions |
| Firebase Auth records (deleted users) | Per Firebase retention policy (review) | Open question — confirm retention behavior for minor accounts |

**Open questions on retention:**
- Retention periods for NCMEC-related records are subject to 18 U.S.C. 2258A and must be confirmed with legal counsel.
- GDPR right-to-erasure requests from EU users may conflict with the 2-year retention on removed content. Legal team must define the resolution policy.
- COPPA requires deletion of personal information collected from under-13 users upon parent/guardian request. The account deletion flow must handle this within the 30-day window.

---

## 16. Open Questions — Human / Legal / Product Decision Required

The following questions were identified during the safety audit on 2026-06-11. Each must be resolved and the answer documented before the app is launched to the public.

**OQ-1 (OPEN) — Minimum age floor:** Is the minimum age floor 13 (US COPPA) or 16 (GDPR-K for certain EU jurisdictions)? If the app will be available in the EU, GDPR-K compliance requires explicit parental consent for under-16 in some member states. Legal team must confirm the jurisdiction scope and document the binding minimum age.

**OQ-2 (OPEN) — Guardian tools scope:** The `isGuardianApprovedContact()` function returns `true` (allow) when the guardian approval document does not exist. This means the guardian-approval DM gate is non-functional. What is the intended guardian permission model: read-only oversight, active approve/deny, or emergency-only access? A T&S Lead decision is required before this can be implemented.

**OQ-3 (OPEN) — legalReviewer custom claim:** Is the `legalReviewer` custom claim defined anywhere in the Cloud Functions auth layer? If not, the `legalHolds` collection access rule is unenforced. Assign an engineering owner to implement and document the claim-minting flow.

**OQ-4 (OPEN) — Which Firestore rules file is live:** Which file is actually deployed to production — `firestore.deploy.rules` (in AMENAPP/) or `firestore.rules` (at root)? The `firebase.json` comment says to change the `firestore.rules` field before deploying. The `safety-hardening` branch has both files modified but they have diverged: the `safetyAuditLog/guardianLinkRequests` gap exists in `firestore.deploy.rules` but not in `firestore.rules`. Engineering must run `firebase deploy --only firestore:rules --dry-run` and confirm which file is live.

**OQ-5 (OPEN) — Unauthenticated read of public posts (OPEN-5):** Has a product decision been made about whether SEO-driven unauthenticated reads are intentional? This affects both privacy posture and COPPA risk (minors' public posts are readable without account). Product and Legal must make an explicit call and document it.

**OQ-6 (OPEN) — moderationQueue Admin SDK restriction tested:** Has the `allow create: if isAdminSDK()` restriction on `moderationQueue` been tested end-to-end with actual iOS clients? The silent `try?` calls in `AmenChildSafetyService`, `AmenModerationService`, and `AntiHarassmentEngine` mean no runtime error surfaces if the write silently fails. Engineering must add error logging to these call sites and run an end-to-end test.

**OQ-7 (OPEN) — /users/{userId} field exposure:** Does any Cloud Function read fields from `/users/{userId}` (e.g., `ageTier`, `churchId`, `isMinor`) to make trust or authorization decisions? If so, the unrestricted any-signed-in-user read on that collection means those decision inputs are readable by other users. An adversary can read another user's `ageTier` to learn their minor status. Engineering must audit all CF reads of this collection and restrict field-level exposure.

**OQ-8 (OPEN) — one_users/witnesses CF:** The `one_users/witnesses` subcollection comment says "CF validates both-party acceptance" but no CF callable is named. Which CF is expected to run, and does it enforce the constraint before the Firestore write or only after?

**OQ-9 (OPEN) — MusicContentLayer collections in Firestore rules:** Are there any collections written by the MusicContentLayer (`RightsMonetizationService`, `FaithMusicGraphService`, `AmenPulseDigestService`) not yet covered by Firestore rules? The `safety-hardening` branch shows those files modified and they likely write to music-specific collections.

**OQ-10 (OPEN) — NCMEC submission environment variable:** Is `NCMEC_SUBMISSION_ENABLED` set to `true` in production? If not, the app is collecting `ncmecReports` but never submitting to NCMEC. Once the platform reaches the threshold defined in 18 U.S.C. 2258A, this may constitute a legal violation. Legal team must determine the current threshold status and timeline for enabling.

**OQ-11 (OPEN) — isGuardianApprovedContact fallthrough:** The `isGuardianApprovedContact()` bug (returns `true` on missing document) is a confirmed defect. Engineering must fix before launch. T&S Lead must also define the guardian approval scope (OQ-2) to implement the correct behavior.

**OQ-12 (OPEN) — chat_videos Storage rule gap:** The `chat_videos` path is used for DM video uploads but has no Storage rule. Any authenticated user may be able to write to any `conversationId`. Engineering must add a Storage rule that restricts writes to participants of the conversation.

**OQ-13 (OPEN) — Legacy profileImages path:** The legacy `users/{uid}/profileImages/{filename}` path uses `allow read: if isSignedIn()` while the newer `profilePhotos/{uid}/{photoId}` path uses `allow read: if true` (unauthenticated). Is the legacy path still actively used? If so, the inconsistency must be resolved with an explicit product decision.

**OQ-14 (OPEN) — retryHelper.js status code inspection:** Does `withRetry` in `retryHelper.js` inspect HTTP status codes (429/5xx) or only caught exceptions? If only exceptions, the retry gap between `moderatePost.js` and `moderateUGC.js` is a separate code defect. Engineering must audit and fix.

**OQ-15 (OPEN) — aiModeration.moderateContent fallback:** What does `aiModeration.moderateContent` (which overwrites the `contentModeration` export at `index.js` line 300) actually do? Does it use the `!/unsafe/i.test` fallback pattern? Engineering must audit this export chain.

**OQ-16 (OPEN) — Comment moderation coverage:** Is there server-side moderation for `posts/{postId}/comments/{commentId}` documents? If not, all comments bypass the moderation pipeline (CRITICAL finding #4). Engineering must confirm or implement a trigger.

**OQ-17 (OPEN) — moderateDMMessage gen-1 reliability:** The `moderateDMMessage` trigger is gen-1. Is the Cloud Run quota exhaustion that forced other functions to v1 also affecting `moderateDMMessage` reliability? Engineering must monitor drop rates for this trigger.

**OQ-18 (OPEN) — Direct client writes to comments:** Are Firestore security rules preventing direct client writes to `posts/{postId}/comments/{commentId}` without going through the `addComment` callable? If not, the comment moderation gap can be exploited without any server-side enforcement. Engineering must audit rules.

**OQ-19 (OPEN) — NCMEC text-CSAM path:** The `moderatePost.js` child-safety escalation path sets `externalReport.submitted: false` with a `TODO` placeholder for `NCMEC_CYBERTIPLINE_TODO`. Has a real NCMEC API key been configured and tested end-to-end for text-detected CSAM?

**OQ-20 (OPEN) — Firestore TTL policy enabled:** Is there a Firestore TTL policy actually enabled on `moderationQueue.expireAt` and `moderationDeadLetter` in the Firebase Console? This requires a manual step in Firebase Console > Firestore > Indexes > TTL. Engineering must confirm.

**OQ-21 (OPEN) — NCMEC SLA and key holder:** Who is the designated SLA key holder for NCMEC submissions? What is the maximum acceptable time between CSAM detection and NCMEC filing? This must be defined and contractually enforced before any launch. Legal team owns this decision.

**OQ-22 (OPEN) — Guardian system Cloud Function:** Is the `onDocumentCreated` Cloud Function for `/guardianLinkRequests` implemented anywhere not covered by this audit? If not, the entire guardian system is inert.

**OQ-23 (OPEN) — Can pastors DM minors:** Has a product decision been made about whether verified church leaders (pastors) may initiate DMs with minor members of their congregation? This is a high-risk capability requiring explicit policy documentation and technical enforcement. Until documented: NO. Church leaders may respond to minor-initiated messages only, in the context of a shared space, with all messages passing the adult-minor detection pipeline.

**OQ-24 (OPEN) — Algolia incremental sync:** Does every incremental Algolia user-sync path (e.g., real-time profile updates) call `shouldExcludeFromPeopleIndex()`? Only the bulk sync path was confirmed. Engineering must audit all write paths to the Algolia index.

**OQ-25 (OPEN) — CSAM detection pipeline deployed:** Is the CSAM detection pipeline (hash-matching or ML scan) actually deployed and producing `detectionSource` values of `ios_hash_match` or `cf_vision_scan`? The `prepareCSAMEscalation()` method exists but its callers were not confirmed in this audit. Engineering must verify end-to-end.

**OQ-26 (OPEN) — Report button on all minor-visible surfaces:** Is there a report/flag button present on every surface where minors can see content or be contacted? QA must confirm DMs, space messages, and comments all have accessible report triggers.

**OQ-27 (OPEN) — ageTier admin bypass risk:** The `allow update: if false` Firestore rule for `ageTier` applies only to clients, not to the Firebase Console or Admin SDK. Is there a mechanism to prevent an admin with Firestore console access from manually setting `ageTier` to `tierD` for a minor? Engineering must document the accepted risk and implement an audit alert for any direct `ageTier` mutations via Admin SDK.

**OQ-28 (OPEN) — Storage rules deployed:** Is `storage.rules` actually deployed to production? Several iOS upload paths (`post_media`, `chat_videos`, `profile_images`) are absent from `storage.rules` and would be silently denied if the hardened rules are live. Engineering must run `firebase deploy --only storage --dry-run` and confirm current state.

**OQ-29 (OPEN) — Stripe webhook file ambiguity:** Is the legacy `stripeWebhook.js` (root-level) or `stripe/stripeWebhook.js` live in production? Engineering must trace the `stripeFunctions.js` import chain and confirm.

**OQ-30 (OPEN) — App Check enforcement status:** Have the 33+ Berean OS Cloud Functions with `enforceAppCheck: false` ever been deployed to production? What is the current status of the App Check migration ticket from the Trust OS audit? Engineering must provide a status update and a deadline.

**OQ-31 (OPEN) — NCMEC ESP agreement:** Has the NCMEC CyberTipline ESP agreement been initiated? The `TODO_ESP_ID` and `TODO_ESP_API_KEY` placeholders in the codebase suggest registration has not been completed. Legal team must initiate and track this process.

**OQ-32 (OPEN) — safeMessagingGateway direct write bypass:** Is `safeMessagingGateway.js` the sole DM-writing path, or can messages be written directly to Firestore by the client? If Firestore security rules do not block client writes to the `messages` collection, the `isBanned` check in the gateway is bypassable. Engineering must verify rules.

**OQ-33 (OPEN) — AmenRBACService path canonical:** Does `AmenRBACService.resolveRole` use the path `roles/{contextType}/{contextId}/members/{uid}/membership` — and is this the same path that Cloud Functions read? If CFs use a different schema, role checks are split and potentially inconsistent.

**OQ-34 (OPEN) — App Check project-level enforcement:** Are Firebase App Check attestation tokens enforced in the Firebase project console (not just at the function level)? App Check can be bypassed if the project-level enforcement toggle is off even when individual functions declare `enforceAppCheck: true`. Engineering must verify the project console setting.

**OQ-35 (OPEN) — moderateUploadedImage CF latency:** What is the latency between a file being uploaded to `profilePhotos/` and the `moderateUploadedImage` CF completing its SafeSearch check? If this window exceeds 5 seconds under normal load, a CDN may cache the public URL before removal, making deletion insufficient. Engineering must measure p99 latency under production load.

**Standing policy decisions (must be explicitly documented before launch):**

- Paid organizations do NOT bypass content moderation. This is non-negotiable.
- Paid users do NOT receive reduced moderation scrutiny. This is non-negotiable.
- Pastors and church leaders may NOT initiate DMs with minors until OQ-23 is resolved with explicit written policy.
- NCMEC reporting is manual until OQ-10, OQ-19, and OQ-31 are resolved.

---

## 17. Manual Launch Checklist

This checklist must be completed and signed off by the designated owner before any public launch (beta or App Store).

### Critical safety — block launch if any item is unchecked

- [ ] All CRITICAL findings addressed and verified by T&S Lead
- [ ] All HIGH findings addressed and verified by Engineering Lead
- [ ] Legal team has reviewed CSAM escalation plan (Section 7) and signed off in writing
- [ ] NCMEC integration approved by legal and wired, OR manual NCMEC process documented, trained, and staffed (OQ-10, OQ-21, OQ-31)
- [ ] `isGuardianApprovedContact()` bug fixed (OQ-2, OQ-11)
- [ ] `legalReviewer` custom claim implemented and tested (OQ-3)
- [ ] Guardian link requests Cloud Function implemented and tested (OQ-22)
- [ ] Direct client writes to `comments` subcollection blocked by Firestore rules (OQ-18)
- [ ] Comment moderation CF trigger confirmed deployed and processing all comments (OQ-16)
- [ ] CSAM detection pipeline confirmed end-to-end (OQ-25)
- [ ] Minimum age floor confirmed by legal and enforced in age verification flow (OQ-1)
- [ ] Guardian consent model defined, implemented, and tested (OQ-2)
- [ ] T&S Lead role assigned to a named human (OQ-21)
- [ ] NCMEC SLA defined and documented (OQ-21)

### Infrastructure — block launch if any item is unchecked

- [ ] App Check enabled in Firebase project console (OQ-34)
- [ ] App Check migration completed for Berean OS CFs or exceptions formally documented (OQ-30)
- [ ] All secrets migrated to `defineSecret` pattern (Section 13)
- [ ] `NCMEC_SUBMISSION_ENABLED` status confirmed and consistent with legal guidance (OQ-10)
- [ ] Firestore rules deployed — confirm which file is live and that it is the intended file (OQ-4)
- [ ] Storage rules deployed and tested against all active upload paths (OQ-28)
- [ ] Moderation CFs deployed and processing queue (including gen-2 vs gen-1 status confirmed)
- [ ] Safety CFs deployed (CSAM, guardian, anti-harassment)
- [ ] Firestore TTL policy enabled for `moderationQueue` and `moderationDeadLetter` (OQ-20)
- [ ] Cloud Function logs retention extended to 1 year for safety-critical functions
- [ ] `stripe/stripeWebhook.js` vs root-level `stripeWebhook.js` ambiguity resolved (OQ-29)

### Quality assurance

- [ ] Age verification flow QA passed end-to-end on device
- [ ] Minor discovery tested: Tier A users do not appear in public People search
- [ ] Minor discovery tested: Tier B/C users do not appear outside their communities
- [ ] Adult-minor DM gating tested: Tier D user cannot DM Tier A user outside guardian list
- [ ] Report button confirmed present on: posts, comments, DMs, space messages
- [ ] CSAM escalation drill completed (synthetic test content, not real CSAM) with all steps logged
- [ ] Legal hold block tested: user cannot delete content with active legal hold
- [ ] Appeal flow tested end-to-end: submit then review then approve then safety re-check then restore
- [ ] Moderation dead-letter queue tested: content lands in dead-letter on NIM outage, not auto-approved
- [ ] `moderationAuditLog` immutability confirmed: update/delete attempts rejected
- [ ] Algolia index confirmed: minor UIDs absent from People index (bulk and incremental sync) (OQ-24)
- [ ] `chat_videos` Storage rule added and tested (OQ-12)
- [ ] `safeMessagingGateway` confirmed as sole DM write path (OQ-32)
- [ ] `AmenRBACService` path confirmed consistent with Cloud Functions RBAC reads (OQ-33)

### Legal and compliance

- [ ] COPPA compliance review completed by legal
- [ ] GDPR-K review completed (if EU launch planned) (OQ-1)
- [ ] Privacy policy updated to reflect minor data handling
- [ ] NCMEC ESP registration initiated (OQ-31)
- [ ] Data retention policy reviewed and approved by legal (Section 15)
- [ ] GDPR right-to-erasure vs moderation retention conflict resolved by legal
- [ ] Pastor-minor DM policy documented and enforced (OQ-23)

---

*End of SAFETY_RUNBOOK.md — last updated 2026-06-11 on branch safety-hardening*
*This document must be re-reviewed whenever the safety-hardening branch is merged or any OQ item above is resolved.*

---

## Appendix: Safety Consolidation Changes (2026-06-11)

### New Capabilities

- **submitSafetyReport CF**: real backend for iOS report buttons (auth + App Check + rate-limited); routes all client-originated moderationQueue writes server-side via Admin SDK batch; critical categories (csam/child_safety/grooming) trigger escalation pipeline
- **Guardian DM gate**: fails closed on partial/corrupt documents — `approved` field absent on an existing document returns false via `?? false`; OPEN-2 (doc-absent policy) is a HUMAN-DECISION pending T&S Lead resolution
- **CSAM delete lock**: Firestore rule blocks ALL client updates when `moderation.status` is `escalated`, `csam_suspected`, or `removed`; content in terminal safety states is CF/Admin SDK only from that point forward
- **NeMo Guard fail-closed**: `catch` block in moderateUGC.js and moderationGateway.js now sets `safe = false` unconditionally; the `!/unsafe/i.test(raw)` jailbreak pattern is removed and commented with an explicit security warning
- **All moderation fail-open paths eliminated**: contentModerationTriggers.js catch now sets `visible: false, flaggedForReview: true`; FAIL_OPEN constant removed from contentModeration.js
- **Storage quarantine-first model**: all client upload paths (post_media, profile_images, legacy posts/, chat_videos, sanctuary_media, voice devotionals, sermon audio) now have explicit Storage rules with MIME allowlists, per-type size caps, create-only enforcement, and owner-only reads while in quarantine
- **chat_videos explicit rule**: Storage rule added with conversationParticipant check, video/* MIME enforcement, 100 MB size cap, and participant-only read
- **Quarantine overwrite blocked**: quarantine path changed from `allow create, update` to `allow create` only — no mid-moderation overwrite possible
- **App Check on Berean OS + Selah**: `enforceAppCheck: true` added to all 33+ Berean OS and Selah onCall functions; FUNCTIONS_EMULATOR guard in place for local dev; Console enforce-mode is human STEP 4
- **UID enumeration closed**: `backfillUsernameLookup` now requires `request.auth.token.admin === true` (same guard as `setAdminClaim` and `banUserPhone`)
- **allowDM() adult-to-minor fix**: `AmenRBACService.allowDM()` now returns `false` for `.minor` role and for all non-leader adults contacting a minor; only owner/executiveAdmin/pastor proceed to CF for parental-consent verification
- **Unknown-age DM blocked**: `minorProtection.js` `eitherUnknown` + `contentType=="dm"` now returns `allowed: false, reason: "age_unknown_dm_blocked_fail_closed"`

### New Documents

- **DECISION_DOC_SAFETY.md**: 35 questions in 3 groups (Legal, Product, Trust & Safety) for human sign-off; A-01 = NCMEC ESP registration, A-05 = age verification vendor decision
- **DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md**: single human deploy checklist covering all pending CF deploys, Firestore rules, Storage rules, and App Check Console enforce-mode steps

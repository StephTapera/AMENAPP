# Amen Safety Runbook

**Version:** 1.0  
**Date:** 2026-06-11  
**Branch:** safety-hardening  
**Status:** DRAFT — requires legal review before go-live

---

## 1. Safety Principles

### 1.1 Foundational Commitments

The Amen platform is built for faith communities. Safety is not a feature — it is the prerequisite for trust. Every design, moderation, and escalation decision must pass four tests:

1. **Harm Prevention First.** When a rule is ambiguous, default to protecting the potentially harmed party, not the potentially harmful actor.
2. **Minor Protection is Absolute.** Any risk to a user under 18 — especially under 13 — overrides platform engagement, growth, or creator monetization considerations without exception.
3. **Fail Closed.** When safety systems cannot determine a user's age, consent status, or content classification, they must default to the most restrictive safe state, not the most permissive.
4. **Human Review in the Loop.** Automated systems (AI moderation, grooming heuristics, rate limiters) are first-pass filters only. Any content or account that reaches a high-severity queue requires a human decision before enforcement action is final.

### 1.2 Safety Officer

**Role:** Chief Safety Officer (CSO) / Trust and Safety Lead  
**Current Assignee:** [ASSIGN BEFORE LAUNCH — required for NCMEC CyberTipline registration]  
**Responsibilities:**
- Final authority on enforcement decisions for Severity 1 incidents
- Approves any change to CSAM escalation code or NCMEC submission configuration
- Signs off on all legal hold creation within 24 hours of creation
- Quarterly review of this runbook
- Point of contact for law enforcement requests

### 1.3 Safety Hierarchy

```
Safety Officer (CSO)
├── Trust & Safety Lead
│   ├── Senior Moderators (Severity 1-2 decisions)
│   └── Moderators (Severity 3-4 decisions, queue clearance)
├── Legal Counsel
│   └── Legal Hold approvals, NCMEC coordination
└── Engineering Safety Contact
    └── Incident response, system fixes, audit log retrieval
```

---

## 2. Content Lifecycle

### 2.1 Post Submission Flow

```
User submits content
        │
        ▼
Pre-publication AI check (NeMo Guard text / Vision LLM images)
        │
   ┌────┴────┐
   │         │
PASS       FLAGGED
   │         │
   ▼         ▼
Published  Held for review
           (visible=false pending)
```

### 2.2 Content States

| State | Description | Visibility |
|---|---|---|
| `published` | Live, passed moderation | Public per audience setting |
| `held` | Queued for human review | Not visible |
| `escalated` | Escalated (moderation.status=escalated) | Hidden (visible=false) |
| `removed` | Enforced removal | Not visible |
| `legal_hold` | Under legalHold=true flag | Not visible, exempt from deletion |
| `appealed` | Removed but appeal open | Not visible pending appeal |

### 2.3 Post Report Flow

```
User files report
        │
        ▼
Rate limit check (10 reports/day per user)
        │
        ▼
Category check
        │
   ┌────┴──────────────────────────┐
   │                               │
Child Safety Categories         All other categories
(child_safety, csam_suspected,       │
 child_exploitation,                 ▼
 child_grooming,              moderationQueue
 minor_sexualization)                │
   │                                 ▼
   ▼                         Senior Moderator review
escalateChildSafety()         within SLA
   │
   ▼
createLegalHold() + escalationQueue
   │
   ▼
Safety Officer notified within 1 hour
```

**KNOWN BUG (P0 — MUST FIX BEFORE LAUNCH):** `blockMuteReport.js` imports `escalateChildSafety` from `../moderation/escalation`, but `escalation.js` does not export that function. This import will throw a TypeError at runtime, causing CSAM reports to fall through to the normal review queue or be silently dropped. See Section 14 for remediation owner.

---

## 3. Moderation Queue Operations

### 3.1 Queue Types

| Queue | Firestore Collection | Handler Role |
|---|---|---|
| Standard moderation | `moderationQueue` | Moderator |
| Child safety escalation | `escalationQueue` | Senior Moderator + Safety Officer |
| Legal holds | `legalHolds` | Legal + Safety Officer |
| Invite safety review | `inviteSafetyQueue` | Moderator |
| Grooming risk flags | `moderationQueue` (flagType=grooming) | Senior Moderator |

### 3.2 SLA Targets

| Queue | Target Resolution |
|---|---|
| Child safety / CSAM escalation | 1 hour from creation (24/7) |
| Grooming risk (score >=4) | 2 hours |
| Standard harassment / hate | 4 hours (business hours) |
| Standard spam / off-topic | 24 hours |
| Appeals | 72 hours |

### 3.3 Queue Triage Workflow

1. Open the moderation dashboard and filter by `status = pending`, sorted by `createdAt ASC`.
2. For each item, review: content snapshot, report category, reporter notes, subject's account age and tier.
3. Assign a severity level (see Section 4).
4. Take action: Approve (restore/dismiss), Remove, Escalate, or Request More Info.
5. Log your decision with a reason code. Do not leave a queue item unactioned after viewing it.

### 3.4 Reason Codes

| Code | Meaning |
|---|---|
| `HARM_MINOR` | Content harms or targets a minor |
| `CSAM` | Child sexual abuse material confirmed |
| `GROOMING` | Grooming behavior pattern detected |
| `HARASSMENT` | Targeted harassment / coordinated attack |
| `SELF_HARM` | Self-harm or suicide ideation content |
| `HATE_SPEECH` | Hate speech / targeted bigotry |
| `SPAM` | Spam / coordinated inauthentic behavior |
| `FALSE_POSITIVE` | Report was unfounded |
| `CONTEXT_OK` | Content acceptable in context |

---

## 4. Incident Response

### 4a. Minor Safety

**Definition:** Any incident where a user under 18 may be at risk of contact exploitation, inappropriate adult contact, or exposure to harmful content.

**Triggers:**
- Grooming risk score >= 3 for an adult-to-minor message thread
- An adult user attempting to DM an unrelated minor (blocked by system, but elevated if repeated)
- A minor's profile discovered by a non-guardian despite `discoverySafetyMode` restrictions
- A sanctuary (Spaces) invite from an unrelated adult to a minor routed to `inviteSafetyQueue`

**Response Steps:**
1. **Immediately** verify age tier of both parties. Check `minorAgeBand` field (blocked / tierB / tierC / tierD).
2. Confirm the block or restriction was enforced by the system. If the DM or invite went through, treat as P0.
3. Freeze the adult account (suspend pending review) — do not alert the account holder.
4. Preserve all message content via `createLegalHold()` before any deletion.
5. Escalate to Safety Officer within 1 hour.
6. If content indicates grooming or solicitation, escalate to CSAM path (Section 4b).
7. If minor is under 13: mandatory Safety Officer review + legal counsel notification within 2 hours.
8. Document the incident in the audit log with timeline, actions taken, and outcome.

**Pastor-Minor DM Policy:**  
Pastors, ministry leaders, and church staff accounts are NOT exempt from minor protection controls. The system treats all adult-to-unrelated-minor DM attempts identically regardless of account role. No configuration, admin override, or feature flag bypasses this block. If a pastoral care use case genuinely requires communication with a minor, it must flow through a guardian-approved sanctuary channel with guardian visibility, not a direct message. Any attempt to bypass this via admin writes to `guardianIds` must be reviewed by the Safety Officer and logged.

**KNOWN GAP:** The `_hasApprovedRelationship` guardian check does not verify a separate consent record exists — a Firestore write could whitelist an unrelated adult. Moderators should treat any unexpectedly approved adult-minor relationship as a potential data integrity issue and escalate for engineering review.

### 4b. CSAM Detection

**Definition:** Any content that depicts, suggests, or may constitute child sexual abuse material, including AI-generated imagery of minors in sexual contexts.

**CRITICAL: This is a legal obligation, not just a policy violation.**

**Detection Sources:**
- User report with category `csam_suspected`, `child_exploitation`, `child_sexual_exploitation_material`, `minor_sexualization`, or `child_grooming`
- AI vision moderation flag on uploaded images/video
- Grooming risk detection with attached media
- Law enforcement referral

**Response Steps:**
1. **Do not view the content beyond what is necessary to confirm the report category.**
2. Immediately trigger `createLegalHold()` — content must be preserved before any deletion.
3. Set `visible=false` on the content document immediately.
4. Suspend the posting account immediately.
5. Page the Safety Officer via emergency channel — do not wait for business hours.
6. Safety Officer contacts Legal Counsel within 1 hour.
7. Legal Counsel initiates NCMEC CyberTipline reporting process (see Section 5).
8. Do NOT communicate with the reported user about the investigation.
9. Preserve all related content (account, DMs, connections) under legal hold.
10. Cooperate with any law enforcement request via Legal Counsel.

**KNOWN BUG:** The `escalateChildSafety` import in `blockMuteReport.js` is broken (see Section 14). Until this is fixed, moderators must manually monitor `contentReports` for CSAM categories and escalate them directly. Do not assume the automated fast-path is working.

**KNOWN GAP:** NCMEC reporting (`reportToNcmec`) is currently a stub that always throws. No automated CyberTipline submission is possible until the Safety Officer and Legal Counsel approve the integration and a compliance-approved engineer replaces the stub. All NCMEC reports must be filed manually by Legal Counsel through the web portal until this is resolved.

### 4c. Harassment Campaign

**Definition:** A coordinated pattern of multiple users reporting, blocking, or targeting a single account, or a single actor targeting multiple users with harassing content.

**Triggers:**
- 5+ reports against a single account within 24 hours from different reporters
- An account that has been blocked by 10+ unique users in 7 days
- Coordinated spam or hate content across multiple posts from one or more accounts

**Response Steps:**
1. Confirm the pattern is coordinated, not organic (check reporter account ages, IP metadata if available).
2. Shadow-restrict the target account (limit reach without alerting) while investigation is active.
3. If the target of harassment is a minor, escalate to Section 4a immediately.
4. Remove individual content items that violate policy. Do not mass-remove without review.
5. If accounts involved are clearly coordinated fake accounts, suspend and document for potential legal referral.
6. Notify the victim that action is being taken (do not share details of investigation).
7. Consider temporary posting cool-down on the harassing account(s) before full suspension if the pattern is new.
8. Document the campaign pattern with screenshot evidence in the audit log.

### 4d. Self-Harm Content

**Definition:** Posts, messages, or profile content that expresses suicidal ideation, self-harm intent, or provides methods/encouragement of self-harm.

**Response Steps:**
1. Do not remove the content immediately — removal may cut off access to help.
2. Overlay the Safe Messaging resource sheet on the content (if system supports in-line intervention).
3. Send the posting user a direct safety resource message with crisis hotline information (988 Suicide & Crisis Lifeline; Crisis Text Line: text HOME to 741741).
4. Flag the account for check-in by the moderation team within 24 hours.
5. If the content is instructional (provides methods) rather than a cry for help, remove after the resource message is delivered.
6. Do not apply punitive enforcement (suspension, strikes) to a self-harm post — treat the user as someone who needs support, not punishment.
7. If there is evidence of imminent danger (specific plan, time, location), escalate to Safety Officer and engage emergency services guidance from Legal Counsel.
8. Log the incident as self-harm in the audit log without reproducing the content text.

---

## 5. CSAM Escalation

### 5.1 Current Status

**NCMEC Reporting: NOT CONFIGURED**

The `reportToNcmec` function in `functions/moderation/escalation.js` is a correctly gated stub. It always throws with the message: `"NCMEC reporting not yet configured — requires compliance approval"`. This is intentional and correct — automated CyberTipline submission requires:

1. NCMEC Electronic Service Provider (ESP) account registration
2. Legal Counsel review and approval of submission schema
3. Safety Officer sign-off
4. Compliance-approved engineering implementation
5. Test submission with NCMEC sandbox environment

**Until the above steps are complete, ALL CSAM reports must be manually filed by Legal Counsel through the NCMEC CyberTipline web portal at: https://www.missingkids.org/gethelpnow/cybertipline**

### 5.2 NCMEC Approval Process

The following steps are required before automated NCMEC reporting can go live:

| Step | Owner | Status |
|---|---|---|
| Register Amen as an ESP with NCMEC | Safety Officer + Legal | PENDING |
| Obtain ESP account credentials | Legal | PENDING |
| Legal review of submission field mapping | Legal Counsel | PENDING |
| Engineering implements `reportToNcmec` stub replacement | Engineering Safety Contact | BLOCKED on legal approval |
| NCMEC sandbox test submission | Engineering + Safety Officer | BLOCKED |
| Production go-live approval | Safety Officer | BLOCKED |

### 5.3 Manual NCMEC Reporting Procedure

Until automation is live, follow this procedure for every confirmed CSAM incident:

1. Legal Counsel receives escalation from Safety Officer.
2. Legal Counsel logs into NCMEC CyberTipline portal.
3. Submit report with: incident date/time, platform name (Amen), account identifiers (do not include PII in non-secure channels), content description (do not attach CSAM to non-secure channels — use NCMEC secure upload), any known location data.
4. Record the NCMEC Report ID in the Amen `legalHolds` document for the case: set `externalReport.ncmecReportId` and `externalReport.submitted=true`.
5. Retain confirmation of submission in legal files.

### 5.4 Legal Hold for CSAM

All CSAM escalations must invoke `createLegalHold()` which:
- Writes an immutable snapshot to `legalHolds/{holdId}` with SHA-256 `snapshotHash`
- Sets `visible=false` on the content document
- Writes to `escalationQueue` with `requiresHumanReview=true`
- Sets `legalHold=true` on the source document (exempting it from all deletion policies)

**IMPORTANT:** Never delete content under legal hold. The `legalHold=true` flag must be checked by all data retention jobs before any deletion. See Section 13.

---

## 6. Legal Hold Process

### 6.1 When to Create a Legal Hold

- Any confirmed or suspected CSAM content
- Any account under law enforcement investigation
- Any content that is subject to a litigation hold notice
- Any content that is evidence in an active moderation appeal where the content was removed
- Accounts suspected of coordinated minor exploitation

### 6.2 Creating a Legal Hold

Call `createLegalHold(db, { contentId, contentType, contentSnapshot, caseId, requestedBy })`.

The function will:
1. Write an immutable record to `legalHolds/{holdId}` with `snapshotHash`, `immutable:true`, `legalHold:true`
2. Set `legalHold:true` on the source document
3. The hold exempts the document from all automated deletion and retention purges

**IMPORTANT KNOWN GAP:** `immutable:true` is an advisory field value only. Firestore security rules must be verified to deny all update and delete operations on `legalHolds` documents, including from Admin SDK callers using `update()`. This must be confirmed by Engineering before go-live.

### 6.3 Legal Hold Lifecycle

| Phase | Action | Owner |
|---|---|---|
| Created | Snapshot written, content hidden | System |
| Reviewed | Safety Officer confirms within 24h | Safety Officer |
| Active investigation | No deletion, no access without authorization | Legal |
| Resolved | Legal Counsel files disposition | Legal Counsel |
| Released | Safety Officer approves hold release | Safety Officer |
| Archived | Record retained per legal retention schedule | Legal |

### 6.4 Evidence Access

`getLegalHoldEvidence()` requires `trust_safety_admin` or `legal_admin` role verification by the caller. This role check is **not enforced inside the function** — callers are responsible. Before calling this function, document in your workflow that the requesting party has the appropriate role and the request is logged in the audit trail. A miscoded caller with no role check can retrieve CSAM evidence snapshots.

**This must be fixed before launch:** Add an in-function role assertion to `getLegalHoldEvidence`.

---

## 7. Appeals Lifecycle

### 7.1 Appeal Eligibility

Users may appeal:
- Content removal decisions
- Account suspension (temporary or permanent)
- DM restrictions

Users may NOT appeal:
- Legal holds (these are out of moderator control)
- CSAM-related removals (no appeal process; law enforcement matter)
- Blocks placed by other users (those are user-controlled)

### 7.2 Appeal Flow

```
User submits appeal
        │
        ▼
System logs appeal with original decision metadata
        │
        ▼
Assigned to a different moderator than original decision
        │
        ▼
72-hour review window
        │
   ┌────┴────┐
   │         │
UPHELD    OVERTURNED
   │         │
   ▼         ▼
User         Content/account restored
notified     + audit entry logged
```

### 7.3 Appeal Principles

- Appeals must be reviewed by a different moderator than the one who made the original decision.
- The reviewing moderator must document their reasoning — "I agree with the original decision" is not sufficient.
- For Severity 1 or 2 content removals, appeals must be reviewed by a Senior Moderator or above.
- If an appeal reveals a systemic misclassification pattern, escalate to the Safety Officer for a policy review.

---

## 8. Moderator Roles and Permissions

### 8.1 Role Definitions

| Role | Firestore Custom Claim | Capabilities |
|---|---|---|
| `moderator` | `role: "moderator"` | View moderation queue; approve/remove standard content; file reports; view standard audit entries |
| `senior_moderator` | `role: "senior_moderator"` | All moderator caps + view child safety queue + grooming risk queue + make Severity 1-2 decisions |
| `trust_safety_admin` | `role: "trust_safety_admin"` | All senior_moderator caps + view legal holds + call getLegalHoldEvidence + admin rate limit status |
| `legal_admin` | `role: "legal_admin"` | View and disposition legal holds + getLegalHoldEvidence + NCMEC record updates |
| `safety_officer` | `role: "safety_officer"` | All roles + approve NCMEC go-live + approve legal hold release + override enforcement decisions |
| `engineering_safety` | `role: "engineering_safety"` | Audit log read (full) + rate limit reset + system diagnostics (no content access) |

### 8.2 Role Assignment

- Roles are assigned via Firebase Custom Claims by an Admin SDK call.
- No user can assign their own role.
- Role assignments must be approved by the Safety Officer and logged in the audit trail.
- Moderator roles must be revoked within 24 hours of employment termination.

### 8.3 Principle of Least Privilege

- Assign the minimum role needed for the job function.
- Temporary elevated access (e.g., a moderator needing to access the legal queue for a specific case) must be time-bounded and logged.
- `getRateLimitStatus` is admin-only by policy but currently has no in-function role check — callers must verify role externally until this is fixed.

---

## 9. Audit Log Policy

### 9.1 What is Logged

Every moderation action must produce an audit log entry with:
- Timestamp (UTC)
- Actor UID and role
- Action type (reason code from Section 3.4)
- Target content ID or account UID
- Before-state and after-state (or reference to content snapshot in legalHolds)
- Case ID if associated with an escalation

### 9.2 Audit Log Integrity

- Audit logs must be append-only. No audit record may be updated or deleted.
- Firestore security rules must deny `update` and `delete` on audit log collections from all callers including Admin SDK.
- Audit log integrity must be verified quarterly by the Engineering Safety Contact.

### 9.3 Retention

- Audit logs: retained for 7 years minimum.
- CSAM incident audit logs: retained permanently (no expiry).
- Rate limit counter documents: expire automatically after 2 days per TTL field. **Note:** No automated cleanup job exists — a scheduled Cloud Function purge should be created (see Section 14).

### 9.4 Access

- Audit logs are readable by `trust_safety_admin`, `legal_admin`, `safety_officer`, and `engineering_safety` roles.
- Full audit log export requires Safety Officer approval.
- Law enforcement requests for audit log data must be routed through Legal Counsel.

---

## 10. Minor Protection Model

### 10.1 Minimum Age Policy

- **Under 13:** Blocked from the platform. Profile is hidden from all non-guardian discovery. No DMs permitted with non-guardians. Age is enforced via `minorAgeBand=blocked` tier. **COPPA compliance requires this tier to be treated as a hard exclusion.**
- **13-15 (tierB):** Restricted DM, restricted discovery, no adult DM.
- **16-17 (tierC/tierD):** Reduced restrictions but adult-to-minor DM still blocked for unrelated parties.

### 10.2 COPPA Compliance

The Children's Online Privacy Protection Act (COPPA) applies to users under 13. The Amen platform must:

- Not collect personal information from users under 13 without verifiable parental consent.
- Not knowingly allow users under 13 to create accounts without a guardian-linked consent record.
- Delete personal data for users under 13 upon parent/guardian request within 30 days.
- Not use data from users under 13 for advertising targeting.

**Current Status:** Age assurance relies on user-submitted `minorAgeBand` values validated by `setMinorFlag`. There is no third-party age verification. This is a COPPA compliance risk. Until a verifiable parental consent system is in place, the platform should not knowingly permit under-13 users. See Section 14.

### 10.3 Guardian Consent

Guardian relationships are stored in `guardianIds` on minor user profiles. A guardian relationship grants:
- Visibility of the minor's profile
- Ability to be in the same sanctuary space
- Exemption from the adult-to-minor DM block

**Current Gap:** There is no separate guardian consent record verification step. A Firestore write by an admin can whitelist any adult as a guardian without the minor or a legitimate guardian approving. This must be remediated before launch (see Section 14).

**Guardian Consent Process (Intended):**
1. Minor account signals a guardian UID.
2. System sends a consent request to the guardian's account/email.
3. Guardian explicitly accepts.
4. Only upon acceptance is `guardianIds` updated.
5. All consent records are retained in an immutable audit log.

### 10.4 Age Assurance Known Gaps

- `setMinorFlag` allows `isMinor=false` with `minorAgeBand='13_15'` simultaneously — inconsistent state is writable.
- Unknown-age users in non-DM paths (sanctuary_invite, reply) may have their `requiresReview=true` flag dropped silently if no `safetyAlert` write occurs.
- The grooming risk reply counter has no time-window filter — old interactions count toward the threshold indefinitely.

### 10.5 Discovery Controls

- Under-13 profiles: hidden from all non-guardian discovery.
- 13-17 profiles with `discoverySafetyMode` enabled: hidden from non-guardian adult searches.
- `validateMinorDiscovery` enforces these rules server-side.

---

## 11. AI Moderation Provider

### 11.1 Current Configuration

- **Text moderation:** NeMo Guard (NVIDIA)
- **Image/video moderation:** Vision LLM (provider TBD — confirm before launch)
- AI moderation is a pre-publication first-pass filter only.
- All AI flags result in `held` status pending human review — no AI-only removals.

### 11.2 AI Moderation Limitations

- AI moderation is not a CSAM detector. It is a content classifier. Confirmed CSAM detection requires human review and follows Section 4b.
- AI classifiers have known false positive and false negative rates. Human review is mandatory for all enforcement actions.
- AI moderation does not apply to DM content (only post/comment content). DM safety relies on the minor protection and grooming detection systems.

### 11.3 AI Moderation Failure Mode

If the AI moderation service is unavailable:
- Content submission falls through to a held state (fail-safe: content is queued for human review).
- Do not switch to a pass-through mode under AI outage.
- Engineering Safety Contact must be notified within 1 hour of AI moderation service outage.

---

## 12. Firebase Secrets Management

### 12.1 Secret Inventory

| Secret | Storage | Rotation Frequency |
|---|---|---|
| `CLAUDE_API_KEY` | Firebase Secret Manager | Rotated 2026-06-05; rotate every 90 days |
| `APPLE_MUSIC_DEVELOPER_TOKEN` | Firebase Secret Manager | Required for AdaptiveComposer CF; not yet configured |
| `FIREBASE_WEB_API_KEY` | Firebase Secret Manager | Required for deploy step; confirm status |
| NCMEC ESP credentials | Legal Counsel secure storage | On registration (not yet obtained) |

### 12.2 Secret Rotation Procedure

1. Generate new secret value using the appropriate provider's console.
2. Write the new value to Firebase Secret Manager via `firebase functions:secrets:set SECRET_NAME`.
3. Redeploy affected Cloud Functions to pick up the new secret version.
4. Verify the affected functions are healthy after redeployment.
5. Revoke the old secret version after 24 hours of confirmed healthy operation.
6. Log the rotation in the audit trail with timestamp and operator.

### 12.3 Secret Access Policy

- No secrets are hardcoded in source code.
- No secrets are committed to git. The `.gitignore` is configured to exclude `.env` and secret files.
- Only Cloud Functions with an explicit `runWith({ secrets: [...] })` declaration can access secrets.
- Secret access is auditable via Firebase Secret Manager access logs.

---

## 13. Data Retention

### 13.1 Retention Schedule

| Data Type | Retention Period | Deletion Method |
|---|---|---|
| Published posts | Until user-deleted + 30 days | User-initiated + CF retention job |
| Deleted posts (no hold) | 30 days after deletion | Automated CF scheduled job |
| DM messages | Until conversation deleted + 30 days | User-initiated + CF retention job |
| Audit logs | 7 years minimum | Manual only, Safety Officer approval |
| CSAM incident audit logs | Permanent | No deletion permitted |
| Legal hold content | Indefinite pending disposition | Legal Counsel disposition only |
| Rate limit counters | 2 days (TTL field set) | Automated (scheduled purge CF — PENDING BUILD) |
| User accounts (deleted) | 90 days then purge | Automated CF |
| Under-13 user data | Upon verified parent request, 30 days | Manual by Safety Officer + Engineering |
| Analytics / usage logs | 13 months | Automated |

### 13.2 Legal Hold Exemption

Any document with `legalHold=true` is exempt from all automated deletion and retention purges. All retention Cloud Functions must check this field before deleting any document. This is a hard requirement.

### 13.3 GDPR / CCPA Deletion Requests

- User data deletion requests must be fulfilled within 30 days.
- Exceptions: data under legal hold, data required for NCMEC reporting, audit log entries (anonymized on request).
- Deletion requests are processed by the Engineering Safety Contact with Safety Officer sign-off.

---

## 14. Open Questions

The following items are unresolved and must be addressed before the platform launches to the public. Each has a designated owner and priority.

| # | Issue | Priority | Owner | Status |
|---|---|---|---|---|
| OQ-01 | **BROKEN IMPORT (P0):** `blockMuteReport.js` imports `escalateChildSafety` from `../moderation/escalation` but that function is not exported there. Fix: either export `escalateChildSafety` from `escalation.js` (reconcile the two implementations) or update the import to use `moderatePost.js`. | P0 | Engineering Safety Contact | OPEN |
| OQ-02 | **DUPLICATE ESCALATION SCHEMAS (P0):** `escalation.js createLegalHold` and `legalHold.js createLegalHold` write to `legalHolds` with different schemas. These must be reconciled into a single canonical implementation before launch. | P0 | Engineering Safety Contact | OPEN |
| OQ-03 | **NCMEC ESP Registration:** Safety Officer must register Amen as an Electronic Service Provider with NCMEC before `reportToNcmec` stub can be replaced. Required for legal compliance. | P0 | Safety Officer + Legal | OPEN |
| OQ-04 | **CSAM Fast-Path Fallback Silent Failure:** The `catch` block on CSAM escalation logs the error but does not page or re-throw. A failing escalation silently degrades CSAM content to the normal review queue. Fix: add pager/alert on escalation failure. | P0 | Engineering Safety Contact | OPEN |
| OQ-05 | **Guardian Consent Verification Gap:** `_hasApprovedRelationship` does not verify a consent record — admin writes can whitelist unrelated adults as guardians. Requires a guardian consent record system before COPPA-adjacent minor features go live. | P0 | Engineering + Legal | OPEN |
| OQ-06 | **App Check Status:** Firebase App Check enforcement status is unknown. App Check prevents unauthorized API calls. Confirm: is App Check enforced in production? Is the migration from older attestation complete? | P1 | Engineering Safety Contact | OPEN |
| OQ-07 | **Assign Safety Officer:** The CSO/Safety Officer role must be assigned to a named individual before launch. Required for NCMEC registration and Severity 1 incident handling. | P0 | Founder / Leadership | OPEN |
| OQ-08 | **COPPA Verifiable Parental Consent:** No third-party age verification or verifiable parental consent system exists. Until this is in place, the platform must not knowingly permit under-13 users. Document the age-gate mechanism (e.g., date-of-birth gate at signup that blocks under-13). | P0 | Engineering + Legal | OPEN |
| OQ-09 | **`setMinorFlag` Inconsistent State:** `isMinor=false` + `minorAgeBand='13_15'` is writable without error. Add validation to reject contradictory combinations. | P1 | Engineering | OPEN |
| OQ-10 | **Reply Grooming Counter Time Window:** The safetyAlerts query counting prior adult-to-minor replies has no time window filter. Old interactions inflate the count. Add a 90-day lookback window. | P1 | Engineering | OPEN |
| OQ-11 | **Unknown-Age Non-DM Path Silent Drop:** Sanctuary invite and reply paths for unknown-age users return `requiresReview=true` but do not write a `safetyAlert` record. Add the safetyAlert write for these cases. | P1 | Engineering | OPEN |
| OQ-12 | **`getLegalHoldEvidence` Role Check:** The function has no in-function role assertion. Add a role guard before any evidence retrieval. | P1 | Engineering | OPEN |
| OQ-13 | **Rate Limit Race Condition:** The check-then-increment pattern is not atomic. Replace with a single Firestore transaction that reads and conditionally increments. | P2 | Engineering | OPEN |
| OQ-14 | **Rate Limit Counter Purge Job:** No scheduled Cloud Function purges expired rate limit counter documents. Build a scheduled purge job. | P2 | Engineering | OPEN |
| OQ-15 | **`getRateLimitStatus` Role Check:** The function has no in-function role check. Add a role assertion. | P2 | Engineering | OPEN |
| OQ-16 | **CHILD_SAFETY_CATEGORIES Alias Gaps:** `blockMuteReport.js` does not include `minor_abuse`, `trafficking`, or `child_sexual_exploitation_material` as recognized child safety category strings. Add these aliases. | P1 | Engineering | OPEN |
| OQ-17 | **Anon Mode Safety:** Anonymous mode behavior under minor protection rules is unspecified. Define: can an anonymous user DM a minor? Can a minor post anonymously? | P1 | Safety Officer + Engineering | OPEN |
| OQ-18 | **Org Verification for Churches:** No organization verification process exists for church accounts. A malicious actor could create a fake church account and contact minors through ministry features. Define and implement org verification. | P1 | Trust & Safety Lead | OPEN |
| OQ-19 | **`snapshotHash` Non-Determinism:** `JSON.stringify(contentSnapshot)` key ordering is non-deterministic across JS runtimes, making the SHA-256 hash unreliable for tamper detection. Use a canonicalized serialization method. | P2 | Engineering | OPEN |
| OQ-20 | **No SLA Alerting on Escalation Queue:** Cases in `escalationQueue` have no automated operator notification. Wire a Cloud Function trigger or alerting rule that pages the Safety Officer when a new escalation is created. | P1 | Engineering | OPEN |

---

## 15. Pre-Launch Safety Checklist

This checklist must be signed off before any public launch (beta or App Store).

### 15.1 Critical Blockers (P0 — Must Be Green Before Any Launch)

- [ ] **OQ-01:** Broken `escalateChildSafety` import fixed and tested
- [ ] **OQ-02:** Duplicate `createLegalHold` schemas reconciled into one implementation
- [ ] **OQ-03:** NCMEC ESP registration completed OR written Safety Officer memo confirming manual reporting procedure is in effect and understood by Legal Counsel
- [ ] **OQ-04:** CSAM escalation failure alerting wired
- [ ] **OQ-05:** Guardian consent verification system built or feature flagged off with under-18 DM fully blocked
- [ ] **OQ-07:** Safety Officer role assigned to a named individual
- [ ] **OQ-08:** COPPA age gate at signup blocks users who declare age < 13; legal review confirms approach

### 15.2 High Priority (P1 — Must Be Green Before Public Beta)

- [ ] **OQ-06:** App Check enforcement status confirmed and documented
- [ ] **OQ-09:** `setMinorFlag` inconsistent state validation added
- [ ] **OQ-10:** Grooming counter time window added (90-day lookback)
- [ ] **OQ-11:** Unknown-age non-DM safety alert write added
- [ ] **OQ-12:** `getLegalHoldEvidence` in-function role assertion added
- [ ] **OQ-16:** CHILD_SAFETY_CATEGORIES alias gaps filled
- [ ] **OQ-20:** Escalation queue SLA alerting wired

### 15.3 Process Checks

- [ ] At least two trained moderators on-call at all times (or off-hours escalation procedure documented)
- [ ] Safety Officer emergency contact method documented and tested
- [ ] Moderation dashboard tested and accessible to assigned moderators
- [ ] Legal Counsel briefed on manual NCMEC reporting procedure
- [ ] Audit log integrity verified by Engineering Safety Contact
- [ ] Firestore security rules verified: `legalHolds` denies all client and Admin SDK `update`/`delete`
- [ ] Firebase App Check status confirmed
- [ ] All P0 open questions assigned to named owners with target resolution dates
- [ ] This runbook reviewed by Legal Counsel
- [ ] This runbook reviewed and signed by Safety Officer

---

*This runbook is a living document. It must be reviewed quarterly and updated whenever a significant system change, incident, or policy decision affects any section. Changes require Safety Officer approval.*

*Last updated: 2026-06-11 | Branch: safety-hardening*

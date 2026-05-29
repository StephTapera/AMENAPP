# AMEN — Abuse Detection Spec

**Version:** 1.0.0
**Date:** 2026-05-29
**Branch:** berean/ui-consolidation-v1
**Agent:** Safety Agent 8 — Signal Extraction & Review Queue

---

## Scope & Philosophy

AMEN is a faith community. The people who use it are often in spiritually and emotionally vulnerable states — seeking healing, community, guidance, and God. That context makes exploitation on this platform uniquely harmful and uniquely distinct from abuse on generic social apps.

This spec defines the signal extraction layer that identifies potential abuse patterns and routes them for **human review**. It does not define enforcement. No content is automatically removed. No account is automatically restricted. All signals flow to the `safetyReviews` collection where human moderators or a future human-in-the-loop system act on them.

**This agent builds pipes and flags. Policy enforcement decisions are explicitly out of scope and marked `[DECISION REQUIRED]` throughout this document.**

---

## 1. Threat Taxonomy

### 1.1 Spiritual Abuse

**Definition:** Communication that uses faith language, spiritual authority, or religious framing to coerce, isolate, demean, or control another person.

**Why it is hard:** Legitimate pastoral exhortation, prophetic language, and theological correction can superficially resemble coercion. Detection must be signal-based (patterns + velocity + relationship context), not single-message binary. Denominational variation is significant — e.g., some traditions use "rebuke" and "correction" language normally; others would not.

**`[DECISION REQUIRED]:`** Define the boundary between:
- Acceptable pastoral correction ("I believe God is calling you to...")
- Coercive control ("God told me you must leave your family")
- The app must document a denomination-agnostic definition before auto-routing or restricting

**Signal patterns detected:**
- Commands to cut off family/friends framed as divine instruction
- Claims of exclusive divine authority over a specific recipient ("Only I can save you")
- Accusations of spiritual failure used to pressure compliance ("rebellious spirit", "unsubmissive")
- Faith-based shame spirals ("God is disappointed in you unless you...")
- Isolation tactics dressed as sanctification ("your friends are pulling you away from God")

**Surfaces scanned:** DMs, group chats (Spaces), comment threads, prayer wall comments.

---

### 1.2 Financial Exploitation

**Definition:** Using faith, spiritual obligation, or ministry framing to extract money from users.

**Why it is distinct from legitimate tithing/giving:** Legitimate generosity on AMEN is opt-in, community-visible, directed to verified organizations, and never conditioned on personal spiritual favor. Exploitation patterns are characterized by:
- Direct solicitation in private messages
- Promises of spiritual return on financial investment ("sow a seed and God will multiply it")
- Urgency or shame pressure
- Unverified payment methods (personal Venmo, Zelle, crypto wallets)
- Fake ministry/charity accounts soliciting funds

**`[DECISION REQUIRED]:`**
- Threshold for money-mention rate per sender per day that triggers a review event
- Whether verified nonprofit orgs (Covenant tier) are exempt from financial signal scanning
- Whether to surface a "Giving Safety Notice" to the recipient when signals are detected

**Signal patterns detected:**
- Seed faith / prophetic giving language in direct messages
- Payment method mentions (Zelle, Venmo, CashApp, Wire, Crypto, Bitcoin) in DM context
- Conditional blessing language ("give to unlock", "donate to receive prayer")
- Ministry fund solicitation with personal payment details
- Urgency + money combination ("urgent need" + payment method in same or adjacent message)

**Surfaces scanned:** DMs, Spaces messages, prayer request comments.

---

### 1.3 Romance Fraud

**Definition:** A user constructs a false romantic/spiritual relationship with rapid intimacy escalation, then requests money or attempts to move the target off-platform.

**Why faith apps are a high-risk surface:** Users on AMEN are often seeking genuine connection and spiritual partnership. "God brought us together" framing is both normal in this community and a key fraud script. Trust is extended quickly in faith contexts.

**Signal patterns detected:**
- Rapid divine-destiny romantic framing ("God sent you to me", "you are my covenant partner")
- Financial emergency narrative + payment request in same conversation thread
- Off-platform push pattern ("let's continue this on WhatsApp/Telegram/Signal/email")
- Combination of expressed deep intimacy + recent account creation (`[DECISION REQUIRED]`: age threshold)
- Geographic inconsistency claims that create victim sympathy (stranded, hospitalized, military abroad)

**`[DECISION REQUIRED]:`**
- Whether account age < N days + romance signal should trigger a different (elevated) severity
- Whether to surface an in-app "Be aware of romance fraud" notice to recipients (opt-in? auto?)
- Off-platform push: auto-insert a safety notice into the conversation vs. queue for review only

**Surfaces scanned:** DMs only (most romance fraud occurs in private channels).

---

### 1.4 Mass-DM Spam

**Definition:** High-velocity unsolicited direct messaging, typically for solicitation, phishing, or low-quality promotion.

**Signal patterns detected:**
- Sender DM count exceeding velocity threshold within a rolling time window
- Same or near-identical message body sent to N distinct recipients
- Combination: high-velocity + financial/off-platform signals = elevated severity

**`[DECISION REQUIRED]:`**
- `MASS_DM_THRESHOLD_PER_HOUR` — current placeholder: 20 messages/hour. Needs product decision.
- `MONEY_MENTION_THRESHOLD_PER_DAY` — current placeholder: 5 messages/day. Needs product decision.
- Whether to implement a per-sender daily DM cap at the send layer (separate from detection)
- Whether rate-exceeded senders get silent queuing (current approach) or an in-app warning

**Surfaces scanned:** `conversations/{id}/messages/` subcollection.

---

## 2. Signal Extractors

Signal extraction runs in the `abuseDetectionSignals.js` Cloud Function triggered on new DM messages. Extraction is **metadata-only by default** — full message content is not stored in the review event unless a future policy decision enables it.

### 2.1 Pattern-Match Signal Extraction

```
extractSignals(text: string) → [{ type, patternHint, confidence }]
```

- Runs all `SIGNALS` regex batteries (spiritualAbuse, financialExploitation, romanceFraud)
- Returns an array of matching signal objects
- Each signal carries a base `confidence: 0.7` (pattern match only, no ML scoring)
- Multiple signals of the same type in one message increase severity, not confidence per signal

### 2.2 Velocity Signal Extraction

```
checkDMVelocity(senderId: string) → void (side-effect: queues review if threshold exceeded)
```

- Uses `users/{senderId}/dmVelocity/{hourKey}` for per-hour counting
- Hourly key format: `YYYY-MM-DDTHH` (UTC ISO string slice)
- If count >= `MASS_DM_THRESHOLD_PER_HOUR`: queues a `mass_dm_velocity` review event at `high` severity
- Counter is written regardless of threshold to maintain accurate velocity state

### 2.3 Confidence Scoring

| Signal Source | Base Confidence | Notes |
|---|---|---|
| Single regex pattern match | 0.7 | Prone to false positives without context |
| Two or more pattern matches in one message | 0.7 per signal; severity elevated to `high` | |
| Velocity threshold exceeded | 0.9 | Objective count — low false-positive rate |
| `[FUTURE]` ML classifier score | TBD | Reserved for v2 enhancement |

**`[DECISION REQUIRED]:`** Whether confidence threshold for content snippet storage should be 0.9 (as currently coded) or a different value.

---

## 3. Risk Event Stream — `safetyReviews/{reviewId}` Schema

```
safetyReviews/{reviewId}
  type:                 "abuse_signal"             // string — fixed for this system
  senderId:             string                      // UID of message sender
  recipientId:          string | null               // UID of recipient (null for velocity-only events)
  surface:              "dm" | "mass_dm_velocity" | "prayer_wall" | "space_message"
  signals: [
    {
      type:             "spiritualAbuse" | "financialExploitation" | "romanceFraud" | "mass_dm"
      confidence:       number (0.0 – 1.0)
    }
  ]
  severity:             "medium" | "high"
  detectedAt:           Timestamp (server)
  status:               "pending" | "reviewed" | "dismissed" | "escalated" | "actioned"
  requiresHumanReview:  true                        // always true — no auto-action
  contentSnippet:       string | null               // [DECISION REQUIRED] — null by default
  reviewedBy:           string | null               // moderator UID, set on review
  reviewedAt:           Timestamp | null
  reviewNotes:          string | null
  actionTaken:          string | null               // free-text, set by moderator
```

### 3.1 Severity Derivation

| Condition | Severity |
|---|---|
| One signal matched | `medium` |
| Two or more signals matched in same message | `high` |
| Velocity threshold exceeded | `high` |
| `[DECISION REQUIRED]` Romance fraud + account age < N days | `critical` (proposed) |

### 3.2 Firestore Rules Requirement

`safetyReviews` must be server-write-only from client perspective. Reads restricted to `isAdmin()` or `isModerator()`. This collection is already categorized as "Server-only (no client read)" in the threat model. **No rule changes are made by this agent — see `[DECISION REQUIRED]` below.**

**`[DECISION REQUIRED]:`** Whether moderators should be able to query by `senderId` or `status` without exposing cross-user data to non-admin moderators. Field-level or collection-group security may be needed.

---

## 4. Velocity Heuristics

### 4.1 Mass-DM Velocity

**Current placeholder threshold:** 20 DMs / hour per sender.

**`[DECISION REQUIRED]:`**
- What is the legitimate maximum DM rate for a community leader or ministry account?
- Should verified Covenant-tier organizations have a higher or unlimited threshold?
- Is a per-hour window the right granularity, or should a rolling 15-minute window be used?
- Should the first threshold breach produce a `medium` event and a second breach within 24 hours produce `high`?

### 4.2 Money-Mention Rate

**Current placeholder threshold:** 5 money-mention signals / day per sender.

**`[DECISION REQUIRED]:`**
- A pastor discussing tithing in a group Spaces channel may legitimately mention money frequently. Is the surface (DM vs. group) a sufficient discriminator?
- Should money-mention rate be measured per sender-recipient pair (1:1 exploitation) rather than per sender total?
- What is the lookback window — rolling 24 hours? calendar day UTC?

### 4.3 Cross-Signal Velocity Escalation

**Proposed (not yet implemented):** If a sender triggers both a pattern-match signal AND a velocity signal within 1 hour, the combined severity should be escalated to `critical` and routed to a priority review queue.

**`[DECISION REQUIRED]:`** Approve this cross-signal escalation logic and define the priority queue destination.

---

## 5. What This System Intentionally Does NOT Do

This is an explicit list of actions this agent does not perform and this system must never perform automatically without explicit human decision:

1. **No automatic content removal.** No message is deleted, hidden, or suppressed by this system.
2. **No automatic account restriction.** No user is muted, suspended, rate-limited, or banned by this system.
3. **No automatic notifications to either party.** The sender is not warned. The recipient is not alerted. (Subject to future policy decision.)
4. **No content stored by default.** Message content is not written to the review event unless a `[DECISION REQUIRED]` policy explicitly enables it with appropriate access controls.
5. **No cross-user signal aggregation.** Signals from one conversation are not combined with signals from another to build a "risk profile" — that would require a separate data retention and privacy policy decision.
6. **No profiling of religious practice.** Signal matching on spiritual language is used only to detect exploitation — it is not used to score, rank, categorize, or profile users' spiritual expression or beliefs.
7. **No denominational enforcement.** Signals are intentionally broad and defer to human judgment for theological context.

---

## 6. Community Health Metrics (Read-Only Dashboard Signals)

The following metrics should be surfaced on an internal moderator/trust-safety dashboard. These are read signals only — they do not drive any automated action.

| Metric | Firestore Source | Update Frequency |
|---|---|---|
| Open `safetyReviews` count by severity | `safetyReviews` where `status == "pending"` | Real-time |
| Review queue age (oldest pending event) | `safetyReviews` order by `detectedAt` ASC | Real-time |
| Signal type breakdown (week over week) | Aggregated from `safetyReviews` by `signals[].type` | Daily scheduled |
| Top signal senders (anonymized count) | Aggregated from `safetyReviews` by `senderId` | Daily scheduled |
| False positive rate (dismissed / total reviewed) | `safetyReviews` where `status == "dismissed"` | Weekly |
| Mass-DM velocity events per day | `safetyReviews` where `surface == "mass_dm_velocity"` | Daily |
| Financial exploitation signals per day | Filter by `signals[].type == "financialExploitation"` | Daily |
| Romance fraud signals per day | Filter by `signals[].type == "romanceFraud"` | Daily |
| Spiritual abuse signals per day | Filter by `signals[].type == "spiritualAbuse"` | Daily |
| Mean time to review (MTTR) | `reviewedAt - detectedAt` aggregated | Weekly |

**`[DECISION REQUIRED]:`**
- Who has read access to this dashboard? Internal trust-safety team only? Community leaders?
- Should aggregate (non-PII) community health metrics be published to users as a transparency report?
- How long should resolved `safetyReviews` documents be retained? (Privacy / legal hold consideration)

---

## 7. Decision Table — All `[DECISION REQUIRED]` Items

| ID | Category | Question | Current Placeholder / Default | Decision Owner |
|---|---|---|---|---|
| D-01 | Spiritual Abuse | Define the denomination-agnostic boundary between pastoral correction and coercive spiritual abuse | No definition — deferred to human review | Product + Faith Advisory |
| D-02 | Spiritual Abuse | Should spiritual abuse signals in DMs from accounts with Pastor/Leader role claims be escalated? | No escalation — same as all users | Trust & Safety team |
| D-03 | Financial | `MONEY_MENTION_THRESHOLD_PER_DAY` — how many money-mention signals per sender per day before queuing? | 5 | Trust & Safety team |
| D-04 | Financial | Are verified Covenant-tier organizations exempt from financial signal thresholds? | No exemption | Product + Legal |
| D-05 | Financial | Should recipients see a "Giving Safety Notice" when financial signals are detected in their DMs? | No notice — silent queue | Product + UX |
| D-06 | Romance Fraud | Should account age < N days + romance signal trigger `critical` severity? | Not implemented | Trust & Safety team |
| D-07 | Romance Fraud | Off-platform push detection: silent queue vs. in-conversation safety card? | Silent queue only | Product + UX |
| D-08 | Mass-DM | `MASS_DM_THRESHOLD_PER_HOUR` — how many DMs per hour before queuing? | 20 | Trust & Safety team |
| D-09 | Mass-DM | Per-hour vs. rolling 15-min window for velocity counting? | Per-hour (UTC hourKey) | Engineering |
| D-10 | Mass-DM | Should senders receive an in-app warning when they approach the velocity threshold? | No warning | Product |
| D-11 | Content Storage | Should `contentSnippet` be stored in the review event for confidence >= 0.9? | null (not stored) | Legal + Privacy |
| D-12 | Scanning Scope | Should all DMs be scanned, or only DMs from accounts flagged by other signals? | All DMs scanned | Privacy + Engineering |
| D-13 | Escalation | Cross-signal escalation: velocity + pattern match in 1 hour → `critical` priority queue? | Not implemented | Trust & Safety team |
| D-14 | Auto-restriction | Define any conditions (if any) under which automatic restrictions may be applied in the future | None — human review only | Executive + Legal |
| D-15 | Dashboard Access | Who has read access to the moderator dashboard and aggregated metrics? | Internal team only | Product + Legal |
| D-16 | Data Retention | How long are resolved `safetyReviews` documents retained? | Indefinite (not defined) | Legal |
| D-17 | Transparency | Should aggregate safety metrics be published in a user-facing transparency report? | No | Product |
| D-18 | Firestore Rules | Should moderators query by `senderId` across reviews, and how is that access scoped? | Not defined | Engineering + Legal |

---

## 8. Related Files & Systems

| File | Role |
|---|---|
| `functions/abuseDetectionSignals.js` | Signal extraction + review event queuing (this agent) |
| `functions/safeMessagingGateway.js` | Pre-send harassment detection (DM layer — runs before delivery) |
| `functions/bereanGuardrails.js` | Input/output guardrails for the Berean AI assistant |
| `functions/bereanShield.js` | Berean AI shield and content safety |
| `functions/reportFunctions.js` | User-initiated content reports → `reports/` collection |
| `functions/contentModeration.js` | Downstream enforcement pipeline (triggered by reports) |
| `functions/rateLimiter.js` | Per-user rate limiting utility |
| `firestore.rules` | Access control for all collections including `safetyReviews` |
| `docs/security/THREAT_MODEL.md` | Broader attack-surface threat model |

---

*This spec is intentionally incomplete where marked `[DECISION REQUIRED]`. Those gaps must be closed by the policy team before any enforcement features are built on top of this detection layer.*

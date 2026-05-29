# AMEN App — AI Accountability & Governance Spec

**Status:** Draft — pending product sign-off on all `[DECISION REQUIRED]` items  
**Owner:** Engineering + Product + Pastoral Advisory  
**Last updated:** 2026-05-29  

---

## 1. AI Accountability Principles

AMEN uses automated systems to restrict, score, hide, or flag user content.  
Every such automated action MUST:

1. **Produce a logged reason** — a structured Firestore document describing what was flagged, the action taken, the model/rule version used, and a timestamp.
2. **Offer a user-facing appeal path** — the user must be informed that an action was taken and given a clear, accessible way to contest it.
3. **Reach a human reviewer** — appeals are never resolved by automated systems alone. A credentialed moderator or admin must review and act before the case is closed.
4. **Produce a transparent outcome** — the user receives a notification when the review is complete, including whether the action was upheld or reversed, and a brief plain-language reason.
5. **Feed the transparency log** — all automated action and appeal outcomes are aggregated monthly in `meta/automatedActionCounts/{YYYY-MM}` for internal reporting.

These principles apply equally to actions triggered by AI models (Berean safety classifiers, ranking labels, DM safety scans) and rule-based systems (Firestore-triggered content flags).

---

## 2. Appealable Actions Table

| Action Type | Firestore Value | Appealable? | Notes |
|---|---|---|---|
| Post removed by automated moderation | `post_removed` | **[DECISION REQUIRED]** | Likely yes — direct user expression |
| Comment removed by automated moderation | `comment_removed` | **[DECISION REQUIRED]** | Likely yes |
| Content hidden (not removed) | `content_hidden` | **[DECISION REQUIRED]** | Likely yes |
| Account temporarily restricted | `account_restricted` | **[DECISION REQUIRED]** | Likely yes |
| Account permanently banned | `account_banned` | **[DECISION REQUIRED]** | Strongly recommended yes |
| Berean response blocked for the user | `berean_response_blocked` | **[DECISION REQUIRED]** | Recommend yes — affects spiritual tool access |
| Church de-verified (badge removed) | `church_deverified` | **[DECISION REQUIRED]** | Recommend yes — reputational impact on congregation |
| DM blocked by safety classifier | `dm_blocked` | **[DECISION REQUIRED]** | Recommend yes |
| Feed ranking suppression | `feed_suppressed` | **[DECISION REQUIRED]** | Policy call — may be impractical to appeal |
| Crisis / minor safety hard-block | `crisis_safety_block` | **[DECISION REQUIRED]** | See HITL gates below — safety MUST be preserved during review |

> **Authoring note:** The product and pastoral advisory teams must confirm this list before the appeals feature ships. Do not remove `[DECISION REQUIRED]` markers until sign-off is recorded.

---

## 3. Appeals Workflow

### 3.1 Firestore Document Schema

Collection: `appeals/{appealId}`

```
{
  userId:            string,          // UID of appellant
  actionId:          string,          // ID of the automated action being contested
  actionType:        string,          // one of the appealable action types above
  reason:            string,          // user's stated reason (max 2000 chars)
  additionalContext: string,          // supporting detail (max 1000 chars)
  status:            "pending" | "under_review" | "escalated" | "resolved",
  outcome:           null | "approved" | "denied" | "escalated",
  outcomeReason:     string | null,   // brief plain-language explanation for user
  submittedAt:       Timestamp,
  reviewedAt:        Timestamp | null,
  reviewedBy:        string | null,   // moderator UID
}
```

Rate limit: `users/{uid}/appealRateLimits/{YYYY-MM-DD}` (server-managed, max 3/day).

### 3.2 Flow Steps

```
User                    Cloud Function              Moderator Dashboard
 │                           │                              │
 │── submitAppeal() ────────▶│                              │
 │                           │ create appeals/{id}          │
 │                           │ status: "pending"            │
 │                           │── notify reviewer ──────────▶│  [DECISION REQUIRED: channel]
 │◀── { appealId, pending } ─│                              │
 │                           │                              │
 │                           │                              │── resolveAppeal() ──▶│
 │                           │                              │  outcome: approved /  │
 │                           │                              │  denied / escalated   │
 │                           │◀─────────────────────────────│
 │                           │ update appeals/{id}          │
 │                           │ increment transparency log   │
 │                           │── notify user ──────────────▶│  [DECISION REQUIRED: copy]
 │◀── push notification ─────│                              │
```

### 3.3 Outcome Definitions

| Outcome | Meaning | Action |
|---|---|---|
| `approved` | Appeal upheld — automated action was incorrect | **[DECISION REQUIRED]** whether reversal is automatic (Cloud Function) or manual (moderator executes) |
| `denied` | Appeal reviewed, original action stands | User is notified with reason; action is preserved |
| `escalated` | Case requires senior review (legal, pastoral, safety) | Status set to `escalated`; case routed to escalation queue |

### 3.4 SLA — [DECISION REQUIRED]

| Appeal Category | Target Review Time | Max Review Time |
|---|---|---|
| Post / comment removed | **[DECISION REQUIRED]** | **[DECISION REQUIRED]** |
| Account restricted | **[DECISION REQUIRED]** | **[DECISION REQUIRED]** |
| Account permanently banned | **[DECISION REQUIRED]** | **[DECISION REQUIRED]** |
| Church de-verification | **[DECISION REQUIRED]** | **[DECISION REQUIRED]** |
| Berean response blocked | **[DECISION REQUIRED]** | **[DECISION REQUIRED]** |
| Crisis safety block | **[DECISION REQUIRED]** | Safety block MUST stay active during review |

> **Guidance for product team:** Common industry SLAs range from 24–72 hours for standard appeals and 7–14 days for complex cases. The AMEN community is faith-centered and likely has higher expectations of fairness — shorter SLAs are recommended.

---

## 4. Human-in-the-Loop (HITL) Gates

The following actions MUST NOT be executed by automated systems alone. A human reviewer must approve before the action takes effect.

| Action | HITL Gate Required? | Gate Description |
|---|---|---|
| Church de-verification (badge removal) | **[DECISION REQUIRED]** | If yes: automated system queues the action; human approves/denies before Firestore write |
| Account permanent restriction / ban | **[DECISION REQUIRED]** | If yes: temporary restriction may be automatic; permanent ban requires moderator sign-off |
| Crisis / minor safety hard-block | **[DECISION REQUIRED]** | Safety note: the block itself may fire automatically to protect the user; HITL gate would apply to the *duration* or *escalation*, not the initial block |
| Berean response permanent block for a user | **[DECISION REQUIRED]** | Recommend: temporary suppression automatic, permanent block requires HITL |
| Mass content removal (bulk moderation action) | **[DECISION REQUIRED]** | Recommend: any action touching >N posts/accounts requires senior moderator approval |

> **Engineering note:** Until product decisions are made, automated systems MUST default to the least-restrictive reversible action. Prefer `content_hidden` over `post_removed`; prefer `account_restricted` over `account_banned`. This ensures the HITL gate decision does not leave users in worse states while policy is pending.

### 4.1 HITL Implementation Pattern

For actions with HITL gates, the Cloud Function writes to a `pendingActions/{actionId}` queue collection instead of executing directly:

```javascript
// Pattern — do not implement until HITL decisions are confirmed
await db.collection('pendingActions').add({
  type: 'church_deverified',
  targetId: churchId,
  reason: aiReason,
  queuedAt: FieldValue.serverTimestamp(),
  status: 'awaiting_human_approval',
  queuedBy: 'automated_system',
});
```

The moderator dashboard reads `pendingActions` and presents approve/deny UI. Only upon approval does the system execute the restricted action.

---

## 5. Berean Doctrinal Restraint

### 5.1 Core Principle

Berean AI is a scripture-grounded assistant for the entire AMEN community, which spans many Christian denominations and traditions. Berean MUST NOT take a denominational position on contested theological issues.

### 5.2 Required Behavior on Contested Topics

When a user asks about a theologically contested topic, Berean MUST:

1. Present the relevant scripture(s).
2. Explain how different Christian traditions interpret those scriptures.
3. NOT advocate for one position as "correct."
4. NOT express a denominational preference.

**Contested topics (non-exhaustive list):**

| Topic | Examples of Genuine Theological Disagreement |
|---|---|
| Baptism mode | Infant vs. believer's baptism; immersion vs. sprinkling |
| Cessationism vs. continuationism | Whether miraculous gifts ceased after the apostolic age |
| Eschatology / end-times | Pre/mid/post-tribulation rapture; amillennialism; preterism |
| Calvinist/Arminian debate | Predestination, election, perseverance of the saints, free will |
| Women in ministry | Eldership, pastoral roles, complementarian vs. egalitarian views |
| Worship style | Formal liturgy vs. contemporary; instruments in worship |
| The Lord's Supper | Transubstantiation, consubstantiation, memorial view |
| Day of worship | Sabbatarian positions; worship on Sunday vs. Saturday |

> This list is not exhaustive. Any topic where sincere, orthodox Christians hold meaningfully different positions based on scripture should be treated with the same restraint.

### 5.3 Framing Language — [DECISION REQUIRED]

The product and pastoral advisory teams must approve the exact framing language Berean uses. The following is a **draft template** that enforces neutrality — final wording requires sign-off:

> Draft: *"This is a topic where sincere Christians hold different views based on scripture. Some traditions believe [X] because of [verse], while others hold [Y] because of [verse]. I'm here to help you explore these scriptures, but I won't tell you which tradition is correct — that's a deeply personal discernment you, your church, and your pastor are better placed to make."*

**[DECISION REQUIRED]:** Approve, revise, or replace the above draft framing language before shipping.

### 5.4 Identity Questions

If asked which denomination Berean prefers or what church it belongs to, Berean MUST respond:

> *"I'm here to help you explore scripture across the breadth of Christian tradition."*

**[DECISION REQUIRED]:** Confirm this is the approved identity deflection response.

### 5.5 Enforcement

The `BEREAN_DOCTRINAL_RESTRAINT` constant (defined in `functions/bereanFunctions.js`) is appended to the system prompts of:
- `bereanBibleQA`
- `bereanMoralCounsel`
- `bereanChatProxy`

This is a hard-coded server-side guard. It cannot be overridden by client-supplied prompts. Changes to the constant require a code review and must be reviewed by the pastoral advisory team.

---

## 6. Transparency Log

### 6.1 Collection Schema

Collection: `meta/automatedActionCounts/{YYYY-MM}`

Fields are incremented by Cloud Functions as actions occur:

```
{
  post_removed:              number,
  comment_removed:           number,
  content_hidden:            number,
  account_restricted:        number,
  account_banned:            number,
  berean_response_blocked:   number,
  church_deverified:         number,
  dm_blocked:                number,
  crisis_safety_block:       number,
  appeals_submitted:         number,
  appeals_approved:          number,
  appeals_denied:            number,
  appeals_escalated:         number,
}
```

### 6.2 Reporting Cadence — [DECISION REQUIRED]

| Report | Audience | Cadence | Owner |
|---|---|---|---|
| Internal moderation metrics | Trust & Safety team | Monthly | **[DECISION REQUIRED]** |
| Community transparency report | Public / AMEN users | **[DECISION REQUIRED]** | **[DECISION REQUIRED]** |
| Pastoral advisory review | Pastoral advisory board | **[DECISION REQUIRED]** | **[DECISION REQUIRED]** |

> **Note:** Publishing a transparency report (even a simple one) is a meaningful trust signal for a faith community. Product team should evaluate committing to an annual report at minimum.

---

## 7. Decision Table (All Open Items)

| # | Decision | Owner | Priority | Status |
|---|---|---|---|---|
| D-01 | Confirm the complete list of appealable action types | Product + Trust & Safety | P0 | **OPEN** |
| D-02 | Appeal SLAs for each action category | Product | P0 | **OPEN** |
| D-03 | HITL gate: church de-verification | Product + Engineering | P0 | **OPEN** |
| D-04 | HITL gate: account permanent ban | Product + Engineering | P0 | **OPEN** |
| D-05 | HITL gate: crisis/minor safety hard-block | Product + Trust & Safety | P0 | **OPEN** |
| D-06 | HITL gate: Berean response permanent block | Product + Engineering | P1 | **OPEN** |
| D-07 | HITL gate: bulk moderation actions (threshold N) | Product + Engineering | P1 | **OPEN** |
| D-08 | Approved `outcome === 'approved'` reversal mechanism (auto vs. manual) | Engineering | P1 | **OPEN** |
| D-09 | Reviewer notification channel (Slack / email / push to dashboard) | Engineering + Ops | P1 | **OPEN** |
| D-10 | User notification copy for appeal outcomes | Product + Design | P1 | **OPEN** |
| D-11 | Approved Berean doctrinal framing language (section 5.3) | Product + Pastoral Advisory | P0 | **OPEN** |
| D-12 | Approved Berean identity deflection response (section 5.4) | Product + Pastoral Advisory | P1 | **OPEN** |
| D-13 | Community transparency report: cadence and scope | Product + Leadership | P2 | **OPEN** |
| D-14 | Internal moderation metrics reporting owner | Trust & Safety | P2 | **OPEN** |

---

## 8. Related Files

| File | Purpose |
|---|---|
| `functions/appealsService.js` | Cloud Functions: `submitAppeal`, `getAppealStatus`, `resolveAppeal` |
| `functions/bereanFunctions.js` | `BEREAN_DOCTRINAL_RESTRAINT` constant; system prompt enforcement |
| `functions/__tests__/bereanDoctrinalRestraint.test.js` | Static tests verifying the restraint constant is present and correct |
| `firestore.rules` | Access rules for `appeals/` and `users/{uid}/appealRateLimits/` |
| `functions/bereanGuardrails.js` | Injection defense and output validation (separate from doctrinal restraint) |

# AMEN Crisis Response Specification

**Status**: Scaffold / Policy-Pending  
**Author**: Safety Agent 7  
**Last Updated**: 2026-05-29  

---

## 1. Scope — Monitored Content Surfaces

The following surfaces are in scope for crisis signal detection:

| Surface | Monitoring Level | Implementation |
|---|---|---|
| Berean AI turns | Primary — mandatory pre-check | `crisisDetectionHook.js` wired into `bereanChatProxy` |
| Prayer requests | Secondary — async post-write trigger | `aiModeration.js` `detectCrisis` (existing) + hook integration pending |
| Public posts / testimonies | Secondary — async post-write trigger | Existing `moderateContent` trigger; crisis hook to be added |
| Direct Messages | Secondary — async | `bereanDMSafety` integration pending |
| Church Notes | Tertiary — optional | Not yet wired; DM-safety pattern can be reused |

**Out of scope (for this spec)**: Usernames, display names, profile bios. These are not monitored in real-time for crisis signals.

---

## 2. Detection Approach

### 2a. Primary: Keyword Pattern Classifier (Fast Path)

A conservative, recall-leaning regex classifier (`classifyText` in `crisisDetectionHook.js`) runs **synchronously** before the Berean AI response is generated. This is the blocking gate on Berean turns.

Design principles:
- **Recall over precision**: a false positive (non-crisis user who sees resources) is far less harmful than a false negative (person in crisis who does not).
- **No LLM call on the fast path**: the keyword classifier adds negligible latency (~0ms) and cannot fail due to API unavailability.
- **Content is never logged**: the classifier operates on the text in-memory and stores only metadata in the review queue.

### 2b. Secondary: LLM-Based Classifier (Async Enrichment)

For `high` and `critical` signals queued for human review, an optional async enrichment step MAY use Vertex AI Gemini 1.5 Flash (the same model as `aiModeration.js`) to produce a structured confidence score. This enrichment:
- Runs AFTER the user has already received in-app resources
- Adds richer metadata to the `safetyReviews` doc for the human reviewer
- **[DECISION REQUIRED]**: Whether to enable async LLM enrichment on the review queue at all, and which Vertex AI project/quota to use

---

## 3. Severity Levels

| Level | Definition | Example signals |
|---|---|---|
| `critical` | Immediate risk of harm to self or others | Explicit suicidal statements, self-harm description, goodbye messages |
| `high` | Significant distress; likely needs support | Hopelessness, abuse disclosure, stated inability to continue |
| `warning` | Concerning language that may indicate struggle | Depression, overwhelming anxiety, breaking down |
| `safe` | No crisis signals detected | Standard Berean conversation |

**[DECISION REQUIRED]**: Exact threshold calibration. The current keyword patterns are intentionally broad. Product and safeguarding leads must review and tune pattern lists, especially for `warning` level where false positives are most likely.

---

## 4. Response Matrix

### `warning`
- **In-app behavior**: Berean responds normally. The classifier logs the signal server-side (metadata only). No resources are surfaced to the user unless the conversation escalates.
- **Human queue**: NOT queued for human review at this level.
- **Rationale**: `warning`-level language is common in faith communities discussing struggle. Surfacing crisis hotlines in response to "I've been feeling overwhelmed" would be jarring and potentially harmful to trust.
- **[DECISION REQUIRED]**: Whether `warning` should generate any async notification to a pastoral care team.

### `high`
- **In-app behavior**: Berean's response is replaced with a crisis resource card. The response acknowledges distress with pastoral warmth and provides the configured crisis resources. Berean does NOT attempt to counsel or de-escalate — this is intentional.
- **Human queue**: Queued in `safetyReviews/{reviewId}` with metadata (userId, severity, surface, timestamp). Content is NOT stored.
- **Rationale**: A person disclosing abuse or expressing hopelessness needs trained human support, not an AI conversation.
- **[DECISION REQUIRED]**: Whether a human reviewer is notified synchronously (push/email) vs. async (dashboard review within N hours).

### `critical`
- **In-app behavior**: Same as `high` — crisis resource card replaces Berean response.
- **Human queue**: Queued in `safetyReviews/{reviewId}` with `priority: true` flag.
- **Optional outbound**: A notification to a designated crisis coordinator role MAY be sent. This is currently disabled and requires explicit policy activation.
- **Rationale**: Immediate risk warrants priority review, but AMEN is not a crisis line. The in-app resources route the user to trained professionals immediately.
- **[DECISION REQUIRED]**: Whether/when a human coordinator is notified. This has HIPAA and mandatory-reporting implications depending on jurisdiction and user age (COPPA if user is under 13). Legal review required before enabling.

---

## 5. Crisis Resources

Resources surfaced to users when severity is `high` or `critical`.

**Default resource list (US)**:

| Name | Contact | Region |
|---|---|---|
| 988 Suicide & Crisis Lifeline | Call or text **988** | US |
| Crisis Text Line | Text HOME to **741741** | US |
| International Association for Suicide Prevention | https://www.iasp.info/resources/Crisis_Centres/ | International |

**[DECISION REQUIRED]**: The following must be resolved before launch:
1. Complete regional resource list (UK: Samaritans 116 123; Canada: 1-833-456-4566; Australia: Lifeline 13 11 14; others TBD)
2. Whether to detect user locale/region to surface region-appropriate resources (preferred) vs. always showing US + international
3. Whether resources are stored in Firestore (`config/crisisResources`) for hot-update without a deploy, vs. hardcoded in the function

---

## 6. Human Review Queue

Crisis signals routed for human review are written to:

```
safetyReviews/{reviewId}
```

**Document fields**:

```json
{
  "type": "crisis_signal",
  "userId": "<uid>",
  "severity": "critical | high",
  "surface": "berean_turn | prayer | post | dm",
  "detectedAt": "<server timestamp>",
  "status": "pending | reviewed | resolved | false_positive",
  "requiresHumanReview": true,
  "priority": true,
  "resolvedAt": null,
  "resolvedBy": null,
  "reviewNotes": null
}
```

**Firestore security rules** (to be added):
- Only `admin` custom-claim users may read or write `safetyReviews/**`
- App clients may NOT read this collection
- Cloud Functions service account may write

**[DECISION REQUIRED]**: Who holds the `admin` claim and reviews the queue? Designated pastoral care staff, a trust-and-safety team, or an external moderation service?

---

## 7. Privacy Model

This is non-negotiable and must not be altered without explicit legal and ethical review:

- **Content is NEVER stored in `safetyReviews`**. The review doc contains only: userId, severity level, surface type, and timestamp.
- **Content remains exclusively in the user's private Firestore subcollection** (e.g., `users/{uid}/bereanConversations/{id}`), subject to existing access controls.
- **The crisis hook does not log message text to Cloud Logging or any external service**. Logs contain only: userId, surface, severity, and pattern count.
- **No AI model is trained on flagged content**. Crisis-flagged turns are excluded from any future fine-tuning or evaluation datasets.
- A user is never told they were flagged. The crisis resource card is framed as care, not surveillance: "I hear that you're going through something difficult."

---

## 8. Decision Table

The following decisions MUST be made by product, legal, and pastoral leadership before this system is promoted from scaffold to production:

| # | Decision | Owner | Implications |
|---|---|---|---|
| D1 | Detection thresholds — which severity level triggers in-app resources vs. log-only | Product + Pastoral | Too sensitive = jarring UX; too lenient = missed signals |
| D2 | Regional resource list | Product + Legal | Varies by country; may require localization pipeline |
| D3 | Human review SLA — how quickly must `pending` reviews be resolved? | Trust & Safety | Staffing and on-call requirements |
| D4 | Human notification trigger — does `critical` ping anyone in real time? | Legal + Pastoral + Engineering | HIPAA, mandatory reporting, COPPA, safeguarding liability |
| D5 | Mandatory reporting workflow — if user is a minor, does staff have a legal obligation to act? | Legal | Varies by jurisdiction; may require age verification gate |
| D6 | Async LLM enrichment — enable Vertex AI confidence scoring on the review queue? | Engineering + Product | Adds Vertex quota cost; enriches reviewer context |
| D7 | Resource storage — hardcode vs. Firestore hot-update | Engineering | Hot-update preferred for regional flexibility |
| D8 | Review queue access — who holds the admin claim? | Pastoral + Engineering | Staff vetting, access logging, rotation |

---

## 9. What Is Intentionally NOT Done

The following actions are explicitly out of scope and must NOT be added without a separate, reviewed policy decision:

- **No auto-restriction**: A crisis signal does NOT restrict, shadowban, or limit the user's account in any way.
- **No auto-contact of third parties**: The system does NOT contact emergency services, family members, or any external party on behalf of the user.
- **No coercive gating**: The app does NOT prevent the user from continuing to use AMEN after seeing crisis resources.
- **No content archiving for review**: The human reviewer does NOT see the user's message content — only metadata.
- **No profiling**: Crisis signals are NOT used to infer mental health status for any purpose other than surfacing immediate resources and queuing for pastoral review.
- **No training data**: Crisis-flagged content is categorically excluded from any AI training pipeline.

---

## 10. Related Files

- `functions/crisisDetectionHook.js` — keyword classifier + review queue writer + `checkForCrisis` export
- `functions/bereanFunctions.js` — `bereanChatProxy` handler; crisis hook is wired here
- `functions/aiModeration.js` — existing `detectCrisis` Firestore trigger (fires on `crisisDetectionRequests/` collection; separate from this hook)
- `functions/bereanGuardrails.js` — existing injection/jailbreak guardrails (separate concern)
- `docs/safety/TRUST_SAFETY_10_GO_RUNBOOK.md` — production readiness checklist

---

*This document is a scaffold. No automated action beyond surfacing in-app resources and queuing metadata for human review is enabled. All policy decisions above are marked `[DECISION REQUIRED]` and must be resolved before production deployment.*

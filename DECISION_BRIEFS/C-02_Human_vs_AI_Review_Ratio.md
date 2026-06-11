# C-02: Human vs AI Review Ratio
**Group:** LATER (post-launch, within 90 days)
**Decision:** What percentage of flagged content items require human review vs. automated resolution?

---

## Recommended Answer
CSAM: 100% human review (NCMEC guidance requires it). Self-harm: AI detection + human escalation when confidence is below 90%. Hate speech / harassment: 80% human review. Routine spam / low-severity profanity filter hits: AI-only.

## Rationale
NCMEC guidance explicitly states that CSAM reports require human verification before filing — an AI false positive filed as a NCMEC CyberTipline report is a serious error that wastes law enforcement resources and may harm the accused. Self-harm content requires human judgment because context matters enormously (a post about overcoming depression reads very differently from an active crisis post). High-volume low-stakes content (spam, mild profanity) can be AI-only to keep the human queue tractable.

## What the code already does (file:line)
- `functions/moderation/escalation.js` — escalation pipeline categorizes by severity; CSAM flagged as `urgency: "critical"`
- `functions/ncmecReporter.js:60–115` — CSAM queue writes to `ncmecSubmissionQueue` for human operator review
- NeMo Guard pipeline (`functions/nvidiaClient.js`) — AI moderation first pass exists

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Recommended ratios | Add `requiresHumanReview: true/false` field to moderation queue based on category | Operational clarity |
| AI-only for everything except CSAM | Change escalation CF thresholds | Self-harm and harassment may be under-reviewed |
| 100% human review | No code change; staffing decision | Queue floods human reviewer; unsustainable |

## Legal consultation required?
NO — operational policy decision, though NCMEC guidance is effectively binding for CSAM review.

---
**Status:** ☐ OPEN (90-day post-launch deadline)
**Owner:** Safety Officer

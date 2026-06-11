# B-14: Berean AI Access Policy for Minors
**Group:** BEFORE-LAUNCH
**Decision:** What is the access policy for Berean AI features when the authenticated user is a minor? No confirmed age gate exists on Berean AI callables.

---

## Recommended Answer
Berean AI spiritual guidance features (scripture lookup, prayer prompts, devotionals) available to all ages. Berean AI counseling-adjacent features (grief, mental health, relationship advice) restricted to 16+ or require guardian visibility on sessions. Crisis routing (988 resources, pastoral alert) always enabled regardless of age.

## Rationale
Berean AI is a core product differentiator for the faith community. Blocking all AI for minors is overly restrictive and reduces the product's value for youth ministry. The distinction is between spiritual formation content (appropriate for all ages) and counseling-adjacent responses (appropriate for adults or with guardian oversight). A 13-year-old asking Berean AI about Psalm 23 is different from a 13-year-old asking about depression and coping with suicidal thoughts — the latter requires additional safeguards.

## What the code already does (file:line)
- `AMENAPP/AMENAPP/BereanConversationView.swift` — Berean conversation UI; no confirmed age gate in view
- `AMENAPP/SelahScripture/SelahAIAccessGate.swift` — Selah AI access gate references `isMinorSafe`
- Gap: No confirmed `ageTier` check found at the Berean AI callable entry point
- Gap: No confirmed "counseling-adjacent feature" category gate for minors in Berean AI backend

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Recommended tiered access | Add `ageTier` check in Berean AI callable; define counseling-adjacent category list | Balanced; requires category definition work |
| Fully available to all ages | No change | Counseling-adjacent AI responses to minors without guardrails |
| Blocked entirely for minors | Add `if isMinor: throw permission-denied` in Berean AI callable | Overly restrictive; breaks youth ministry use case |

## Legal consultation required?
NO — product and safety policy decision. Document the category definitions for counseling-adjacent vs. spiritual guidance.

---
**Status:** ☐ OPEN
**Owner:** Safety Officer + Product

# B-04: Anonymous Prayer Requests
**Group:** BEFORE-LAUNCH
**Decision:** Should users be able to submit anonymous prayer requests? If so, under what conditions?

---

## Recommended Answer
Allow anonymous prayer requests with: rate limiting (max 3/day per user), mandatory server-side moderation before posting, author identity stored server-side for legal hold and moderation purposes (only the display is anonymous), and crisis keyword auto-routing to pastoral contact regardless of the anonymous flag.

## Rationale
Anonymous prayer requests are a compelling faith-community feature — users with sensitive situations (addiction, mental health, relationship crises) may not post publicly under their own name but would benefit from community prayer. Completely blocking anonymity reduces this use case substantially. The key safeguards are: (1) identity is never truly hidden server-side — it is only hidden from display; (2) crisis routing cannot be skipped because the user chose anonymous; (3) rate limiting prevents anonymous content flooding and makes moderation tractable.

## What the code already does (file:line)
- No dedicated anonymous prayer request service found; likely handled by general post creation
- `functions/moderation/escalation.js` — escalation pipeline exists for all content types
- Gap: No confirmed anonymous prayer request flow; no confirmed rate limiter for anonymous posts
- Gap: Crisis keyword routing (for Berean AI / 988 resources) does not appear to have an explicit anonymous-post bypass check

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Allow with rate limit + moderation (recommended) | Add anonymous flag to prayer request post; CF moderation pre-post; rate limit CF | Balanced; requires CF build |
| Allow without restriction | Add anonymous flag only | Moderation gap; anonymous flooding; crisis routing bypass risk |
| Not allowed | No change (disable anonymous option in UI) | Simpler; loses meaningful faith-community use case |

## Legal consultation required?
NO — product and moderation policy decision.

---
**Status:** ☐ OPEN
**Owner:** Product + Safety Officer

# B-16: `chat_videos` Storage Path Write Access
**Group:** BEFORE-LAUNCH
**Decision:** Is there a Storage rule for the `chat_videos/{conversationId}/` path that restricts writes to conversation participants only?

---

## Recommended Answer
Add a Storage rule for `chat_videos` that: restricts write to conversation participants only (CF-enforced), enforces a MIME type allowlist (video/mp4, video/quicktime), and caps file size at a defined limit (recommended: 100MB). Participant validation must be CF-enforced, not client-side.

## Rationale
Without a Storage rule, any authenticated user can write a file to `chat_videos/{anyConversationId}/` — meaning they can inject media into conversations they are not a participant of. This is a direct privacy violation: a third party can push content into a private DM thread between two people who have nothing to do with them. It also creates a CSAM injection vector: an attacker could push CSAM into a victim's conversation, potentially causing the victim to be flagged.

## What the code already does (file:line)
- `storage.rules` — `chat_videos` path rule: not found during audit (gap confirmed)
- `functions/safeMessagingGateway.js` — DM message write goes through the gateway with ban check; video upload path may bypass gateway
- Gap: No Storage rule for `chat_videos/{conversationId}/` exists

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| CF-enforced participant check + rule (recommended) | Add Storage rule; add `validateChatVideoUpload` CF callable | Correct; prevents injection attacks |
| Client-enforced participant check | Add rule checking `request.auth.uid in resource.metadata.participants` | Metadata is client-controlled; bypassable |
| Block all DM video uploads | Deny writes to `chat_videos/` entirely | Feature disabled; safe but loss of functionality |

## Legal consultation required?
NO — technical security decision.

---
**Status:** ☐ OPEN
**Owner:** Engineering Lead

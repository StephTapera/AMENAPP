# C-11: Hidden Comment Moderation Trigger Confirmation
**Group:** LATER (post-launch, within 90 days)
**Decision:** Does a server-side comment moderation trigger exist in `Backend/functions/src/index.ts` or `v2functions.js`? The `functions/` directory audit did not find one.

---

## Recommended Answer
Search `Backend/functions/src/index.ts` and `v2functions.js` for a `moderateComment` trigger. If not found, implement it as a `onDocumentCreated` trigger on `posts/{postId}/comments/{commentId}` that routes through the NeMo Guard moderation pipeline.

## Rationale
Without a server-side comment moderation trigger, all comment content relies entirely on client-side pre-submission moderation (if any) or user reports. An attacker who bypasses the `addComment` callable (addressed in B-18) and writes directly to the comments collection will have their comment appear without any server-side moderation. Even if B-18's direct write block is in place, comments submitted through the callable should also have a server-side trigger that re-checks the content after creation (defense in depth).

## What the code already does (file:line)
- `functions/index.js` — `moderateComment` trigger not found in this file
- `Backend/functions/src/index.ts` — not searched during audit; Q-16 flags this as the potential location
- `functions/v2functions.js` — not confirmed to contain comment moderation trigger
- Gap: No confirmed `moderateComment` trigger exists; location unconfirmed

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Find existing trigger | Search `Backend/functions/src/index.ts`; document location | No code change if found |
| Implement `moderateComment` trigger | Add `onDocumentCreated` on `posts/{postId}/comments/{commentId}`; route to NeMo Guard | Required if not found |
| Accept no comment moderation trigger | No change | Comments bypass server-side moderation; CSAM/hate speech can appear in comments |

## Legal consultation required?
NO — technical security decision.

---
**Status:** ☐ OPEN (90-day post-launch deadline)
**Owner:** Engineering Lead

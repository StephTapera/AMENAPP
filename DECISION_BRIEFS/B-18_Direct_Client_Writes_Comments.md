# B-18: Direct Client Writes to Comments Collection
**Group:** BEFORE-LAUNCH
**Decision:** Do Firestore security rules prevent direct client writes to `posts/{postId}/comments/{commentId}` without going through the `addComment` callable?

---

## Recommended Answer
Confirm (or implement) a Firestore rule that denies all direct client writes to the comments collection. `allow create` on comments should require the write to originate from the Admin SDK (CF callable path only). Implement a `moderateComment` trigger if not already present.

## Rationale
If a client can write directly to the comments collection, the entire comment moderation pipeline is bypassed. Any attacker can post content, spam, or CSAM as a comment by writing directly to Firestore without going through the `addComment` callable. The callable enforces moderation; a direct write does not. This is a textbook moderation bypass gap.

## What the code already does (file:line)
- `firestore.rules` — comments rule needs verification; `allow create: if isAdminSDK()` pattern should apply
- Gap: No confirmed test of the comments Firestore rule from a direct iOS client write
- Gap: No confirmed `moderateComment` Cloud Function trigger found in `functions/` directory
- Note: B-11 covers the parallel gap for `moderationQueue`; this brief covers comments specifically

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Block direct client writes (recommended) | Confirm `firestore.rules` denies direct client write to `comments`; if not present, add it; add `moderateComment` CF trigger | Correct |
| Allow direct client writes | Change rules to `allow create: if isSignedIn()` | Moderation bypass; CSAM injection in comments |
| Disable comments | Remove comments feature at rules layer | Extreme; not appropriate |

## Legal consultation required?
NO — technical security decision.

---
**Status:** ☐ OPEN
**Owner:** Engineering Lead

# A-07: Storage Rules Deployment Status
**Group:** ANSWER-NOW (HARD BLOCKER)
**Decision:** Is `storage.rules` actually deployed to production, and do the rules cover the `post_media`, `chat_videos`, `profile_images`, `berean/ocr_queue`, and `creator/users` paths?

---

## Recommended Answer
Run `firebase deploy --only storage --dry-run` immediately to confirm deployment status. If not deployed or if paths are missing, add rules for all absent paths with explicit allowlists and redeploy before any production launch.

## Rationale
If the hardened `storage.rules` file has never been deployed, every Storage path is accessible to any Firebase-authenticated user — including paths containing minor profile images and DM video uploads. If the rules are deployed but missing `chat_videos` and `post_media`, those features are silently blocked for legitimate users but the paths may be accessible via direct SDK calls. The audit confirmed `storage.rules` exists at the repo root but its production deployment status is unknown.

## What the code already does (file:line)
- `storage.rules` (root) — file exists; deployment status unconfirmed
- `firebase.json` — references `storage.rules` for deployment (confirm `"storage": { "rules": "storage.rules" }`)
- Gap: `chat_videos/{conversationId}/` — no rule found covering this path
- Gap: `post_media/{uid}/` — presence in rules unconfirmed by audit
- Gap: `profile_images/{uid}/` — separate from `profilePhotos/{uid}/{photoId}` path; rule presence unconfirmed

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Deploy current `storage.rules` after adding missing paths | Add rules for `chat_videos`, `post_media`, `profile_images`; deploy | Correct path; resolves all Storage security gaps |
| Deploy as-is (missing paths) | No rule changes; deploy existing file | DM video uploads silently fail or are open; chat privacy broken |
| Leave undeployed | No change | Default Firebase Storage rules: any authenticated user reads/writes anything |

## Legal consultation required?
NO — technical infrastructure decision.

---
**Status:** ☐ OPEN
**Owner:** Engineering Lead

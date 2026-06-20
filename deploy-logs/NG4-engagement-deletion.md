# NG-4 — engagement corpus deletion (DRAFT for founder approval)

**Client side is done** (`VertexAIPersonalizationService.recordEngagement` is now a no-op — the
`engagementEvents` write is removed). This stops corpus growth. The remaining steps are
server/ops and require human approval per CLAUDE.md (function deletion + data deletion).

## Why this is safe to delete
Wave 0 diagnostic — the corpus has **no live consumer**:
- `functions/aiPersonalization.js` `generatePersonalizedFeed` is the only reader — **zero Swift
  callers**, and its Vertex call is a `Math.random()` mock (`aiPersonalization.js:166-174`).
- `exportEngagementData` (`aiPersonalization.js:412`) is `onCall` with no automated trigger / no Swift caller.
- `getHybridFeed` / `getPredictedFeed` (Swift) are dead.

## Human steps (do NOT run unattended)
1. **Remove the Cloud Functions** (from repo root, targeted, us-east1 is the default for new/changed —
   but these are deletions): drop `generatePersonalizedFeed`, `exportEngagementData`, and the unused
   `filterSmartNotifications`/personalization exports from `functions/aiPersonalization.js` and the
   `require("./aiPersonalization")` block in `functions/index.js:49`. Deploy with explicit approval:
   `firebase deploy --only functions:default:generatePersonalizedFeed` (and siblings) — note that
   removing exports triggers orphan-deletion prompts; review them.
2. **Delete the data**: drop the `engagementEvents` collection (and `notificationEngagement` if also
   unused) via an admin script, after confirming step 1 removed all readers.
3. **Remove dead Swift** (follow-up cleanup PR): the 4 `recordEngagement` call sites in
   `PostCard.swift`, plus `exportEngagementData`/`exportToGCS`/`triggerModelTraining`/
   `getPredictedFeed`/`getHybridFeed`/`updateUserInterests`/`personalizationConsentGranted`.
4. **Privacy manifest**: once collection is gone, revisit the collected-data-types disclosure
   (Product Interaction / User-ID-linked) — likely removable. Privacy review territory.

## If you DON'T delete (keep for later)
The prior consent-gated, adult-only fail-closed guard (commit 79433d97) is the fallback — it kept
the write off by default. Deletion supersedes it; reverting this commit restores the guard.

# Agent-3 Rate Limiting & Spam Prevention Audit
**Date:** 2026-05-27  
**Auditor:** Agent-3 (6-agent comments system audit)  
**Scope:** Rate limiting and spam prevention across the comment submission pipeline.

---

## PHASE 1 — AUDIT FINDINGS

### Q1. Are there any rate limits today? Client-side throttle, server-side enforcement, or both?

**Finding: Two partial client-side layers exist. No server-side enforcement for RTDB comments.**

| Layer | Service | What it enforces | Bypassable? |
|-------|---------|-----------------|-------------|
| Firestore daily counter | `NewAccountRestrictionService` | Per-account-age daily limits (e.g., 5/day newborn, 200/day mature) | Yes — counter written from client; direct RTDB write bypasses entirely |
| In-memory min-delay + per-60s | `InteractionThrottleService` | 6 comments per 60 s, 10-second min delay between comments | Yes — in-memory, resets on app restart, no per-post window |
| Post slow-mode | `InteractionThrottleService.commentCooldownRemaining` | Per-post configurable cooldown (0 = off) | Yes — stored in `UserDefaults`, trivially clearable |

**Missing before this audit:**
- No rolling 60-minute window
- No per-post rolling window
- No duplicate-text detection
- No cross-post spam signal
- No mention-bomb or link-spam signals
- No countdown UX for rolling-window blocks (only for slow-mode)

---

### Q2. Where does rate-limit state live?

| State | Storage | Reset mechanism |
|-------|---------|----------------|
| Daily comment count | `Firestore: user_rate_limits/{userId}` — `"commenting"` field | Resets when `date` key differs from today (checked in `getTodayUsageCount`, line 355) |
| In-flight dedup (P0-1) | In-memory `Set<String>` in `CommentService.inFlightCommentRequests` | Cleared in `defer` after each request |
| Slow-mode last-post time | In-memory `[String: Date]` in `InteractionThrottleService.lastCommentTimes` | Cleared on app restart |
| Throttle interaction history | In-memory `[String: [InteractionRecord]]` in `InteractionThrottleService.interactionHistory` | Pruned hourly; cleared on app restart |

**Evidence:**  
- `NewAccountRestrictionService.swift:355-375` — `getTodayUsageCount` reads `user_rate_limits/{userId}`  
- `InteractionThrottleService.swift:25-26` — `interactionHistory` dict  
- `InteractionThrottleService.swift:330` — `lastCommentTimes` dict  
- `CommentService.swift:82` — `inFlightCommentRequests` Set

---

### Q3. What signals could indicate spam?

**Existing signals (pre-audit):**  
- `InteractionThrottleService.swift:171-188` — 5+ different posts in 5 minutes → `.spam` threat level (prevents submission)  
- `InteractionThrottleService.swift:191-208` — 10+ interactions with same user's content in 10 minutes → `.brigading` (prevents submission)  
- `ContentRiskAnalyzer.swift:418-433` — `spamScamSignals` for cash-flips, phishing, impersonation (content-risk, not frequency-based)

**Missing before this audit:**  
- No normalized duplicate-text check across recent comments  
- No cross-post identical text signal  
- No mention-bomb signal (>5 @-mentions per comment)  
- No link-spam signal (>3 URLs per comment)  

---

### Q4. Is there a duplicate-detection check?

**Partial.** Two mechanisms existed:

1. **In-flight dedup** (`CommentService.swift:81-90`, lines 331-341): blocks double-tap on the exact same `{postId}|{userId}|{normalizedContent}` key while the network request is in flight. Uses `makeRequestId` (normalized content, stable across launches). This is a race-condition fix, not a spam check.

2. **InteractionThrottleService** has NO normalized-text duplicate check. It only counts per-target-post frequency.

**Gap:** A user can post the exact same comment text repeatedly as long as they wait 10 seconds between each, or post it to many different posts within a minute.

---

### Q5. How are limits surfaced to the user?

| Limit | UX before audit |
|-------|----------------|
| Daily Firestore limit (code -11) | `CommentsView.swift:2348-2350` — inline `rateLimitMessage` banner above composer; submit button disabled |
| Slow-mode (creator-set) | `CommentsView.swift:1019-1033` — orange "Comment in Xs" timer; button disabled via `cooldownRemaining > 0` |
| `InteractionThrottleService` throttle | NOT wired to CommentsView! `checkInteraction()` is never called from `CommentsView.submitComment()` or `CommentService.addComment()`. It exists but is not in the hot path. |

**Gap:** The most granular in-memory throttle (`InteractionThrottleService`) is not connected to the comment submission path. Only the daily Firestore check and the slow-mode check are wired.

---

### Q6. Are there different limits for new accounts vs trusted accounts?

**Yes, via `NewAccountRestrictionService`.** Five tiers exist:

| Tier | Age | Comment daily limit |
|------|-----|-------------------|
| Newborn | 0–2 days | 5/day |
| Infant | 3–6 days | 10/day |
| Young | 7–13 days | 20/day |
| Established | 14–29 days | 50/day |
| Mature | 30+ days | 200/day |

**Evidence:** `NewAccountRestrictionService.swift:113-119`

**Gap:** The daily limit is per-day (resets at midnight), not per-minute or per-hour. A mature user with 200/day could post all 200 in 200 seconds with no short-window throttle.

---

## PHASE 2 — SAFE FIXES APPLIED

### Fix 1: New `CommentRateLimiter` Swift actor

**File:** `AMENAPP/CommentRateLimiter.swift` (new file)

Implements rolling-window rate limiting and spam signals:

- **5 per rolling 60 s** (general); **2 per rolling 60 s** (new account: `< 7 days`)
- **30 per rolling 60 min** (general); **15 per rolling 60 min** (new account)
- **5 per post per rolling 10 min** (per-post anti-flood)
- Account age check via `Auth.auth().currentUser?.metadata.creationDate` (no async Firestore fetch needed)
- Spam signals (soft-warn — do not hard-block):
  - Duplicate text: normalized (lowercase, strip punctuation, collapse whitespace), last 10 submissions
  - Cross-post: same normalized text on 3+ different posts within 5 min
  - Mention bomb: > 5 @-mentions in one comment
  - Link spam: > 3 URLs in one comment
- `secondsUntilNextAllowed(isNewAccount:)` for countdown UI

### Fix 2: `CommentService.addComment` — wire `CommentRateLimiter`

**File:** `AMENAPP/CommentService.swift`

**Lines added after the existing `NewAccountRestrictionService.canComment()` check (line ~231):**

```swift
// ✅ [AGENT-3] CLIENT-SIDE ROLLING-WINDOW RATE LIMIT
let isNewAccount = CommentRateLimiter.currentUserIsNewAccount()
let rollingCheck = await CommentRateLimiter.shared.checkCanPost(
    postId: postId, text: content, isNewAccount: isNewAccount
)
switch rollingCheck {
case .failure(let rlError) where rlError.isHardLimit:
    throw NSError(domain: "CommentService", code: -20, …)
case .failure(let rlError):
    // soft spam signal — log and allow through
case .success:
    break
}
```

**After successful write (line ~533):**
```swift
await CommentRateLimiter.shared.recordSubmission(postId: postId, text: content)
```

Error code -20 is used (distinct from -11 daily limit) so `CommentsView` can distinguish the two.

### Fix 3: `CommentsView` — handle code -20 + countdown UX

**File:** `AMENAPP/CommentsView.swift`

Three changes:

1. **Error handler** (catch block, ~line 2348): handles `code == -20` by setting `rateLimitMessage = "Slow down — give the conversation room to breathe."` and calling `startCooldownTimer(remaining: retryAfter)` to show the existing countdown UI.

2. **Submit button disabled** (~line 1163): extended condition to also disable while `cooldownRemaining > 0`, so rolling-window blocks correctly disable the send button until the countdown reaches zero.

3. **Per-second timer** (~line 1419): added a 1-second `Timer.publish` `.onReceive` to drive the countdown display. Auto-clears `rateLimitMessage` when the cooldown expires (if message is the rolling-window message text). Only updates `currentTime` when `cooldownRemaining > 0` to minimise unnecessary redraws.

---

## PHASE 3 — VERIFICATION

### Files Changed

| File | Change |
|------|--------|
| `AMENAPP/CommentRateLimiter.swift` | **NEW** — 190-line Swift actor; `CommentRateLimitError` enum; `currentUserIsNewAccount()` helper |
| `AMENAPP/CommentService.swift` | +27 lines in `addComment()` to check and record rolling-window limiter |
| `AMENAPP/CommentsView.swift` | +14 lines: handle code -20, extend button disabled condition, add 1-second timer |

### Xcode Diagnostic Results

```
AMENAPP/CommentRateLimiter.swift   — 0 errors, 0 warnings
AMENAPP/CommentService.swift        — 0 errors, 0 warnings
AMENAPP/CommentsView.swift          — 0 errors, 0 warnings
```

### Manual Test Plan

**Scenario 1: General per-minute hard limit**
1. Sign in as a mature account (30+ days old).
2. Comment on a post 5 times in quick succession (within 60 s).
3. Expected: 6th attempt blocked. Rate limit banner appears: "Slow down — give the conversation room to breathe." Countdown timer shows "Comment in Xs". Send button disabled.
4. Wait for countdown to reach 0. Expected: Banner auto-clears, send button re-enables.

**Scenario 2: New-account per-minute limit (2/min)**
1. Sign in with an account created < 7 days ago (check `Auth.auth().currentUser?.metadata.creationDate`).
2. Comment on a post twice in < 60 s.
3. Expected: 3rd attempt blocked with the rolling-window banner and countdown.

**Scenario 3: Per-post 10-minute limit**
1. Comment on a single post 5 times over > 60 s (to avoid per-minute limit).
2. Expected: 6th comment on that post blocked with "You've commented a lot here" message.
3. Comment on a DIFFERENT post immediately after.
4. Expected: Allowed (different post bucket).

**Scenario 4: Duplicate text soft-warn**
1. Post the same comment text twice on different posts.
2. Expected: Second attempt goes through (soft-warn only) but a `dlog` line is emitted: `[CommentRateLimiter] Spam signal: You already posted that…`
3. Verify no crash or hard block.

**Scenario 5: Mention bomb**
1. Type a comment with 6+ @-mentions (e.g., "@a @b @c @d @e @f hello").
2. Expected: Soft-warn logged; comment still submits (spam signals are advisory).

**Scenario 6: Countdown clears banner**
1. Trigger the per-minute rate limit.
2. Wait for countdown to reach 0 (observe 1-second updates in the "Comment in Xs" label).
3. Expected: Banner disappears, button re-enables automatically — no tap required.

**Scenario 7: Slow-mode + rolling-window coexistence**
1. Have a post with slow-mode set to 30 s.
2. Post a comment; then immediately try another.
3. Expected: Slow-mode cooldown fires first (orange "Comment in Xs"). Rolling-window limit does not fire (only 1 of 5 quota used).
4. Try to post 5 more within 60 s. Expected: Rolling-window fires after 5th.

---

## Pre-existing Rate Limit Issues NOT fixed (out of scope for client-only fixes)

| Issue | Reason deferred |
|-------|----------------|
| `InteractionThrottleService.checkInteraction()` not wired to comment submission path | Would duplicate the rolling-window logic added by this agent; needs a coordinated refactor to avoid double-counting |
| Server-side RTDB rate enforcement | Requires Cloud Functions deployment |
| Daily Firestore counter is client-writeable (spoofable) | Server-side enforcement needed |

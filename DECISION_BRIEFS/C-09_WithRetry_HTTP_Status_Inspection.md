# C-09: `withRetry` HTTP Status Inspection
**Group:** LATER (post-launch, within 90 days)
**Decision:** Does `withRetry` in `retryHelper.js` inspect HTTP 429/5xx status codes, or only caught exceptions? Transient NIM API failures may not be retried.

---

## Recommended Answer
Update `withRetry` to inspect HTTP status codes (429, 500, 502, 503, 504) in addition to caught exceptions. Add exponential backoff with jitter for 429 responses specifically. Confirm fix with a unit test.

## Rationale
NVIDIA NIM (the moderation AI service called by `moderateUGC.js`) is a cloud API that can return HTTP 429 (rate limited) or 5xx (transient error) responses. If `withRetry` only retries on thrown exceptions and not on HTTP error status codes, a response with `{ status: 429, body: "rate limited" }` that doesn't throw will be treated as a successful empty moderation result — effectively silently failing and passing content through without moderation. This is a moderation bypass via API rate limiting.

## What the code already does (file:line)
- `functions/retryHelper.js` — `withRetry()` exists; HTTP status inspection not confirmed during audit
- `functions/nvidiaClient.js` — NVIDIA NIM client; calls `moderateUGC.js`
- Gap: No test confirming `withRetry` retries on 429 specifically

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Inspect HTTP status + exponential backoff (recommended) | Update `withRetry` to check `response.status`; add 429 backoff logic | Correct; prevents silent moderation bypass on rate limit |
| Keep as-is, accept current behavior | No change | 429 responses silently fail moderation; content passes through |
| Replace with Axios retry interceptor | Replace `withRetry` with axios-retry library | Mature solution; dependency addition |

## Legal consultation required?
NO — technical reliability decision.

---
**Status:** ☐ OPEN (90-day post-launch deadline)
**Owner:** Engineering Lead

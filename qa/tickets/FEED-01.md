# FEED-01 — Quote/repost optimistic update never rolls back on failure

- **Flow:** Feed action → quote repost
- **File:** `PostCard.swift:~3365-3371`
- **Severity:** broken-flow
- **Scope:** IN-SCOPE
- **Status:** OPEN (static, not runtime-verified)

**Expected:** Optimistic `hasReposted = true` / `repostCount += 1` is rolled back if `publishQuotePost` fails.
**Actual:** The callback sets `hasReposted = true` and increments `repostCount` immediately without awaiting the publish result or catching errors, so a failed quote still shows as succeeded.

**Static repro:** No `await`/`catch` around the publish call in the quote callback; state is mutated unconditionally.

**Suspected fix:** Await `publishQuotePost`; on error roll back `hasReposted`/`repostCount` and surface an error toast (match the like-action rollback pattern already used elsewhere in `PostInteractionsService`).

# C-10: `aiModeration.moderateContent` Fail-Closed Audit
**Group:** LATER (post-launch, within 90 days)
**Decision:** Does `aiModeration.moderateContent` use a fail-closed pattern (exact-match safe/unsafe check) or a fail-open pattern (regex `!/unsafe/i.test(result)` that passes anything not explicitly labeled unsafe)?

---

## Recommended Answer
Confirm `aiModeration.moderateContent` uses exact-match checking (`result === "safe"` returns true; anything else returns false — fail closed). If it uses the `!/unsafe/i.test()` pattern, fix it: a result of `"error"`, `"unknown"`, `""`, or `null` should all be treated as unsafe.

## Rationale
`aiModeration.moderateContent` is exported from `index.js` and overwrites `contentModeration` at line 300. Its fail-closed posture determines how the entire moderation pipeline behaves on ambiguous AI responses. The `!/unsafe/i.test(result)` pattern passes any result that doesn't contain the word "unsafe" — including `"error"`, empty string, or a garbled NIM API response. An adversary who can cause the NIM API to return an error could thereby bypass moderation entirely. The correct pattern is an allowlist: only `result === "safe"` passes.

## What the code already does (file:line)
- `functions/index.js:300` — `aiModeration.moderateContent` export (overwrites `contentModeration`)
- Gap: Internal implementation of `aiModeration.moderateContent` fail-closed posture not confirmed during audit
- Gap: Whether the `!/unsafe/i.test()` pattern or exact-match is used is unconfirmed

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Confirm exact-match fail-closed | Read `aiModeration.js`; verify the pattern; add unit test | Correct; minimal effort |
| Fix from regex to exact-match | Change `!/unsafe/i.test(result)` to `result === "safe"` | Fixes silent bypass on error responses |
| Accept regex pattern | No change | NIM API errors pass content without moderation |

## Legal consultation required?
NO — technical security decision.

---
**Status:** ☐ OPEN (90-day post-launch deadline)
**Owner:** Engineering Lead

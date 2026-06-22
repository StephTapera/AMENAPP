# B-09: Unauthenticated Read of Public Posts (OPEN-5)
**Group:** BEFORE-LAUNCH
**Decision:** Should public posts be readable by unauthenticated users? The OPEN-5 flag in the Firestore rules acknowledges this is an intentional open question.

---

## Recommended Answer
For launch, gate all reads behind `isSignedIn()` unless SEO is a stated launch requirement. If SEO is required, implement a CF-served proxy that strips author identity and age-sensitive metadata (especially `ageTier`, `isMinor`, `birthYear`, `churchId`) before unauthenticated reads rather than exposing raw Firestore documents.

## Rationale
Unauthenticated access to raw Firestore documents means any web scraper, research bot, or bad actor can download all public posts without creating an account. This includes posts from minor accounts whose `ageTier` field may be visible in the document, enabling targeted outreach outside the app. COPPA specifically restricts collection of personal data from children by "any means" including web scraping. The SEO benefit of public posts is real but does not require exposing the full document structure — a CF proxy can serve SEO-friendly HTML while stripping sensitive fields.

## What the code already does (file:line)
- `firestore.rules` — OPEN-5 comment in rules header: unauthenticated read intentionally left open
- Gap: No CF-served proxy for unauthenticated post reads exists in the current `functions/` directory
- Gap: No field-stripping logic for unauthenticated reads found

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Gate all reads behind auth (recommended for launch) | Change `firestore.rules` OPEN-5 to require `isSignedIn()` | No SEO; safest option |
| CF proxy strips PII | Build CF that reads Firestore and returns sanitized JSON; Firestore rule blocks direct unauthenticated read | Correct long-term solution; requires build effort |
| Allow raw unauthenticated reads | No change; remove OPEN-5 comment | COPPA risk; minor data exposed |

## Legal consultation required?
NO — product decision with COPPA implications. COPPA analysis is straightforward: unauthenticated reads of minor posts is prohibited.

---
**Status:** ☐ OPEN
**Owner:** Product (SEO decision) + Engineering Lead (proxy build if SEO required)

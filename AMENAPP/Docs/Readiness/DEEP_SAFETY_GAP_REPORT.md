# Deep Safety Gap Report

Generated: 2026-06-16
Scope: Module B deep data, safety, device, AI, abuse, moderation, accessibility, notification, and cost surfaces.
Verdict standard: UNVERIFIED is not PASS. Source-level fixes are not production fixes until deployed by a human.

## Changes Made In This Pass

| Area | File | Change | Lane |
|---|---|---|---|
| AI prompt-injection | `AMENAPP/AMENAPP/Backend/functions/src/bereanChatProxy.ts` | Removed client-controlled `systemPromptSuffix` append. | 🟢 fixed source / 🟡 deploy |
| AI prompt-injection | `AMENAPP/AMENAPP/Backend/functions/src/bereanChatProxyStream.ts` | Removed client-controlled `systemPromptSuffix` append. | 🟢 fixed source / 🟡 deploy |
| App Check | `AMENAPP/AMENAPP/Backend/functions/src/bereanChatProxy.ts` | Changed non-stream callable to `enforceAppCheck: true`. | 🟢 fixed source / 🟡 deploy |
| Secrets | `AMENAPP/AMENAPP/Config.xcconfig` | Removed committed Google Maps API key value. | 🟢 fixed source / 🟡 rotate/restrict |

## Abuse Threat Model

| Threat Actor | Primary Controls Found | Gap | Lane |
|---|---|---|---|
| Spam bot / flooder | Berean rate limits and some App Check enforcement exist. | Not all callables proven App Check enforced; comment/message rate-limit tests not found. | 🟡 |
| Email/phone enumerator | No direct public lookup proof found. | Search/invite/contact sync non-oracle behavior UNVERIFIED. | 🟡 |
| Scraper | Firestore rules contain signed-in reads for public-ish surfaces. | Pagination caps/listener bounds not comprehensively verified. | 🟢/🟡 |
| Harasser/doxxer | Blocked-user checks exist in comments and conversations; moderation queue exists. | PII-in-content warning/hard block not fully verified across composer/message flows. | 🟢/🟡 |
| Adult targeting minors | Age-tier and minor DM rules exist. | Legal threshold/open questions remain in rules header. | 🔴/🟡 |
| Prompt-injection attacker | Server prompts contain spiritual-authority guardrails; suffix injection fixed. | Client-supplied history/context still not source-visibility checked server-side. | 🟢/🟡 |
| Paywall bypass | Entitlement fields blocked in rules; StoreKit manager exists. | Stripe vs Apple IAP compliance remains decision brief. | 🔴 |
| Function/cost overloader | AI rate limits, quota, max message length exist. | Fanout caps, link-preview SSRF, upload/transcode caps need targeted verification. | 🟡 |
| Compromised mod / insider | Moderation audit log and CF-only writes exist. | Reason-code enforcement and least-privilege tiers not fully verified in UI/functions. | 🟡 |

## Comment, Message, Reply Safety

| Gate | Status | Evidence / Gap | Lane |
|---|---|---|---|
| Report path on every post/comment/message/profile/space | UNVERIFIED | Report/moderation collections and views exist; every surface not checked. | 🟢 |
| Block path on every identity | UNVERIFIED | `blockedUsers` rules and block enforcement exist; every identity surface not checked. | 🟢 |
| Block enforced server-side | PARTIAL PASS | Rules check blocks for comments/conversations; notification suppression not proven. | 🟡 |
| Moderation queue exists or high-risk UGC disabled | PASS source | `moderationQueue`, `moderationDecisions`, content safety services exist. | 🟡 deploy |
| Comment/message rate limits | UNVERIFIED | AI rate limits found; UGC write rate limits not proven. | 🟡 |
| PII detection before post | UNVERIFIED | Smart comment/moderation services exist; hard PII block not proven. | 🟢/🟡 |
| Deleted/blocked/hidden content removed from cache/search/AI | UNVERIFIED | Soft-delete and blocked checks exist in rules; cache/search/AI purging not proven. | 🟡 |
| Moderation fields backend-only | PASS source | Rules block client moderation field writes. | 🟡 deploy |

## Device, Permissions, Notifications, Widgets

| Gate | Status | Evidence / Gap | Lane |
|---|---|---|---|
| Clear permission strings | FAIL/PARTIAL | Camera and Contacts strings exist; mic/speech/location/photo strings missing from Info.plist search despite code references. | 🟢 |
| Denied fallback | UNVERIFIED | Not all permission flows audited. | 🟢 |
| Contacts not uploaded silently | UNVERIFIED | Contacts permission and manifest collection exist; explicit upload path not proven. | 🟡 |
| Location not required unnecessarily | UNVERIFIED | Location/context strings found; Info.plist location usage string not found. | 🟢 |
| Widgets/Live Activities hide private data | UNVERIFIED/FAIL risk | Prayer and intelligence Live Activity code exists; generic lock-screen proof missing. | 🟢/🟡 |
| Deep links re-check auth | UNVERIFIED | Multiple deep-link routers exist; auth recheck not comprehensively proven. | 🟢 |
| App Intents gated | UNVERIFIED | `INSendMessageIntent` declared; Siri/Spotlight private-content gating not proven. | 🟢/🔴 |
| Pasteboard silent reads | PASS partial | Writes to pasteboard found; no silent reads found in sampled search. | 🟢 |

## AI Safety

| Gate | Status | Evidence / Gap | Lane |
|---|---|---|---|
| No provider keys in iOS | PARTIAL PASS | AI provider keys are empty/commented; Google Maps key removed; YouVersion/Youtube client placeholders remain and must stay empty. | 🟡 |
| No private context without consent | UNVERIFIED | DM consent sheet exists; other AI contexts not fully consent-gated. | 🟢/🟡 |
| No blocked/deleted/private exposure | UNVERIFIED | Some block rules exist; AI source visibility not proven. | 🟢/🟡 |
| Prompt-injection mitigated | PARTIAL PASS | Removed client system suffix; system prompts guard authority claims. Client-supplied content still needs quote/visibility boundaries. | 🟢/🟡 |
| Crisis/medical/legal safeguards | PARTIAL PASS | Sensitive topic policy and safety validator exist; provider failure behavior not fully verified. | 🟡 |
| Final user confirmation before AI sends/posts/reports | UNVERIFIED | Action systems exist; no comprehensive confirmation proof. | 🟢 |
| AI memory clear/disable/do-not-use controls | PARTIAL PASS | Memory delete/toggle callables and context grants exist; all settings not verified. | 🟢/🟡 |

## Accessibility

| Gate | Status | Evidence / Gap | Lane |
|---|---|---|---|
| VoiceOver can complete onboarding/report/block/delete-account | UNVERIFIED | Many accessibility labels exist; no UI automation run. | 🟢 |
| Dynamic Type primary flows intact | UNVERIFIED | No preview/device validation performed. | 🟢 |
| Reduce Motion/Transparency respected | UNVERIFIED | Liquid Glass/motion surfaces require targeted audit. | 🟢 |
| No icon-only critical buttons | UNVERIFIED | Not exhaustively checked. | 🟢 |
| Sensitive prayer/reporting safe exit | UNVERIFIED | No global safe-exit proof found. | 🟢/🔴 |

## Cost and Abuse Controls

| Gate | Status | Evidence / Gap | Lane |
|---|---|---|---|
| AI quota limited | PASS source for Berean stream; partial for callable | Stream enforces rate and daily quota; non-stream enforces rate only. | 🟡 |
| Upload size/type limited | UNVERIFIED | Storage rules were not found in Xcode project listing. | 🟡 |
| Notification fanout capped | UNVERIFIED | Notification functions/routes exist; caps not verified. | 🟡 |
| Link previews safe / no SSRF | UNVERIFIED | Smart share/deep link functions exist; SSRF allowlist not verified. | 🟡 |
| Function retries idempotent | UNVERIFIED | Not audited exhaustively. | 🟡 |
| Budget alerts documented | FAIL doc-only before this pass | Added to human gate queue/deploy plan. | 🟡 |

## Deep Acceptance Gates

| Category | Status | Blocking? | Notes |
|---|---|---|---|
| PII | FAIL | Yes | User doc public/private split, live activity token logging, logs/analytics proof, and email/phone search tests remain. |
| UGC | FAIL | Yes | Report/block everywhere, UGC rate limits, PII detection, and notification suppression not fully proven. |
| Device | FAIL | Yes | Missing/UNVERIFIED permission strings and Live Activity/widget privacy proof. |
| Accessibility | UNVERIFIED | Yes for App Store readiness | Needs UI automation or manual VoiceOver/Dynamic Type pass. |
| Security | FAIL | Yes | App Check and prompt suffix fixed in source, but deploy/emulator proof and storage rules are missing. |
| AI | FAIL | Yes | Source-visibility and consent gates still incomplete/UNVERIFIED. |
| Cost/abuse | FAIL | Yes | Fanout/upload/link-preview/budget controls not verified. |

## Remaining Findings by Lane

| Priority | Lane | Finding | Owner Action |
|---|---|---|---|
| P0 | 🟡 | Deploy App Check and prompt-injection fixes to Berean functions. | Human deploy after tests. |
| P0 | 🟡 | Rotate/restrict exposed Google Maps key. | Google Cloud console. |
| P1 | 🟢 | Remove raw Live Activity push token logging. | Source patch. |
| P1 | 🟡 | Split public user profile from private owner data or emulator-test current schema. | Rules/schema owner. |
| P1 | 🟡 | Add Firestore emulator tests for email/phone/push-token/report/mod/admin access. | Backend owner. |
| P1 | 🟢/🟡 | Server-side AI source-visibility checks for private context. | AI/backend owner. |
| P1 | 🟢 | Add/verify missing purpose strings for mic/speech/location/photos if code paths are active. | iOS owner. |
| P1 | 🔴 | Decide Firebase tracking/ATT/App Store privacy labels posture. | Legal/product. |
| P1 | 🔴 | Decide Stripe vs Apple IAP for digital goods. | Legal/product. |

## Final Risk Rating

| Rating | Result |
|---|---|
| App Store risk | HIGH until privacy manifest, ATT, permissions, payment interpretation, and accessibility gates are reviewed. |
| Production risk | HIGH until P0 deploy gates, key rotation, emulator tests, and AI source-visibility checks are complete. |
| Recommendation | Not ready for App Store or broad TestFlight with sensitive-data features enabled. Limited internal TestFlight only with AI/contact/location/widgets/Live Activities behind OFF flags. |

## Verification

- Source-level changes were made only; no production deploy was performed.
- No Firebase emulator, npm test suite, Xcode build, device run, or UI automation completed yet.
- Remaining unknowns are intentionally marked UNVERIFIED rather than PASS.

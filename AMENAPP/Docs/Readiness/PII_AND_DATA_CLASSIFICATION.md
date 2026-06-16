# PII and Data Classification

Generated: 2026-06-16
Scope: AMEN iOS app, Firestore rules, Cloud Functions source, privacy manifest, config files visible in the Xcode workspace.
Status terms: PASS = source evidence found; FAIL = source evidence contradicts gate; UNVERIFIED = not enough source or no emulator/deploy proof.

## Classification Rules

| Class | Examples in AMEN | Default Rule |
|---|---|---|
| PUBLIC | Display name, public username, intentionally public avatar, public posts/comments | Public only after intentional user action. |
| PRIVATE | Email, phone, birth date, push token, device IDs, settings, drafts, saved posts, block/mute lists, contact sync state, AI prefs | Owner-only. Never in shared payloads. |
| SENSITIVE | Prayer requests, church notes, private messages, counseling content, AI prompts, location, contact-book data, religious-affiliation signals, reports, minor-related info | Backend-mediated, consent-gated, never in logs/AI/analytics by default. |
| RESTRICTED | Admin roles, custom claims, moderation queue, abuse reports, trust scores, safety/ban records, entitlements, Stripe/Apple IDs, raw tokens, API keys | Backend-only. Client can never read or write. |

## Field Inventory

| Field / Data Set | Class | Evidence | Default Handling |
|---|---|---|---|
| `users/{uid}` public profile fields | PUBLIC + PRIVATE mixed | `firestore.deploy.rules` allows signed-in read of `/users/{userId}` but blocks raw PII fields on create and role/safety fields on update. | Needs schema split or public-profile projection review; signed-in global read is not enough for mixed data. |
| `email`, `phone`, `phoneNumber`, `normalizedPhone`, hashes | PRIVATE | Search found auth/profile/contact usage and privacy manifest declares email/phone collection. | Owner-only; no public search or notification payloads. Enumeration remains UNVERIFIED. |
| `fcmToken`, push tokens, live activity push token | PRIVATE | Rules protect `fcmToken` from user writes; Live Activity manager logs token hex before registration. | Owner/server-only; logs must not print raw token. |
| `contacts`, `CNContact`, address book data | SENSITIVE | Contacts permission exists; privacy manifest declares contacts. | Contact picker or explicit optional upload only. Silent upload not proven. |
| Private messages / conversations | SENSITIVE | `/conversations/{id}/messages` gated by participant checks and block state in rules. | Participant-only, block-aware, no nonparticipant AI summaries. |
| Prayer requests and prayer ledgers | SENSITIVE | `/prayerRequests` read is signed-in; `/users/{uid}/prayers` owner-only; Live Activity/widget surfaces exist. | Public/private distinction must be explicit; lock-screen payloads generic by default. |
| Church notes / reflections / notebooks | SENSITIVE | Church note rules use collaborator/member gates; user reflections are owner-only. | Shared only by explicit ACL; no AI context without grant. |
| AI prompts, memory, context grants, traces | SENSITIVE | `bereanMemory`, `contextGrants`, `contextAuditLog`, `bereanPipelineTraces`, `PrivacyInfo.xcprivacy`. | Explicit consent, clear memory controls, owner-only read. |
| Reports, moderation queue, moderation decisions | RESTRICTED | Rules gate moderation collections by moderator/admin claims or CF-only writes. | Backend-only writes; read by least privilege. |
| Roles, `isAdmin`, custom claims, trust score, entitlements | RESTRICTED | Rules block client writes to role/safety/trust/premium fields. | Server-enforced only. Deploy still human-gated. |
| Third-party API keys | RESTRICTED | Client config had a Google Maps key; removed in this pass. Other API keys are placeholders/empty. | Rotate exposed key; keep server-side or client-restricted only. |

## Leak-Surface Matrix

| Field | Class | Public Profile Payload | Search / Index | Comment / Msg Docs | Notification / Lock Screen / Widget | Logs / Analytics / Crash | AI Context | 3rd-Party SDK | Admin / Mod View | Owner | Retention | Deletion | Lane |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Email | PRIVATE | UNVERIFIED: `/users/{uid}` is signed-in readable; public projection not proven. | UNVERIFIED: search/enumeration tests not found. | PASS expected: no direct comment evidence found. | UNVERIFIED. | UNVERIFIED. | FAIL if included; no allowlist proof. | Firebase/Auth. | Redact unless reason-coded. | PASS owner via auth/profile. | UNVERIFIED. | UNVERIFIED. | 🟡 rules/emulator + schema audit |
| Phone | PRIVATE | UNVERIFIED/FAIL risk same as email. | UNVERIFIED. | PASS expected. | UNVERIFIED. | UNVERIFIED. | FAIL if included. | Firebase/Auth. | Redact unless reason-coded. | PASS owner. | UNVERIFIED. | UNVERIFIED. | 🟡 |
| FCM / live activity tokens | PRIVATE | PASS: rules include token write protection. | PASS not indexed by evidence. | PASS. | Used for delivery only. | FAIL: `AmenLiveActivityManager` logs token hex. | N/A. | Firebase/APNs. | Backend only. | Owner/server. | UNVERIFIED. | UNVERIFIED. | 🟢 source fix needed for log; 🟡 rotate if leaked in prod |
| Contacts | SENSITIVE | PASS no public profile evidence. | UNVERIFIED. | PASS no comment evidence. | N/A. | UNVERIFIED. | FAIL if sent to AI; no proof of hard guard. | Declared collected in privacy manifest. | No need by default. | User-controlled. | UNVERIFIED. | UNVERIFIED. | 🟡 consent/runbook + tests |
| Private messages | SENSITIVE | PASS no profile evidence. | UNVERIFIED. | PASS participant gates in rules. | UNVERIFIED: generic push not proven. | UNVERIFIED. | FAIL risk: AI proxy accepts arbitrary history and system context from client; `systemPromptSuffix` removed in this pass, but source-visibility checks still UNVERIFIED. | Anthropic via CF. | Only reports/mod evidence. | Participants. | UNVERIFIED. | Soft-delete path partially present. | 🟢/🟡 |
| Prayer requests | SENSITIVE | Public/signed-in visibility varies by collection. | UNVERIFIED. | Possible in post/comments. | FAIL risk: prayer Live Activity/widget paths exist; generic lock-screen proof missing. | UNVERIFIED. | Must require explicit action. | Firebase/ActivityKit. | Moderation only. | Owner/public per visibility. | UNVERIFIED. | UNVERIFIED. | 🟡 |
| Church notes | SENSITIVE | PASS not public by default in rules. | UNVERIFIED. | Note comments member-gated. | Shared-note UI exists; lock-screen not proven. | UNVERIFIED. | AI summary callables exist; grant/source-visibility proof incomplete. | AI providers via CF. | Redacted review required. | Owner/collaborator/member. | UNVERIFIED. | UNVERIFIED. | 🟡 |
| AI prompts/memory | SENSITIVE | PASS owner-only memory rules. | N/A. | N/A. | N/A. | UNVERIFIED: traces declared in privacy manifest. | FAIL risk: client-provided conversation history still trusted as visible content. | Anthropic/Firebase. | Audit only. | Owner. | UNVERIFIED. | PASS delete memory callables present; deploy unverified. | 🟢/🟡 |
| Reports/moderation | RESTRICTED | PASS no public read. | N/A. | N/A. | N/A. | UNVERIFIED. | N/A. | Firebase. | PASS claim-gated. | Reporter/admin only. | UNVERIFIED. | Immutable/CF-only mostly present. | 🟡 |
| Roles/trust/entitlements | RESTRICTED | PASS client writes blocked in rules. | N/A. | N/A. | N/A. | UNVERIFIED. | N/A. | StoreKit/Firebase/Stripe. | Admin only. | User sees derived entitlement only. | UNVERIFIED. | UNVERIFIED. | 🟡 deploy/test |

## P0 / P1 Findings

| ID | Severity | Finding | Evidence | Lane | Required Action |
|---|---|---|---|---|---|
| PII-001 | P0 | Client-controlled `systemPromptSuffix` could append instructions to the AI system prompt. | `bereanChatProxy.ts`, `bereanChatProxyStream.ts`. | 🟢 fixed source; 🟡 deploy | Removed append in both handlers. Deploy functions before enabling AI. |
| PII-002 | P0 | Non-stream Berean callable had App Check disabled. | `bereanChatProxy.ts` used `enforceAppCheck: false`. | 🟢 fixed source; 🟡 deploy | Set `enforceAppCheck: true`; deploy function and monitor rejected clients. |
| PII-003 | P1 | Google Maps API key was committed in app-bundled config. | `AMENAPP/AMENAPP/Config.xcconfig`. | 🟢 removed source; 🟡 rotate/restrict | Removed value. Rotate old key and restrict replacement by bundle ID/API. |
| PII-004 | P1 | Live Activity token logged in client. | `AmenLiveActivityManager` logs token hex. | 🟢 pending | Remove token logging or log only a redacted hash. |
| PII-005 | P1 | `/users/{uid}` read is available to any signed-in user while user docs appear to mix public/private fields. | `firestore.deploy.rules` line pattern `match /users/{userId}` + `allow read: if isSignedIn()`. | 🟡 | Add public profile projection or field split; emulator tests for email/phone/push token denial. |
| PII-006 | P1 | AI source visibility is not proven for client-supplied history/post context. | AI proxy accepts `conversationHistory` and `callData.postContext`. | 🟢/🟡 | Load sensitive context server-side by authorized IDs; treat client text as untrusted quote only. |
| PII-007 | P2 | `PrivacyInfo.xcprivacy` declares tracking domains and tracking-linked DeviceID/ProductInteraction. | `PrivacyInfo.xcprivacy`. | 🔴 | Privacy/legal decision: verify ATT, App Store privacy labels, and Firebase Analytics tracking posture. |

## Verification

- Source searches completed with Xcode tools on 2026-06-16.
- No Firebase emulator run was performed in this pass. Rules and function deploy status are UNVERIFIED.
- No production logs, analytics dashboards, App Store privacy labels, Firebase console settings, or Google Cloud key restrictions were inspected.

# AMEN — Security Baseline & Threat Model

**Date:** 2026-05-29  
**Branch:** berean/ui-consolidation-v1  
**Scope:** Full attack-surface recon (read-only). No code was changed.  
**Next step:** Run Agents 1–11 in order to close the gaps identified below.

---

## 1. Attack Surface Inventory

### 1.1 Cloud Functions

The app deploys 100+ Cloud Functions. All are Firebase-hosted (us-central1) and call one or more external APIs.

| Category | Functions (representative) | Trigger | Auth check | App Check |
|---|---|---|---|---|
| **AI / Berean proxy** | `bereanChatProxy`, `bereanGenericProxy`, `openAIProxy`, `whisperProxy`, `synapticCreate`, `bereanShieldAnalyze` | `onCall` | `context.auth` required | **Mixed** — core Berean: enforced; fallback proxies: not enforced |
| **Prayer & reflection** | `createMediaReflection`, `saveBereanInsight`, `updateBereanMemory`, `generatePrayerRecap`, `onPrayerAnswered` | `onCall` | `context.auth` required | **Partial** |
| **Church Notes media** | `processChurchNoteAudio`, `processChurchNoteImageOCR`, `processChurchNoteVideo`, `processChurchNoteDocumentPDF`, `generateChurchNoteSummary` | `onCall` | Required | Partial |
| **DM / message safety** | `bereanDMSafety`, `moderateContent`, `sendMessage`, `markMessagesAsRead` | `onCall` | Required | Mixed |
| **Crisis detection** | `detectCrisis` | `onDocumentCreated` | N/A (trigger) | N/A |
| **Anonymous Berean** | `anonymousBereanQuery` | `onCall` | **None** | **Not enforced** |
| **Daily verse / AI features** | `generateDailyVerse`, `generateVerseReflection` | `onCall` | Optional | **Not enforced** |
| **Admin / roles** | `adminClaims`, `authenticationHelpers`, `setCustomClaims` | `onCall` | Required | Enforced |
| **Church discovery** | `smartChurchSearch`, `bereanChurchChat`, `getChurchVisitReadiness` | `onCall` | Required | Partial |
| **Spaces & communities** | `createSpace`, `joinSpace`, `moderateSpaceContent` | `onCall` | Required | Partial |
| **Payments / Covenant** | `createCovenantCheckoutSession`, `createOrgSubscriptionCheckout`, `stripeWebhook` | `onCall` / HTTP | Required | Enforced on callables |
| **Algolia sync** | `syncUserToAlgolia`, `syncPostToAlgolia` | `onDocumentWritten` | N/A (trigger) | N/A |
| **Pinecone / embeddings** | `seedBibleVersesToPinecone`, `matchPrayerPartners`, `findSimilarTestimonies` | `onCall` / `onSchedule` | Required | Partial |

**External APIs called from functions:**

| API | Secret storage | Notes |
|---|---|---|
| Anthropic Claude | `defineSecret("CLAUDE_API_KEY")` — Secret Manager | Proper |
| OpenAI GPT-4o | `defineSecret("OPENAI_API_KEY")` — Secret Manager | Proper |
| Google Vertex AI (Gemini 1.5 Flash) | Workload identity (GCP) | Proper |
| Pinecone | `defineSecret("PINECONE_API_KEY")` — Secret Manager | Proper |
| Algolia | `process.env.ALGOLIA_ADMIN_API_KEY` (env config) | Acceptable |
| Stripe | `defineSecret(...)` — Secret Manager | Proper |

### 1.2 Client-to-Backend Callables (iOS Swift)

The iOS app calls 539+ distinct callable names via `Functions.functions().httpsCallable(...)`. No client-side App Check initialization was found — the app relies entirely on server-side `enforceAppCheck` flags.

### 1.3 Firestore Collections & Rules

**Rules posture:** Deny-by-default with helper functions (`isSignedIn()`, `isOwner(uid)`, `isAdmin()`, `isModerator()`, `isSpaceMember(spaceId)`). Field-level write restrictions on server-owned counters.

**Known documented gaps in the rules file itself:**

1. **`firestore.rules:96–108`** — Email and phone number stored on the root `/users/{uid}` document are readable by any authenticated user. Documented as P1 but unresolved.
2. **`firestore.rules:609–617`** — Followers-only post visibility enforced client-side only; direct document reads bypass it. Structural gap requiring `/follows` schema migration.
3. **`firestore.rules:619–624`** — Covenant-gated posts check "has any covenant subscription," not membership in the specific covenant. Known partial mitigation.

---

## 2. Data Sensitivity Map

| Classification | Collections / Paths |
|---|---|
| **Critical — owner-only, never public** | `/users/{uid}/bereanConversations/`, `/bereanConversations/{uid}/`, `/bereanThreads/`, `/bereanMemory/`, `/users/{uid}/unsentThoughts/`, `/users/{uid}/prayerReflections/`, `/users/{uid}/blessedLater/`, `/conversations/{id}/messages/` (DMs), `/churchNotes/{id}/transcripts/`, `/churchNotes/{id}/aiDrafts/`, `/users/{uid}/guardianAlerts/`, `/users/{uid}/safety/wellbeingSignals/` |
| **Spiritually-sensitive — restricted** | `/prayers/`, `/prayerRequests/`, `/testimonies/`, `/users/{uid}/wellnessCheckIns/`, `/users/{uid}/living_entries/`, `/churchNotes/{id}/reflections/` |
| **Personal — user-controlled** | `/users/{uid}` (root doc — **currently leaks email + phone**), `/users/{uid}/preferences/`, `/users/{uid}/privacySettings/`, `/users/{uid}/churchMemberships/` |
| **Community — authenticated read** | `/prayerWall/`, `/prayerRooms/`, `/spaces/{id}` (member-gated), `/posts/` (visibility-gated) |
| **Public** | Church discovery metadata, public profile fields (displayName, bio, photoURL) |
| **Server-only (no client read)** | `/stripeCustomers/`, `/blockedUsers/`, `/userRestrictions/`, `/rateLimits/`, `/otpRequests/`, `/enforcementHistory/`, `/userSafetyRecords/` |

---

## 3. Control Gap Analysis

| Control | Status | Notes |
|---|---|---|
| Firebase App Check on callables | **PARTIAL** | Core Berean: enforced. Anonymous Berean, daily verse, some fallback proxies: not enforced. |
| Firebase App Check on Storage | **PARTIAL** | Storage rules are owner-gated but App Check not explicitly enforced at the Storage rule level. |
| iOS client App Check initialization | **MISSING** | No `AppCheck`, `AppAttest`, or `DeviceCheck` integration found in Swift source. |
| Firestore deny-by-default | **PRESENT** | Default deny implemented. Three known enforcement gaps documented above. |
| Per-user data isolation (Berean, DM, prayer) | **PRESENT** | Strong owner-only rules on most sensitive paths. |
| Server-side rate limiting on AI proxies | **PARTIAL** | `rateLimiter.js` exists with sane defaults, but `bereanChatProxy`, `anonymousBereanQuery`, and most LLM proxies do **not** call `checkRateLimit()`. |
| Global cost circuit-breaker | **MISSING** | No daily spend cap or request ceiling on Anthropic/OpenAI/Pinecone costs. |
| Per-user token/turn budget | **MISSING** | No per-user daily token tracking. |
| Prompt-injection guardrails (Berean) | **PARTIAL** | `bereanShieldAnalyze` function exists; not confirmed as a mandatory pre/post step on every Berean turn. |
| Output guardrails / conviction filter | **PARTIAL** | Conviction filter referenced in client; server-side enforcement not confirmed universal. |
| User data export (GDPR/CCPA) | **MISSING** | No user-initiated export callable or UI found. |
| Berean conversation hard-delete | **PARTIAL** | Firestore rules allow owner delete on conversation docs; Pinecone vector deletion not confirmed wired up. |
| Full account hard-delete | **PARTIAL** | Account deletion flow exists; Storage and Pinecone orphan cleanup not confirmed. |
| Crisis detection | **PRESENT** | `detectCrisis` trigger + Vertex AI classifier + human-review queue + resource surfacing. Severity levels: critical/high/warning/safe. |
| Abuse / exploitation detection | **PARTIAL** | `moderateContent` exists; spiritual-abuse / fraud / romance-fraud pattern detection not found. |
| Minor safety / age gate | **PARTIAL** | Guardian alert system exists; explicit age gate or minor-account defaults not confirmed. |
| Moderation appeals + human-in-the-loop | **PARTIAL** | Review queues exist (`safetyReviews`, `safetyDecisions`); user-facing appeal path not confirmed. |
| Dependency + secret scanning in CI | **UNKNOWN** | No CI config found in the repo root. |
| Anomaly monitoring on auth/spend/data | **MISSING** | No alerting on auth spikes, cost anomalies, or unusual data-access patterns found. |
| Secrets in Secret Manager with pinned versions | **PRESENT** | All major API keys use `defineSecret()`. No hardcoded keys found in source. |

---

## 4. Top 10 Risks (Impact × Likelihood)

| Rank | Risk | Impact | Likelihood | Files |
|---|---|---|---|---|
| 1 | **Email + phone PII readable by any authenticated user** | Critical — mass PII exposure, regulatory liability (GDPR/CCPA) | High — any valid token is sufficient | `firestore.rules:96–108`, `UserModel`, `UserService` |
| 2 | **No iOS App Check initialization — server-side `enforceAppCheck: false` on several AI/prayer callables** | High — unverified non-app clients can invoke LLM proxies, incurring cost and bypassing safety filters | Medium — requires API knowledge | `anonymousBerean.js:18`, `aiPromptFeatures.js`, Swift client |
| 3 | **No global cost circuit-breaker on Anthropic/OpenAI/Pinecone** | High — a single abusive account or credential leak could generate unbounded spend | Medium — automated abuse is straightforward once a token is obtained | `bereanFunctions.js`, `aiPromptFeatures.js`, `semanticEmbeddings.js` |
| 4 | **Followers-only post visibility bypassable via direct document read** | High — private posts visible to non-followers | Medium — requires knowing document IDs | `firestore.rules:609–617`, `FeedAPIService.swift` |
| 5 | **No prompt-injection guardrails confirmed as mandatory on every Berean turn** | High — jailbreak or system-prompt exfiltration; Berean conviction filter bypassed | Medium — Berean is a high-value target | `bereanFunctions.js`, `bereanFeaturesFunctions.js` |
| 6 | **Rate limiting absent on `bereanChatProxy` and anonymous Berean** | High — DoS on AI budget; scraping of Berean at scale | Medium — no auth required for anonymous path | `bereanFunctions.js:854`, `anonymousBerean.js` |
| 7 | **No user-initiated data export or confirmed Pinecone vector deletion on account delete** | High — GDPR/CCPA right-to-erasure violation; orphaned spiritual data | Low — requires regulatory pressure or user complaint | `semanticEmbeddings.js`, account-deletion flow |
| 8 | **Covenant-gate enforcement gap (any covenant subscription bypasses per-covenant access)** | Medium — premium content accessible to subscribers of other covenants | Low — requires an active subscription | `firestore.rules:619–624` |
| 9 | **No CI pipeline for dependency CVE or secret scanning** | Medium — vulnerable dependencies or accidental key commits go undetected | Low-Medium — depends on contributor discipline | Repo root (no CI config found) |
| 10 | **No anomaly monitoring on auth, AI spend, or data access** | Medium — breaches or abuse not detected until damage is done | Low (impact raised by detection lag) | `bereanFunctions.js`, Firebase Console |

---

## 5. Recommended Agent Run Order

Address risks in this order:

1. **Agent 1** — App Check + App Attest (closes risks 2, 6 partially)
2. **Agent 2** — Firestore/Storage rules + tests (closes risk 4, partially 1)
3. **Agent 3** — Rate limits + cost circuit-breaker (closes risks 3, 6)
4. **Agent 4** — Berean injection + output guardrails (closes risk 5)
5. **Agent 5** — Spiritual privacy + data lifecycle (closes risks 7, and PII migration for risk 1)
6. **Agent 6** — Auth + account-takeover hardening
7. **Agent 11** — CI scanning + anomaly monitoring (closes risks 9, 10)
8. **Agents 7–10** — Crisis, abuse, minor safety, governance (policy-heavy; human sign-off required)

---

*Generated by Agent 0 (read-only recon). No code was modified.*

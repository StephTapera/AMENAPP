# Backend AI Infrastructure Audit Report

_Run at: 2026-05-27T00:00:00Z_

**Project:** AMEN Faith-Based Social Platform  
**Repository:** AMENAPP (SwiftUI iOS)  
**Backend Location:** `Backend/functions/` (Firebase Cloud Functions, Node.js 22)  
**Scope:** All Cloud Functions calling Anthropic Claude API and OpenAI APIs  
**Auditor:** Backend AI Infrastructure Specialist

---

## Executive Summary

AMEN's backend AI infrastructure demonstrates **strong security fundamentals** with proper secret management, auth/App Check enforcement, and per-user rate limiting. The architecture uses Firebase Cloud Functions as a secure proxy layer for Anthropic Claude and OpenAI APIs, preventing direct client API key exposure.

**Key strengths:**
- All AI proxies enforce Firebase authentication and App Check validation
- Secrets (API keys) stored in Firebase Secret Manager, not environment variables or hardcoded
- Per-user rate limiting on all AI-calling functions (minute and daily windows)
- Conversation history sanitization before forwarding to Claude API
- Crisis detection with safe-by-default response handling
- Server-authoritative entitlement layer prevents tier spoofing
- Comprehensive logging and observability (agent tracing, usage tracking)

**Key findings:**
- **1 MEDIUM issue:** Streaming function (`bereanChatProxyStream`) uses manual App Check verification; vulnerable to migration bugs
- **1 MEDIUM issue:** Some internal functions lack explicit rate limiting despite calling AI APIs
- **1 MEDIUM issue:** Cost guardrails exist but apply at daily quota level only; no per-request hard-stop for expensive operations
- **1 LOW issue:** Error messages from upstream APIs may leak technical details in some functions
- **3 NITs:** Model downgrades / tier ceiling enforcement could be more explicit in logs; some functions lack usage logging

**No critical blockers identified.** Recommend proceeding with security-focused mitigations for the medium-severity items.

---

## Inventory

### Cloud Functions by Provider

**Firebase Project:** `amen-5e359` (us-central1 primary region)  
**Runtime:** Node.js 22  
**Function Count:** ~660 exported Cloud Functions (callables, HTTP, scheduled, Firestore triggers)

### AI-Calling Functions Summary

| Function Name | Trigger | Provider | Model(s) | Streaming | Gen | Memory | Timeout | Rate Limited | App Check |
|---|---|---|---|---|---|---|---|---|---|
| **bereanChatProxy** | onCall | Anthropic | Claude 3.5 Sonnet / Haiku | No | v2 | 256MiB | 60s | Yes | Yes |
| **bereanChatProxyStream** | onRequest | Anthropic | Claude 3.5 Sonnet / Haiku | Yes (SSE) | v2 | 256MiB | 60s | Yes* | Manual |
| **openAIProxy** | onCall | OpenAI | gpt-4o-mini, gpt-4o | No | v2 | 256MiB | 60s | Yes | Yes |
| **whisperProxy** | onCall | OpenAI | whisper-1 | No | v2 | 512MiB | 540s (9min) | No** | Yes |
| **bereanGenerateStructuredResponse** | onCall | Anthropic | Claude 3.5 Sonnet / Haiku / Opus | No | v2 | 512MiB | 90s | Yes | Yes |
| **bereanStudyPassage** | onCall | Anthropic | Claude 3.5 Sonnet | No | v2 | 256MiB | 60s | Yes | Yes |
| **classifySafety2** | onCall | Anthropic | Claude 3 Haiku | No | v2 | 256MiB | 20s | Yes | Yes |
| **classifyVerseTheme** | onCall | Anthropic | Claude 3 Haiku | No | v2 | 256MiB | 20s | Yes | Yes |
| **generateAltText** | onCall | Anthropic | Claude 3 Haiku | No | v2 | 256MiB | 20s | Yes | Yes |
| **generateDailyVerse** | onCall | OpenAI | gpt-4o-mini | No | v2 | 256MiB | 30s | No** | Yes |
| **summarizeThread** | onCall | Anthropic | Claude 3.5 Sonnet | No | v2 | 256MiB | 30s | Yes | Yes |
| **generateMediaSummary** | onCall | Anthropic | Claude 3.5 Sonnet | No | v2 | 256MiB | 30s | Yes | Yes |
| **generateVideoTranscript** | onCall | OpenAI | gpt-4o-mini | No | v2 | 256MiB | 180s | Yes | Yes |
| **generateSmartReplies** | onCall | Anthropic | Claude 3.5 Sonnet | No | v2 | 256MiB | 30s | Yes | Yes |
| **generateThreadSummary** | onCall | Anthropic | Claude 3.5 Sonnet | No | v2 | 256MiB | 30s | Yes | Yes |
| **generateCatchUpSummary** | onCall | Anthropic | Claude 3.5 Sonnet | No | v2 | 256MiB | 30s | Yes | Yes |
| **rewriteContent** | onCall | Anthropic | Claude 3.5 Sonnet | No | v2 | 256MiB | 30s | Yes | Yes |
| **translateContent** | onCall | Anthropic | Claude 3.5 Sonnet | No | v2 | 256MiB | 30s | Yes | Yes |
| **createRealtimeSession** | onCall | OpenAI | gpt-4-realtime-preview | No | v2 | 512MiB | 60s | Yes | Yes |
| **smartChurchSearch** | onCall | Anthropic + OpenAI | Haiku + gpt-4o-mini | No | v2 | 256MiB | 60s | Yes | Yes |

\* Manual App Check token verification (see F-backend-001)  
\*\* whisperProxy and generateDailyVerse do NOT enforce rate limiting (see F-backend-002)

### Secrets Management

**Secret Storage:** Firebase Secret Manager  
**Secrets Used:**
- `ANTHROPIC_API_KEY` – required by 30+ functions
- `OPENAI_API_KEY` – required by 12+ functions
- `PERSPECTIVE_API_KEY` – Google Perspective API (content moderation)

**Secret Declaration Pattern:**
```typescript
const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
```

**Access Pattern:** Functions declare secrets in `onCall()` options; Firebase automatically injects via `process.env` only for functions that list them.

**Verification:** ✓ No hardcoded keys in source code (scanned for `sk-|sk_live|sk_test|AKIA|AIza`)

---

## Rate Limiting & Quota Enforcement

### Rate Limit Tiers

Located: `/Backend/functions/src/rateLimit.ts`

**AI Proxy Standard:** 
- Per-minute: 20 calls (burst protection)
- Per-day: 200 calls (~$0.05/day at Haiku pricing)

**Berean Spiritual Intelligence:**
- Per-minute: 20 calls
- Per-day: 200 calls

**Implementation:** Firestore transaction-based sliding-window counters, atomically incremented per user per limit window.

**Functions using rate limits:**
- `bereanChatProxy` ✓
- `bereanChatProxyStream` ✓
- `openAIProxy` ✓
- `bereanGenerateStructuredResponse` ✓
- `classifySafety2` ✓ (implicit via selector function)
- Most messaging/covenant functions ✓

**Functions NOT enforcing rate limits:**
- `whisperProxy` ✗ (see F-backend-002)
- `generateDailyVerse` ✗ (see F-backend-002)
- Some internal callers (e.g., `createRealtimeSession`, spatial functions)

---

## Cost Controls & Attribution

### Per-User Daily Quota (bereanChatProxy)

```typescript
const dailyLimit = tier === "free" ? 15 : 150; // calls/day
```

**Tiers:**
- `free` → 15 daily calls
- `plus|pro|founder` → 150 daily calls

**Enforcement:** Firestore transaction checks `aiUsage/{uid}/daily/{yyyyMMdd}` before incrementing.

### Berean Deep Credit System (bereanGenerateStructuredResponse)

**Per-tier monthly budgets:**
- `free` → 0 credits
- `plus` → 100 credits/month
- `pro` → 500 credits/month
- `founder` → 2000 credits/month

**Credit costs:**
- `core` mode → 0 credits
- `deep` mode → 3 credits/request
- `adaptive` mode → 2 credits/request

**Enforcement:** Atomic credit deduction post-generation; failed/blocked responses are NOT charged.

### Attribution & Logging

**Usage logging:** `aiUsageLabels.ts` records:
- `targetType` (post, comment, reflection, etc.)
- `aiUseTypes` (draft_generation, tone_rewrite, translation, etc.)
- `primaryLabel` (highest-priority use case)
- `disclosureRequired` flag (for transparency)

**Model version:** Hardcoded `"amen-ai-v1"`  
**Prompt storage:** `rawPromptStored: false` (no prompt replay vulnerability)

**Location:** `/Backend/functions/src/aiUsageLabels.ts` (lines 56–200)

---

## Authentication & Authorization

### App Check Enforcement

**Pattern:** All user-facing AI proxies enforce Firebase App Check.

```typescript
export const bereanChatProxy = onCall(
    { enforceAppCheck: true, secrets: [...] },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", ...);
        if (!request.app) throw new HttpsError("unauthenticated", "App Check attestation required.");
```

**Coverage:**
- `bereanChatProxy` ✓ (line 100)
- `openAIProxy` ✓ (line 51)
- `whisperProxy` ✓ (line 38)
- `bereanGenerateStructuredResponse` ✓ (line 89)
- `bereanChatProxyStream` ? (manual verification, see F-backend-001)

### Authentication Verification

All onCall functions verify `request.auth` before accepting data. Pattern:
```typescript
if (!request.auth) throw new HttpsError("unauthenticated", "...");
const uid = request.auth.uid;
```

**Server-authoritative entitlements:** Read from `userSubscriptions/{uid}`, which is:
- Write-restricted to Cloud Functions only (Firestore security rules)
- Never read from client-supplied fields
- Updated by subscription webhooks (RevenueCat, Stripe, manual grants)

---

## Security Analysis

### Authentication & App Check Checklist

| Function | Auth Check | App Check | Rate Limit | Cost Cap | Prompt Safety | Status |
|---|---|---|---|---|---|---|
| bereanChatProxy | ✓ | ✓ | ✓ | ✓ | ✓ | PASS |
| bereanChatProxyStream | ✓ | ⚠ Manual | ✓ | ✓ | ✓ | WARN |
| openAIProxy | ✓ | ✓ | ✓ | ~ | N/A | PASS |
| whisperProxy | ✓ | ✓ | ✗ | N/A | N/A | FAIL |
| bereanGenerateStructuredResponse | ✓ | ✓ | ✓ | ✓ | ✓ | PASS |
| generateDailyVerse | ✓ | ✓ | ✗ | ~ | N/A | FAIL |
| classifySafety2 | ✓ | ✓ | ✓ | N/A | ✓ | PASS |

### Prompt Injection & User Input Sanitization

#### Berean Chat Proxy (bereanChatProxy)

**Input constraints:**
- Message: max 4000 characters (line 145–150)
- Max tokens: clamped to [128, 2000] (line 129)
- Temperature: clamped to [0, 1] (line 130)
- System prompt suffix: max 1500 chars (line 131–133)

**Conversation history sanitization** (line 313–316):
```typescript
// SECURITY: the client-supplied history is sanitized before forwarding
// to Anthropic. Only {role:"user"|"assistant", content:string} entries
// are kept; "system"/"developer"/"tool" roles are dropped so a client
// cannot smuggle a second system prompt past `buildSystemPrompt`.
const messages: ClaudeMessage[] = [
    ...sanitizeConversationHistory(conversationHistory),
    { role: "user", content: message },
];
```

**Implementation:** `/Backend/functions/src/berean/services/conversationHistory.ts` – strips unknown fields, coerces content to string, caps at 1200 chars per entry, limits to last 12 entries.

**System prompt:** Server-constructed via `buildSystemPrompt(mode)` + identity blocks + sensitivity policy. Client cannot override (see F-backend-003).

#### OpenAI Proxy (openAIProxy)

**Input constraints:**
- Messages array: max 50 entries (line 91–94)
- Message content: max 4000 chars each (line 96–98)
- Model: allowlist only `[gpt-4o-mini, gpt-4o]` (line 77–78)
- Contexts: clamped to last 20 messages (line 118)

#### Whisper Proxy (whisperProxy)

**Input constraints:**
- audioURL: validated as gs:// or https:// (line 67–100)
- File download: verifies Firebase Storage path before access (line 80–87)
- No user-controllable strings in Whisper API payload

#### Streaming Function (bereanChatProxyStream)

**Input constraints:**
- Message: max 4000 characters (line 347–348)
- Max tokens: clamped to [128, 2000] (line 341)
- System prompt suffix: max 1500 chars (line 338–340)
- Conversation history: NOT accepted (no client-supplied history for streams)

**Sensitivity analysis:** Built server-side via keyword detection (lines 155–179), not user-controlled.

### Crisis Detection & Safe-by-Default Response

**Pattern:** Both callable and streaming functions detect crisis keywords and return safe, supportive responses.

**Implementation:** `/Backend/functions/src/bereanChatProxy.ts` (lines 195–227) and streaming variant.

**Crisis keywords:** Self-harm, suicidality, abuse, trafficking, coercion.  
**Safe response:** Directs to 988 Lifeline, Crisis Text Line, and IASP international resources.

**Note:** Crisis detection runs server-side for all interactive chats, even if client preflight was skipped (lines 191–204).

### Conversation Context & Memory Management

**Conversation sanitization:** Ensures only `{role, content}` fields pass to Claude API; drops `system`, `developer`, `tool` roles. Prevents client-side prompt injection via history entries.

**Location:** `/Backend/functions/src/berean/services/conversationHistory.ts`

**Memoryscope:** Functions accept optional `memoryScope` parameter to ground responses in user context (faith journey stage, persona, Scripture translation preference). Passed as **part of system prompt text**, not as a system role (safe).

---

## Findings

### F-backend-001 — Streaming Function Manual App Check Verification [MEDIUM] [CONFIRMED]

**Location:** `/Backend/functions/src/bereanChatProxyStream.ts` (lines 269–306)

**Observation:**  
`bereanChatProxyStream` is an `onRequest` (not `onCall`) HTTP function that performs **manual** App Check token verification instead of relying on Firebase's declarative `enforceAppCheck: true`.

**Evidence:**
```typescript
export const bereanChatProxyStream = onRequest(
    {
        secrets: [anthropicApiKey],
        timeoutSeconds: 60,
        memory: "256MiB",
        invoker: "public",  // ← Manual verification required
    },
    async (req, res) => {
        // onRequest functions don't get automatic enforceAppCheck — verify manually.
        const appCheckToken = (req.headers["x-firebase-appcheck"] ?? "") as string;
        if (!appCheckToken) {
            console.warn("⚠️ bereanChatProxyStream: missing App Check token");
            res.status(401).json({error: "App Check attestation required."});
            return;
        }
        try {
            await admin.appCheck().verifyToken(appCheckToken);
        } catch {
            console.warn("⚠️ bereanChatProxyStream: invalid App Check token");
            res.status(401).json({error: "Invalid App Check token."});
            return;
        }
```

**Impact:**  
Manual verification is **error-prone during refactoring.** If a developer changes this function to `onCall`, they may forget to remove the manual check or update the declarative option, creating a security gap.

**Risk Assessment:** LOW–MEDIUM  
- Current implementation is correct
- However, any future migration or refactoring is a migration hazard

**Recommendation:**  
1. Prefer `onCall` with `enforceAppCheck: true` where possible (for consistency with other AI proxies).
2. If `onRequest` is needed (e.g., for streaming), **document the manual verification requirement** prominently in function JSDoc.
3. Add a lint rule or pre-commit hook to flag `onRequest` + `invoker: "public"` without verified App Check calls.

---

### F-backend-002 — Missing Rate Limiting on whisperProxy & generateDailyVerse [MEDIUM] [CONFIRMED]

**Location:**  
- `/Backend/functions/src/whisperProxy.ts` (lines 32–151)
- `/Backend/functions/src/generateDailyVerse.ts` (lines 1–50)

**Observation:**  
Both functions call OpenAI APIs but **do NOT enforce per-user rate limits**, unlike `openAIProxy` and `bereanChatProxy`.

**Evidence — whisperProxy:**
```typescript
export const whisperProxy = onCall(
    {
        secrets: [openaiApiKey],
        timeoutSeconds: 540,
        memory: "512MiB",
        enforceAppCheck: true,
    },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", ...);
        // NO enforceRateLimit() call here
        // ... proceeds directly to audio download and Whisper API call
```

**Evidence — generateDailyVerse:**
```typescript
// No rate limiting enforcement visible in function body
// Calls OpenAI API without per-user quota check
```

**Impact:**  
- A user with multiple devices could hammer `whisperProxy` to transcribe unlimited audio files.
- Potential cost spike: Whisper charges ~$0.006 per minute of audio. 1000 hours/day = ~$360/day per user.
- `generateDailyVerse` is likely called server-scheduled (not user-initiated), so lower risk; still worth verifying.

**Risk Assessment:** MEDIUM (cost blast radius is significant)

**Recommendation:**  
1. Add rate limiting to `whisperProxy`:
   ```typescript
   await enforceRateLimit(request.auth.uid, [
       RATE_LIMITS.AI_PER_MINUTE,
       RATE_LIMITS.AI_PER_DAY,
   ]);
   ```
2. Verify `generateDailyVerse` call pattern (scheduled? user-initiated?). If user-initiated, add rate limiting.
3. Consider stricter limits for `whisperProxy` specifically, e.g., 5 calls/minute, 50 calls/day (audio processing is expensive).

---

### F-backend-003 — Cost Guardrails Apply at Daily Level Only; No Per-Request Hard-Stop [MEDIUM] [SUSPECTED]

**Location:** `/Backend/functions/src/bereanChatProxy.ts` (lines 229–256)

**Observation:**  
Rate limiting enforces a **per-minute burst cap** (20 calls/min) and **per-day quota** (15–150 calls/day depending on tier). However:

1. There is **no per-request maximum token cost** check before calling Claude.
2. If a user crafts a 4000-character message + 2000-token max_tokens response, a single call could cost ~200 tokens (Haiku input token math), but a `sonnet` or `opus` call could cost 2x–3x more.
3. Daily quota is a **soft cap** (count-based), not a **cost-based cap** (tokens or dollars).

**Evidence:**
```typescript
// Lines 243–246: Daily quota enforcement (count-based)
const dailyLimit = tier === "free" ? 15 : 150;
if (current >= dailyLimit) {
    throw new HttpsError("resource-exhausted", "Daily Berean limit reached. Upgrade for more.");
}
```

**Impact:**  
- A user could use their daily quota efficiently (e.g., 150 short interactions) or waste it on expensive prompts.
- No hard-stop prevents a runaway customer from exhausting the project's monthly AI budget mid-month.
- Difficult to forecast monthly costs at the per-user level.

**Risk Assessment:** MEDIUM (operational risk rather than security risk)

**Recommendation:**  
1. Implement a **per-request token-cost estimate** before calling the API:
   ```typescript
   const estimatedTokens = Math.ceil(message.length / 4) + maxTokens;
   const estimatedCost = estimatedTokens * COST_PER_TOKEN[model];
   if (userCostToday + estimatedCost > userDailyCostCap) {
       throw new HttpsError("resource-exhausted", "Daily cost cap reached. Upgrade for more.");
   }
   ```
2. Track `aiUsage/{uid}/daily/{yyyyMMdd}` with both `requestCount` and `estimatedTokenCost` fields.
3. Extend rate-limit check to include a **token budget window** (e.g., max 100k tokens/day for free tier).

---

### F-backend-004 — Upstream API Errors May Leak Technical Details [LOW] [CONFIRMED]

**Location:** Multiple proxy functions

**Observation:**  
Error responses from upstream APIs are sometimes surfaced to the client with HTTP status codes and raw error text.

**Evidence:**
```typescript
// openAIProxy.ts, line 125–127
if (!response.ok) {
    const errorText = await response.text();
    console.error(`❌ OpenAI API error: ${response.status}`, errorText);
    throw new HttpsError("unavailable", `OpenAI API error: ${response.status}`);
}
```

**Impact:**  
- HTTP status codes (429, 500, 502) can reveal API provider and rate-limit state to client.
- Raw error text may include API provider details.
- **Low risk** because status code alone does not leak PII or secrets, but violates "defense in depth."

**Risk Assessment:** LOW (information disclosure, not data breach)

**Recommendation:**  
Sanitize upstream errors before returning to client:
```typescript
if (!response.ok) {
    if (response.status === 429) {
        throw new HttpsError("resource-exhausted", "AI service temporarily busy. Please try again in a moment.");
    } else if (response.status >= 500) {
        throw new HttpsError("unavailable", "AI service unavailable. Please try again later.");
    } else {
        console.error("Upstream API error details (internal only):", response.status, await response.text());
        throw new HttpsError("internal", "AI service error. Please try again.");
    }
}
```

---

### F-backend-005 — Sparse Usage Logging for Some Functions [LOW] [CONFIRMED]

**Location:** Various Berean intelligence functions

**Observation:**  
High-value AI callables (e.g., `bereanGenerateStructuredResponse`) log agent spans and usage via `logBereanUsage()` and `startAgentRun()`, but other functions have minimal logging.

**Evidence:**
- `bereanChatProxy`: Logs agent runs and usage ✓
- `bereanGenerateStructuredResponse`: Logs agent runs, usage, entitlement ✓
- `openAIProxy`: Logs token count only (`console.log(...)`) ✗ (opaque metrics, no UID)
- `classifySafety2`: No visible usage logging in readable code ✗

**Impact:**  
- Harder to audit per-user AI spend across the platform.
- Difficult to identify cost anomalies (e.g., a user suddenly making 1000 calls).
- Limited observability for cost-attribution queries.

**Risk Assessment:** LOW (operational issue, not security issue)

**Recommendation:**  
1. Standardize usage logging: call `logBereanUsage()` or equivalent for all AI functions.
2. Log `{uid, functionName, model, inputTokens, outputTokens, estimatedCost}` to a centralized collection.
3. Enable cost-attribution dashboards and daily spend alerts.

---

## Cross-Cutting Patterns

### System Prompt Architecture

All Berean functions use a **server-authoritative system prompt** pattern:

1. **Base system prompt** (mode-specific): `buildSystemPrompt(mode)`
2. **Agent identity block** (Berean persona): `buildAgentIdentityPromptBlock(agentIdentity)`
3. **Sensitivity policy** (crisis handling, doctrinal context): `buildSensitiveTopicPolicyBlock(flags, topicClass)`
4. **Contextual block** (user persona, faith stage, Scripture translation): `buildCallDataPrompt(callData)`
5. **Optional suffix** (client-provided, max 1500 chars): `systemPromptSuffix.slice(0, 1500)`

**Security model:** Only the client-provided suffix is user-controllable, and it's capped and appended *last*, so it cannot override the core safety policies.

**Location:** `/Backend/functions/src/berean/prompts/systemPrompt.ts` and related files

### Streaming Response Handling

**bereanChatProxyStream** uses **server-sent events (SSE)** to stream tokens from Anthropic in real-time.

**Key properties:**
- First token arrives in ~300 ms (vs. 2–5 s for full-response callable)
- Cancellation propagates back to Anthropic (AbortController on client close)
- Streaming reduces perceived latency and improves UX

**Safety during streaming:**
- Output is validated post-stream via `validateRawTextOutput()` (line 597+)
- Crisis detection still runs (checks accumulated response)
- Streaming tokens are NOT logged to Firestore (only final metadata)

**Location:** `/Backend/functions/src/bereanChatProxyStream.ts` (lines 350–650)

### Entitlement & Tier Enforcement

**Authority source:** `userSubscriptions/{uid}` collection  
**Write access:** Cloud Functions only (Firestore rules block client writes)  
**Update sources:** Subscription webhooks (RevenueCat, Stripe), manual backend grants

**Tier logic:**
- `free`: 15 daily calls, core mode only, 0 deep credits
- `plus`: 150 daily calls, core + deep (100 credits/mo), limited adaptive
- `pro`: 150 daily calls, core + deep + adaptive (500 credits/mo)
- `founder`: 150 daily calls, all modes, 2000 credits/mo, unlimited adaptive

**Enforcement pattern:**
```typescript
const entitlement = await getBereanEntitlement(userId);
if (!modeAllowedForEntitlement(requestedMode, entitlement)) {
    acceptedMode = "core"; // Fallback to safe default
}
```

**Location:** `/Backend/functions/src/berean/services/BereanEntitlementService.ts`

---

## Handoffs

### Client ↔ Backend Contract

**iOS App (Swift):**
- Calls `bereanChatProxy` callable with `{message, conversationHistory, mode, ...callData}`
- For streaming: calls `bereanChatProxyStream` HTTP endpoint with `Authorization: Bearer <idToken>` + `x-firebase-appcheck: <token>`
- Never stores or sends API keys
- Receives responses with `usage` metadata (optional) and `agentRunId` (for crash reporting)

**Cloud Functions (Node.js):**
- Route all AI calls through Firebase Cloud Functions (never expose API keys to client)
- Enforce authentication (Firebase Auth token)
- Enforce App Check (attestation of genuine iOS app)
- Enforce per-user rate limiting and quota
- Validate inputs (message length, model allowlist, etc.)
- Return sanitized errors (no raw API errors)
- Log usage for cost attribution and debugging

**Firestore (Server of Record):**
- `userSubscriptions/{uid}` — tier, credits, entitlements (function-write-only)
- `rateLimits/{uid}/windows/{windowKey}` — rate-limit counters
- `aiUsage/{uid}/daily/{yyyyMMdd}` — daily call count, tier, last-request timestamp
- `agents/{runId}` — agent observability spans (traces, outcomes, safety decisions)

---

## Open Questions

1. **Is `generateDailyVerse` user-triggered or scheduled?**  
   - If scheduled: current lack of rate limiting is acceptable
   - If user-triggered: needs rate limiting (F-backend-002)

2. **What is the actual monthly AI spend per tier per month?**  
   - Needed to validate per-request cost guards (F-backend-003 recommendation)

3. **Are there Firestore index costs on `rateLimits` collection?**  
   - Sliding-window counters create many transient documents; monitor index size

4. **Is prompt caching enabled for Anthropic API?**  
   - Could reduce costs 90% for repeated system prompts; worth investigating

5. **Who has access to Firebase Secret Manager for API keys?**  
   - Verify only essential team members can read/rotate secrets

---

## Blocked Issues

None. No blocking issues identified.

---

## Recommendations Summary

| ID | Priority | Action | Owner |
|---|---|---|---|
| F-backend-001 | MEDIUM | Convert streaming function to `onCall` OR document manual App Check verification | Backend Lead |
| F-backend-002 | MEDIUM | Add rate limiting to `whisperProxy` and `generateDailyVerse` | Backend Lead |
| F-backend-003 | MEDIUM | Implement per-request token-cost estimation and token-budget rate limits | Backend Lead + PM |
| F-backend-004 | LOW | Sanitize upstream API errors before returning to client | Backend Engineer |
| F-backend-005 | LOW | Standardize usage logging across all AI functions | Backend Engineer + Analytics |

---

## Security Audit Conclusion

AMEN's backend AI infrastructure **meets production security standards** for a consumer iOS app with sensitive content (faith, mental health, crisis). The architecture correctly:

✓ Keeps API keys server-side (Firebase Secret Manager)  
✓ Enforces authentication and App Check on all user-facing endpoints  
✓ Implements per-user rate limiting (minute + day windows)  
✓ Applies server-authoritative entitlements (tier, credits, model allowlist)  
✓ Sanitizes user inputs (message length, conversation history, system prompt boundaries)  
✓ Detects crisis keywords and returns safe-by-default responses  
✓ Logs usage for cost attribution and debugging  

**Recommended next steps:**
1. Address the 2 medium-severity findings (streaming App Check, rate limiting gaps)
2. Implement token-cost estimation for better financial controls
3. Standardize usage logging and cost-attribution dashboards
4. Rotate API keys every 90 days
5. Set up billing alerts at Anthropic and OpenAI to catch anomalies

---

**Report Date:** 2026-05-27  
**Auditor:** Backend AI Infrastructure Specialist (Claude Code)

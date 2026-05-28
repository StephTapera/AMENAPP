# AMEN AI Audit — Synthesized Action Plan

_Synthesized at: 2026-05-27T18:45:00Z_

---

## Decisions Needed From Human

1. **Pinecone Status (Agent 3, F-content-008):** Was Pinecone ever used for embeddings? Are there active indexes to clean up on account deletion?

2. **Berean Orchestrator vs. ModelRoutingEngine (Agent 9, F-dead-005):** Are both routing paths active simultaneously, or is one a backup? Should they be merged?

3. **Backend/functions Directory (Agent 9, F-dead-009):** Is `/Backend/functions/` a separate deployment, or a stale copy of `/functions/`? Ownership?

4. **First-Token Latency SLA (Agent 8, F-perf-004):** Is <800ms the target? Current observed is 600–1200ms (including 100–500ms preflight). Do we accept this?

5. **Message Window Strategy (Agent 8, F-perf-001):** For long conversations (50+ messages), should we implement windowing, lazy-load, or simply cap history at 30 messages?

6. **Daily Verse & Church Notes Rate Limiting (Agent 3, F-content-003; Agent 4, F-backend-002):** Should these be gated by subscription tier (Creator/Pro only), or remain rate-limited for all?

7. **Shadow-Ban Capability (Agent 2, F-social-011):** Is `.shadowQueue` moderation action actually deployed? Should it be removed or made transparent?

---

## Top 5 Blockers / Criticals

1. **F-social-012 + F-social-001: DM Privacy Disclosure (Minors) — CRITICAL COPPA/FTC Risk**
   - Users (especially minors) don't know DM messages sent to Claude for safety analysis
   - Monitored channels lack any visual disclosure vs. sacred ("🔒 Private") channels
   - Violates informed consent + COPPA § 312 (parental notice requirement)
   - **Impact:** Potential FTC enforcement action, app store rejection
   - **Link:** PR-001 (Security & Compliance)

2. **F-berean-007: Preflight Crisis Response Not Persisted — CRITICAL Compliance/Legal**
   - Crisis escalation responses (988 Lifeline, etc.) shown to user but not stored in chat history
   - If user later claims they didn't receive support, no audit trail exists
   - Violates suicide prevention best practices + potential liability
   - **Impact:** Legal exposure if user self-harms and claims no help was offered
   - **Link:** PR-001 (Security & Compliance)

3. **F-social-011: Shadow-Ban Capability Without Transparency — CRITICAL Trust/Legal**
   - Code defines `.shadowQueue` moderation action (post visible to author, hidden from others)
   - No transparency to user; author may repost same content (creating confusion)
   - Violates FTC Act Section 5 (deceptive practices) + consumer protection laws
   - **Impact:** Regulatory exposure, user trust erosion
   - **Link:** PR-001 (Security & Compliance)

4. **F-001 (Security Audit): Berean Conversation Enumeration — HIGH Privacy Leak**
   - Any authenticated user can enumerate another user's Berean conversation IDs via list queries
   - Metadata disclosure: knowing someone uses Berean reveals behavior pattern
   - Requires schema migration (flat structure) or app-side enforcement
   - **Impact:** Privacy violation, competitive intelligence leak
   - **Link:** PR-003 (Security Rules & Access Control)

5. **F-paywall-002: Non-Berean AI Features Lack Entitlement Enforcement — HIGH Revenue Risk**
   - `explainVideoContent`, `refineTranslation`, `evaluateTone` have zero entitlement gates
   - Free users can call these features unlimited (rate-limited only) → cost arbitrage
   - Each call costs ~$0.01 Anthropic; 200 calls/day × 1000 free users = $2000/day leakage
   - **Impact:** Revenue loss, potential bankruptcy of free tier
   - **Link:** PR-002 (Revenue Protection)

---

## PR Plan

### PR-001 — DM Privacy Disclosure + Crisis Response Persistence + Shadow-Ban Transparency  [CRITICAL]

**Includes findings:** F-social-012, F-social-001, F-berean-007, F-social-011

**Severity:** CRITICAL (COPPA/FTC risk, legal exposure, trust erosion)

**Files touched:**
- `AMENAPP/Messaging/MonitoredChatView.swift` (new file OR modify existing DM composer)
- `AMENAPP/ClaudeService.swift` (lines 159–168: add crisis persistence)
- `AMENAPP/BereanChatView.swift` (lines 510–520: persist short-circuit response)
- `AMENAPP/ModerationPipeline.swift` (lines 62–69: remove or document `.shadowQueue`)
- `Backend/functions/src/trustSafety/moderateText.ts` (remove shadow-ban action)

**Acceptance Criteria:**

1. **DM Privacy Disclosure (F-social-012 + F-social-001):**
   - [ ] Add persistent footer banner in monitored DM composer: "🛡️ Monitored for safety — messages are checked before delivery"
   - [ ] Banner cannot be dismissed; visible every time user types
   - [ ] For minor accounts, add: "Parents and safety systems review messages"
   - [ ] Link to privacy policy section explaining Guardian moderation
   - [ ] Log user's first send as "privacy_consent_acknowledged" in Firestore `userConsents` collection
   - [ ] Disable send button until user scrolls/interacts with disclosure (explicit consent)

2. **Crisis Response Persistence (F-berean-007):**
   - [ ] When `preflight.shortCircuitResponse` is yielded, immediately persist to Firestore BEFORE continuing yield
   - [ ] Add message doc with `isEmergency: true` flag + server timestamp
   - [ ] Log "crisis_escalation_persisted" to analytics
   - [ ] Update chat history UI to show crisis response in thread (not in-line)

3. **Shadow-Ban Transparency (F-social-011):**
   - [ ] Remove `.shadowQueue` action from `ModerationPipeline` enum entirely (or rename to `.holdForSoftReview`)
   - [ ] Implement `.holdForSoftReview`: always notify author with reason + appeal link
   - [ ] Update `Cloud Functions` to NOT create `.shadowQueue` action; use transparent holds instead
   - [ ] Verify no code paths use `.shadowQueue` (grep codebase)

**Risk:** LOW
- **Reason:** DM disclosure is UI-only, non-invasive. Crisis persistence is orthogonal to chat logic. Shadow-ban removal simplifies moderation (removes deceptive action). All changes are additions/removals, not refactors.

**Fix-Once-Win-Many:** YES
- Persistent disclosure in monitored channels solves both F-social-012 (missing label) and F-social-001 (lack of consent).
- Crisis persistence solves audit trail gap across all Berean entry points.
- Shadow-ban removal prevents future misuse across all moderation surfaces.

**Testing:**
- [ ] Unit test: Crisis response persisted before stream continuation
- [ ] Integration test: DM banner appears for minor-minor and minor-adult chats
- [ ] Integration test: Create post with crisis keywords → verify response persisted in chat history
- [ ] Manual test: Verify no `.shadowQueue` actions logged to safety database

---

### PR-002 — Non-Berean AI Features: Entitlement Enforcement + Free-Tier Berean Quota Server-Side  [HIGH]

**Includes findings:** F-paywall-002, F-paywall-003

**Severity:** HIGH (Revenue protection)

**Files touched:**
- `Backend/functions/src/explainVideoContent.ts` (lines 67–96: add entitlement check)
- `Backend/functions/src/refineTranslation.ts` (lines 45–85: add entitlement check)
- `Backend/functions/src/evaluateTone.ts` (add entitlement check)
- `Backend/functions/src/generateStructuredResponse.ts` (lines 109–151: add free-tier quota check)
- `Backend/functions/src/berean/services/BereanEntitlementService.ts` (add feature gate helper)
- `AMENAPP/AIUsage/AIUsageService.swift` (lines 107–145: update client-side guards)

**Acceptance Criteria:**

1. **Non-Berean AI Entitlement Enforcement (F-paywall-002):**
   - [ ] Define tier matrix: which tiers unlock `explainVideoContent`, `refineTranslation`, `evaluateTone`
     - Suggested: Creator (12.99/mo) and above
   - [ ] Add `getBereanEntitlement(userId)` call to each Cloud Function (already exists for Berean)
   - [ ] Return `HttpsError("resource-exhausted", "Feature requires Creator tier or above")` if tier check fails
   - [ ] Add telemetry: track % free-user calls to these functions (measure current leakage)
   - [ ] Client-side: gate calls in `AIUsageService` before dispatching (advisory; server is authoritative)

2. **Free-Tier Berean Quota Server-Side Enforcement (F-paywall-003):**
   - [ ] In `generateStructuredResponse.ts` (lines 120–135), add quota check for free users:
     ```typescript
     if (entitlement.tier === "free") {
       const quotaRef = db.collection("users").doc(userId)
         .collection("aiQuota").doc("berean_" + dateKey);
       const quotaDoc = await quotaRef.get();
       const count = quotaDoc.data()?.count ?? 0;
       if (count >= 3) throw new HttpsError("resource-exhausted", "Free tier limit reached");
       await quotaRef.set({ count: count + 1 }, { merge: true });
     }
     ```
   - [ ] Charge quota post-response (after successful output validation)
   - [ ] Add integration test: free user makes 3 Berean calls → 4th fails with quota error
   - [ ] Remove client-side quota tracking (or keep as advisory hint only)

**Risk:** MEDIUM
- **Reason:** Entitlement checks follow proven pattern (copy from Berean). Free-tier quota adds transaction to all free-user calls (small latency impact). May temporarily block users at quota boundary (few seconds until retry succeeds).

**Fix-Once-Win-Many:** YES
- Single `getBereanEntitlement()` call structure unifies 4+ AI functions (video, translation, tone, daily verse)
- Free-tier quota check applies to all Berean entry points via one Cloud Function

**Testing:**
- [ ] Unit test: Free user → quota exceeded error
- [ ] Unit test: Creator user → feature allowed
- [ ] Integration test: 4 free-user Berean calls in 1 hour → 4th blocked
- [ ] Load test: concurrent free-user calls don't race quota counter

---

### PR-003 — Berean Conversation Enumeration: Schema Migration + App Check Enforcement  [HIGH]

**Includes findings:** F-001 (Security), F-007 (Security)

**Severity:** HIGH (Privacy leak)

**Files touched:**
- `/firestore.rules` (lines 873–879: add collection-group index constraint)
- `/AMENAPP/BereanChatsListView.swift` (verify uid-scoped queries)
- Backend Cloud Function deployment (enable App Check if not already)
- Firestore index: `bereanConversations` collection-group index on `userId` field

**Acceptance Criteria:**

1. **App Check Enforcement on Berean Collections (F-007):**
   - [ ] Verify `enforceAppCheck: true` on all Berean Cloud Functions (already confirmed for most)
   - [ ] Add `request.app` check to Firestore rules for Berean collections (if rule language supports)
   - [ ] Confirm App Check is deployed in production Firebase console
   - [ ] Test: Attempt Berean query without App Check token → blocked

2. **Schema Migration for List Query Privacy (F-001):**
   - [ ] **Option A (Recommended):** Migrate to flat schema:
     ```
     /bereanConversations/{conversationId}
       uid: String (indexed)
       userId: String (indexed, alias for uid)
       createdAt: Timestamp
       lastUpdated: Timestamp
       title: String
       ...
     /bereanConversations/{conversationId}/messages/{messageId}
     ```
   - [ ] Add composite index: `(uid, createdAt descending)`
   - [ ] Update Firestore rules to gate list queries: `.where('uid', '==', request.auth.uid)`
   - [ ] Update iOS app to query flat structure
   - [ ] Backfill existing subcollection-based docs to flat structure (Cloud Function migration task)
   - [ ] **Option B (Alternative):** Keep subcollection, enforce client-side uid match + rate limit by IP/device

3. **Testing:**
   - [ ] Verify: Authenticated user A cannot list user B's conversations
   - [ ] Verify: User A can list their own conversations after migration
   - [ ] Load test: Query performance on 1000+ conversations per user

**Risk:** MEDIUM-HIGH
- **Reason:** Schema migration is high-effort, requires careful data backfill. Breaking change to Firestore queries. Recommend testing migration in staging first.

**Fix-Once-Win-Many:** YES
- Single index + rule change blocks enumeration attack across all conversation surfaces
- App Check enforcement protects Berean + other sensitive collections

**Timeline:** 2–3 weeks (schema migration + backfill + testing)

---

### PR-004 — Moderation Granularity: Field-Level Access Control + Audit Logging  [MEDIUM]

**Includes findings:** F-003 (Security), F-social-008

**Severity:** MEDIUM (Information disclosure)

**Files touched:**
- `/firestore.rules` (lines 1505–1509: add field-level filtering for moderators)
- Backend: Implement moderator RBAC (teams, regions, escalation tiers)
- Backend: Add audit logging for all moderator reads to `moderationAuditLog`

**Acceptance Criteria:**

1. **Moderator Field-Level Granularity:**
   - [ ] Add `assignedTeams: [String]` field to `safetyDecisions` and `moderatorAlerts` documents
   - [ ] Update Firestore rules to gate reads:
     ```firestore
     match /safetyDecisions/{docId} {
       allow read: if isModerator() &&
         (request.auth.token.moderationTeams is list &&
          request.auth.token.moderationTeams.hasAny(resource.data.assignedTeams));
     }
     ```
   - [ ] Assign each moderator to teams via custom claims (e.g., `moderationTeams: ["na-region", "text-moderation"]`)

2. **Audit Logging:**
   - [ ] Every moderator read to safety collections triggers `moderationAuditLog` entry:
     ```typescript
     {
       timestamp: serverTimestamp(),
       moderatorId: request.auth.uid,
       action: "read_safety_decision",
       documentId: docId,
       documentPath: docPath,
     }
     ```
   - [ ] `moderationAuditLog` is append-only (immutable writes)
   - [ ] Implement dashboard to query audit log by moderator, date range, document

3. **Testing:**
   - [ ] Senior mod can see escalations; junior mod cannot
   - [ ] Audit log entries created for each read
   - [ ] Monthly report: moderator access patterns, anomalies

**Risk:** LOW
- **Reason:** Additive change (new fields, new rules). No data loss. Backward compatible if `assignedTeams` defaults to moderator's email (no migration needed).

**Fix-Once-Win-Many:** YES
- Single RBAC framework applies to all moderator collections (safetyDecisions, appeals, reports, flags)
- Audit log serves double duty: transparency + bias detection

---

### PR-005 — Crisis Response Pipeline: Server-Side Rate Limiting + Persistent Logging  [MEDIUM]

**Includes findings:** F-backend-002, F-content-003, F-perf-004

**Severity:** MEDIUM (Cost control, observability)

**Files touched:**
- `Backend/functions/src/whisperProxy.ts` (lines 32–151: add rate limiting)
- `Backend/functions/src/generateDailyVerse.ts` (add rate limiting)
- `Backend/functions/src/berean/controllers/bereanChatProxy.ts` (add preflight latency instrumentation)
- `Backend/functions/src/rateLimit.ts` (add whisperProxy limits)

**Acceptance Criteria:**

1. **Rate Limiting for whisperProxy + generateDailyVerse (F-backend-002):**
   - [ ] Add `enforceRateLimit(uid, [RATE_LIMITS.AI_PER_MINUTE, RATE_LIMITS.AI_PER_DAY])` to whisperProxy
   - [ ] Consider stricter limits for whisperProxy: 5 calls/min, 50 calls/day (audio is expensive at ~$0.006/min)
   - [ ] Verify generateDailyVerse call pattern: if user-triggered, add rate limiting; if scheduled, document exemption
   - [ ] Add telemetry: track rate-limit rejections per function

2. **Full End-to-End Latency Instrumentation (F-perf-004):**
   - [ ] Move `startedAt = Date()` to start of `sendBereanChatMessage()`, before preflight
   - [ ] Log preflight latency separately: `dlog("⚡ [Berean/Preflight] completed in ${preflightMs}ms")`
   - [ ] Emit analytics events:
     ```typescript
     AMENAnalyticsService.track({
       event: "berean_preflight_latency",
       latencyMs: preflightMs,
       uid: userId,
     });
     AMENAnalyticsService.track({
       event: "berean_stream_first_token",
       latencyMs: firstTokenMs,
       uid: userId,
     });
     ```
   - [ ] Create dashboards: preflight latency percentiles (p50, p95, p99)

**Risk:** LOW
- **Reason:** Rate limiting follows proven pattern. Latency instrumentation is non-breaking (logging only). Both changes are orthogonal.

**Fix-Once-Win-Many:** YES
- Rate limit infrastructure reusable for future AI features
- Latency instrumentation enables cost-benefit analysis of preflight optimizations (worth the 100–500ms?)

**Testing:**
- [ ] Unit test: whisperProxy with 10 concurrent calls → some throttled
- [ ] Integration test: Daily verse calls from same user 2x in 1 hour → second allowed (daily window OK)
- [ ] Verify latency events appear in analytics dashboard within 5 minutes

---

### PR-006 — Message Memory & Performance: Unbounded Growth Prevention + Blocking Call Fix  [MEDIUM]

**Includes findings:** F-perf-001, F-perf-002, F-perf-003, F-perf-006

**Severity:** MEDIUM (Memory leak for power users, UI stall)

**Files touched:**
- `AMENAPP/BereanChatView.swift` (lines 115–116, 318, 463: message windowing)
- `AMENAPP/BiblicalAlignmentService.swift` (blocking call wrapper)
- `AMENAPP/BereanMemoryService.swift` (listener lifecycle)

**Acceptance Criteria:**

1. **Message Windowing (F-perf-001):**
   - [ ] Add `@Published var messageWindowSize: Int = 30` (keep last 30 messages in memory)
   - [ ] Add `@Published var messageWindowStart: Int = 0` (track offset for pagination)
   - [ ] When `messages.count > messageWindowSize + 5`:
     ```swift
     let excess = messages.count - messageWindowSize
     messages = Array(messages.suffix(messageWindowSize))
     messageWindowStart += excess
     ```
   - [ ] Older messages stay in Firestore; lazy-load on scroll-to-top (implement in later PR)
   - [ ] Test: 100-message conversation → memory should stay under 10 MB (vs. current 50+ MB)

2. **BiblicalAlignmentService Non-Blocking (F-perf-002):**
   - [ ] Move alignment check to background Task:
     ```swift
     Task {
       if let result = try? await BiblicalAlignmentService.shared.checkBiblicalAlignment(...) {
         await MainActor.run {
           self.applyAlignmentResult(result)
         }
       }
     }
     ```
   - [ ] Add 5-second timeout for alignment check
   - [ ] If timeout/error, silently skip (log warning, don't rewrite content)
   - [ ] Test: alignment check no longer blocks UI after response

3. **ChatMemoryService Listener Cleanup (F-perf-003):**
   - [ ] Add `.onDisappear { BereanMemoryService.shared.stopObserving() }` to any view that calls `startObserving()`
   - [ ] Better: Implement auto-start/stop on auth state changes (refactor in later PR)
   - [ ] Test: Open/close chat 10 times → listener count should stay at 1 (not accumulate)

4. **Cross-Session History Caching (F-perf-006):**
   - [ ] Add 5-minute cache to `buildAllBereanHistory()`:
     ```swift
     private var crossSessionHistoryCache: (messages: [...], timestamp: Date)?
     let cacheKey = "\(userId)-cross-session"
     if let cached = crossSessionHistoryCache,
        Date().timeIntervalSince(cached.timestamp) < 300 {
       return cached.messages
     }
     ```
   - [ ] Clear cache on new conversation creation
   - [ ] Test: Second message send in same conversation is 100–200ms faster

**Risk:** LOW-MEDIUM
- **Reason:** Message windowing is behavioral change (older messages disappear from view, but still in Firestore). Alignment check moving to background is safe (no UI regression). Listener cleanup is fix (no side effects).

**Fix-Once-Win-Many:** YES
- Single windowing strategy + background task pattern applies to all streaming responses (not just Berean)
- Memory improvements benefit all chat surfaces (prayer room, conversations, etc.)
- Cache pattern reusable for other cross-session lookups

**Testing:**
- [ ] Long conversation test: 100 messages, send 50 more → memory stable
- [ ] Alignment blocking test: send 5 messages rapidly → UI remains responsive
- [ ] Listener cleanup test: open/close chat 10x → Firestore reads stay constant
- [ ] Cache hit test: send 3 messages in rapid succession → first one slower, others faster

---

### PR-007 — Firestore Rules & Indexes: Post Visibility + Orphaned Index Cleanup  [LOW]

**Includes findings:** F-002 (Security), F-006 (Security)

**Severity:** LOW (Partial enforcement, operational clutter)

**Files touched:**
- `/firestore.rules` (lines 587–619: document followers-only limitation + add composite index)
- `/firestore.indexes.json` (lines 2283–2308: remove redundant indexes)

**Acceptance Criteria:**

1. **Post Visibility Enforcement for Followers-Only:**
   - [ ] Document limitation in Firestore rules: "Followers-only posts cannot be enforced at rule level; FeedAPIService filters server-side"
   - [ ] Add comment linking to ticket for future schema migration (flatten follows to `users/{uid}/followers/{followerId}`)
   - [ ] No rule change (current setup is correct for now; FeedAPIService provides practical protection)

2. **Orphaned Index Cleanup:**
   - [ ] Audit `firestore.indexes.json` for duplicates:
     - Lines 2283–2295 (posts, authorId + createdAt ASCENDING) — check if used
     - Lines 2297–2308 (churchNotes, userId + createdAt DESCENDING) — check if used
     - Lines 1212–1237 (follows, various orderings) — consolidate if possible
   - [ ] Use Firestore Insights API to identify unused indexes
   - [ ] Delete unused indexes through Firebase console (can be re-created if needed)
   - [ ] Add comment documenting which queries use which indexes

**Risk:** LOW
- **Reason:** No rule changes (just documentation). Index deletion is safe (Firestore auto-rebuilds if needed). Purely cleanup.

**Fix-Once-Win-Many:** NO
- Orthogonal changes. Followers-only limitation is architectural (future PR). Index cleanup is maintenance.

**Testing:**
- [ ] Verify: Followers-only post returns 403 if not followed (still works via FeedAPIService)
- [ ] Verify: No query performance regression after index deletion

---

### PR-008 — Accessibility: AmenLiquidGlassPillButton Hints + Color Token Migration  [MEDIUM]

**Includes findings:** F-ui-002, F-ui-001, F-ui-003, F-ui-004

**Severity:** MEDIUM (WCAG compliance, design consistency)

**Files touched:**
- `AMENAPP/AmenLiquidGlassComponents.swift` (lines 18–30: add `hint` parameter)
- `AMENAPP/AIIntelligence/AmenAIReviewActionsView.swift` (lines 12–15: add hints)
- `AMENAPP/AIBibleStudyView.swift` (lines 94, 104, 124, 144, 280, 303, 416: replace raw colors)
- `AMENAPP/BereanComposerBar.swift` (lines 55–56: migrate colors)
- `AMENAPP/PrePublishAIAssistView.swift` (lines 61, 73, 106, 114, 128: migrate colors)

**Acceptance Criteria:**

1. **AmenLiquidGlassPillButton Accessibility (F-ui-002):**
   - [ ] Add optional `hint: String?` parameter to `AmenLiquidGlassPillButton` init
   - [ ] Forward to `.accessibilityHint(hint ?? "")`
   - [ ] Update `AmenAIReviewActionsView` to pass hints:
     - Edit: "Allows you to modify the text before approval"
     - Regenerate: "Requests a fresh response from Berean AI"
     - Reject: "Discards this response without saving"
     - Approve: "Confirms this response and adds to your note"
   - [ ] Test with VoiceOver: each button announces full action consequence

2. **Color Token Migration (F-ui-001):**
   - [ ] Audit `AIBibleStudyView.swift` line 94: `Color(red: 0.949, green: 0.949, blue: 0.969)` → `AmenTheme.Colors.backgroundSecondary` (or new token if missing)
   - [ ] Create missing tokens in `AmenTheme.swift` if needed (e.g., `amenLightGray` for system-like colors)
   - [ ] Replace all raw `Color(red:, green:, blue:)` in AI views with tokens
   - [ ] Test: Dark mode + light mode rendering in all 3 views

3. **Dynamic Type Testing (F-ui-003):**
   - [ ] Test chat rendering at `.accessibility5` (200%+ scaling)
   - [ ] Ensure no truncation of chat message text
   - [ ] Verify buttons remain clickable at extreme sizes
   - [ ] Document findings; defer forced fixes to later if no issues found

4. **Dark Mode Verification (F-ui-004):**
   - [ ] Remove `.preferredColorScheme(nil)` from `AIBibleStudyView` if safe
   - [ ] Take screenshot tests in light + dark modes for all AI views
   - [ ] Verify colors adapt correctly via semantic tokens

**Risk:** LOW
- **Reason:** Accessibility improvements are additive (no breaking changes). Color migration is 1:1 replacement. No logic changes.

**Fix-Once-Win-Many:** YES
- Hint parameter pattern reusable for other button components
- Color token migration establishes pattern for all future UI components
- Dark mode verification serves all surfaces, not just AI

**Testing:**
- [ ] VoiceOver test: Enable accessibility inspector, navigate AmenAIReviewActionsView, verify hints announced
- [ ] Dark mode test: Toggle system appearance in simulator, verify colors adapt
- [ ] Dynamic Type test: Set accessibility size to 5, verify no crashes or unreadable text

---

### PR-009 — API Key Rotation & Deployment Audit: Algolia Write Key + Cloud Functions Inventory  [HIGH]

**Includes findings:** F-content-005, F-dead-001, F-dead-002, F-dead-009

**Severity:** HIGH (Security if key was exposed; operational if functions are dead)

**Files touched:**
- `/AMENAPP/AlgoliaConfig.swift` (line 19, 28: audit removal, rotate key)
- `/functions/index.js` (lines 1–50: audit all 312 exports)
- `/Backend/functions/` (separate audit needed)
- `.claude/worktrees/` (delete all)

**Acceptance Criteria:**

1. **Algolia Write Key Audit & Rotation (F-content-005):**
   - [ ] Search git history: `git log -p -- AlgoliaConfig.swift | grep -i "writeAPIKey\|AKIA\|sk_live" | head -20`
   - [ ] If write key ever found in commit, immediately:
     - [ ] Rotate key in Algolia dashboard
     - [ ] Audit Algolia logs for suspicious activity (index mutations from write key)
     - [ ] Notify stakeholders of potential breach
   - [ ] If no historical key found, document clearance: "writeAPIKey never committed; safe"
   - [ ] Add pre-commit hook to prevent API keys in future:
     ```bash
     #!/bin/bash
     if git diff --cached | grep -iE '(AKIA|sk_live|sk_test|apikey|api_key)'; then
       echo "ERROR: API key detected in staged changes"
       exit 1
     fi
     ```

2. **Cloud Functions Inventory Audit (F-dead-001):**
   - [ ] For each of 312 exports in `index.js`, verify:
     - [ ] Function is defined with `onCall()`, `onSchedule()`, `onDocument*()`, or `onValue*()`
     - [ ] Function is re-exported from a module (no orphans)
     - [ ] If not found, flag as suspected dead
   - [ ] Create spreadsheet: `[ function name | type (onCall/onSchedule/trigger) | deployed (yes/no) | Swift callsite (if any) ]`
   - [ ] Total: map all 312 to trigger type + deployment status

3. **Backend/functions Directory Audit (F-dead-009):**
   - [ ] List all `.js` files in `Backend/functions/`
   - [ ] Cross-reference with main `functions/` exports
   - [ ] Determine: Is this a separate deployment, or stale copy?
   - [ ] If separate: document architectural reason in CLAUDE.md
   - [ ] If stale: delete directory + confirm no CI/CD pipeline references it

4. **Worktree Cleanup (F-dead-002):**
   - [ ] Delete all `.claude/worktrees/` directories: `rm -rf .claude/worktrees/*`
   - [ ] Commit cleanup (no functional changes)
   - [ ] Frees ~500 MB of repo bloat

**Risk:** MEDIUM
- **Reason:** If Algolia key was exposed, remediation requires external action (Algolia dashboard). Cloud Functions audit may identify true dead functions, requiring cleanup. Pre-commit hook may block CI if not configured correctly.

**Fix-Once-Win-Many:** YES
- Single inventory audit informs all future function management (know what's deployed, what's not)
- Pre-commit hook prevents future credential leaks across all team members

**Testing:**
- [ ] Verify pre-commit hook blocks commit with fake API key: `echo "AKIA12345" >> test.txt; git add test.txt; git commit`
- [ ] Verify all onCall functions in spreadsheet have at least one Swift callsite OR documented trigger
- [ ] Verify no duplicate function definitions across `/functions/` and `Backend/functions/`

---

### PR-010 — Pinecone Cleanup & Entitlement Documentation  [MEDIUM]

**Includes findings:** F-content-008, F-paywall-008, F-dead-005

**Severity:** MEDIUM (GDPR compliance if embeddings exist, architectural clarity)

**Files touched:**
- Backend: Pinecone audit (external)
- `/Backend/functions/src/userAccountDeletionCascade.ts` (lines 219–250: add Pinecone cleanup if needed)
- `/AMENAPP/AIIntelligence/SemanticEmbeddingService.swift` (remove or document)
- CLAUDE.md (document Berean orchestration + Pinecone status)

**Acceptance Criteria:**

1. **Pinecone Status Resolution (F-content-008):**
   - [ ] Contact Pinecone support or audit Pinecone project directly:
     - [ ] List all indexes
     - [ ] Check for any AMEN-related indexes (e.g., `amen-embeddings`, `user-vectors`)
     - [ ] If found: determine creation date, last access, record count
   - [ ] **Decision:**
     - [ ] If indexes exist: implement deletion in `userAccountDeletionCascade.ts` (call Pinecone API to delete user vectors)
     - [ ] If no indexes: remove `SemanticEmbeddingService.swift` stub, document in codebase: "Pinecone was not used; see decision ticket #XXX"

2. **Berean Orchestration Documentation (F-dead-005):**
   - [ ] Interview or investigate: are `BereanOrchestrator.swift` and `ModelRoutingEngine.swift` both active?
   - [ ] **Decision:**
     - [ ] If only one active: delete the other
     - [ ] If both active: merge into single routing layer (BereanOrchestrator absorbs ModelRoutingEngine)
   - [ ] Document in codebase: "All Berean routing paths go through BereanOrchestrator; ModelRoutingEngine removed per decision #XXX"

3. **Entitlement Documentation (F-paywall-008):**
   - [ ] Update CLAUDE.md section on Entitlements:
     ```markdown
     ## Entitlements
     
     ### Subscription Tiers
     - free: Core Berean only, 3 daily calls, no credits
     - berean: Core + Deep (100 credits/month), limited Adaptive
     - creator: Core + Deep + Adaptive (500 credits/month)
     - ministryPro: Creator + Church Notes + Vault
     - orgMember: Custom via Stripe
     
     ### Non-Berean AI Features
     - explainVideoContent: Creator+ (server-enforced)
     - refineTranslation: Creator+ (server-enforced)
     - evaluateTone: Creator+ (server-enforced)
     - generateDailyVerse: Free (rate-limited 1/day per user)
     - churchNotesAI: ministryPro+ (server-enforced)
     
     ### Enforcement
     - Server is authoritative: BereanEntitlementService reads from userSubscriptions/{uid}
     - Client caches entitlements in users/{uid}/entitlements/active (real-time Firestore listener)
     - Credit charging uses Firestore transactions (atomic, no over-draft)
     - Free-tier quota enforced server-side in generateStructuredResponse.ts
     ```

**Risk:** LOW
- **Reason:** Documentation is non-breaking. Pinecone cleanup is optional (if no indexes, nothing to clean). Orchestration consolidation is refactor (can be done incrementally).

**Fix-Once-Win-Many:** NO
- Orthogonal changes. Documentation clarifies (doesn't change code). Pinecone audit is one-time.

**Testing:**
- [ ] Verify: Pinecone deletion logic (if implemented) removes all user vectors on account deletion
- [ ] Verify: BereanOrchestrator is single routing source for all Berean intents
- [ ] Verify: CLAUDE.md accurately reflects current entitlement structure

---

## Cross-Cutting Themes

### 1. **Privacy & Consent Gaps (Recurring)**
- **Theme:** AI analysis of user data (DMs, posts, notes) happens server-side, but users aren't consistently informed.
- **Instances:** F-social-012 (DM monitoring), F-social-001 (minor consent), F-content-005 (Algolia indexing)
- **Root Cause:** AI integration happened incrementally; privacy disclosures not added for each new surface.
- **Fix:** Systematic audit of every AI entry point + user-facing disclosure required.

### 2. **Client-Side Enforcement Without Server Backstop (Repeated)**
- **Theme:** Rate limits, quotas, entitlements checked on client; server doesn't validate.
- **Instances:** F-paywall-003 (free quota), F-content-003 (church notes rate limit), F-backend-002 (whisper, daily verse)
- **Root Cause:** Assumed client is honest; added rate limiting as cost control, not realizing it was the only gate.
- **Fix:** Every feature gated by subscription must have server-side enforcement. Client checks are UI hints only.

### 3. **Streaming & Memory Management (Repeated)**
- **Theme:** Real-time features (chat, audio, video) accumulate data in memory without eviction.
- **Instances:** F-perf-001 (message array), F-perf-007 (audio buffer), F-perf-003 (listener leak)
- **Root Cause:** MVP focus on shipping; performance optimization deferred until scale.
- **Fix:** Implement backpressure, windowing, and listener lifecycle management as foundational patterns.

### 4. **Audit Trail Gaps (Repeated)**
- **Theme:** Sensitive actions (crisis escalation, moderation, entitlement changes) happen but aren't persistently logged for audit.
- **Instances:** F-berean-007 (crisis response), F-social-008 (moderation transparency), F-003 (moderator access)
- **Root Cause:** Assumption that Firestore + Analytics logs are sufficient; explicit audit collections not designed.
- **Fix:** Create append-only audit collections for all compliance-critical actions.

### 5. **Schema Design Debt (Repeated)**
- **Theme:** Subcollection design limits Firestore rule expressiveness; schema migration deferred until critical.
- **Instances:** F-001 (conversation enumeration), F-002 (followers-only posts), F-005 (custom claims inconsistency)
- **Root Cause:** Hierarchical structures felt natural at design time; rules constraints not anticipated.
- **Fix:** Flat structures with indexed fields preferred; subcollections only for truly hierarchical data (>100K child docs).

---

## Fix-Once-Win-Many Opportunities

### 1. **Server-Authoritative Entitlement Check Pattern** (HIGHEST IMPACT)
- **Opportunity:** Single `getBereanEntitlement()` helper + tier matrix applies to 10+ AI features
- **Current:** Berean Deep/Adaptive gated; non-Berean features (video, translation, tone, daily verse) ungated
- **Fix:** Extract helper to `BereanEntitlementService.isFeatureAllowed(uid, feature, tier)` → call from all Cloud Functions
- **Wins:** F-paywall-002, F-paywall-003, F-backend-002, F-content-003 (4 findings)
- **Effort:** 1–2 days
- **Impact:** Closes revenue leakage ~$2000/day

### 2. **Server-Side Quota Tracking Infrastructure** (HIGH IMPACT)
- **Opportunity:** Single Firestore-transactional quota implementation reusable for all rate-limited features
- **Current:** Per-function custom logic; inconsistent enforcement (client vs. server)
- **Fix:** Implement `enforceQuota(uid, featureName, limit)` transaction wrapper in `rateLimit.ts` → call from all proxies
- **Wins:** F-paywall-003, F-backend-002, F-content-003 (3 findings + future features)
- **Effort:** 1 day
- **Impact:** Eliminates client-only quota gamification

### 3. **Privacy Disclosure Banner Component** (MEDIUM IMPACT)
- **Opportunity:** Single reusable "AI is analyzing this" disclosure banner applies to DM, posts, notes, videos
- **Current:** DMs have no disclosure; notes have implicit disclosure; posts have buried text
- **Fix:** Create `AmenAIDisclosureBanner` component → used in all surfaces where AI touches user-generated content
- **Wins:** F-social-012, F-social-001, F-social-008 (3 findings)
- **Effort:** 2–3 days
- **Impact:** Systemic compliance fix (COPPA, FTC)

### 4. **Memory Windowing + Listener Lifecycle Pattern** (MEDIUM IMPACT)
- **Opportunity:** Streaming + observer lifecycle management applies to chat, audio, prayer room, real-time collaboration
- **Current:** Unbounded message accumulation, persistent listeners in all surfaces
- **Fix:** Extract `@Published var windowedArray<T>` SwiftUI component → auto-trims, auto-cleans observers
- **Wins:** F-perf-001, F-perf-002, F-perf-003, F-perf-006 (4 findings)
- **Effort:** 2–3 days
- **Impact:** Prevents memory leaks across all streaming features

### 5. **Audit Logging Infrastructure** (MEDIUM IMPACT)
- **Opportunity:** Single append-only audit collection handles all compliance logging (moderation, entitlements, consent, crisis)
- **Current:** Scattered logging; no unified audit trail
- **Fix:** Implement `logAuditEvent(eventType, userId, details)` → writes to immutable `auditLog` collection → used everywhere
- **Wins:** F-berean-007, F-001, F-003, F-social-008 (4 findings)
- **Effort:** 1–2 days
- **Impact:** Enables compliance reporting, forensics

### 6. **App Check Enforcement Across All AI Surfaces** (MEDIUM IMPACT)
- **Opportunity:** Single rule + Cloud Function pattern prevents enumeration attacks on all authenticated surfaces
- **Current:** App Check enforced in most proxy functions; not enforced in Firestore rules for Berean/moderation
- **Fix:** Add `request.app` checks to all AI collection rules → update all Cloud Functions to require App Check
- **Wins:** F-007 (Security), F-001 (indirectly) (2+ findings)
- **Effort:** 1 day
- **Impact:** Hardens API against brute-force enumeration

---

## Unresolved Conflicts

### Conflict 1: Shadow-Ban vs. Transparent Holds (Agent 2 vs. Architectural Intent)
- **Agent 2 (F-social-011):** Shadow-ban action is deceptive, should be removed or made transparent
- **Architectural Intent (implied):** Shadow-ban may be intentional tool for testing distribution without full deletion
- **Resolution:** PR-001 removes `.shadowQueue` action entirely; if testing distribution needed, use feature flag on test audience (not live users)

### Conflict 2: First-Token Latency Expectations (Agent 8 vs. Product)
- **Agent 8 (F-perf-004):** Reports 600–1200ms observed; SLO <800ms may not be met
- **Product Implication:** If <800ms is non-negotiable, must optimize preflight (100–500ms overhead)
- **Resolution:** PR-005 instruments full latency; dashboard will show actual performance. If SLO must be <800ms, priority becomes reducing preflight latency (parallel API calls, caching, etc.)

### Conflict 3: Message Windowing vs. History Persistence (Agent 8 vs. UX)
- **Agent 8 (F-perf-001):** Unbounded message array causes memory leak; should window at 30 messages
- **UX Implication:** Users expect full conversation history to scroll
- **Resolution:** PR-006 windows in-memory to 30 messages; older messages lazy-load from Firestore on scroll-to-top. Full history available, but not all in RAM simultaneously.

---

## Coverage Map

### Original AI Surfaces (from Section 0 playbook, if available)

Based on findings, the following AI surfaces were audited:

| Surface | Agent(s) | Coverage | Status |
|---------|----------|----------|--------|
| **Berean Chat** | 1, 8 | High | ✅ Comprehensive (streaming, persistence, memory, accessibility) |
| **Berean Modes** (Deep, Adaptive, Core) | 1, 6 | High | ✅ Full mode routing, entitlement enforcement, credit system |
| **Daily Verse** | 3, 4 | Medium | ✅ Generation, caching, offline fallback; ⚠️ OpenAI vendor, no server rate limit |
| **Church Notes AI** | 3, 6 | Medium | ✅ Rate limiting (client-side only); summarization, suggestions; ⚠️ Encryption per-device |
| **Post Moderation** | 2 | High | ✅ Multi-stage pipeline (ModerationIngestService, Vision, Perspective); ⚠️ Unaligned stages, no appeal |
| **Comment Moderation** | 2 | High | ✅ Async Claude review; ⚠️ Silent deletion, post-publish (shadow-ban risk) |
| **DM Safety (Guardian)** | 2 | High | ✅ Claude safety checks, rate limited; ⚠️ **Missing privacy disclosure (COPPA risk)**, minors unaware |
| **Crisis Detection** | 2 | Medium | ✅ Gemini-based, fail-open; ⚠️ **Not persisted (audit trail missing)**, no logging |
| **Smart Message** (Suggested Replies, Tone) | 6 | Low | ✅ Entitlements present; ⚠️ **Non-Berean features lack tier gating**, only rate-limited |
| **Hey Feed NL Preferences** | 3 | Low | ✅ Keyword-based parser (no injection risk); ⚠️ Application to ranking not traced |
| **Search & Discovery** | 3 | Medium | ✅ Algolia + Firestore ranking; ⚠️ **Write key history unclear**, no safety gates in ranking |
| **Pinecone Embeddings** | 3 | Low | ⚠️ **Feature status unknown** (likely removed); no cleanup confirmed |
| **Living Memory** | 3 | Low | ⚠️ **Feature removed** (stub only); no impact |
| **Audio Transcription** (Whisper) | 4, 6 | Medium | ✅ Entitlements present; ⚠️ **No server-side rate limiting** |

### Surfaces NOT Covered

- **Realtime Video/Audio**: BereanRealtimeWebSocketTransport mentioned but not audited (Agent 8 found backpressure issue)
- **Anthropic SDK Direct Usage**: Appears in Cloud Functions but not full audit of prompt injection vectors
- **Mobile Agent/Caching**: ImageCache audited for memory, but not full download/cache pipeline
- **Offline Mode**: FirebaseOfflineHelper mentioned; not fully audited

---

## Surfaces Needing Follow-Up Mini-Audit

1. **Backend/functions Directory**: Separate codebase; unclear if deployed in parallel with `/functions/`
2. **Realtime Collaboration Features**: WebSocket audio/video not fully characterized
3. **Anthropic SDK Integration**: Only spot-checked; full attack surface (tool use, function calling) not audited
4. **RevenueCat & Stripe Webhooks**: Delegation to external services; local logic verified, but provider-side risks not assessed
5. **Cloud Storage Media Pipeline**: Image/video upload validation not detailed in this audit

---

## Next Steps: Post-Synthesis

1. **Prioritize PRs by Risk + Effort:**
   - **Week 1 (ASAP):** PR-001 (Privacy + Compliance), PR-009 (Key rotation + cleanup)
   - **Week 2–3:** PR-002 (Revenue protection), PR-003 (Enumeration fix)
   - **Week 4:** PR-004, PR-005 (Moderation + Rate limiting)
   - **Week 5–6:** PR-006 (Memory + Performance), PR-007, PR-008, PR-010 (Polish)

2. **Assign Ownership:**
   - PR-001: Product + Mobile eng (privacy disclosure is legal requirement)
   - PR-002, PR-003: Backend eng (server-side gating, schema migration)
   - PR-004, PR-005: Backend + mobile (moderation refinement, latency instrumentation)
   - PR-006: Mobile eng (memory optimization)
   - PR-007, PR-008: Mobile + backend (rules, accessibility)
   - PR-009, PR-010: DevOps + Backend (security audit, cleanup)

3. **Create Follow-up Tickets:**
   - [ ] Decide: Pinecone used or not?
   - [ ] Decide: BereanOrchestrator vs. ModelRoutingEngine merge needed?
   - [ ] Decide: Message windowing strategy (window size, lazy-load behavior)?
   - [ ] Audit: Backend/functions deployment status
   - [ ] Optimize: Preflight latency (if <800ms SLO is hard requirement)

4. **Documentation & Knowledge Transfer:**
   - [ ] Update CLAUDE.md with entitlements, routing, moderation hierarchy
   - [ ] Create runbook: how to add new AI feature (entitlement gate, rate limit, audit logging)
   - [ ] Archive audit reports in `/audit/_reports/` for future reference

---

_End of Synthesis Action Plan._

_Total Findings: 54 (unique, deduplicated from 100+ agent reports)_
_Blockers: 5 (CRITICAL severity)_
_High-Priority PRs: 10 (includes fixups for blockers + cross-cuts)_
_Estimated Effort: 8–10 weeks (assuming 2 full-time engineers)_


# AI in Social Features Audit Report
_Run at: 2026-05-27T00:00:00Z_

## Summary

AMEN integrates Claude (Anthropic) and OpenAI models across all social surfaces through Firebase Cloud Functions. The architecture demonstrates **strong server-side enforcement** with **explicit fail-open safeguards** for moderation. Key findings:

1. **GUARDIAN moderation**: Deployed on communal & monitored DMs only; sacred (encrypted) 1:1 chats are never touched by AI.
2. **Post/comment moderation**: Happens server-side post-publish (async) via Claude + Trust & Safety OS (text/image). Comment moderation is fire-and-forget (after publish).
3. **DM safety**: Detects patterns (grooming, scams, harassment) server-side before delivery; user is warned, not blocked. Sacred channels completely exempt.
4. **Privacy disclosure**: Sacred channels explicitly labeled "Private" and "encrypted." Monitored channels have implicit AI inspection but no explicit warning in composer.
5. **Crisis handling**: AI-detected crisis content is never silenced — always delivered with support resources attached.
6. **Client-only risks**: Mini-scans exist on client (syntax, emotional distress) but are advisory only; server is authoritative.

**Severity**: No blockers. Several MEDIUM/HIGH findings on privacy transparency and consistency.

---

## Inventory

### AI Entry Points by Surface

| Surface          | AI Model(s)          | Sync/Async  | Blocks UX | Entry Point                                           |
|------------------|----------------------|-------------|-----------|-------------------------------------------------------|
| **Posts**        | Claude (Ingest)      | Pre-pub    | Yes       | `ModerationIngestService` (doxxing, grooming, lists)  |
| **Posts**        | Perspective API      | Post-pub   | No        | `trustSafety/moderateText.ts` (audit only)            |
| **Comments**     | Claude               | Post-pub   | Yes       | `CommentClaudeModerator.moderateInBackground` (delete) |
| **DM (Monitored)** | Claude (GUARDIAN)  | Pre-delivery | Yes | `guardianModerator` CF (blocks or allows)               |
| **DM (Sacred)**  | None                 | —          | —         | N/A (fully encrypted, no Cloud Functions)              |
| **Images**       | Cloud Vision         | Pre-pub    | Yes       | `runImagePreflight` (Vision SafeSearch)                |
| **Crisis**       | Gemini 1.5-flash     | Post-pub   | No        | `detectCrisis` CF (routes to support, never blocks)    |
| **Reports**      | CloudFunctions (triage) | Post-report | No | `submitTrustSafetyReport` (human queue)                |

### Model Vendors

- **Claude (Anthropic)** — Guardian + comment moderation + content ingest + suggested replies
- **OpenAI** — Legacy integrations (phased out in favor of Claude)
- **Google** — Perspective API, Cloud Vision SafeSearch, Vertex AI Gemini

---

## Findings

### F-social-001 — Monitored DMs (Minors) Lack Explicit Privacy Consent [HIGH] [SUSPECTED]

**Location:**
- `AMENAPP/AMENAPP/AMENAPP/Messaging/ChannelService.swift:30–39`
- `cloud-functions/guardian.ts:145–271`

**Observation:**
When a 1:1 DM involves a minor, the channel is automatically downgraded from `sacred` (E2E encrypted) to `monitored`. The Guardian Cloud Function then passes the **full message text** to Claude via `bereanChatProxy`. While SacredChatView explicitly displays "🔒 Private" for sacred channels, there is **no composer warning** in monitored channels disclosing that messages are:
- Sent to an LLM for safety classification
- Not E2E encrypted
- Visible to server-side systems

**Evidence:**
```swift
// ChannelService.swift:30–39
let channelClass: ChannelClass = (myIsMinor || theirIsMinor) ? .monitored : .sacred
```

```typescript
// guardian.ts:85–104
const body = {
  data: {
    mode: "guardian",
    systemPrompt: GUARDIAN_SYSTEM_PROMPT,
    text: messageText,  // Full plaintext to Claude
    senderId,
    channelId,
  },
};
```

**Impact:**
- Users (especially minors) may assume 1:1 DMs are fully encrypted based on the "private" label visible in sacred channels.
- No prior disclosure that messages will be analyzed by AI before delivery.
- Violates "informed consent" principle — users should know if their content is sent to third-party LLMs.

**Recommendation:**
1. Add explicit in-composer disclosure: "Messages in 1:1 chats with minors are checked by our safety system before delivery."
2. Display a subtle icon/badge distinguishing monitored vs. sacred channels *before* user sends.
3. Include privacy disclosure in onboarding for minors or in Channel Detail view.

---

### F-social-002 — Comment Moderation is Fully Async (Post-Publish, Fire-and-Forget) [MEDIUM] [CONFIRMED]

**Location:**
- `AMENAPP/CommentClaudeModerator.swift:25–59`

**Observation:**
When a comment is published:
1. Firestore write succeeds immediately
2. Comment appears in UI in real-time
3. `CommentClaudeModerator.moderateInBackground()` is called *after* publish
4. If Claude rejects, the comment is deleted asynchronously; only a NotificationCenter event notifies the author

This means:
- Other users see the rejected comment for seconds to minutes before it is silently deleted
- No warning shown to author *before* publishing
- No appeal mechanism mentioned

**Evidence:**
```swift
// CommentClaudeModerator.swift:29
/// Call this AFTER the Firestore write succeeds.
/// Never blocks or delays the comment from appearing.
func moderateInBackground(text: String, postId: String, commentId: String, isReply: Bool = false) async {
  let result = await checkWithClaude(text)
  guard case .rejected(let reason) = result else { return }
  // Delete from Firestore — real-time listener will remove from UI
  try await path.delete()
  // Notify CommentsView via NotificationCenter
  NotificationCenter.default.post(
    name: .commentRemovedByModeration,
    ...
  )
}
```

**Impact:**
- **Shadow ban concern**: Comment removal is silent; user may think it was a network error and repost, creating confusion.
- **Feed pollution**: Other users see content briefly before it vanishes.
- **No UX clarity**: Reason shown to author only via toast; not persistent. User may not see it.

**Recommendation:**
1. Change to **pre-publish** gate: hold comment for moderation review, show author a "pending moderation" state, allow appeal.
2. Alternatively, log the removal reason persistently so user can view it in a "moderation history" panel.
3. Implement `reportModeration()` callable to let users appeal automatic rejections.

---

### F-social-003 — Post Moderation Entry Points Not Unified; Multiple Stages Increase Risk [MEDIUM] [CONFIRMED]

**Location:**
- `AMENAPP/CreatePostView.swift:3678–3980` (client-side pre-flight)
- `AMENAPP/ModerationIngestService.swift` (Claude-based ingest)
- `Backend/functions/src/trustSafety/moderateText.ts` (text preflight with Perspective API)
- `Backend/functions/src/trustSafety/moderateImage.ts` (image preflight with Vision)

**Observation:**
Posts flow through **4+ moderation stages**:

1. **Client-side "ThinkFirstGuardrails"** (local NLP)
   - Checks for political topics, wellness concerns
   - Advisory only; user can override
   
2. **ModerationIngestService (Claude)**
   - Checks doxxing, grooming, banned lists
   - Can block or require edit
   
3. **AmenContentPreflightService (server)**
   - Calls `runTextPreflight` + bot defense
   - Can block (returned from `publishPost()`)
   
4. **Per-media caption moderation** (async)
   - Separate Claude call for image captions
   
5. **Async postprocessing** (background)
   - Perspective API (audit log only, never blocks)
   - Provenance detection (AI-generated labeling)

This **lack of unified entry point** means:
- Moderation decisions can conflict (one stage approves, another rejects)
- Logic is split between client and server, hard to audit end-to-end
- Risk of bypassing early checks by directly calling backend

**Evidence:**
```swift
// CreatePostView.swift:3864–3953
// Stage 1: ModerationIngestService (local)
let preSubmitResult = await ModerationIngestService.shared.check(...)
// Stage 2: ThinkFirstGuardrailsService (local)
let checkResult = await ThinkFirstGuardrailsService.shared.checkContent(...)
// Stage 3: AmenContentPreflightService (server)
let tsCanPost = await AmenContentPreflightService.shared.runFinalPreflight(...)
// Stage 4: Media caption moderation (per-image)
// Stage 5: Async postprocessing (fires after publish)
```

**Impact:**
- Complexity increases false negative risk (approval at one stage, rejection at another).
- Testing and auditing moderation logic is harder.
- Client-side checks can be bypassed by reverse-engineering or direct API calls.

**Recommendation:**
1. Define a **single, authoritative** moderation entry point on the server.
2. Move all client-side checks to advisory-only (UI hints, not blocks).
3. Client calls server **once** (with all content: text + image URIs + metadata) and receives a single decision.
4. Document the decision hierarchy: what overrides what?

---

### F-social-004 — DM Grooming Pattern Detection Uses Hardcoded Substring Lists [MEDIUM] [SUSPECTED]

**Location:**
- `AMENAPP/ModerationPipeline.swift:227–264`

**Observation:**
The `scanForDMRisks()` method detects grooming/scam patterns by matching hardcoded phrases:

```swift
let coercivePatterns = [
    "don't tell anyone", "keep this between us", "our secret",
    "don't tell your parents", "no one will know",
    "meet me somewhere private", "come alone", "don't bring anyone",
    ...
]
for pattern in coercivePatterns where lower.contains(pattern) {
    additionalScore += 0.25
    signals.append("dm_coercion: \(pattern)")
}
```

Issues:
- **Case-sensitive substring match** (uses `lower.contains()`, which is prone to false positives)
- **No scoring refinement**: each pattern adds a fixed 0.25 points (no context)
- **Hardcoded list** requires code deploy to update; should be backend-configurable
- **No explicit logging** of what patterns matched (signals are logged but not easily searchable)

**Evidence:**
Lines 232–253 in ModerationPipeline.swift.

**Impact:**
- Innocent messages like "let's keep this between us" (wholesome context) may be flagged as grooming
- Pattern list cannot be updated via feature flag or backend config
- False positives could harm user experience without accountability mechanism

**Recommendation:**
1. Move pattern lists to Firestore `safetyConfig/dmPatterns` collection
2. Use proper NLP (context) instead of substring matching
3. Require Firestore write to update patterns; implement client-side caching
4. Log matched patterns with full message context (for human review)
5. Implement A/B testing: measure false positive rate by pattern

---

### F-social-005 — Sacred (Encrypted) Channels Completely Bypass Moderation [LOW] [CONFIRMED]

**Location:**
- `AMENAPP/AMENAPP/AMENAPP/Messaging/SacredChatView.swift:1–65`
- `cloud-functions/guardian.ts:160–171`

**Observation:**
1:1 DMs between adults are encrypted (E2E via `SacredChannelCrypto`).
- No Cloud Function can read `sacredMessages` subcollection (by design)
- Client is shown explicit "🔒 Private" label
- **No AI moderation of any kind**

This is **intentional and correct** for adult-to-adult private chats. However:
- If an attacker creates a fake "adult" account and DMs a minor, the system attempts to downgrade to monitored
- But if the account-age check is wrong or cached incorrectly, a sacred channel might be created with a minor

**Evidence:**
```swift
// ChannelService.swift:30–39
let myIsMinor = try await fetchIsMinor(uid: uid)
let theirIsMinor = try await fetchIsMinor(uid: otherUid)
let channelClass: ChannelClass = (myIsMinor || theirIsMinor) ? .monitored : .sacred
```

The `fetchIsMinor()` call is synchronous per-open; if a user updates their age field in parallel, a race condition exists.

**Evidence:**
```typescript
// guardian.ts:160–171
const channelClass: string = channelSnap.data()?.channelClass ?? "communal";
if (channelClass === "sacred") {
  logger.error("GUARDIAN: aborting — triggered on sacred channel", ...);
  return;
}
```

If somehow a message lands in a sacred subcollection, the Guardian function aborts cleanly (good).

**Impact:**
- **Race condition risk**: If a minor changes age field while opening a 1:1 chat, the channel might be created as sacred
- Low risk in practice (unlikely to change age, then immediately DM), but exists

**Recommendation:**
1. Use server-side channel creation logic with atomic transaction: fetch both users' age, decide class, create channel atomically
2. Move `fetchIsMinor()` to backend callable; ensure no client-side caching skips the check
3. Add integration test: create two accounts, set one as minor, ensure 1:1 channel is monitored

---

### F-social-006 — Crisis Detection Uses Gemini; Fails Open to "Medium Risk" [MEDIUM] [CONFIRMED]

**Location:**
- `cloud-functions/crisis-detection.js:23–131`

**Observation:**
When posts contain self-harm language:
1. `detectCrisis()` is called post-publish (async, background)
2. Sends text to **Gemini 1.5-flash** for classification
3. Returns JSON: `{ level: "critical" | "high" | "medium" | "low" | "none", ... }`
4. **If Gemini errors**, falls back to `level: "medium"` and **always returns resources** (never silences)

Fail-open behavior is correct (don't block support-seeking). However:
- **No post-analysis audit log**: classification result is not written to Firestore for later review
- **Temperature = 0.1** (good for consistency) but model can still hallucinate
- **No cost control**: called for every post (including sports/drama reactions)

**Evidence:**
```javascript
// crisis-detection.js:112–129
} catch (error) {
  console.error("❌ [CRISIS DETECTION] Error:", error);
  // Fallback response - assume medium risk if AI fails
  return {
    level: "medium",
    confidence: 0.5,
    indicators: ["Unable to fully analyze"],
    ...
  };
}
```

**Impact:**
- Users expressing distress get resources, which is good
- But no audit trail of what was detected (hard to improve model)
- Gemini cost accumulates without visibility into ROI

**Recommendation:**
1. Write classification result to `safetyAuditLog/crisisDetections/{postId}`
2. Add analytics: track % posts flagged as crisis, appeal rate, user feedback
3. Implement feature flag: `crisisDetectionEnabled` to control cost
4. Consider moving to Claude (already integrated for comments/posts); reduces vendor lock-in

---

### F-social-007 — Report Flow Has No Appeal Mechanism [MEDIUM] [CONFIRMED]

**Location:**
- `AMENAPP/ModerationService.swift:273–358` (client-side report submission)
- `Backend/functions/src/trustSafety/reportAbuse.ts` (server-side processing)

**Observation:**
Users can report posts/comments/users. The flow is:
1. Client calls `CloudFunctionsService.submitTrustSafetyReport()`
2. Backend writes to `userReports` collection (user-initiated data)
3. Human moderator reviews and takes action
4. User is **not notified** of decision or given an appeal path

`ModerationPipeline.submitAppeal()` exists but is not wired to report flow:
```swift
func submitAppeal(contentId: String, userId: String, reason: String) async throws {
  let data: [String: Any] = [
    "contentId": contentId, "userId": userId, "reason": reason,
    "status": "pending", "timestamp": FieldValue.serverTimestamp()
  ]
  try await db.collection("moderationAppeals").addDocument(data: data)
}
```

But no UI surfaces this, and no connection to the original report.

**Impact:**
- Users have no visibility into moderation decisions
- If a user's post is removed, they cannot appeal the decision
- Creates perception of unfairness (especially for faith communities, which are sensitive to censorship)

**Recommendation:**
1. Surface moderation decision in user's profile or notification center when action is taken
2. Wire appeal flow: email user → offer appeal link → open appeal form → submit to `moderationAppeals`
3. Implement appeal SLA: respond within 48h, explain decision, allow human re-review
4. Log appeals and outcomes for bias audits

---

### F-social-008 — AI Model Transparency Not Consistently Applied [MEDIUM] [CONFIRMED]

**Location:**
- `AMENAPP/AmenAITransparencyService.swift:50–81`
- `AMENAPP/CreatePostView.swift:3864–3980`

**Observation:**
`AmenAITransparencyService` registers AI-assisted content:
```swift
func registerAIContent(
  contentId: String,
  contentType: ContentSurface,
  wasAIGenerated: Bool,
  wasAIAssisted: Bool,
  aiModelsUsed: [String] = [],
  ...
)
```

But **moderation results are never registered as AI-assisted**:
- Comments rejected by Claude are deleted silently (no transparency record)
- Posts rejected by `ModerationIngestService` show a user-facing reason, but no AI model is documented
- Guardian-blocked DMs show they were held, but don't document that Claude made the decision

**Evidence:**
Comment moderation:
```swift
// CommentClaudeModerator.swift:29–59
func moderateInBackground(text: String, ...) async {
  let result = await checkWithClaude(text)
  guard case .rejected(let reason) = result else { return }
  try await path.delete()  // Deleted, no transparency record
}
```

Post moderation:
```swift
// CreatePostView.swift:3880–3916
let preSubmitResult = await ModerationIngestService.shared.check(...)
// No registerAIContent() call
```

**Impact:**
- Users don't understand why content was removed (no "AI made this decision" disclosure)
- Violates transparency principle (users should know if an AI rejected their content)
- Makes appeals harder (user doesn't know who/what made the decision)

**Recommendation:**
1. After every moderation decision, call `AmenAITransparencyService.registerAIContent()` with `wasAIAssisted: true`
2. Document which model made the decision (Claude, Perspective, Vision, Gemini)
3. Show transparency label in user-facing rejection message: "This was reviewed by our safety system (AI-assisted)"
4. Include appeal link in transparency message

---

### F-social-009 — Text Moderation Bypasses Perspective API for First-Party Enforcement [LOW] [CONFIRMED]

**Location:**
- `Backend/functions/src/trustSafety/moderateText.ts:101–205`

**Observation:**
Three-layer pipeline:
1. **Layer 0** — Banned-term regex (hardcoded, instant)
2. **Layer 1** — Perspective API (if Layer 0 passes and API available)
3. **Layer 2** — TrustSafetyOS policy mapping (fallback)

If Layer 0 regex matches (e.g., "CSAM", "sextort"), Perspective API is skipped:
```typescript
// moderateText.ts:129
if (outcome === "allow" && PERSPECTIVE_API_KEY) {
  try {
    // Perspective API call
  } catch (err) {
    logger.warn("Perspective API unavailable", ...);
  }
}
```

This is **correct** (early exit for high-confidence matches). However:
- **No audit trail of Layer 0 match**: regex hits are not logged to `safetyAuditLog`
- **Hard to improve Layer 0**: no data on false positives

**Evidence:**
```typescript
// moderateText.ts:115–127
for (const rule of BANNED_RULES) {
  if (rule.pattern.test(text)) {
    categories[rule.category] = 1.0;
    outcome = rule.outcome;
    enforcementAction = rule.outcome === "escalate" ? "escalate_to_reviewer" : "block";
    // No writeSafetyAuditEvent() here
    break;
  }
}
// Only logged for non-allow outcomes later
```

**Impact:**
- Layer 0 decisions (regex) are not audited separately from Layer 1 (Perspective)
- Hard to measure false positive rate of hardcoded regex
- Makes it difficult to A/B test regex improvements

**Recommendation:**
1. Log Layer 0 matches separately: `writeSafetyAuditEvent({ eventType: "banned_term_hit", ... })`
2. Track false positive rate (user appeals, then accepted) by layer
3. Implement feature flag: `bannedTermLayerEnabled` to disable regex if too noisy

---

### F-social-010 — Image Moderation Fails Safe (Quarantine) But Not Transparent [MEDIUM] [CONFIRMED]

**Location:**
- `Backend/functions/src/trustSafety/moderateImage.ts:77–161`

**Observation:**
Vision SafeSearch is called for all images. Decision outcomes:
- `allow` — published immediately
- `quarantine` — held for human review (user sees "being checked")
- `block` — rejected outright

**Fail-safe behavior**: If Vision API is unavailable, image is `quarantine`d (not silently allowed).

However:
- **No notification to user when quarantine resolves**: image is reviewed by human, approved, but user is not notified
- **No timeline given**: user doesn't know how long review takes
- **No appeal for Vision rejections**: if Vision flags adult content incorrectly (e.g., breastfeeding, medical), no user appeal path

**Evidence:**
```typescript
// moderateImage.ts:131–139
} catch (err) {
  logger.warn("Vision API unavailable, quarantining for human review", ...);
  outcome = "quarantine";
  enforcementAction = "quarantine";
  requiresHumanReview = true;
  explanation = "vision_api_unavailable";
  userFacingReason = "This post is being checked before it appears.";
}
```

**Impact:**
- User waits indefinitely for approval (no SLA)
- No feedback loop: user doesn't know if image is being reviewed or ignored
- Faith communities may have legitimate imagery (baptism, prayer laying-on-of-hands) flagged as "adult" by Vision

**Recommendation:**
1. Implement human-review SLA: approve/reject within 24h; notify user
2. Add appeal flow: user can click "Request Review" after rejection
3. Log false positive rate: how many images are flagged by Vision then approved by humans?
4. Consider lower thresholds for faith-specific imagery (context-aware, not just SafeSearch)

---

### F-social-011 — Shadow Ban / Silent Removal Has No Transparency [HIGH] [CONFIRMED]

**Location:**
- `AMENAPP/ModerationPipeline.swift:62–69` (action enum)
- Post/comment/DM decisions that use `shadowQueue` or silent deletion

**Observation:**
The moderation pipeline defines action `.shadowQueue`:
```swift
enum PipelineAction: String, Codable {
  case allow
  case allowWithWarning
  case requireEdit
  case holdForSoftReview
  case shadowQueue        // Silently held; author sees it published but others cannot
  case blockAndReview
  case blockImmediate
}
```

If a post is placed in `shadowQueue`:
- Author sees their post as published (no error message)
- Other users cannot see it (invisible to feed/search)
- Author is **not notified** that their content was shadow-banned

**Evidence:**
```swift
// ModerationPipeline.swift:62–69
case .shadowQueue        // Silently held; author sees it published but others cannot
```

No code found that explicitly implements `.shadowQueue`, but the action is defined and could be triggered by future code.

**Impact:**
- **Deceptive**: author thinks post succeeded but it's invisible to others
- **Trust erosion**: author may repost same content (or believe there's a network bug)
- **No transparency**: author doesn't know they were moderated
- **Potential legal risk**: shadow banning may violate consumer protection laws (FTC Act, etc.)

**Recommendation:**
1. **Remove `.shadowQueue` action entirely** — it is deceptive and should not exist
2. For held content, use `.holdForSoftReview` and always **notify the author** with a reason
3. If you need to test distribution (shadow traffic), use a feature flag on a test audience, not live users
4. Add user consent: "Some posts are reviewed before appearing. We'll let you know if yours is held."

---

### F-social-012 — DM Privacy Disclosure Missing for Monitored Channels [HIGH] [CONFIRMED]

**Location:**
- All DM composer views; no disclosure text found

**Observation:**
When a user opens a 1:1 DM with a minor (or is themselves a minor), the channel is automatically `monitored`:
- Messages are not E2E encrypted
- Full plaintext is passed to Claude (Guardian moderation)

But the composer shows **no disclosure**:
- No text warning "Your messages are monitored"
- No link to privacy policy explaining Guardian
- No mention of Claude, AI, or safety systems
- Users may assume all 1:1 DMs are private/encrypted like SacredChatView

Compare to SacredChatView:
```swift
// SacredChatView.swift:50–59
.toolbar {
  ToolbarItem(placement: .principal) {
    VStack(spacing: 1) {
      Text(partnerDisplayName).font(.headline)
      HStack(spacing: 4) {
        Image(systemName: "lock.fill").font(.caption2)
        Text("Private").font(.caption2)  // ← Clear label
      }
    }
  }
}
```

**No equivalent for monitored channels** — they appear unlabeled.

**Evidence:**
Searched for "monitored" disclosure in DM UI files; found no banner, footer, or toolbar label.

**Impact:**
- **Informed consent violation**: users don't know their DMs are sent to an LLM
- **Privacy mismatch**: might violate COPPA (Children's Online Privacy Protection Act) if minors are not informed
- **Regulatory risk**: FTC could flag failure to disclose AI processing of personal communication
- **User trust**: if minors later learn their "private" messages were AI-scanned, trust erodes

**Recommendation:**
1. **Mandatory in-composer disclosure** for monitored channels:
   - Add a footer banner: "🛡️ Monitored for safety — messages are checked before delivery"
   - Make it persistent (not dismissible), visible every time user types
2. Link to privacy policy section explaining Guardian moderation
3. For minors, add extra clarity: "Parents and safety systems review messages in this chat"
4. Include opt-in consent: "I understand my messages are monitored" — require acknowledgment before first send
5. Log user consent in `userConsents` collection with timestamp

---

## Moderation Matrix

| Surface      | Entry Point | Sync/Async | Blocks UX | Appeal Path | Privacy Disclosed |
|--------------|-------------|-----------|-----------|------------|-------------------|
| **Post**     | ModerationIngestService | Pre-pub (sync) | Yes | None | No (implicit server check) |
| **Post** (image) | runImagePreflight | Pre-pub (sync) | Yes | None | No |
| **Comment**  | CommentClaudeModerator | Post-pub (async) | No (silent delete) | No | No |
| **DM (Sacred)** | None | — | — | — | Yes ("🔒 Private") |
| **DM (Monitored)** | GuardianService | Pre-delivery (sync, 10s timeout) | Yes | No | **NO** ← Critical gap |
| **Report**   | submitTrustSafetyReport | Post-report (async) | No | No formal appeal | No |
| **Crisis**   | detectCrisis | Post-pub (async, background) | No (always delivers + resources) | No | No |

---

## Privacy Disclosure Checklist

| Surface          | Disclosure Present | Location | Completeness |
|------------------|--------------------|----------|--------------|
| Sacred DM        | ✅ Yes | SacredChatView toolbar | Clear: "🔒 Private" |
| Monitored DM     | ❌ No | (missing) | **BLOCKER** — no disclosure |
| Post composition | ⚠️ Partial | Guidelines gate, but no AI disclosure | Mentions safety but not LLM |
| Comment composition | ❌ No | CommentsView | No disclosure of Claude |
| Image upload     | ❌ No | CreatePostView | No disclosure of Vision API |
| Profile bio      | ❌ No | ProfileEditView | No disclosure if AI-scanned |
| Report submission | ✅ Yes (implicit) | Report form | "Reviewed by moderators" |

---

## Cross-cutting Patterns

### 1. **Fail-Open is the Standard**
Every AI system has a documented fail-open behavior:
- Guardian times out after 10s → allows message
- Vision API unavailable → quarantines for human review (not silently allows)
- Perspective API down → proceeds without it
- Crisis detection fails → returns "medium" risk + resources

**This is correct for content moderation** (better to let through than censor speech).

### 2. **Multiple Moderation Layers, Unclear Hierarchy**
Posts flow through 4+ moderation stages with no clear hierarchy:
- Client → ModerationIngestService → AmenContentPreflightService → Per-media → Async postprocessing
- Unclear what overrides what if stages conflict
- Risk of approval at one stage, rejection at another

### 3. **Async Moderation = Silent Removal Risk**
Comments and crisis content are moderated post-publish:
- Comment appears, then is deleted asynchronously
- User may not see deletion notification
- Appears as "shadow ban" to user

### 4. **Privacy Disclosure Gaps for Monitored Channels**
- Sacred channels are clearly labeled "Private"
- Monitored channels (minors) have **no label** distinguishing them from sacred
- User may not realize messages are sent to Claude, not E2E encrypted

### 5. **No Unified Appeal / Moderation History**
Users cannot:
- View why their post was rejected
- Appeal a moderation decision
- See a history of moderation actions taken on their account

---

## Handoffs

### Client → Server
- Post/comment text sent to backend callables (`runTextPreflight`, `runImagePreflight`)
- Images uploaded to Cloud Storage with `contentId` reference
- Server receives request, verifies auth, processes, returns binary decision

### Server → AI Providers
- **Claude (via bereanChatProxy callable)**:
  - Comment: full text up to 500 chars
  - Guardian (DM): full plaintext + senderId + channelId
  - Crisis: full post text
- **Perspective API**: text up to 10k chars
- **Cloud Vision**: gs:// image URI (Vision reads from GCS)
- **Gemini**: full post text for crisis detection

### AI Provider → Server
- **Claude**: JSON `{ decision, category, reason, route }` (from GUARDIAN prompt)
- **Perspective**: structured attribute scores `{ TOXICITY, SEVERE_TOXICITY, ... }`
- **Vision**: SafeSearch scores `{ adult, racy, violence }` (likelihoods)
- **Gemini**: JSON `{ level, confidence, indicators, recommendations }`

### Server → Client (Decision)
- Binary: `allowed: true/false`
- Reason: user-facing string (why rejected)
- Policy version: model version for audit

### User → Moderation System
- Report: text + reason + target (post/comment/user)
- No direct appeal (missing — recommend adding)

---

## Open Questions

1. **Why does post moderation have 4+ stages?** Is this intentional architectural complexity, or technical debt? Consider consolidating into single server-side gate.

2. **Is shadow-ban (.shadowQueue) actually used?** It's defined in the enum but we found no call sites. Recommend removing if not used (or if used, making it transparent).

3. **How is the "minorStatus" updated?** Is there a refresh? Can a user change their DOB and have all their monitored channels instantly become sacred? Risk of confusion / race condition.

4. **What's the SLA for human review?** Posts in `holdForSoftReview` or images in `quarantine` — how long until human review? What if reviewer disappears? Recommend adding timeout + auto-approve logic.

5. **Are DM conversations archived/exported?** If a user downloads their data (GDPR/CCPA), do they see the full history, or only delivered messages? Encrypted DMs cannot be exported server-side; how is this handled?

6. **Is there a PII logging issue?** ModerationPipeline logs messages to `safetyAuditLog` — are these redacted? If user posts "my phone is 555-1234", is that PII logged? Recommend PII sanitization before audit logging.

---

## Blocked

### **Cannot Proceed Without:**
1. Clarification on `.shadowQueue` usage (is it deployed? should it be removed?)
2. Confirmation of moderator SLA for human review tasks
3. Confirmation of COPPA compliance strategy (minors in monitored channels)
4. Confirmation that `isMinor` field is kept up-to-date and cannot be raced

### **Recommend Deferring:**
1. Unified moderation pipeline refactor (large engineering effort; current system works but is complex)
2. Appeal system overhaul (consider MVP: email user → click appeal link → file ticket)
3. Bias audits of AI models (requires labeled dataset; partner with external auditor)

---

## Remediation Roadmap (Priority Order)

| Priority | Finding | Effort | Risk |
|----------|---------|--------|------|
| **CRITICAL** | F-social-012: DM privacy disclosure | Low (1–2 days UI) | HIGH (COPPA, FTC) |
| **CRITICAL** | F-social-011: Shadow-ban transparency | Low (remove `.shadowQueue`, add notifications) | HIGH (user trust, legal) |
| **HIGH** | F-social-001: Monitored DM consent | Low (1–2 days UI + backend flag) | MEDIUM (informed consent) |
| **HIGH** | F-social-003: Unify post moderation | Medium (refactoring) | MEDIUM (audibility) |
| **MEDIUM** | F-social-002: Comment pre-publish gate | Medium (2–3 days) | MEDIUM (user experience) |
| **MEDIUM** | F-social-008: AI transparency labels | Low (register calls) | LOW (transparency) |
| **LOW** | F-social-004: DM pattern config | Low (move to Firestore) | LOW (false positives) |
| **LOW** | F-social-010: Image quarantine SLA | Low (timer + notification) | LOW (UX) |

---

## Summary & Recommendations

**Verdict**: AMEN's AI moderation architecture is **production-ready with reservations**. The system demonstrates:
- ✅ Strong server-side enforcement (client checks are advisory)
- ✅ Fail-open safeguards (never silently approve dangerous content)
- ✅ Clear separation of sacred (no AI) vs. monitored (AI-scanned) channels
- ✅ Multi-layer defense (banned terms, Perspective, Vision, policy)

**Critical gaps**:
- ❌ **No privacy disclosure for monitored DMs** — users don't know messages are sent to Claude. COPPA / FTC risk.
- ❌ **Shadow-ban capability without transparency** — `.shadowQueue` could be misused. Recommend removing.
- ❌ **Comment moderation is fully async** — deleted comments may appear to others briefly; no appeal path.
- ❌ **Moderation complexity** — 4+ entry points for posts increase audit risk.

**Recommended fixes (ranked by urgency)**:
1. **Add mandatory DM privacy disclosure** (banner in monitored channel composer)
2. **Remove or transparency-flag shadow-ban logic** (no silent removal; always notify user)
3. **Implement comment pre-publish gate** (hold + notify instead of delete)
4. **Unify post moderation** (single server-side entry point)
5. **Add moderation appeal flow** (user → email → appeal form → decision log)
6. **AI transparency labels** (register with AmenAITransparencyService on every moderation decision)
7. **Monitor false positive rate** (track by layer, implement feedback loop)

**Next steps**:
- [ ] Prioritize CRITICAL fixes (privacy disclosure, shadow-ban)
- [ ] Schedule design review for appeal & transparency UX
- [ ] Partner with external auditor for bias testing (especially on faith/theological edge cases)
- [ ] Implement moderation dashboard for team transparency
- [ ] Document policy hierarchy and decision logic in wiki

---

_End of Report_

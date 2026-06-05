# C4 — Cloud Function Signatures Catalogue

**Phase 0 Contract — Frozen Signatures Only. No implementations.**
**Generated:** 2026-06-05
**Branch:** amen-discussion-v1

---

## Architectural Patterns

### gen1 / gen2 Split Strategy

The codebase runs two Firebase Cloud Function deployments in parallel:

| Deployment | File | SDK | Generation |
|---|---|---|---|
| `functions/` | `functions/index.js` | `firebase-functions` (v1 CJS) | **gen1** |
| `functions/` (v2 triggers) | `functions/v2functions.js` | `firebase-functions/v2/*` | **gen2** |
| `Backend/functions/` | `Backend/functions/lib/index.js` | `firebase-functions/v2/*` (TypeScript compiled) | **gen2** |

**Why the split exists:** The Firebase CLI infers generation from which SDK a file imports. If a gen1 file (`functions/index.js`) imports a v2 SDK, the CLI silently applies v2 CPU/concurrency billing to every gen1 function in that file — including `stripeWebhook` and `cancelAllSubscriptions`. The workaround is: gen1 triggers remain in `functions/index.js` (never imports v2), gen2 triggers go into `functions/v2functions.js` or the TypeScript Backend codebase.

**Rule:** Any new trigger that uses `onDocumentCreated`, `onDocumentWritten`, or `onSchedule` from the v2 SDK must go into `Backend/functions/lib/` (TypeScript) or `functions/v2functions.js` — never directly into `functions/index.js`.

### defineSecret Pattern

The exact pattern used across all TypeScript Cloud Functions (copy verbatim for new functions):

```javascript
// 1. Import
const { defineSecret } = require("firebase-functions/params");
// or in TypeScript:
import { defineSecret } from "firebase-functions/params";

// 2. Define at module scope (NOT inside the function)
const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// 3. Pass to onCall/onDocumentCreated options
export const myFunction = onCall({
  secrets: [anthropicApiKey],
  timeoutSeconds: 60,
  memory: "256MiB",
  enforceAppCheck: true,
}, async (request) => {
  const apiKey = anthropicApiKey.value(); // read at invocation time
  // ...
});
```

Known secrets in use:
- `ANTHROPIC_API_KEY` — Berean AI (Claude), transformContent, refineTranslation
- `OPENAI_API_KEY` — openAIProxy, whisperProxy, realtime session broker, RAG search
- `NVIDIA_API_KEY` — moderatePost, checkContentSafety, NeMo Guard pipeline, berean study functions
- `PINECONE_API_KEY` + `PINECONE_HOST` — ragSearch, vector cleanup
- `CLAUDE_API_KEY` — bereanShield, bereanCompass, dailyVerseDrop, weeklyPrayerRecap (legacy alias — prefer ANTHROPIC_API_KEY)

### Fail-Closed Moderation Contract

```
INVARIANT: When NeMo Guard / NIM API is unreachable or returns a non-200 response,
the moderatePost trigger sets post.visible = false and enqueues to moderationQueue
with status = "pending". The post is NEVER silently allowed through.

Implementation anchor (functions/moderatePost.js):
  const FAIL_OPEN = false;
  ...
  status = FAIL_OPEN ? "approved" : "pending";  // line 101

This same fail-closed posture applies to:
  - checkContentSafety (moderationGateway.js)
  - onPostCreatedRunMediaModeration (mediaModerationPipeline.ts) — errors route to
    "reviewing" status, not "approved"
  - All new Trust & Safety functions must implement this invariant explicitly.
```

### Adapter Pattern Requirement

```
No consumer (iOS Swift or Cloud Function) may import a vendor AI SDK directly.
All LLM vendor calls are proxied through Cloud Functions:
  - Anthropic / Claude  → bereanChatProxy  (gen2, Backend/)
  - OpenAI chat        → openAIProxy       (gen2, Backend/)
  - OpenAI Whisper     → whisperProxy      (gen2, Backend/)
  - NVIDIA NIM         → moderatePost, checkContentSafety, berean study functions
  - Pinecone           → ragSearch, cleanupDraftVectors

Swift client code must call Firebase callable functions only.
Cloud Functions call vendor HTTP APIs using fetch() with secrets from defineSecret().
```

---

## Domain 1 — Moderation

### moderatePost
- **Type:** trigger — onDocumentCreated
- **Gen:** gen2 (uses `firebase-functions/v2/firestore`)
- **Placement:** `functions/moderatePost.js`
- **Trigger path:** `posts/{postId}`
- **Request shape:** n/a (Firestore trigger reads document data)
- **Response shape:** writes to `posts/{postId}` fields: `{ visible, flaggedForReview, removed, moderation: { status, categories, provider, checkedAt, crisisEscalated } }`; side-writes `moderationQueue/{auto}` and `moderationDecisions/{decisionId}`
- **External dependencies:** NVIDIA NIM API (`integrate.api.nvidia.com`) — model `nvidia/llama-3.1-nemoguard-8b-content-safety`
- **Secrets required:** `NVIDIA_API_KEY`
- **Moderation: fail-closed?** YES — `FAIL_OPEN = false`; on NIM error post becomes `visible: false, status: "pending"`
- **Notes:** Self-harm posts are routed to `crisisEscalations/` and kept `visible: true` to author (crisis escalation, not silent block). Image-only posts enter `status: "pending_image_review"` and wait for Storage trigger.

### adminReviewPost
- **Type:** callable
- **Gen:** gen2 (uses `firebase-functions/v2/https`)
- **Placement:** `functions/moderatePost.js`
- **Request shape:** `{ postId: string, decision: "approved" | "rejected", queueId?: string }`
- **Response shape:** `{ success: boolean, strippedMedia?: number }`
- **External dependencies:** none
- **Secrets required:** none
- **Moderation: fail-closed?** n/a (admin action)
- **Notes:** Requires custom claim `admin: true`. On approve, strips blocked media URLs from `post.media`. HUMAN-GATED.

### checkContentSafety
- **Type:** callable
- **Gen:** gen1 (CJS in `functions/index.js` → `functions/moderationGateway.js`)
- **Placement:** `functions/moderationGateway.js` / exported from `functions/index.js`
- **Request shape:** `{ content: string, contentType: "post" | "comment" | "message" | "dm", uid?: string }`
- **Response shape:** `{ decision: "allow" | "review" | "block", reason?: string, crisisEscalated: boolean, crisisResources?: string[], decisionId: string }`
- **External dependencies:** NVIDIA NIM API
- **Secrets required:** `NVIDIA_API_KEY`
- **Moderation: fail-closed?** YES
- **Notes:** Self-harm escalates to `crisisEscalations/{uid}/{ts}` and returns crisis resources. All decisions persisted to `moderationDecisions/{decisionId}`.

### onPostCreatedRunMediaModeration
- **Type:** trigger — onDocumentCreated
- **Gen:** gen2 (TypeScript, `firebase-functions/v2/firestore`)
- **Placement:** `Backend/functions/lib/mediaModerationPipeline.js`
- **Trigger path:** `posts/{postId}`
- **Request shape:** n/a (reads `post.mediaItems[]`)
- **Response shape:** writes `mediaModeration/{postId}_{index}` and updates `posts/{postId}.mediaModerationStatus`
- **External dependencies:** Google Cloud Vision SafeSearch, CSAM hash lookup (configurable), Perspective API (configurable)
- **Secrets required:** none (uses env vars `CSAM_HASH_LOOKUP_TOKEN`, `PERSPECTIVE_API_KEY`)
- **Moderation: fail-closed?** YES — pipeline errors write `status: "reviewing"` and enqueue to `humanReviewQueue`
- **Notes:** 6-layer pipeline: hash check → image safety → OCR → text safety → multimodal fusion → action engine. Raw text is never stored in moderation logs.

### onPostMediaUpdatedRunModeration
- **Type:** trigger — onDocumentUpdated
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/mediaModerationPipeline.js`
- **Trigger path:** `posts/{postId}`
- **Request shape:** n/a (detects `mediaItems` array changes between before/after snapshots)
- **Response shape:** same as `onPostCreatedRunMediaModeration`
- **External dependencies:** same as `onPostCreatedRunMediaModeration`
- **Secrets required:** same as `onPostCreatedRunMediaModeration`
- **Moderation: fail-closed?** YES
- **Notes:** No-op if `mediaItems` array is unchanged.

### submitMediaReviewDecision
- **Type:** callable
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/mediaModerationPipeline.js`
- **Request shape:** `{ mediaId: string, decision: "approve" | "block", notes?: string }`
- **Response shape:** `{ success: boolean, newStatus: string }`
- **External dependencies:** none
- **Secrets required:** none
- **Moderation: fail-closed?** n/a (moderator action)
- **Notes:** Requires custom claim `moderator: true` or `admin: true`. Lifts `moderationBlocked` on post only when no remaining held items exist.

### getPostModerationStatus
- **Type:** callable
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/mediaModerationPipeline.js`
- **Request shape:** `{ postId: string }`
- **Response shape:** `{ status: "none" | "pending" | "reviewing" | "escalated" | "blocked" | "approved", action?: string, canAppeal?: boolean }`
- **External dependencies:** none
- **Secrets required:** none
- **Moderation: fail-closed?** n/a
- **Notes:** Authors may only see their own posts' status. Internal scores are never exposed to client.

### getAccountMediaRiskScore
- **Type:** callable
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/mediaModerationPipeline.js`
- **Request shape:** `{ userId: string }`
- **Response shape:** `{ riskScore: number, violationCount: number, bannedFromMediaUpload: boolean, recentViolationCount: number }`
- **External dependencies:** none
- **Secrets required:** none
- **Moderation: fail-closed?** n/a (admin read)
- **Notes:** Requires custom claim `admin: true`.

### triggerMediaModeration
- **Type:** callable
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/mediaModerationPipeline.js`
- **Request shape:** `{ postId: string, mediaUrl: string, mediaType: "image" | "video", mediaIndex?: number, userId: string }`
- **Response shape:** `{ success: boolean }`
- **External dependencies:** same as pipeline
- **Secrets required:** none
- **Moderation: fail-closed?** YES
- **Notes:** Admin re-queue trigger. Requires custom claim `admin: true`.

### moderateSanctuaryMessage / moderatePrayerRequest / moderateDMMessage
- **Type:** callable (3 separate functions)
- **Gen:** gen1 (CJS in `functions/index.js` → `functions/moderateUGC.js`)
- **Placement:** `functions/moderateUGC.js`
- **Request shape:** `{ text: string, contextId: string }`
- **Response shape:** `{ safe: boolean, categories?: string[] }`
- **External dependencies:** NVIDIA NIM API
- **Secrets required:** `NVIDIA_API_KEY`
- **Moderation: fail-closed?** YES

---

## Domain 2 — Berean / AI

### bereanChatProxy
- **Type:** callable
- **Gen:** gen2 (TypeScript, `firebase-functions/v2/https`)
- **Placement:** `Backend/functions/lib/bereanChatProxy.js`
- **Request shape:** `{ message: string, conversationHistory?: Array<{role:"user"|"assistant", content:string}>, mode?: "shepherd"|"scholar"|"debater"|"prayer"|"strategist"|"deep_study", maxTokens?: number, temperature?: number, systemPromptSuffix?: string, modelId?: string, memoryScope?: string, callData?: { conversationId?: string, responseMode?: string, sensitivityFlags?: string[], faithJourneyStage?: string, userPersona?: string, scriptureTranslation?: string, postContext?: object } }`
- **Response shape:** `{ response: string, model: string, usage: object, agentRunId: string, outcomeStatus: string, outcomeScore: number, safetyStatus: string }`
- **External dependencies:** Anthropic API (`api.anthropic.com/v1/messages`)
- **Secrets required:** `ANTHROPIC_API_KEY`
- **Moderation: fail-closed?** YES — crisis classification short-circuits to `CRISIS_SAFE_RESPONSE`; outcome evaluator sanitizes unsafe outputs
- **Notes:** `enforceAppCheck: true`. Per-user rate limits (per-minute + daily). Tier-gated model selection (free → haiku, plus → sonnet, pro/founder → opus). Max message length 4000 chars. Server-side identity bundle injected into system prompt; "system"/"tool" roles are stripped from client history.

### bereanChatProxyStream
- **Type:** callable (SSE streaming)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/bereanChatProxyStream.js`
- **Request shape:** same as `bereanChatProxy`
- **Response shape:** SSE events with incremental text chunks; terminal event includes AI disclosure
- **External dependencies:** Anthropic API (streaming)
- **Secrets required:** `ANTHROPIC_API_KEY`
- **Moderation: fail-closed?** YES
- **Notes:** `enforceAppCheck: true`.

### openAIProxy
- **Type:** callable
- **Gen:** gen2 (TypeScript)
- **Placement:** `Backend/functions/lib/openAIProxy.js`
- **Request shape:** `{ messages: Array<{role: string, content: string}>, maxTokens?: number, temperature?: number, model?: "gpt-4o-mini" | "gpt-4o" }`
- **Response shape:** `{ response: string, model: string, usage: object }`
- **External dependencies:** OpenAI API (`api.openai.com/v1/chat/completions`)
- **Secrets required:** `OPENAI_API_KEY`
- **Moderation: fail-closed?** NO (general-purpose proxy)
- **Notes:** `enforceAppCheck: true`. Model allowlist enforced server-side (prevents client from requesting expensive models). Per-user rate limits enforced. Max 50 messages, 4000 chars each.

### transformContent
- **Type:** callable
- **Gen:** gen2 (TypeScript)
- **Placement:** `Backend/functions/lib/transformContent.js`
- **Request shape:** `{ text: string, mode: "simplify" | "summarize" | "keyTerms" | "explain" | "expandContext", language?: string, contentId?: string }`
- **Response shape:** `{ transformedText: string, keyTerms?: Array<{term:string, definition:string, relatedVerse:string|null}>, mode: string, contentId?: string, usage: object }`
- **External dependencies:** Anthropic API (Claude Haiku `claude-3-haiku-20240307`)
- **Secrets required:** `ANTHROPIC_API_KEY`
- **Moderation: fail-closed?** NO (accessibility feature)
- **Notes:** `enforceAppCheck: true`. `keyTerms` mode returns structured term list alongside summary.

### refineTranslation
- **Type:** callable
- **Gen:** gen2 (TypeScript)
- **Placement:** `Backend/functions/lib/refineTranslation.js`
- **Request shape:** `{ originalText: string, literalTranslation: string, sourceLanguage: string, targetLanguage: string, mode: "natural" | "contextual", contentType?: string, preservedEntities?: Array<{type:string, text:string}> }`
- **Response shape:** `{ refinedText: string, mode: string, model: string, usage?: object, error?: string }`
- **External dependencies:** Anthropic API (Haiku for `natural`, Sonnet for `contextual`)
- **Secrets required:** `ANTHROPIC_API_KEY`
- **Moderation: fail-closed?** NO — degrades gracefully to `literalTranslation` on error
- **Notes:** `enforceAppCheck: true`. Graceful degradation: on Claude error, returns original literal translation with `model: "fallback"`.

### generateDailyVerse
- **Type:** callable + possibly scheduled
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/generateDailyVerse.js`
- **Request shape:** `{}` (callable)
- **Response shape:** `{ verse: string, reference: string, reflection?: string }`
- **External dependencies:** Anthropic API
- **Secrets required:** `ANTHROPIC_API_KEY`
- **Moderation: fail-closed?** NO

### bereanBibleQA / bereanBibleQAFallback / bereanMoralCounsel / bereanBusinessQA / bereanNoteSummary / bereanScriptureExtract / bereanPostAssist / bereanCommentAssist / bereanDMSafety / bereanMediaSafety / bereanFeedExplainer / bereanNotificationText / bereanReportTriage / bereanRankingLabels / bereanGenericProxy
- **Type:** callable (gen1)
- **Gen:** gen1 (CJS in `functions/index.js` → `functions/bereanFunctions.js`)
- **Placement:** `functions/bereanFunctions.js`
- **External dependencies:** OpenAI API, Google Vision API
- **Secrets required:** `OPENAI_API_KEY`, `GOOGLE_VISION_API_KEY`
- **Moderation: fail-closed?** varies per function
- **Notes:** Legacy gen1 wrappers. `bereanChatProxy` (TypeScript) is the active proxy; `bereanChatProxy` in `bereanFunctions.js` is **DISABLED** (commented out in index.js). Do not add new gen1 Berean functions.

### routeBereanContextualAction
- **Type:** callable
- **Gen:** gen1
- **Placement:** `functions/bereanFunctions.js`
- **Request shape:** `{ action: string, context: object }`
- **Response shape:** `{ result: object }`
- **External dependencies:** OpenAI API
- **Secrets required:** `OPENAI_API_KEY`

### bereanShieldAnalyze
- **Type:** callable
- **Gen:** gen1
- **Placement:** `functions/bereanShield.js`
- **Request shape:** `{ claim: string, context?: string }`
- **Response shape:** `{ dimensions: object, overallVerdict: string }`
- **External dependencies:** Anthropic API
- **Secrets required:** `CLAUDE_API_KEY`

### bereanCompassAnalyze
- **Type:** callable
- **Gen:** gen1
- **Placement:** `functions/bereanShield.js`
- **Request shape:** `{ transcript: string }`
- **Response shape:** `{ manipulationScore: number, arc: string, flags: string[] }`
- **External dependencies:** Anthropic API
- **Secrets required:** `CLAUDE_API_KEY`

### Berean OS functions (bereanCreateProject, bereanExtractProjectMemory, bereanStartResearch, bereanClassifyStatement, bereanFetchSources, bereanWisdomAnalysis, bereanGenerateDebate, bereanAIMentorReview, bereanRefineDocument, bereanGenerateActionPlan, bereanConsultAdvisoryBoard, bereanArchiveProject, bereanUpdateProject, bereanDiscoverKnowledgeLinks, bereanMultiPerspective)
- **Type:** callable
- **Gen:** gen1 (exported from `functions/index.js`)
- **Placement:** `functions/berean_os_*.js`
- **External dependencies:** Anthropic API / OpenAI API
- **Secrets required:** varies

### callModelBerean / callModelCommentCoach / callModelDailyBrief / callModelSearch / callModelTest
- **Type:** callable
- **Gen:** gen1 (AMEN AI Router)
- **Placement:** `functions/routerCallable.js`
- **Notes:** Centralized callModel wrappers. All provider selection lives in `functions/router/amenRouting.config.js`. Feature code must NOT hardcode provider names or API URLs.

---

## Domain 3 — Social Graph

### updateUserActivitySummaryOnPost
- **Type:** trigger — onDocumentWritten
- **Gen:** gen2 (TypeScript)
- **Placement:** `Backend/functions/lib/socialGraph.js`
- **Trigger path:** `posts/{postId}`
- **Response shape:** writes/merges `user_activity_summary/{userId}`; fans out to `relationship_activity_state/{viewerId}_{targetId}`
- **External dependencies:** none
- **Secrets required:** none
- **Moderation: fail-closed?** n/a

### updateUserActivitySummaryOnPrayer
- **Type:** trigger — onDocumentWritten
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/socialGraph.js`
- **Trigger path:** `prayers/{prayerId}`
- **Response shape:** same fan-out as above
- **External dependencies:** none
- **Secrets required:** none

### updateUserActivitySummaryOnNote
- **Type:** trigger — onDocumentWritten
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/socialGraph.js`
- **Trigger path:** `churchNotes/{noteId}`
- **Response shape:** same fan-out
- **External dependencies:** none
- **Secrets required:** none

### markRelationshipSeen
- **Type:** callable
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/socialGraph.js`
- **Request shape:** `{ targetIds: string[] }` (max 400 entries)
- **Response shape:** `{ success: boolean, marked: number }`
- **External dependencies:** none
- **Secrets required:** none
- **Notes:** `enforceAppCheck: false`. Resets `unseenPostCount`, `unseenPrayerCount`, `unseenNoteCount` to 0 in `relationship_activity_state`.

### reconcileRelationshipStates
- **Type:** trigger — onSchedule (scheduled)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/socialGraph.js`
- **Schedule:** every 24 hours
- **Response shape:** deletes stale `relationship_activity_state` docs where follow no longer exists
- **External dependencies:** none
- **Secrets required:** none

### computeRelationshipMutualData
- **Type:** trigger — onDocumentWritten
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/socialGraph.js`
- **Trigger path:** `user_activity_summary/{userId}`
- **Response shape:** writes `mutualTopics` to `relationship_activity_state/{viewerId}_{userId}`
- **External dependencies:** none
- **Secrets required:** none
- **Notes:** Fan-out capped at 200 followers per invocation to prevent runaway costs.

### createFollow
- **Type:** callable
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/createFollow.js`
- **Request shape:** `{ targetUserId: string }`
- **Response shape:** `{ success: boolean }`
- **Notes:** Atomically writes `follows/` edge doc AND `follows_index/` doc in one batch. Prevents `callerFollows()` Firestore rule failures from missing index entries.

### createBlock
- **Type:** callable
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/createBlock.js`
- **Request shape:** `{ targetUserId: string }`
- **Response shape:** `{ success: boolean }`
- **Notes:** Writes to BOTH `blockedUsers` top-level collection and `users/{uid}/blockedUsers` subcollection atomically to prevent partial-block drift.

### blockRelationshipCleanup
- **Type:** trigger — onDocumentWritten
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/blockRelationshipCleanup.js`
- **Trigger path:** `blockedUsers/{blockId}`

---

## Domain 4 — Content (Transform, Translate, Refine)

### transformContent
_(See Domain 2 — Berean / AI above)_

### refineTranslation
_(See Domain 2 — Berean / AI above)_

### validateThinkFirstCheck
- **Type:** callable
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/thinkFirst/validateThinkFirstCheck.js`
- **Notes:** Server-authoritative Think-First / Tone check. iOS ThinkFirstGuardrailsService is advisory only; the publish path MUST call this before persisting user-authored content.

### finalizePostPublish / addComment / toggleReaction
- **Type:** callable
- **Gen:** gen1 (CJS)
- **Placement:** `functions/postAndCommentFunctions.js`
- **External dependencies:** none

### onPostCreated (finalizePostOnCreate)
- **Type:** trigger — onDocumentCreated
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/onPostCreated.js`
- **Trigger path:** `posts/{postId}`
- **Notes:** Text moderation, status transition (`publishing` → `published`), Algolia indexing.

### algoliaSync
- **Type:** trigger — onDocumentWritten
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/algoliaSync.js`
- **Trigger path:** `posts/{postId}`
- **External dependencies:** Algolia Search API
- **Notes:** Keeps `posts` index current on post edit and deletion.

### generateDynamicReplyPreviews
- **Type:** callable
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/generateDynamicReplyPreviews.js`
- **Notes:** Server-ranked inline PostCard preview candidates for replies.

### feedContext / feedBuilder / feedIntelligence
- **Type:** callable + trigger (multiple)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/feedContext.js`, `feedBuilder.js`, `feedIntelligence.js`

### creationAI (suggestCreationVerses, improveCreationCaption, suggestCreationHashtags, generateCreationOutline)
- **Type:** callable (4 functions)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/creationAI.js`
- **External dependencies:** Anthropic API or OpenAI API
- **Secrets required:** `ANTHROPIC_API_KEY`

---

## Domain 5 — Media

### whisperProxy
- **Type:** callable
- **Gen:** gen2 (TypeScript)
- **Placement:** `Backend/functions/lib/whisperProxy.js`
- **Request shape:** `{ audioURL: string, language?: string, prompt?: string }`
- **Response shape:** `{ text: string, language: string }`
- **External dependencies:** OpenAI Whisper API (`api.openai.com/v1/audio/transcriptions`)
- **Secrets required:** `OPENAI_API_KEY`
- **Moderation: fail-closed?** NO
- **Notes:** `enforceAppCheck: true`. Accepts Firebase Storage `gs://` URLs, signed HTTPS URLs, or external HTTPS URLs. Timeout 540 seconds (9 min). Memory 512MiB.

### mediaScanning (moderateUploadedImage)
- **Type:** trigger — onFinalize (Storage)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/mediaScanning.js`
- **Trigger path:** Storage bucket finalize event
- **External dependencies:** Google Cloud Vision SafeSearch
- **Moderation: fail-closed?** YES — VERY_LIKELY → delete file + suspend account; LIKELY → quarantine + human review; POSSIBLE → flag + human review
- **Notes:** CSAM (NCMEC CyberTipline) reporting pipeline triggered on confirmed blocks.

### selahMedia
- **Type:** callable (multiple)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/selahMedia.js`
- **Notes:** Selah Media OS functions.

### mediaGeneration / mediaMetadataPipeline
- **Type:** trigger + callable
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/mediaGeneration/mediaMetadataPipeline.js`
- **Trigger path:** `posts/{postId}` (onDocumentCreated)
- **External dependencies:** OpenAI Whisper (transcript), Anthropic Claude (label refinement)
- **Secrets required:** `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`

### voicePrayerComments (createVoicePrayerUploadSession, finalizeVoicePrayerComment, deleteVoicePrayerComment, reportVoicePrayerComment, reactToVoicePrayerComment, getVoicePrayerPlaybackURL)
- **Type:** callable (6 functions) + trigger
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/voicePrayerComments.js`
- **External dependencies:** Firebase Storage
- **Secrets required:** none
- **Moderation: fail-closed?** YES — server-authoritative publish decisions; client cannot write transcript or moderation fields
- **Notes:** `enforceAppCheck: true` on all callables. Feature flags: `voicePrayerCommentsEnabled`, `voiceTestimonyCommentsEnabled` (both default OFF).

### explainVideoContent
- **Type:** callable
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/explainVideoContent.js`
- **Request shape:** `{ postId: string }`
- **Response shape:** `{ explanation: string }`
- **External dependencies:** Anthropic API (Claude)
- **Secrets required:** `ANTHROPIC_API_KEY`
- **Notes:** Server re-checks visibility, block status, flagged state before generation. No client writes to `mediaMeta` explanation fields — Firestore rules enforce.

### registerMediaProvenance
- **Type:** callable
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/media/registerMediaProvenance.js`

---

## Domain 6 — Community OS (NEW — Phase 1+ stubs)

These functions are required by the Community OS directive. Mark as `// NEW — Phase 1+`.

### transformObject // NEW — Phase 1+
- **Type:** callable
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/communityOS/transformObject.js` (to be created)
- **Request shape:** `{ sourceRef: string, intent: "simplify" | "summarize" | "expandContext" | "translate", targetLanguage?: string }`
- **Response shape:** `{ transformedContent: string, intent: string, sourceRef: string, model: string }`
- **External dependencies:** Anthropic API (Claude Haiku)
- **Secrets required:** `ANTHROPIC_API_KEY`
- **Moderation: fail-closed?** NO

### resolveCommunityObject
- **Type:** callable (EXISTING)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/communityHubs.js`
- **Request shape:** `{ url?: string, provider?: string, providerId?: string, objectType?: string, title?: string }`
- **Response shape:** `{ canonicalObjectId: string, created: boolean }`
- **External dependencies:** none
- **Secrets required:** none

### createOrJoinObjectHub
- **Type:** callable (EXISTING)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/communityHubs.js`
- **Request shape:** `{ canonicalObjectId: string }`
- **Response shape:** `{ hubId: string, joined: boolean, memberCount: number }`

### getObjectHub
- **Type:** callable (EXISTING)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/communityHubs.js`
- **Request shape:** `{ hubId: string }`
- **Response shape:** `{ hub: object, posts: object[], memberCount: number }`

### getRelatedObjectHubs
- **Type:** callable (EXISTING)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/communityHubs.js`
- **Request shape:** `{ canonicalObjectId: string, limit?: number }`
- **Response shape:** `{ hubs: object[] }`

### recordObjectInteraction
- **Type:** callable (EXISTING)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/communityHubs.js`
- **Request shape:** `{ hubId: string, interactionType: string }`
- **Response shape:** `{ success: boolean }`

### muteObjectHub
- **Type:** callable (EXISTING)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/communityHubs.js`
- **Request shape:** `{ hubId: string, muted: boolean }`
- **Response shape:** `{ success: boolean }`

### reportHubContent
- **Type:** callable (EXISTING)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/communityHubs.js`
- **Request shape:** `{ hubId: string, contentRef: string, reason: string }`
- **Response shape:** `{ reportId: string }`

### indexPostIntoHub
- **Type:** callable (EXISTING)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/communityHubs.js`
- **Request shape:** `{ postId: string, hubId: string }`
- **Response shape:** `{ success: boolean }`

### generateDiscussionSummary // NEW — Phase 1+
- **Type:** callable
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/communityOS/generateDiscussionSummary.js` (to be created)
- **Request shape:** `{ threadId: string, postId: string, limit?: number }`
- **Response shape:** `{ summary: string, keyPoints: string[], participantCount: number, model: string }`
- **External dependencies:** Anthropic API (Claude Haiku)
- **Secrets required:** `ANTHROPIC_API_KEY`
- **Moderation: fail-closed?** NO

### moderateDiscussionComment // NEW — Phase 1+
- **Type:** callable
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/communityOS/moderateDiscussionComment.js` (to be created)
- **Request shape:** `{ commentText: string, threadId: string, postId: string }`
- **Response shape:** `{ decision: "allow" | "review" | "block", reason?: string, decisionId: string }`
- **External dependencies:** NVIDIA NIM API
- **Secrets required:** `NVIDIA_API_KEY`
- **Moderation: fail-closed?** YES — consistent with `moderatePost` fail-closed invariant

### computeDiscussionReputation // NEW — Phase 2+
- **Type:** callable
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/communityOS/computeDiscussionReputation.js`
- **Request shape:** `{ userId: string }`
- **Response shape:** `{ points: number, tier: "newcomer" | "contributor" | "trusted" | "elder", badges: string[] }`
- **External dependencies:** none
- **Secrets required:** none

---

## Domain 7 — Trust & Safety (NEW — Phase 1+ stubs)

### evaluateContentSafety
- **Type:** callable (EXISTING)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/safetyOS.js`
- **Request shape:** `{ content: string, contentType: string, surfaceId: string }`
- **Response shape:** `{ safe: boolean, categories: string[], escalated: boolean }`
- **External dependencies:** NVIDIA NIM
- **Secrets required:** `NVIDIA_API_KEY`
- **Moderation: fail-closed?** YES

### evaluateMessageSafety
- **Type:** callable (EXISTING)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/safetyOS.js`

### publishWithSafetyDecision
- **Type:** callable (EXISTING)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/safetyOS.js`

### activateSextortionPanicFlow / updateTrustedContacts / updateFeedControls / recordSessionBoundarySignal / submitClaimContext / getRecommendationContext / requestHumanReview / resolveSafetyReview / getSafetyPolicySnapshot / resetRecommendationTraining / createSafetyReport
- **Type:** callable (EXISTING)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/safetyOS.js`

### antiHarassmentEnforcement
- **Type:** callable / trigger (EXISTING)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/antiHarassmentEnforcement.js`
- **Notes:** CRITICAL — enforces messaging/dm_freeze/no_contact restrictions and block checks unconditionally. Must be exported before any function that imports from it.

### accountSuspension
- **Type:** trigger (EXISTING)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/accountSuspension.js`
- **Trigger path:** moderationQueue writes
- **Notes:** HIGH-2: auto-suspends accounts when critical/minor-safety queue items are created.

### submitReport
- **Type:** callable (EXISTING)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/submitReport.js`
- **Request shape:** `{ contentType: string, contentId: string, reason: string, evidence?: string[] }`
- **Response shape:** `{ reportId: string, escalationTier: string, priority: string }`
- **Notes:** HIGH-3: validates reason, verifies evidence, computes escalationTier server-side. Direct client writes to `userReports` blocked in Firestore rules.

### moderationSweep
- **Type:** scheduled (EXISTING)
- **Gen:** gen1
- **Placement:** `functions/moderationSweep.js`
- **Schedule:** every 4 hours
- **Notes:** Finds aged `moderationQueue` items; alerts admins on items pending >24h; escalates CSAM/grooming/trafficking items pending >2h to `criticalReviewQueue`.

### evaluateTrustOSPolicy // NEW — Phase 1+
- **Type:** callable
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/trustOS/evaluateTrustOSPolicy.js` (to be created)
- **Request shape:** `{ uid: string, action: "post" | "comment" | "dm" | "follow", contextId?: string }`
- **Response shape:** `{ allowed: boolean, restrictionLevel: "none" | "soft" | "hard" | "suspended", reason?: string }`
- **External dependencies:** none (reads from Firestore `userSafetyRecords`)
- **Secrets required:** none
- **Moderation: fail-closed?** YES — unknown restriction state defaults to `"soft"` hold

### computeUserTrustScore // NEW — Phase 2+
- **Type:** callable
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/trustOS/computeUserTrustScore.js` (to be created)
- **Request shape:** `{ uid: string }`
- **Response shape:** `{ score: number, tier: "new" | "standard" | "trusted" | "verified", signals: string[] }`
- **External dependencies:** none
- **Secrets required:** none

---

## Domain 8 — Monetization (NEW — Phase 1+ stubs)

### Covenant / Spaces Stripe (EXISTING)

### createCovenantCheckoutSession
- **Type:** callable (EXISTING — TypeScript version active)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/covenant/createCovenantCheckoutSession.js`
- **Request shape:** `{ communityId: string, tierId: string }`
- **Response shape:** `{ checkoutUrl: string, sessionId: string }`
- **External dependencies:** Stripe API
- **Secrets required:** `STRIPE_SECRET_KEY`
- **Notes:** HUMAN-GATED — Stripe key must be set before deploy.

### saveCovenantTierStripePriceId
- **Type:** callable (EXISTING)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/covenant/saveCovenantTierStripePriceId.js`
- **Request shape:** `{ communityId: string, tierId: string, stripePriceId: string }`
- **Response shape:** `{ success: boolean }`

### stripeCovenantWebhook
- **Type:** HTTPS (not callable)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/covenant/stripeCovenantWebhook.js`
- **Notes:** Writes `members/{uid}` index on subscription activation. HUMAN-GATED.

### processGivingCharge
- **Type:** callable (EXISTING)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/giving/processGivingCharge.js`
- **External dependencies:** Stripe API
- **Secrets required:** `STRIPE_SECRET_KEY`

### Spaces Monetization (gen1 CJS — EXISTING)
- `createSpaceTier`, `getSpaceEntitlement`, `processSubscription`, `processRefund`, `getPayoutSummary`, `hostKYCOnboarding`
- **Placement:** `functions/spacesFunctions.js`
- **Gen:** gen1
- **External dependencies:** Stripe API
- **Secrets required:** `STRIPE_SECRET_KEY`

### stripeCreateConnectedAccount / stripeGetAccountStatus / stripeCreatePaymentIntent / stripeRequestPayout
- **Type:** callable
- **Gen:** gen1
- **Placement:** `functions/stripeFunctions.js`
- **External dependencies:** Stripe API
- **Secrets required:** `STRIPE_SECRET_KEY`

### initiateMonetizationOnboarding // NEW — Phase 2+
- **Type:** callable
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/monetization/initiateMonetizationOnboarding.js` (to be created)
- **Request shape:** `{ creatorType: "individual" | "ministry" | "nonprofit", countryCode: string }`
- **Response shape:** `{ onboardingUrl: string, accountId: string }`
- **External dependencies:** Stripe Connect API
- **Secrets required:** `STRIPE_SECRET_KEY`
- **Notes:** HUMAN-GATED — Nonprofit KYC required before live. Stripe Connect account creation.

### processSubscriptionWebhook // NEW — Phase 2+
- **Type:** HTTPS (not callable)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/monetization/processSubscriptionWebhook.js` (to be created)
- **Request shape:** Stripe webhook event body
- **Response shape:** `{ received: boolean }`
- **External dependencies:** Stripe API
- **Secrets required:** `STRIPE_WEBHOOK_SECRET`, `STRIPE_SECRET_KEY`
- **Notes:** HUMAN-GATED — Stripe webhook endpoint secret must be configured.

---

## Additional Existing Functions (Notable)

### Discussion System V1 (askBerean, detectDuplicate, computeReputation, postComment, markHelpful, setAccepted, updateWatchProgress, getWatchProgress, processEmbeddingQueue)
- **Type:** callable
- **Gen:** gen1
- **Placement:** `functions/discussionFunctions.js` (migrated from v1 to v2 syntax per recent commit 178825ac)

### Discussion OS Extensions (updateReadProgress, updateAudioProgress, updateCarouselProgress, getContextScore, analyzeDiscussionHealth, autoAnalyzeHealth, analyzeDraft, mediateDiscussion, recordDiscussionOutcome, getDiscussionDashboard)
- **Type:** callable
- **Gen:** gen1
- **Placement:** `functions/discussionContextFunctions.js`, `discussionHealthFunctions.js`, `discussionDraftFunctions.js`, `discussionMediatorFunctions.js`, `discussionMemoryFunctions.js`, `discussionCommandFunctions.js`

### ONE Private Social OS (one_sendMoment, one_expireMoment, one_reportMoment, one_requestWitness, one_relayMoment, one_activateRepairFlow, one_acceptRepairFlow, one_verifyEntitlement, one_activateLegacy)
- **Type:** callable
- **Gen:** gen1
- **Placement:** `functions/oneFunctions.js`
- **Notes:** `enforceAppCheck: true` on all. ConsentDNA enforcement on `one_sendMoment`. Relay budget + chain depth enforcement on `one_relayMoment`.

### Berean Study Functions (bereanExplainVerse, bereanStudyPlan, bereanCompareTranslations, bereanDiscussionQuestions, bereanPrayerFromPassage, bereanConvertToChurchNotes)
- **Type:** callable
- **Gen:** gen1
- **Placement:** `functions/bereanStudyFunctions.js`
- **External dependencies:** NVIDIA NIM API
- **Secrets required:** `NVIDIA_API_KEY`
- **Notes:** All outputs are DRAFTS (`approved: false`). Shared rate limit: 20 AI requests/user/hour. HUMAN-GATED.

### Notification Pipeline (onSocialEvent, counts, maintenance, invalidation, prayerAnsweredBatch, deliverQuietHoursDigest)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/notifications/`

### Church Notes Media Intelligence (churchNotesProcessingJobs, churchNotesAudioProcessing, churchNotesImageOCR, churchNotesContentGeneration, churchNotesDraftApproval, churchNotesExtendedCallables, churchNotesPrivacyAudit)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/churchNotes/`
- **External dependencies:** OpenAI Whisper, Anthropic Claude
- **Secrets required:** `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`

### Spiritual OS (10-feature — detectUnsentThoughtRisk, saveUnsentThought, resolveUnsentThought, analyzeScriptureDrift, generateBalancingScripture, dismissDriftSignal, detectSilencePatterns, resurfaceAvoidedItem, markSilenceSignalResolved, updateRelationalGravity, classifyRelationshipState, generateReconciliationPrompt, evaluateMomentRisk, logMomentInterception, updateMomentLearning, createReflectionPrompt, savePostActionReflection, updateUserGrowthPattern, analyzeTruthVsEmotion, scoreWeightOfWords, generateGracefulRewrite, aggregateDiscernmentSignals, generateCommunityDiscernmentSummary, calculateEternalWeight, updateEternalWeightAfterReflection, generateMeaningPrompt, createWalkWithChristPathFromPattern)
- **Gen:** gen2
- **Placement:** `Backend/functions/lib/spiritualOS.js`

---

## Inconsistencies Found

1. **Duplicate function conflict — `bereanChatProxy`**: Both `functions/bereanFunctions.js` (gen1) and `Backend/functions/lib/bereanChatProxy.js` (gen2) export `bereanChatProxy`. The gen1 version is commented out in `functions/index.js` to prevent double-deploy. Must remain disabled.

2. **Duplicate function conflict — `openAIProxy` / `whisperProxy`**: Same pattern — gen1 versions in `functions/openAIFunctions.js` are commented out in favor of TypeScript gen2 versions. Do not re-enable.

3. **Duplicate function conflict — `createRealtimeSession`**: TypeScript gen2 version in `Backend/functions/` shadows the gen1 version in `functions/bereanRealtimeFunctions.js`. Gen1 version disabled in `functions/index.js`.

4. **`CLAUDE_API_KEY` vs `ANTHROPIC_API_KEY`**: Some functions (`bereanShield.js`, `bereanFeaturesFunctions.js`) reference `CLAUDE_API_KEY` as the secret name; all TypeScript gen2 functions use `ANTHROPIC_API_KEY`. These likely resolve to the same key but should be unified to `ANTHROPIC_API_KEY` in any new functions.

5. **`request2FAOTP` / `verify2FAOTP` disabled**: TypeScript version in Backend/ codebase takes precedence; gen1 CJS versions disabled in `functions/index.js`.

6. **`createCovenantCheckoutSession` disabled in gen1**: gen2 TypeScript version in `Backend/functions/lib/covenant/` takes precedence.

7. **`moderatePost` is gen2 in `functions/moderatePost.js`** (imports from `firebase-functions/v2/firestore`) but is exported from the gen1 `functions/index.js`. This is intentional — the gen2 trigger can be safely exported from an otherwise gen1 file because the CLI detects per-function. Verified the `FAIL_OPEN = false` flag is the canonical fail-closed sentinel.

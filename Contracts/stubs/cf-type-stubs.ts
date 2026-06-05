/**
 * cf-type-stubs.ts
 *
 * Phase 0 Contract C4 — TypeScript type stubs for all Cloud Function callables.
 * NO function bodies. Request/response interfaces + one declaration per function.
 *
 * FAIL-CLOSED MODERATION CONTRACT (applies to all moderation callables):
 *   When NeMo Guard / NIM API (integrate.api.nvidia.com) is unreachable or
 *   returns a non-2xx response, any moderation function MUST:
 *     1. Set the content to hidden/pending (never "silently allowed").
 *     2. Enqueue the item to moderationQueue with status = "pending".
 *     3. Return an error response to the client — NOT a permissive "allow".
 *
 *   Implementation anchor: functions/moderatePost.js  →  const FAIL_OPEN = false;
 *
 * ADAPTER PATTERN:
 *   No consumer (Swift or CF) may import a vendor AI SDK directly.
 *   All LLM calls go through proxy CFs in Backend/functions/lib/.
 *
 * GENERATION NOTES:
 *   gen1 = CJS require() + firebase-functions (v1) — lives in functions/index.js
 *   gen2 = ESM/TypeScript + firebase-functions/v2/* — lives in Backend/functions/lib/
 *
 * NEW functions are marked: // NEW: Phase N — <domain>
 * Functions needing human-gated deploy are marked: // HUMAN-GATED
 */

// =============================================================================
// SECTION 1 — MODERATION
// =============================================================================

// --- moderatePost ---
// gen2 trigger (onDocumentCreated "posts/{postId}") — functions/moderatePost.js
// FAIL-CLOSED: FAIL_OPEN = false
// Secret: NVIDIA_API_KEY
// External: NVIDIA NIM API (nvidia/llama-3.1-nemoguard-8b-content-safety)
interface ModeratePostDocData {
  text?: string;
  body?: string;
  authorId?: string;
  userId?: string;
  mediaItems?: Array<{ url: string; type: "image" | "video" }>;
}
interface ModeratePostWriteShape {
  visible: boolean;
  flaggedForReview: boolean;
  removed: boolean;
  moderation: {
    status: "approved" | "blocked" | "pending" | "pending_image_review";
    categories: string[];
    provider: "nvidia-nemoguard" | "image-review-pending";
    checkedAt: FirebaseFirestore.FieldValue;
    crisisEscalated: boolean;
  };
}
declare function moderatePost(event: FirestoreEvent): Promise<void>;

// --- adminReviewPost ---
// gen2 callable — functions/moderatePost.js
// HUMAN-GATED — requires admin: true custom claim
interface AdminReviewPostRequest {
  postId: string;
  decision: "approved" | "rejected";
  queueId?: string;
}
interface AdminReviewPostResponse {
  success: boolean;
  strippedMedia?: number;
}
declare function adminReviewPost(request: CallableRequest<AdminReviewPostRequest>): Promise<AdminReviewPostResponse>;

// --- checkContentSafety ---
// gen1 callable — functions/moderationGateway.js
// FAIL-CLOSED (self-harm escalates to crisisEscalations/{uid}/{ts})
// Secret: NVIDIA_API_KEY
interface CheckContentSafetyRequest {
  content: string;
  contentType: "post" | "comment" | "message" | "dm";
  uid?: string;
}
interface CheckContentSafetyResponse {
  decision: "allow" | "review" | "block";
  reason?: string;
  crisisEscalated: boolean;
  crisisResources?: string[];
  decisionId: string;
}
declare function checkContentSafety(request: CallableRequest<CheckContentSafetyRequest>): Promise<CheckContentSafetyResponse>;

// --- onPostCreatedRunMediaModeration ---
// gen2 trigger (onDocumentCreated "posts/{postId}") — Backend/functions/lib/mediaModerationPipeline.js
// FAIL-CLOSED: errors route to status "reviewing" in humanReviewQueue
// External: Google Cloud Vision SafeSearch, optional CSAM hash lookup, optional Perspective API
declare function onPostCreatedRunMediaModeration(event: FirestoreEvent): Promise<void>;

// --- onPostMediaUpdatedRunModeration ---
// gen2 trigger (onDocumentUpdated "posts/{postId}") — Backend/functions/lib/mediaModerationPipeline.js
// FAIL-CLOSED
declare function onPostMediaUpdatedRunModeration(event: FirestoreEvent): Promise<void>;

// --- submitMediaReviewDecision ---
// gen2 callable — Backend/functions/lib/mediaModerationPipeline.js
// Requires moderator: true or admin: true custom claim
interface SubmitMediaReviewDecisionRequest {
  mediaId: string;
  decision: "approve" | "block";
  notes?: string;
}
interface SubmitMediaReviewDecisionResponse {
  success: boolean;
  newStatus: "approved" | "blocked";
}
declare function submitMediaReviewDecision(request: CallableRequest<SubmitMediaReviewDecisionRequest>): Promise<SubmitMediaReviewDecisionResponse>;

// --- getPostModerationStatus ---
// gen2 callable — Backend/functions/lib/mediaModerationPipeline.js
interface GetPostModerationStatusRequest {
  postId: string;
}
interface GetPostModerationStatusResponse {
  status: "none" | "pending" | "reviewing" | "escalated" | "blocked" | "approved";
  action?: "allow" | "hold" | "block" | "escalate";
  canAppeal?: boolean;
}
declare function getPostModerationStatus(request: CallableRequest<GetPostModerationStatusRequest>): Promise<GetPostModerationStatusResponse>;

// --- getAccountMediaRiskScore ---
// gen2 callable — Backend/functions/lib/mediaModerationPipeline.js
// Requires admin: true custom claim
interface GetAccountMediaRiskScoreRequest {
  userId: string;
}
interface GetAccountMediaRiskScoreResponse {
  riskScore: number;
  violationCount: number;
  bannedFromMediaUpload: boolean;
  recentViolationCount: number;
}
declare function getAccountMediaRiskScore(request: CallableRequest<GetAccountMediaRiskScoreRequest>): Promise<GetAccountMediaRiskScoreResponse>;

// --- triggerMediaModeration ---
// gen2 callable (admin re-queue) — Backend/functions/lib/mediaModerationPipeline.js
// HUMAN-GATED — requires admin: true
interface TriggerMediaModerationRequest {
  postId: string;
  mediaUrl: string;
  mediaType: "image" | "video";
  mediaIndex?: number;
  userId: string;
}
interface TriggerMediaModerationResponse {
  success: boolean;
}
declare function triggerMediaModeration(request: CallableRequest<TriggerMediaModerationRequest>): Promise<TriggerMediaModerationResponse>;

// --- moderateSanctuaryMessage / moderatePrayerRequest / moderateDMMessage ---
// gen1 callable — functions/moderateUGC.js
// FAIL-CLOSED  Secret: NVIDIA_API_KEY
interface ModerateUGCRequest {
  text: string;
  contextId: string;
}
interface ModerateUGCResponse {
  safe: boolean;
  categories?: string[];
}
declare function moderateSanctuaryMessage(request: CallableRequest<ModerateUGCRequest>): Promise<ModerateUGCResponse>;
declare function moderatePrayerRequest(request: CallableRequest<ModerateUGCRequest>): Promise<ModerateUGCResponse>;
declare function moderateDMMessage(request: CallableRequest<ModerateUGCRequest>): Promise<ModerateUGCResponse>;

// =============================================================================
// SECTION 2 — BEREAN / AI
// =============================================================================

// --- bereanChatProxy ---
// gen2 callable — Backend/functions/lib/bereanChatProxy.js
// enforceAppCheck: true  Secret: ANTHROPIC_API_KEY
// FAIL-CLOSED: crisis classification short-circuits to CRISIS_SAFE_RESPONSE
interface BereanConversationHistoryEntry {
  role: "user" | "assistant";
  content: string;
}
interface BereanCallData {
  conversationId?: string;
  responseMode?: string;
  sensitivityFlags?: string[];
  faithJourneyStage?: string;
  userPersona?: string;
  scriptureTranslation?: string;
  memoryScope?: string;
  postContext?: {
    postId: string;
    authorName: string;
    category: string;
    previewText: string;
    bodyText?: string;
    verseReference?: string;
    verseText?: string;
    mediaSummary?: string;
    isSensitive?: boolean;
  };
}
interface BereanChatProxyRequest {
  message: string;
  conversationHistory?: BereanConversationHistoryEntry[];
  mode?: "shepherd" | "scholar" | "debater" | "prayer" | "strategist" | "deep_study";
  maxTokens?: number;
  temperature?: number;
  systemPromptSuffix?: string;
  modelId?: string;
  memoryScope?: string;
  callData?: BereanCallData;
}
interface BereanChatProxyResponse {
  response: string;
  model: string;
  usage: object | null;
  agentRunId: string;
  outcomeStatus: "passed" | "flagged" | "blocked" | "failed";
  outcomeScore: number;
  safetyStatus: "ok" | "flagged" | "blocked";
}
declare function bereanChatProxy(request: CallableRequest<BereanChatProxyRequest>): Promise<BereanChatProxyResponse>;

// --- openAIProxy ---
// gen2 callable — Backend/functions/lib/openAIProxy.js
// enforceAppCheck: true  Secret: OPENAI_API_KEY
interface OpenAIMessage {
  role: "system" | "user" | "assistant";
  content: string;
}
interface OpenAIProxyRequest {
  messages: OpenAIMessage[];
  maxTokens?: number;
  temperature?: number;
  model?: "gpt-4o-mini" | "gpt-4o";
}
interface OpenAIProxyResponse {
  response: string;
  model: "gpt-4o-mini" | "gpt-4o";
  usage: object;
}
declare function openAIProxy(request: CallableRequest<OpenAIProxyRequest>): Promise<OpenAIProxyResponse>;

// --- transformContent ---
// gen2 callable — Backend/functions/lib/transformContent.js
// enforceAppCheck: true  Secret: ANTHROPIC_API_KEY
// External: Anthropic API (Claude Haiku)
interface TransformContentRequest {
  text: string;
  mode: "simplify" | "summarize" | "keyTerms" | "explain" | "expandContext";
  language?: string;
  contentId?: string;
}
interface KeyTerm {
  term: string;
  definition: string;
  relatedVerse: string | null;
}
interface TransformContentResponse {
  transformedText: string;
  keyTerms?: KeyTerm[];
  mode: string;
  contentId?: string;
  usage: object;
}
declare function transformContent(request: CallableRequest<TransformContentRequest>): Promise<TransformContentResponse>;

// --- refineTranslation ---
// gen2 callable — Backend/functions/lib/refineTranslation.js
// enforceAppCheck: true  Secret: ANTHROPIC_API_KEY
// Graceful degradation: returns literalTranslation with model: "fallback" on error
interface PreservedEntity {
  type: string;
  text: string;
}
interface RefineTranslationRequest {
  originalText: string;
  literalTranslation: string;
  sourceLanguage: string;
  targetLanguage: string;
  mode: "natural" | "contextual";
  contentType?: string;
  preservedEntities?: PreservedEntity[];
}
interface RefineTranslationResponse {
  refinedText: string;
  mode: "natural" | "contextual";
  model: string;
  usage?: object;
  error?: string;
}
declare function refineTranslation(request: CallableRequest<RefineTranslationRequest>): Promise<RefineTranslationResponse>;

// --- whisperProxy ---
// gen2 callable — Backend/functions/lib/whisperProxy.js
// enforceAppCheck: true  Secret: OPENAI_API_KEY
// External: OpenAI Whisper API  Timeout: 540s  Memory: 512MiB
interface WhisperProxyRequest {
  audioURL: string; // gs:// or HTTPS URL
  language?: string;
  prompt?: string;
}
interface WhisperProxyResponse {
  text: string;
  language: string;
}
declare function whisperProxy(request: CallableRequest<WhisperProxyRequest>): Promise<WhisperProxyResponse>;

// =============================================================================
// SECTION 3 — SOCIAL GRAPH
// =============================================================================

// --- markRelationshipSeen ---
// gen2 callable — Backend/functions/lib/socialGraph.js
interface MarkRelationshipSeenRequest {
  targetIds: string[]; // max 400
}
interface MarkRelationshipSeenResponse {
  success: boolean;
  marked: number;
}
declare function markRelationshipSeen(request: CallableRequest<MarkRelationshipSeenRequest>): Promise<MarkRelationshipSeenResponse>;

// --- createFollow ---
// gen2 callable — Backend/functions/lib/createFollow.js
interface CreateFollowRequest {
  targetUserId: string;
}
interface CreateFollowResponse {
  success: boolean;
}
declare function createFollow(request: CallableRequest<CreateFollowRequest>): Promise<CreateFollowResponse>;

// --- createBlock ---
// gen2 callable — Backend/functions/lib/createBlock.js
interface CreateBlockRequest {
  targetUserId: string;
}
interface CreateBlockResponse {
  success: boolean;
}
declare function createBlock(request: CallableRequest<CreateBlockRequest>): Promise<CreateBlockResponse>;

// =============================================================================
// SECTION 4 — CONTENT (Transform, Translate, Content Pipeline)
// =============================================================================

// --- validateThinkFirstCheck ---
// gen2 callable — Backend/functions/lib/thinkFirst/validateThinkFirstCheck.js
// Server-authoritative tone/safety check — MUST be called before persisting content
interface ValidateThinkFirstCheckRequest {
  content: string;
  contentType: "post" | "comment" | "reply";
  surfaceId?: string;
}
interface ValidateThinkFirstCheckResponse {
  passed: boolean;
  flags: string[];
  suggestion?: string;
}
declare function validateThinkFirstCheck(request: CallableRequest<ValidateThinkFirstCheckRequest>): Promise<ValidateThinkFirstCheckResponse>;

// --- submitReport ---
// gen2 callable — Backend/functions/lib/submitReport.js
// HIGH-3: validates reason, computes escalationTier server-side
interface SubmitReportRequest {
  contentType: "post" | "comment" | "user" | "message" | "church";
  contentId: string;
  reason: string;
  evidence?: string[];
}
interface SubmitReportResponse {
  reportId: string;
  escalationTier: "standard" | "high" | "critical";
  priority: "low" | "normal" | "high" | "urgent";
}
declare function submitReport(request: CallableRequest<SubmitReportRequest>): Promise<SubmitReportResponse>;

// =============================================================================
// SECTION 5 — MEDIA
// =============================================================================

// --- explainVideoContent ---
// gen2 callable — Backend/functions/lib/explainVideoContent.js
// enforceAppCheck: true  Secret: ANTHROPIC_API_KEY
interface ExplainVideoContentRequest {
  postId: string;
}
interface ExplainVideoContentResponse {
  explanation: string;
}
declare function explainVideoContent(request: CallableRequest<ExplainVideoContentRequest>): Promise<ExplainVideoContentResponse>;

// --- createVoicePrayerUploadSession ---
// gen2 callable — Backend/functions/lib/voicePrayerComments.js
// enforceAppCheck: true
interface CreateVoicePrayerUploadSessionRequest {
  postId: string;
  durationSeconds: number;
  mimeType: string;
}
interface CreateVoicePrayerUploadSessionResponse {
  uploadUrl: string;
  sessionId: string;
  expiresAt: string;
}
declare function createVoicePrayerUploadSession(request: CallableRequest<CreateVoicePrayerUploadSessionRequest>): Promise<CreateVoicePrayerUploadSessionResponse>;

// --- finalizeVoicePrayerComment ---
// gen2 callable — Backend/functions/lib/voicePrayerComments.js
interface FinalizeVoicePrayerCommentRequest {
  sessionId: string;
  postId: string;
  intent?: "prayer" | "testimony" | "question" | "encouragement";
}
interface FinalizeVoicePrayerCommentResponse {
  commentId: string;
  status: "processing" | "published";
}
declare function finalizeVoicePrayerComment(request: CallableRequest<FinalizeVoicePrayerCommentRequest>): Promise<FinalizeVoicePrayerCommentResponse>;

// =============================================================================
// SECTION 6 — COMMUNITY OS (NEW — Phase 1+ stubs)
// =============================================================================

// --- resolveCommunityObject (EXISTING) ---
// gen2 callable — Backend/functions/lib/communityHubs.js
interface ResolveCommunityObjectRequest {
  url?: string;
  provider?: string;
  providerId?: string;
  objectType?: string;
  title?: string;
}
interface ResolveCommunityObjectResponse {
  canonicalObjectId: string;
  created: boolean;
}
declare function resolveCommunityObject(request: CallableRequest<ResolveCommunityObjectRequest>): Promise<ResolveCommunityObjectResponse>;

// --- createOrJoinObjectHub (EXISTING) ---
interface CreateOrJoinObjectHubRequest {
  canonicalObjectId: string;
}
interface CreateOrJoinObjectHubResponse {
  hubId: string;
  joined: boolean;
  memberCount: number;
}
declare function createOrJoinObjectHub(request: CallableRequest<CreateOrJoinObjectHubRequest>): Promise<CreateOrJoinObjectHubResponse>;

// --- getObjectHub (EXISTING) ---
interface GetObjectHubRequest {
  hubId: string;
}
interface GetObjectHubResponse {
  hub: Record<string, unknown>;
  posts: Record<string, unknown>[];
  memberCount: number;
}
declare function getObjectHub(request: CallableRequest<GetObjectHubRequest>): Promise<GetObjectHubResponse>;

// --- getRelatedObjectHubs (EXISTING) ---
interface GetRelatedObjectHubsRequest {
  canonicalObjectId: string;
  limit?: number;
}
interface GetRelatedObjectHubsResponse {
  hubs: Record<string, unknown>[];
}
declare function getRelatedObjectHubs(request: CallableRequest<GetRelatedObjectHubsRequest>): Promise<GetRelatedObjectHubsResponse>;

// --- recordObjectInteraction (EXISTING) ---
interface RecordObjectInteractionRequest {
  hubId: string;
  interactionType: "view" | "post" | "react" | "share" | "save";
}
interface RecordObjectInteractionResponse {
  success: boolean;
}
declare function recordObjectInteraction(request: CallableRequest<RecordObjectInteractionRequest>): Promise<RecordObjectInteractionResponse>;

// --- muteObjectHub (EXISTING) ---
interface MuteObjectHubRequest {
  hubId: string;
  muted: boolean;
}
interface MuteObjectHubResponse {
  success: boolean;
}
declare function muteObjectHub(request: CallableRequest<MuteObjectHubRequest>): Promise<MuteObjectHubResponse>;

// --- reportHubContent (EXISTING) ---
interface ReportHubContentRequest {
  hubId: string;
  contentRef: string;
  reason: string;
}
interface ReportHubContentResponse {
  reportId: string;
}
declare function reportHubContent(request: CallableRequest<ReportHubContentRequest>): Promise<ReportHubContentResponse>;

// --- indexPostIntoHub (EXISTING) ---
interface IndexPostIntoHubRequest {
  postId: string;
  hubId: string;
}
interface IndexPostIntoHubResponse {
  success: boolean;
}
declare function indexPostIntoHub(request: CallableRequest<IndexPostIntoHubRequest>): Promise<IndexPostIntoHubResponse>;

// NEW: Phase 1 — Community OS
// --- transformObject ---
// gen2 callable — Backend/functions/lib/communityOS/transformObject.js (to be created)
// Secret: ANTHROPIC_API_KEY  External: Anthropic API (Claude Haiku)
interface TransformObjectRequest {
  sourceRef: string; // Firestore document path or content URL
  intent: "simplify" | "summarize" | "expandContext" | "translate";
  targetLanguage?: string; // BCP-47 code, required when intent = "translate"
}
interface TransformObjectResponse {
  transformedContent: string;
  intent: string;
  sourceRef: string;
  model: string;
  usage?: object;
}
declare function transformObject(request: CallableRequest<TransformObjectRequest>): Promise<TransformObjectResponse>;

// NEW: Phase 1 — Community OS
// --- generateDiscussionSummary ---
// gen2 callable — Backend/functions/lib/communityOS/generateDiscussionSummary.js (to be created)
// Secret: ANTHROPIC_API_KEY  External: Anthropic API (Claude Haiku)
interface GenerateDiscussionSummaryRequest {
  threadId: string;
  postId: string;
  limit?: number; // max comments to include, default 50
}
interface GenerateDiscussionSummaryResponse {
  summary: string;
  keyPoints: string[];
  participantCount: number;
  model: string;
}
declare function generateDiscussionSummary(request: CallableRequest<GenerateDiscussionSummaryRequest>): Promise<GenerateDiscussionSummaryResponse>;

// NEW: Phase 1 — Community OS
// --- moderateDiscussionComment ---
// FAIL-CLOSED (fail-closed moderation contract applies)
// gen2 callable — Backend/functions/lib/communityOS/moderateDiscussionComment.js (to be created)
// Secret: NVIDIA_API_KEY  External: NVIDIA NIM API
interface ModerateDiscussionCommentRequest {
  commentText: string;
  threadId: string;
  postId: string;
}
interface ModerateDiscussionCommentResponse {
  decision: "allow" | "review" | "block";
  reason?: string;
  decisionId: string;
}
declare function moderateDiscussionComment(request: CallableRequest<ModerateDiscussionCommentRequest>): Promise<ModerateDiscussionCommentResponse>;

// NEW: Phase 2 — Community OS
// --- computeDiscussionReputation ---
// gen2 callable — Backend/functions/lib/communityOS/computeDiscussionReputation.js (to be created)
interface ComputeDiscussionReputationRequest {
  userId: string;
}
interface ComputeDiscussionReputationResponse {
  points: number;
  tier: "newcomer" | "contributor" | "trusted" | "elder";
  badges: string[];
}
declare function computeDiscussionReputation(request: CallableRequest<ComputeDiscussionReputationRequest>): Promise<ComputeDiscussionReputationResponse>;

// =============================================================================
// SECTION 7 — TRUST & SAFETY (NEW — Phase 1+ stubs)
// =============================================================================

// --- evaluateContentSafety (EXISTING) ---
// gen2 callable — Backend/functions/lib/safetyOS.js
// FAIL-CLOSED  Secret: NVIDIA_API_KEY
interface EvaluateContentSafetyRequest {
  content: string;
  contentType: "post" | "comment" | "message" | "profile";
  surfaceId: string;
}
interface EvaluateContentSafetyResponse {
  safe: boolean;
  categories: string[];
  escalated: boolean;
  decisionId?: string;
}
declare function evaluateContentSafety(request: CallableRequest<EvaluateContentSafetyRequest>): Promise<EvaluateContentSafetyResponse>;

// --- evaluateMessageSafety (EXISTING) ---
interface EvaluateMessageSafetyRequest {
  messageText: string;
  conversationId: string;
  recipientId: string;
}
interface EvaluateMessageSafetyResponse {
  safe: boolean;
  nudgeText?: string;
  categories: string[];
}
declare function evaluateMessageSafety(request: CallableRequest<EvaluateMessageSafetyRequest>): Promise<EvaluateMessageSafetyResponse>;

// --- publishWithSafetyDecision (EXISTING) ---
interface PublishWithSafetyDecisionRequest {
  postId: string;
  safetyDecision: "publish" | "hold" | "discard";
  surfaceId?: string;
}
interface PublishWithSafetyDecisionResponse {
  published: boolean;
  postId: string;
  status: string;
}
declare function publishWithSafetyDecision(request: CallableRequest<PublishWithSafetyDecisionRequest>): Promise<PublishWithSafetyDecisionResponse>;

// --- activateSextortionPanicFlow (EXISTING) ---
interface ActivateSextortionPanicFlowRequest {
  conversationId: string;
  evidenceRef?: string;
}
interface ActivateSextortionPanicFlowResponse {
  panicId: string;
  crisisResources: string[];
  conversationLocked: boolean;
}
declare function activateSextortionPanicFlow(request: CallableRequest<ActivateSextortionPanicFlowRequest>): Promise<ActivateSextortionPanicFlowResponse>;

// --- createSafetyReport (EXISTING) ---
interface CreateSafetyReportRequest {
  targetId: string;
  targetType: "user" | "post" | "comment" | "conversation";
  harmCategory: "harassment" | "hate_speech" | "csam" | "grooming" | "trafficking" | "self_harm" | "spam" | "other";
  notes?: string;
  evidenceRefs?: string[];
}
interface CreateSafetyReportResponse {
  reportId: string;
  escalationTier: "standard" | "high" | "critical";
  crisisEscalated: boolean;
}
declare function createSafetyReport(request: CallableRequest<CreateSafetyReportRequest>): Promise<CreateSafetyReportResponse>;

// NEW: Phase 1 — Trust OS
// --- evaluateTrustOSPolicy ---
// FAIL-CLOSED: unknown restriction state defaults to "soft" hold
// gen2 callable — Backend/functions/lib/trustOS/evaluateTrustOSPolicy.js (to be created)
interface EvaluateTrustOSPolicyRequest {
  uid: string;
  action: "post" | "comment" | "dm" | "follow" | "react";
  contextId?: string; // postId, conversationId, etc.
}
interface EvaluateTrustOSPolicyResponse {
  allowed: boolean;
  restrictionLevel: "none" | "soft" | "hard" | "suspended";
  reason?: string;
  expiresAt?: string; // ISO timestamp if restriction is time-bounded
}
declare function evaluateTrustOSPolicy(request: CallableRequest<EvaluateTrustOSPolicyRequest>): Promise<EvaluateTrustOSPolicyResponse>;

// NEW: Phase 2 — Trust OS
// --- computeUserTrustScore ---
// gen2 callable — Backend/functions/lib/trustOS/computeUserTrustScore.js (to be created)
interface ComputeUserTrustScoreRequest {
  uid: string;
}
interface ComputeUserTrustScoreResponse {
  score: number; // 0.0 – 1.0
  tier: "new" | "standard" | "trusted" | "verified";
  signals: string[];
  computedAt: string;
}
declare function computeUserTrustScore(request: CallableRequest<ComputeUserTrustScoreRequest>): Promise<ComputeUserTrustScoreResponse>;

// NEW: Phase 2 — Trust OS
// --- flagContentForEmergencyReview ---
// FAIL-CLOSED
// gen2 callable — Backend/functions/lib/trustOS/flagContentForEmergencyReview.js (to be created)
interface FlagContentForEmergencyReviewRequest {
  contentRef: string; // Firestore path
  contentType: "post" | "comment" | "message";
  urgency: "standard" | "high" | "critical";
  detectedSignal: string;
}
interface FlagContentForEmergencyReviewResponse {
  flagId: string;
  queuePosition: "front" | "normal";
  contentHidden: boolean;
}
declare function flagContentForEmergencyReview(request: CallableRequest<FlagContentForEmergencyReviewRequest>): Promise<FlagContentForEmergencyReviewResponse>;

// =============================================================================
// SECTION 8 — MONETIZATION (NEW — Phase 1+ stubs)
// =============================================================================

// --- createCovenantCheckoutSession (EXISTING) ---
// gen2 callable — Backend/functions/lib/covenant/createCovenantCheckoutSession.js
// HUMAN-GATED  Secret: STRIPE_SECRET_KEY
interface CreateCovenantCheckoutSessionRequest {
  communityId: string;
  tierId: string;
}
interface CreateCovenantCheckoutSessionResponse {
  checkoutUrl: string;
  sessionId: string;
}
declare function createCovenantCheckoutSession(request: CallableRequest<CreateCovenantCheckoutSessionRequest>): Promise<CreateCovenantCheckoutSessionResponse>;

// --- saveCovenantTierStripePriceId (EXISTING) ---
interface SaveCovenantTierStripePriceIdRequest {
  communityId: string;
  tierId: string;
  stripePriceId: string;
}
interface SaveCovenantTierStripePriceIdResponse {
  success: boolean;
}
declare function saveCovenantTierStripePriceId(request: CallableRequest<SaveCovenantTierStripePriceIdRequest>): Promise<SaveCovenantTierStripePriceIdResponse>;

// --- processGivingCharge (EXISTING) ---
// gen2 callable — Backend/functions/lib/giving/processGivingCharge.js
// Secret: STRIPE_SECRET_KEY  External: Stripe API
interface ProcessGivingChargeRequest {
  recipientId: string;
  amountCents: number;
  currency: string;
  paymentMethodId: string;
  note?: string;
  campaignId?: string;
}
interface ProcessGivingChargeResponse {
  chargeId: string;
  status: "succeeded" | "pending" | "failed";
  receiptUrl?: string;
}
declare function processGivingCharge(request: CallableRequest<ProcessGivingChargeRequest>): Promise<ProcessGivingChargeResponse>;

// NEW: Phase 2 — Monetization
// HUMAN-GATED — Stripe Connect + nonprofit KYC required
// --- initiateMonetizationOnboarding ---
// gen2 callable — Backend/functions/lib/monetization/initiateMonetizationOnboarding.js (to be created)
// Secret: STRIPE_SECRET_KEY  External: Stripe Connect API
interface InitiateMonetizationOnboardingRequest {
  creatorType: "individual" | "ministry" | "nonprofit";
  countryCode: string; // ISO 3166-1 alpha-2
  returnUrl: string;
  refreshUrl: string;
}
interface InitiateMonetizationOnboardingResponse {
  onboardingUrl: string;
  accountId: string;
  expiresAt: string;
}
declare function initiateMonetizationOnboarding(request: CallableRequest<InitiateMonetizationOnboardingRequest>): Promise<InitiateMonetizationOnboardingResponse>;

// NEW: Phase 2 — Monetization
// HUMAN-GATED — Stripe webhook endpoint secret must be configured
// --- processSubscriptionWebhook ---
// gen2 HTTPS (not callable) — Backend/functions/lib/monetization/processSubscriptionWebhook.js (to be created)
// Secrets: STRIPE_WEBHOOK_SECRET, STRIPE_SECRET_KEY
interface ProcessSubscriptionWebhookBody {
  id: string;
  type: string; // Stripe event type
  data: { object: Record<string, unknown> };
}
interface ProcessSubscriptionWebhookResponse {
  received: boolean;
}
// Note: Implemented as onRequest (HTTPS), not onCall
declare function processSubscriptionWebhook(req: object, res: object): Promise<void>;

// NEW: Phase 3 — Monetization
// --- getCreatorPayoutSummary ---
// gen2 callable — Backend/functions/lib/monetization/getCreatorPayoutSummary.js (to be created)
// Secret: STRIPE_SECRET_KEY  External: Stripe API
interface GetCreatorPayoutSummaryRequest {
  creatorId: string;
  periodStart: string; // ISO date
  periodEnd: string;
}
interface GetCreatorPayoutSummaryResponse {
  totalEarningsCents: number;
  pendingPayoutCents: number;
  subscriberCount: number;
  newSubscribersThisPeriod: number;
  currency: string;
}
declare function getCreatorPayoutSummary(request: CallableRequest<GetCreatorPayoutSummaryRequest>): Promise<GetCreatorPayoutSummaryResponse>;

// =============================================================================
// UTILITY TYPES (referenced above — not Firebase-specific)
// =============================================================================

/** Minimal type stubs for Firebase callable request/response shapes */
interface CallableRequest<T> {
  data: T;
  auth?: {
    uid: string;
    token: Record<string, unknown> & { admin?: boolean; moderator?: boolean };
  };
  app?: object; // App Check token
}

/** Minimal Firestore event stub */
interface FirestoreEvent {
  params: Record<string, string>;
  data?: {
    before?: { data(): Record<string, unknown> };
    after?: { data(): Record<string, unknown> };
    data(): Record<string, unknown>;
  };
}

/** Firebase Firestore FieldValue placeholder */
declare namespace FirebaseFirestore {
  type FieldValue = object;
}

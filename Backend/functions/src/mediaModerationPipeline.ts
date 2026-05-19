import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onCall } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import vision from "@google-cloud/vision";
import axios from "axios";

const visionClient = new vision.ImageAnnotatorClient();
const REQUIRE_MEDIA_MODERATION_PROVIDERS = process.env.REQUIRE_MEDIA_MODERATION_PROVIDERS === "true";
const CSAM_HASH_LOOKUP_URL = process.env.CSAM_HASH_LOOKUP_URL ?? "";
const CSAM_HASH_LOOKUP_TOKEN = process.env.CSAM_HASH_LOOKUP_TOKEN ?? "";
const PERSPECTIVE_API_KEY = process.env.PERSPECTIVE_API_KEY ?? "";
const PERSPECTIVE_API_URL = process.env.PERSPECTIVE_API_URL ??
  "https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze";

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

type ModerationStatus = "pending" | "approved" | "reviewing" | "blocked" | "escalated";
type ModerationAction = "allow" | "hold" | "block" | "escalate";
type ReviewPriority = "urgent" | "high" | "normal";

interface HashCheckResult {
  matched: boolean;
  category?: string; // "csam" | "terrorism" | "known_harmful"
  hashValue?: string;
}

interface ImageSafetyScore {
  nudity: number;           // 0–1
  sexuallyExplicit: number; // 0–1
  violence: number;         // 0–1
  graphic: number;          // 0–1
  racy: number;             // 0–1
  overallConcern: number;   // 0–1 fused signal
}

interface TextSafetyScore {
  toxicity: number;         // 0–1
  harassment: number;       // 0–1
  hateSpeech: number;       // 0–1
  spam: number;             // 0–1
  selfHarm: number;         // 0–1
  extractedText: string;    // OCR output (not stored in logs)
  overallConcern: number;   // 0–1 fused signal
}

interface FusionResult {
  fusionScore: number;      // 0–1, higher = more concerning
  dominantSignal: string;
  flags: string[];
}

interface ModerationRecord {
  postId: string;
  userId: string;
  mediaUrl: string;
  mediaType: "image" | "video";
  mediaIndex: number;
  status: ModerationStatus;
  hashCheck: HashCheckResult | null;
  imageSafetyScore: ImageSafetyScore | null;
  textSafetyScore: TextSafetyScore | null;
  fusionScore: number;
  action: ModerationAction;
  accountRiskMultiplier: number;
  reviewerId?: string;
  reviewDecision?: "approve" | "block";
  reviewNotes?: string;
  reviewedAt?: admin.firestore.Timestamp;
  createdAt: admin.firestore.Timestamp;
  updatedAt: admin.firestore.Timestamp;
}

interface AccountRiskScore {
  userId: string;
  violationCount: number;
  recentViolations: {
    mediaId: string;
    action: ModerationAction;
    timestamp: admin.firestore.Timestamp;
  }[];
  riskScore: number;        // 0–1
  bannedFromMediaUpload: boolean;
  lastUpdated: admin.firestore.Timestamp;
}

interface PipelineResult {
  mediaId: string;
  status: ModerationStatus;
  action: ModerationAction;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers: App Check + Auth guard
// ─────────────────────────────────────────────────────────────────────────────

function requireAppCheckAndAuth(context: { app?: unknown; auth?: { uid?: string } }): string {
  if (!context.app) throw new Error("App Check required.");
  if (!context.auth?.uid) throw new Error("Authentication required.");
  return context.auth.uid;
}

// ─────────────────────────────────────────────────────────────────────────────
// Layer 1: Hash check
// In production: query a NCMEC PhotoDNA or PDQ hash database.
// ─────────────────────────────────────────────────────────────────────────────

async function runHashCheck(mediaUrl: string): Promise<HashCheckResult> {
  if (!CSAM_HASH_LOOKUP_URL) {
    if (REQUIRE_MEDIA_MODERATION_PROVIDERS) {
      throw new Error("CSAM hash lookup provider is not configured.");
    }
    return { matched: false };
  }

  const response = await axios.post(
    CSAM_HASH_LOOKUP_URL,
    { mediaUrl },
    {
      timeout: 10_000,
      headers: CSAM_HASH_LOOKUP_TOKEN
        ? { Authorization: `Bearer ${CSAM_HASH_LOOKUP_TOKEN}` }
        : undefined,
    }
  );
  const data = response.data as { matched?: boolean; category?: string; hashValue?: string };
  return {
    matched: data.matched === true,
    category: data.category,
    hashValue: data.hashValue,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Layer 2: Image safety analysis
// In production: call Google Cloud Vision SafeSearch, AWS Rekognition, or
// Azure Content Moderator.
// ─────────────────────────────────────────────────────────────────────────────

async function runImageSafety(mediaUrl: string, mediaType: "image" | "video"): Promise<ImageSafetyScore> {
  if (mediaType === "video") {
    return {
      nudity: 0,
      sexuallyExplicit: 0,
      violence: 0,
      graphic: 0,
      racy: 0,
      overallConcern: REQUIRE_MEDIA_MODERATION_PROVIDERS ? 0.7 : 0.45,
    };
  }

  const [result] = await visionClient.safeSearchDetection(mediaUrl);
  const safeSearch = result.safeSearchAnnotation ?? {};
  const adult = likelihoodToScore(safeSearch.adult);
  const racy = likelihoodToScore(safeSearch.racy);
  const violence = likelihoodToScore(safeSearch.violence);
  const medical = likelihoodToScore(safeSearch.medical);

  return {
    nudity: adult,
    sexuallyExplicit: Math.max(adult, racy),
    violence,
    graphic: Math.max(violence, medical),
    racy,
    overallConcern: Math.max(adult, racy, violence, medical),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Layer 3: OCR extraction
// In production: call Google Cloud Vision TEXT_DETECTION or AWS Textract.
// ─────────────────────────────────────────────────────────────────────────────

async function runOCR(mediaUrl: string): Promise<string> {
  const [result] = await (visionClient as any).annotateImage({
    image: { source: { imageUri: mediaUrl } },
    features: [{ type: "TEXT_DETECTION" }],
  });
  return result.fullTextAnnotation?.text ?? "";
}

// ─────────────────────────────────────────────────────────────────────────────
// Layer 4: Text safety analysis
// In production: call Perspective API, AWS Comprehend, or Azure Content
// Moderator on the OCR output.
// ─────────────────────────────────────────────────────────────────────────────

async function runTextSafety(extractedText: string): Promise<TextSafetyScore> {
  if (!extractedText.trim()) {
    return {
      toxicity: 0, harassment: 0, hateSpeech: 0, spam: 0, selfHarm: 0,
      extractedText: "", overallConcern: 0,
    };
  }

  if (PERSPECTIVE_API_KEY) {
    const response = await axios.post(
      `${PERSPECTIVE_API_URL}?key=${encodeURIComponent(PERSPECTIVE_API_KEY)}`,
      {
        comment: { text: extractedText },
        languages: ["en"],
        requestedAttributes: {
          TOXICITY: {},
          SEVERE_TOXICITY: {},
          IDENTITY_ATTACK: {},
          INSULT: {},
          THREAT: {},
        },
        doNotStore: true,
      },
      { timeout: 10_000 }
    );
    const attributeScores = response.data?.attributeScores ?? {};
    const scoreFor = (key: string): number =>
      Number(attributeScores[key]?.summaryScore?.value ?? 0);
    const toxicity = Math.max(scoreFor("TOXICITY"), scoreFor("SEVERE_TOXICITY"));
    const harassment = Math.max(scoreFor("INSULT"), scoreFor("THREAT"));
    const hateSpeech = scoreFor("IDENTITY_ATTACK");
    const overallConcern = Math.max(toxicity, harassment, hateSpeech);

    return {
      toxicity,
      harassment,
      hateSpeech,
      spam: 0,
      selfHarm: 0,
      extractedText: "",
      overallConcern,
    };
  }

  if (REQUIRE_MEDIA_MODERATION_PROVIDERS) {
    throw new Error("Text safety provider is not configured.");
  }

  // Local development fallback. Production sets REQUIRE_MEDIA_MODERATION_PROVIDERS=true.
  const text = extractedText.toLowerCase();
  const toxicPatterns = [/hate|kill|harm|abuse|exploit/i];
  const haramPatterns = [/nude|explicit|xxx/i];
  const hasHighRisk = toxicPatterns.some(p => p.test(text));
  const hasExplicit = haramPatterns.some(p => p.test(text));

  return {
    toxicity: hasHighRisk ? 0.8 : 0,
    harassment: hasHighRisk ? 0.5 : 0,
    hateSpeech: 0,
    spam: 0,
    selfHarm: 0,
    extractedText: "",  // never store raw text in moderation logs
    overallConcern: hasHighRisk ? 0.8 : hasExplicit ? 0.6 : 0,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Layer 5: Multimodal fusion
// Combines image + text signals into a single concern score.
// ─────────────────────────────────────────────────────────────────────────────

function runMultimodalFusion(
  imageSafety: ImageSafetyScore,
  textSafety: TextSafetyScore,
  hashCheck: HashCheckResult
): FusionResult {
  if (hashCheck.matched) {
    return { fusionScore: 1.0, dominantSignal: "hash_match", flags: [`hash:${hashCheck.category}`] };
  }

  // Weighted fusion: image signals carry 60%, text 40%
  const imageContribution = imageSafety.overallConcern * 0.60;
  const textContribution = textSafety.overallConcern * 0.40;
  let fusionScore = imageContribution + textContribution;

  const flags: string[] = [];

  if (imageSafety.sexuallyExplicit > 0.7) flags.push("sexually_explicit");
  if (imageSafety.nudity > 0.7)           flags.push("nudity");
  if (imageSafety.violence > 0.7)         flags.push("violence");
  if (imageSafety.graphic > 0.6)          flags.push("graphic_content");
  if (textSafety.toxicity > 0.7)          flags.push("toxic_text");
  if (textSafety.harassment > 0.6)        flags.push("harassment");
  if (textSafety.hateSpeech > 0.5)        flags.push("hate_speech");
  if (textSafety.selfHarm > 0.4)          flags.push("self_harm");

  // Boost score if multiple signal types fire simultaneously
  if (flags.length >= 2) fusionScore = Math.min(fusionScore * 1.3, 1.0);

  const dominantSignal = flags[0] ?? "clean";
  return { fusionScore: Math.min(fusionScore, 1.0), dominantSignal, flags };
}

// ─────────────────────────────────────────────────────────────────────────────
// Layer 6: Action engine
// Determines allow / hold / block / escalate from fusion score + account risk.
// ─────────────────────────────────────────────────────────────────────────────

function runActionEngine(
  fusion: FusionResult,
  accountRiskMultiplier: number,
  isHashMatch: boolean
): { action: ModerationAction; status: ModerationStatus; priority: ReviewPriority | null } {
  // Hash matches always block immediately, no queue
  if (isHashMatch) {
    return { action: "block", status: "blocked", priority: null };
  }

  const effectiveScore = Math.min(fusion.fusionScore * accountRiskMultiplier, 1.0);

  if (effectiveScore >= 0.9 || fusion.flags.includes("sexually_explicit")) {
    return { action: "block", status: "blocked", priority: null };
  }
  if (effectiveScore >= 0.7 || fusion.flags.includes("violence")) {
    return { action: "escalate", status: "escalated", priority: "urgent" };
  }
  if (effectiveScore >= 0.45 || fusion.flags.length > 0) {
    const priority: ReviewPriority = effectiveScore >= 0.6 ? "high" : "normal";
    return { action: "hold", status: "reviewing", priority };
  }

  return { action: "allow", status: "approved", priority: null };
}

function likelihoodToScore(value: unknown): number {
  switch (String(value ?? "UNKNOWN")) {
    case "VERY_LIKELY": return 0.95;
    case "LIKELY": return 0.75;
    case "POSSIBLE": return 0.45;
    case "UNLIKELY": return 0.15;
    case "VERY_UNLIKELY": return 0.02;
    default: return REQUIRE_MEDIA_MODERATION_PROVIDERS ? 0.6 : 0;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Account risk scoring
// ─────────────────────────────────────────────────────────────────────────────

async function getAccountRiskMultiplier(userId: string): Promise<number> {
  const db = admin.firestore();
  const riskDoc = await db.collection("accountRiskScores").doc(userId).get();

  if (!riskDoc.exists) return 1.0;

  const risk = riskDoc.data() as AccountRiskScore;
  if (risk.bannedFromMediaUpload) return 99; // effectively blocks all media

  // Multiplier: 1.0 at 0 risk, up to 2.5 at max risk
  return 1.0 + (risk.riskScore * 1.5);
}

async function recordViolation(
  userId: string,
  mediaId: string,
  action: ModerationAction
): Promise<void> {
  if (action === "allow") return;

  const db = admin.firestore();
  const ref = db.collection("accountRiskScores").doc(userId);
  const now = admin.firestore.Timestamp.now();

  await db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    const existing = doc.exists ? (doc.data() as AccountRiskScore) : null;

    const recentViolations = existing?.recentViolations ?? [];
    const newViolation = { mediaId, action, timestamp: now };

    // Keep only last 10 violations
    const updatedViolations = [newViolation, ...recentViolations].slice(0, 10);

    // Remove violations older than 90 days when computing score
    const ninetyDaysAgo = Date.now() - 90 * 24 * 60 * 60 * 1000;
    const activeViolations = updatedViolations.filter(
      v => v.timestamp.toMillis() > ninetyDaysAgo
    );

    // Risk score: blocks/escalates count more than holds
    const riskScore = Math.min(
      activeViolations.reduce((acc, v) => {
        if (v.action === "block") return acc + 0.20;
        if (v.action === "escalate") return acc + 0.15;
        return acc + 0.05;
      }, 0),
      1.0
    );

    const violationCount = (existing?.violationCount ?? 0) + 1;
    const bannedFromMediaUpload = riskScore >= 0.8 || violationCount >= 5;

    tx.set(ref, {
      userId,
      violationCount,
      recentViolations: updatedViolations,
      riskScore,
      bannedFromMediaUpload,
      lastUpdated: now,
    } as AccountRiskScore);
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Human review queue
// ─────────────────────────────────────────────────────────────────────────────

async function enqueueForHumanReview(
  postId: string,
  userId: string,
  mediaId: string,
  flags: string[],
  priority: ReviewPriority
): Promise<void> {
  const db = admin.firestore();
  await db.collection("humanReviewQueue").add({
    postId,
    userId,
    mediaId,
    priority,
    reason: flags,
    status: "pending",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Core pipeline runner
// ─────────────────────────────────────────────────────────────────────────────

async function runModerationPipeline(
  postId: string,
  userId: string,
  mediaUrl: string,
  mediaType: "image" | "video",
  mediaIndex: number
): Promise<PipelineResult> {
  const db = admin.firestore();
  const mediaId = `${postId}_${mediaIndex}`;
  const ref = db.collection("mediaModeration").doc(mediaId);
  const now = admin.firestore.Timestamp.now();

  // Fail closed while the asset is scanned. Public visibility is restored only
  // after every media item on the post is approved.
  await db.collection("posts").doc(postId).set({
    moderationBlocked: true,
    mediaModerationStatus: "pending",
    mediaModerationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  // Mark as pending
  await ref.set({
    postId, userId, mediaUrl, mediaType, mediaIndex,
    status: "pending",
    hashCheck: null, imageSafetyScore: null, textSafetyScore: null,
    fusionScore: 0, action: "allow",
    accountRiskMultiplier: 1.0,
    createdAt: now, updatedAt: now,
  } as ModerationRecord);

  try {
    // Run all 4 analysis layers in parallel for speed
    const [hashCheck, imageSafety, extractedText, accountRiskMultiplier] = await Promise.all([
      runHashCheck(mediaUrl),
      runImageSafety(mediaUrl, mediaType),
      runOCR(mediaUrl),
      getAccountRiskMultiplier(userId),
    ]);

    const textSafety = await runTextSafety(extractedText);
    const fusion = runMultimodalFusion(imageSafety, textSafety, hashCheck);
    const { action, status, priority } = runActionEngine(fusion, accountRiskMultiplier, hashCheck.matched);

    // Persist result (raw text is never stored)
    const record: Partial<ModerationRecord> = {
      status,
      action,
      hashCheck: { matched: hashCheck.matched, category: hashCheck.category },
      imageSafetyScore: imageSafety,
      textSafetyScore: { ...textSafety, extractedText: "" }, // strip raw text
      fusionScore: fusion.fusionScore,
      accountRiskMultiplier,
      updatedAt: admin.firestore.Timestamp.now(),
    };
    await ref.update(record);

    // Side effects
    if (priority) {
      await enqueueForHumanReview(postId, userId, mediaId, fusion.flags, priority);
    }
    if (action !== "allow") {
      await recordViolation(userId, mediaId, action);
    }
    if (action === "block" || action === "escalate") {
      // Suppress the post from public feed
      await db.collection("posts").doc(postId).set({
        moderationBlocked: true,
        mediaModerationStatus: status,
        mediaModerationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    return { mediaId, status, action };
  } catch (err) {
    console.error(`[mediaModerationPipeline] error for ${mediaId}:`, err);
    await ref.update({
      status: "reviewing", // fail-safe: send to human review
      action: "hold",
      updatedAt: admin.firestore.Timestamp.now(),
    });
    await db.collection("posts").doc(postId).set({
      moderationBlocked: true,
      mediaModerationStatus: "reviewing",
      mediaModerationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await enqueueForHumanReview(postId, userId, mediaId, ["pipeline_error"], "high");
    return { mediaId, status: "reviewing", action: "hold" };
  }
}

async function applyPostMediaGate(postId: string, results: PipelineResult[]): Promise<void> {
  if (results.length === 0) return;

  const hasBlocked = results.some((result) => result.status === "blocked" || result.action === "block");
  const hasEscalated = results.some((result) => result.status === "escalated" || result.action === "escalate");
  const hasHeld = results.some((result) => result.status === "reviewing" || result.status === "pending");

  let mediaModerationStatus: ModerationStatus = "approved";
  if (hasBlocked) mediaModerationStatus = "blocked";
  else if (hasEscalated) mediaModerationStatus = "escalated";
  else if (hasHeld) mediaModerationStatus = "reviewing";

  const approvedForPublicServing = mediaModerationStatus === "approved";

  await admin.firestore().collection("posts").doc(postId).set({
    moderationBlocked: !approvedForPublicServing,
    mediaModerationStatus,
    mediaModerationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

// ─────────────────────────────────────────────────────────────────────────────
// Trigger: Run pipeline when a post with media is created
// ─────────────────────────────────────────────────────────────────────────────

export const onPostCreatedRunMediaModeration = onDocumentCreated(
  "posts/{postId}",
  async (event) => {
    const post = event.data?.data();
    if (!post) return;

    const mediaItems: { url?: string; type?: string }[] = post.mediaItems ?? [];
    if (mediaItems.length === 0) return;

    const userId: string = post.userId ?? post.authorId ?? "";
    const postId = event.params.postId;

    const results = await Promise.all(
      mediaItems.map((item, index) => {
        const url = item.url ?? "";
        const type = item.type === "video" ? "video" : "image";
        return runModerationPipeline(postId, userId, url, type, index);
      })
    );
    await applyPostMediaGate(postId, results);
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// Trigger: Re-run pipeline when a post's media array changes
// ─────────────────────────────────────────────────────────────────────────────

export const onPostMediaUpdatedRunModeration = onDocumentUpdated(
  "posts/{postId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const beforeItems = JSON.stringify(before.mediaItems ?? []);
    const afterItems  = JSON.stringify(after.mediaItems ?? []);
    if (beforeItems === afterItems) return; // no media change

    const mediaItems: { url?: string; type?: string }[] = after.mediaItems ?? [];
    if (mediaItems.length === 0) return;

    const userId: string = after.userId ?? after.authorId ?? "";
    const postId = event.params.postId;

    const results = await Promise.all(
      mediaItems.map((item, index) => {
        const url = item.url ?? "";
        const type = item.type === "video" ? "video" : "image";
        return runModerationPipeline(postId, userId, url, type, index);
      })
    );
    await applyPostMediaGate(postId, results);
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// Callable: Submit human review decision
// Requires reviewer role — verified server-side via custom claim.
// ─────────────────────────────────────────────────────────────────────────────

export const submitMediaReviewDecision = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheckAndAuth(request);
  const reviewerId = request.auth!.uid;

  // Reviewer role check
  const reviewerToken = request.auth!.token;
  if (!reviewerToken.moderator && !reviewerToken.admin) {
    throw new Error("Reviewer role required.");
  }

  const { mediaId, decision, notes } = request.data as {
    mediaId: string;
    decision: "approve" | "block";
    notes?: string;
  };

  if (!mediaId || !decision) throw new Error("mediaId and decision are required.");

  const db = admin.firestore();
  const ref = db.collection("mediaModeration").doc(mediaId);
  const doc = await ref.get();
  if (!doc.exists) throw new Error("Moderation record not found.");

  const record = doc.data() as ModerationRecord;
  const newStatus: ModerationStatus = decision === "approve" ? "approved" : "blocked";

  await ref.update({
    status: newStatus,
    action: decision === "approve" ? "allow" : "block",
    reviewerId,
    reviewDecision: decision,
    reviewNotes: notes ?? null,
    reviewedAt: admin.firestore.Timestamp.now(),
    updatedAt: admin.firestore.Timestamp.now(),
  });

  // Update human review queue item
  const queueQuery = await db.collection("humanReviewQueue")
    .where("mediaId", "==", mediaId)
    .where("status", "==", "pending")
    .limit(1)
    .get();

  const batch = db.batch();
  queueQuery.docs.forEach(d => {
    batch.update(d.ref, { status: "resolved", resolvedAt: admin.firestore.FieldValue.serverTimestamp() });
  });

  // If reviewer blocked, suppress the post
  if (decision === "block") {
    batch.update(db.collection("posts").doc(record.postId), {
      moderationBlocked: true,
      mediaModerationStatus: "blocked",
      mediaModerationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await recordViolation(record.userId, mediaId, "block");
  } else {
    // If approved, lift only when no blocked/escalated/reviewing item remains.
    const remainingBlocked = await db.collection("mediaModeration")
      .where("postId", "==", record.postId)
      .where("status", "in", ["blocked", "escalated", "reviewing", "pending"])
      .get();
    const hasRemainingHeldItem = remainingBlocked.docs.some((item) => item.id !== mediaId);
    if (!hasRemainingHeldItem) {
      batch.update(db.collection("posts").doc(record.postId), {
        moderationBlocked: false,
        mediaModerationStatus: "approved",
        mediaModerationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }

  await batch.commit();
  return { success: true, newStatus };
});

// ─────────────────────────────────────────────────────────────────────────────
// Callable: Get moderation status for a post (for author UX)
// ─────────────────────────────────────────────────────────────────────────────

export const getPostModerationStatus = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheckAndAuth(request);
  const callerId = request.auth!.uid;

  const { postId } = request.data as { postId: string };
  if (!postId) throw new Error("postId required.");

  const db = admin.firestore();
  const records = await db.collection("mediaModeration")
    .where("postId", "==", postId)
    .get();

  // Authors can only see their own post's moderation status
  const ownRecords = records.docs
    .map(d => d.data() as ModerationRecord)
    .filter(r => r.userId === callerId);

  if (ownRecords.length === 0) return { status: "none" };

  // Overall status: worst status wins
  const statusPriority: Record<ModerationStatus, number> = {
    blocked: 5, escalated: 4, reviewing: 3, pending: 2, approved: 1,
  };
  const worst = ownRecords.reduce((prev, curr) =>
    statusPriority[curr.status] > statusPriority[prev.status] ? curr : prev
  );

  return {
    status: worst.status,
    action: worst.action,
    // Never expose internal scores to client
    canAppeal: worst.status === "blocked",
  };
});

// ─────────────────────────────────────────────────────────────────────────────
// Callable: Get account media risk score (admin only)
// ─────────────────────────────────────────────────────────────────────────────

export const getAccountMediaRiskScore = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheckAndAuth(request);

  const adminToken = request.auth!.token;
  if (!adminToken.admin) throw new Error("Admin role required.");

  const { userId } = request.data as { userId: string };
  if (!userId) throw new Error("userId required.");

  const db = admin.firestore();
  const doc = await db.collection("accountRiskScores").doc(userId).get();
  if (!doc.exists) return { riskScore: 0, violationCount: 0, bannedFromMediaUpload: false };

  const data = doc.data() as AccountRiskScore;
  return {
    riskScore: data.riskScore,
    violationCount: data.violationCount,
    bannedFromMediaUpload: data.bannedFromMediaUpload,
    recentViolationCount: data.recentViolations.length,
  };
});

// ─────────────────────────────────────────────────────────────────────────────
// Callable: Manual media moderation trigger (admin re-queue)
// ─────────────────────────────────────────────────────────────────────────────

export const triggerMediaModeration = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheckAndAuth(request);

  const adminToken = request.auth!.token;
  if (!adminToken.admin) throw new Error("Admin role required.");

  const { postId, mediaUrl, mediaType, mediaIndex, userId } = request.data as {
    postId: string;
    mediaUrl: string;
    mediaType: "image" | "video";
    mediaIndex: number;
    userId: string;
  };

  await runModerationPipeline(postId, userId, mediaUrl, mediaType, mediaIndex ?? 0);
  return { success: true };
});

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

type MediaType = "image" | "video";

interface MediaCaptionInput {
  mediaId: string;
  mediaIndex: number;
  type: MediaType;
  caption?: string | null;
  altText?: string | null;
  scriptureRefs?: string[];
  reflectionPrompt?: string | null;
}

interface MediaCaptionValidationResult {
  mediaId: string;
  mediaIndex: number;
  status: "approved" | "rejected" | "not_required";
  reason?: string | null;
}

interface ValidateMediaCaptionsRequest {
  postId: string;
  mediaItems: MediaCaptionInput[];
}

interface ValidateMediaCaptionsResponse {
  valid: boolean;
  results: MediaCaptionValidationResult[];
  rejectedItems: { mediaIndex: number; mediaId: string; reason: string }[];
}

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const CAPTION_MAX_LENGTH = 2200;
const ALT_TEXT_MAX_LENGTH = 1000;
const REFLECTION_MAX_LENGTH = 500;
const SCRIPTURE_REFS_MAX_COUNT = 10;
const MEDIA_ITEMS_MAX_COUNT = 10;

// Rate limit: 30 caption update calls per hour per user
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000;
const RATE_LIMIT_MAX_CALLS = 30;

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

function requireAppCheck(context: { app?: unknown }): void {
  if (!context.app) {
    throw new HttpsError("unauthenticated", "App Check required.");
  }
}

function trimToNull(value: string | null | undefined): string | null {
  if (!value) return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

async function enforceRateLimit(uid: string): Promise<void> {
  const db = admin.firestore();
  const ref = db.collection("rateLimits").doc(`mediaCaptionValidate_${uid}`);
  const now = Date.now();

  await db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    const data = doc.data();
    const windowStart = data?.windowStart ?? 0;
    const count = data?.count ?? 0;

    if (now - windowStart > RATE_LIMIT_WINDOW_MS) {
      tx.set(ref, { windowStart: now, count: 1 });
    } else if (count >= RATE_LIMIT_MAX_CALLS) {
      throw new HttpsError("resource-exhausted", "Rate limit exceeded. Try again later.");
    } else {
      tx.update(ref, { count: count + 1 });
    }
  });
}

// Lightweight text safety check using keyword heuristics.
// For production, this should route through the existing mediaModerationPipeline.
async function checkCaptionSafety(text: string): Promise<{ safe: boolean; reason?: string }> {
  const lower = text.toLowerCase();

  // Basic hate speech / harassment signals
  const blockedPatterns = [
    /\b(kill yourself|kys|go die)\b/i,
    /\b(n[i1]gg[ae]r|f[a4]gg[o0]t|ch[i1]nk|sp[i1]c)\b/i,
    /\bspam\s*link\b/i,
  ];

  for (const pattern of blockedPatterns) {
    if (pattern.test(lower)) {
      return { safe: false, reason: "Caption contains content that violates community guidelines." };
    }
  }

  return { safe: true };
}

// ─────────────────────────────────────────────────────────────────────────────
// Callable: validateMediaCaptions
// ─────────────────────────────────────────────────────────────────────────────

export const validateMediaCaptions = onCall(
  { enforceAppCheck: true },
  async (request): Promise<ValidateMediaCaptionsResponse> => {
    requireAppCheck(request);

    const auth = request.auth;
    if (!auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const data = request.data as ValidateMediaCaptionsRequest;
    const { postId, mediaItems } = data;

    if (!postId || typeof postId !== "string" || postId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "postId is required.");
    }

    if (!Array.isArray(mediaItems) || mediaItems.length === 0) {
      throw new HttpsError("invalid-argument", "mediaItems must be a non-empty array.");
    }

    if (mediaItems.length > MEDIA_ITEMS_MAX_COUNT) {
      throw new HttpsError(
        "invalid-argument",
        `Too many media items. Maximum is ${MEDIA_ITEMS_MAX_COUNT}.`
      );
    }

    // Rate limit
    await enforceRateLimit(auth.uid);

    const results: MediaCaptionValidationResult[] = [];
    const rejectedItems: { mediaIndex: number; mediaId: string; reason: string }[] = [];

    for (const item of mediaItems) {
      const caption = trimToNull(item.caption);
      const altText = trimToNull(item.altText);
      const reflectionPrompt = trimToNull(item.reflectionPrompt);
      const scriptureRefs = (item.scriptureRefs ?? []).filter(
        (r) => typeof r === "string" && r.trim().length > 0
      );

      // Validate lengths
      if (caption && caption.length > CAPTION_MAX_LENGTH) {
        rejectedItems.push({
          mediaIndex: item.mediaIndex,
          mediaId: item.mediaId,
          reason: `Caption for item ${item.mediaIndex + 1} exceeds ${CAPTION_MAX_LENGTH} characters.`,
        });
        results.push({ mediaId: item.mediaId, mediaIndex: item.mediaIndex, status: "rejected", reason: "Caption too long." });
        continue;
      }

      if (altText && altText.length > ALT_TEXT_MAX_LENGTH) {
        rejectedItems.push({
          mediaIndex: item.mediaIndex,
          mediaId: item.mediaId,
          reason: `Alt text for item ${item.mediaIndex + 1} exceeds ${ALT_TEXT_MAX_LENGTH} characters.`,
        });
        results.push({ mediaId: item.mediaId, mediaIndex: item.mediaIndex, status: "rejected", reason: "Alt text too long." });
        continue;
      }

      if (reflectionPrompt && reflectionPrompt.length > REFLECTION_MAX_LENGTH) {
        rejectedItems.push({
          mediaIndex: item.mediaIndex,
          mediaId: item.mediaId,
          reason: `Reflection for item ${item.mediaIndex + 1} exceeds ${REFLECTION_MAX_LENGTH} characters.`,
        });
        results.push({ mediaId: item.mediaId, mediaIndex: item.mediaIndex, status: "rejected", reason: "Reflection too long." });
        continue;
      }

      if (scriptureRefs.length > SCRIPTURE_REFS_MAX_COUNT) {
        rejectedItems.push({
          mediaIndex: item.mediaIndex,
          mediaId: item.mediaId,
          reason: `Too many scripture references for item ${item.mediaIndex + 1}.`,
        });
        results.push({ mediaId: item.mediaId, mediaIndex: item.mediaIndex, status: "rejected", reason: "Too many scripture refs." });
        continue;
      }

      // Safety check (only if caption exists)
      if (caption) {
        const safety = await checkCaptionSafety(caption);
        if (!safety.safe) {
          rejectedItems.push({
            mediaIndex: item.mediaIndex,
            mediaId: item.mediaId,
            reason: safety.reason ?? "Caption violates community guidelines.",
          });
          results.push({ mediaId: item.mediaId, mediaIndex: item.mediaIndex, status: "rejected", reason: "Caption flagged." });
          continue;
        }
      }

      results.push({
        mediaId: item.mediaId,
        mediaIndex: item.mediaIndex,
        status: caption ? "approved" : "not_required",
      });
    }

    const valid = rejectedItems.length === 0;

    // Write validation result to Firestore for observability
    if (!valid) {
      const db = admin.firestore();
      await db
        .collection("posts").doc(postId.trim())
        .collection("mediaCaptionValidation").doc(auth.uid)
        .set({
          uid: auth.uid,
          checkedAt: admin.firestore.FieldValue.serverTimestamp(),
          rejectedCount: rejectedItems.length,
          totalCount: mediaItems.length,
        }, { merge: true });
    }

    return { valid, results, rejectedItems };
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// Callable: updatePostMediaCaptions (edit-post support)
// ─────────────────────────────────────────────────────────────────────────────

interface MediaCaptionUpdate {
  mediaId: string;
  caption?: string | null;
  altText?: string | null;
  scriptureRefs?: string[];
  reflectionPrompt?: string | null;
}

interface UpdateMediaCaptionsRequest {
  postId: string;
  updates: MediaCaptionUpdate[];
}

export const updatePostMediaCaptions = onCall(
  { enforceAppCheck: true },
  async (request) => {
    requireAppCheck(request);

    const auth = request.auth;
    if (!auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const data = request.data as UpdateMediaCaptionsRequest;
    const { postId, updates } = data;

    if (!postId || typeof postId !== "string") {
      throw new HttpsError("invalid-argument", "postId is required.");
    }
    if (!Array.isArray(updates) || updates.length === 0) {
      throw new HttpsError("invalid-argument", "updates must be a non-empty array.");
    }

    const db = admin.firestore();
    const postRef = db.collection("posts").doc(postId.trim());
    const postSnap = await postRef.get();

    if (!postSnap.exists) {
      throw new HttpsError("not-found", "Post not found.");
    }

    const postData = postSnap.data();
    if (postData?.authorUid !== auth.uid) {
      throw new HttpsError("permission-denied", "Only the post author can update captions.");
    }

    // Rate limit
    await enforceRateLimit(auth.uid);

    const batch = db.batch();
    const now = admin.firestore.FieldValue.serverTimestamp();

    for (const update of updates) {
      const caption = trimToNull(update.caption);
      const altText = trimToNull(update.altText);
      const reflectionPrompt = trimToNull(update.reflectionPrompt);
      const scriptureRefs = (update.scriptureRefs ?? []).filter(
        (r) => typeof r === "string" && r.trim().length > 0
      );

      if (caption && caption.length > CAPTION_MAX_LENGTH) {
        throw new HttpsError("invalid-argument", `Caption for ${update.mediaId} is too long.`);
      }
      if (altText && altText.length > ALT_TEXT_MAX_LENGTH) {
        throw new HttpsError("invalid-argument", `Alt text for ${update.mediaId} is too long.`);
      }
      if (reflectionPrompt && reflectionPrompt.length > REFLECTION_MAX_LENGTH) {
        throw new HttpsError("invalid-argument", `Reflection for ${update.mediaId} is too long.`);
      }
      if (scriptureRefs.length > SCRIPTURE_REFS_MAX_COUNT) {
        throw new HttpsError("invalid-argument", `Too many scripture refs for ${update.mediaId}.`);
      }

      const metaRef = postRef.collection("mediaMeta").doc(update.mediaId);
      batch.set(metaRef, {
        caption: caption ?? admin.firestore.FieldValue.delete(),
        altText: altText ?? admin.firestore.FieldValue.delete(),
        scriptureRefs: scriptureRefs.length > 0 ? scriptureRefs : admin.firestore.FieldValue.delete(),
        reflectionPrompt: reflectionPrompt ?? admin.firestore.FieldValue.delete(),
        captionModerationStatus: caption ? "pending" : "not_required",
        captionUpdatedAt: now,
      }, { merge: true });
    }

    batch.update(postRef, { updatedAt: now });

    await batch.commit();

    return { success: true };
  }
);

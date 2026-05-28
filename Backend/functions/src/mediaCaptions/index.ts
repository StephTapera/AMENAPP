import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";
import { createHash } from "crypto";
import { ImageAnnotatorClient } from "@google-cloud/vision";
import { MEDIA_CAPTION_LIMITS, MediaCaptionModeration, PublishMediaItemInput } from "./contract";
import { moderateText as runTextModeration } from "../safety/TextModerationService";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
const CLAUDE_ALT_TEXT_MODEL = "claude-haiku-4-5-20251001";
let visionClient: ImageAnnotatorClient | null = null;

function getVisionClient(): ImageAnnotatorClient {
  if (!visionClient) visionClient = new ImageAnnotatorClient();
  return visionClient;
}

function requireAuth(request: any): string {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  if (!request.app) throw new HttpsError("unauthenticated", "App Check attestation required.");
  return request.auth.uid;
}

function clean(value: unknown, max: number, field: string): string | null {
  if (value == null) return null;
  if (typeof value !== "string") throw new HttpsError("invalid-argument", `${field} must be a string.`);
  const trimmed = value.trim();
  if (!trimmed) return null;
  if (trimmed.length > max) throw new HttpsError("invalid-argument", `${field} is too long.`);
  return trimmed;
}

function hashText(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

async function moderateCaptionText(uid: string, text: string | null, context: Record<string, unknown>): Promise<MediaCaptionModeration> {
  if (!text) return { status: "not_required", reason: null, checkedAt: admin.firestore.Timestamp.now() };
  const textHash = hashText(text);
  const cached = await db.collection("mediaCaptionModerationCache").doc(textHash).get();
  if (cached.exists) {
    const data = cached.data() ?? {};
    return {
      status: data.status ?? "pending",
      reason: data.reason ?? null,
      checkedAt: data.checkedAt ?? admin.firestore.Timestamp.now(),
    };
  }

  const textDecision = await runTextModeration(text, "post", false, String(context.mediaId ?? ""));
  const rejected = !textDecision.allowed ||
    ["require_edit", "block", "block_and_suspend", "escalate", "escalate_to_legal"].includes(textDecision.enforcement);
  const pending = textDecision.requiresHumanReview;
  const moderation: MediaCaptionModeration = {
    status: rejected ? "rejected" : pending ? "pending" : "approved",
    reason: rejected ? (textDecision.userFacingMessage ?? "This caption needs edits before it can be shown.") : null,
    checkedAt: admin.firestore.Timestamp.now(),
  };

  await db.collection("mediaCaptionModerationCache").doc(textHash).set({
    textHash,
    status: moderation.status,
    reason: moderation.reason,
    checkedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  await db.collection("mediaCaptionModerationAudit").add({
    uid,
    textHash,
    decision: moderation.status,
    context,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return moderation;
}

function sanitizeItem(raw: any, index: number): PublishMediaItemInput {
  const type = raw?.type;
  if (type !== "image" && type !== "video") throw new HttpsError("invalid-argument", "Invalid media type.");
  if (typeof raw?.url !== "string" || !raw.url.trim()) throw new HttpsError("invalid-argument", "Media URL is required.");
  const scriptureRefs = Array.isArray(raw.scriptureRefs) ?
    raw.scriptureRefs
      .filter((ref: unknown) => typeof ref === "string")
      .map((ref: string) => ref.trim())
      .filter((ref: string) => ref.length > 0) :
    [];
  if (scriptureRefs.length > MEDIA_CAPTION_LIMITS.scriptureRefs) throw new HttpsError("invalid-argument", "Too many scripture references.");
  return {
    id: typeof raw.id === "string" ? raw.id : undefined,
    mediaId: typeof raw.mediaId === "string" ? raw.mediaId : undefined,
    mediaIndex: typeof raw.mediaIndex === "number" ? raw.mediaIndex : index,
    type,
    url: raw.url.trim(),
    storagePath: typeof raw.storagePath === "string" ? raw.storagePath.trim() : null,
    caption: clean(raw.caption, MEDIA_CAPTION_LIMITS.caption, "caption"),
    altText: clean(raw.altText, MEDIA_CAPTION_LIMITS.altText, "altText"),
    scriptureRefs: scriptureRefs.slice(0, MEDIA_CAPTION_LIMITS.scriptureRefs),
    reflectionPrompt: clean(raw.reflectionPrompt, MEDIA_CAPTION_LIMITS.reflectionPrompt, "reflectionPrompt"),
  };
}

async function moderateItem(uid: string, item: PublishMediaItemInput): Promise<MediaCaptionModeration> {
  const combined = [item.caption, item.altText, item.reflectionPrompt].filter(Boolean).join("\n");
  return moderateCaptionText(uid, combined || null, { mediaIndex: item.mediaIndex, mediaId: item.mediaId ?? item.id ?? "" });
}

async function describeMediaWithVision(url: string | undefined, mediaType: "photo" | "video"): Promise<string | null> {
  if (!url || mediaType === "video") return null;
  if (!url.startsWith("gs://") && !url.startsWith("http://") && !url.startsWith("https://")) return null;
  try {
    const [result] = await (getVisionClient() as any).labelDetection({ image: { source: { imageUri: url } } });
    const labels = (result.labelAnnotations ?? [])
      .map((label: { description?: unknown }) => label.description)
      .filter((label: unknown): label is string => typeof label === "string" && label.trim().length > 0)
      .slice(0, 5);
    if (labels.length === 0) return null;
    return `Photo showing ${labels.join(", ")}.`;
  } catch {
    return null;
  }
}

function moderationEquals(left: unknown, right: MediaCaptionModeration): boolean {
  const current = left as { status?: unknown; reason?: unknown } | null | undefined;
  return current?.status === right.status && (current.reason ?? null) === (right.reason ?? null);
}

async function deriveModerationForPostMedia(postId: string, uid: string, mediaItems: unknown[]): Promise<{ items: unknown[]; changed: boolean; rejectedCount: number }> {
  let changed = false;
  let rejectedCount = 0;
  const items: unknown[] = [];

  for (const [index, rawItem] of mediaItems.entries()) {
    if (!rawItem || typeof rawItem !== "object") {
      items.push(rawItem);
      continue;
    }

    const itemMap = rawItem as Record<string, any>;
    const metadata = itemMap.frameCaptionMetadata && typeof itemMap.frameCaptionMetadata === "object" ?
      itemMap.frameCaptionMetadata as Record<string, any> :
      null;

    if (!metadata) {
      items.push(itemMap);
      continue;
    }

    const payload: PublishMediaItemInput = {
      id: typeof itemMap.id === "string" ? itemMap.id : undefined,
      mediaId: typeof itemMap.id === "string" ? itemMap.id : undefined,
      mediaIndex: typeof metadata.frameIndex === "number" ? metadata.frameIndex : index,
      type: itemMap.type === "video" ? "video" : "image",
      url: typeof itemMap.url === "string" ? itemMap.url : `post://${postId}/${index}`,
      storagePath: typeof itemMap.storagePath === "string" ? itemMap.storagePath : null,
      caption: clean(metadata.text, MEDIA_CAPTION_LIMITS.caption, "caption"),
      altText: clean(metadata.altText, MEDIA_CAPTION_LIMITS.altText, "altText"),
      scriptureRefs: Array.isArray(metadata.scriptureRefs) ?
        metadata.scriptureRefs.filter((ref: unknown) => typeof ref === "string").slice(0, MEDIA_CAPTION_LIMITS.scriptureRefs) :
        [],
      reflectionPrompt: clean(metadata.reflectionPrompt, MEDIA_CAPTION_LIMITS.reflectionPrompt, "reflectionPrompt"),
    };

    const moderation = await moderateItem(uid, payload);
    if (moderation.status === "rejected") rejectedCount += 1;
    if (!moderationEquals(metadata.captionModeration, moderation)) changed = true;

    items.push({
      ...itemMap,
      frameCaptionMetadata: {
        ...metadata,
        captionModeration: moderation,
      },
    });
  }

  return { items, changed, rejectedCount };
}

export const moderateMediaCaption = onCall({ enforceAppCheck: true, timeoutSeconds: 15 }, async (request) => {
  const uid = requireAuth(request);
  const data = request.data ?? {};
  const item = sanitizeItem({ ...data, type: data.type ?? "image", url: data.url ?? "draft://caption" }, Number(data.mediaIndex ?? 0));
  const status = await moderateItem(uid, item);
  return { status: status.status, reason: status.reason ?? undefined };
});

export const publishPostWithMedia = onCall({ enforceAppCheck: true, timeoutSeconds: 30 }, async (request) => {
  const uid = requireAuth(request);
  const data = request.data ?? {};
  const items: PublishMediaItemInput[] = Array.isArray(data.media) ? data.media.map(sanitizeItem) : [];
  if (items.length === 0) throw new HttpsError("invalid-argument", "At least one media item is required.");
  const moderated = await Promise.all(items.map(async (item) => ({ item, moderation: await moderateItem(uid, item) })));
  const rejectedIndex = moderated.findIndex((entry) => entry.moderation.status === "rejected");
  if (rejectedIndex >= 0) {
    throw new HttpsError("failed-precondition", "media-caption-rejected", {
      code: "media-caption-rejected",
      mediaIndex: rejectedIndex,
      mediaId: moderated[rejectedIndex].item.mediaId ?? moderated[rejectedIndex].item.id ?? "",
      reason: moderated[rejectedIndex].moderation.reason,
    });
  }
  const postRef = await db.collection("posts").add({
    authorId: uid,
    content: clean(data.content, 4000, "content") ?? "",
    mediaItems: moderated.map(({ item, moderation }) => ({
      id: item.id ?? item.mediaId ?? `${item.mediaIndex}`,
      type: item.type,
      url: item.url,
      order: item.mediaIndex,
      frameCaption: item.caption,
      frameCaptionMetadata: {
        id: item.id ?? item.mediaId ?? `${item.mediaIndex}`,
        frameIndex: item.mediaIndex,
        text: item.caption,
        altText: item.altText,
        scriptureRefs: item.scriptureRefs ?? [],
        reflectionPrompt: item.reflectionPrompt,
        captionModeration: moderation,
      },
    })),
    mediaCount: moderated.length,
    moderationStatus: "pending",
    status: "moderating",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { postId: postRef.id, mediaCount: moderated.length };
});

export const updatePostMediaCaptions = onCall({ enforceAppCheck: true, timeoutSeconds: 30 }, async (request) => {
  const uid = requireAuth(request);
  const data = request.data ?? {};
  if (typeof data.postId !== "string") throw new HttpsError("invalid-argument", "postId is required.");
  const postRef = db.collection("posts").doc(data.postId);
  const post = await postRef.get();
  if (!post.exists || post.data()?.authorId !== uid) throw new HttpsError("permission-denied", "Only the owner can update captions.");
  const items: PublishMediaItemInput[] = Array.isArray(data.media) ? data.media.map(sanitizeItem) : [];
  const moderated = await Promise.all(items.map(async (item) => ({
    id: item.id ?? item.mediaId ?? `${item.mediaIndex}`,
    type: item.type,
    url: item.url,
    order: item.mediaIndex,
    frameCaption: item.caption,
    frameCaptionMetadata: {
      id: item.id ?? item.mediaId ?? `${item.mediaIndex}`,
      frameIndex: item.mediaIndex,
      text: item.caption,
      altText: item.altText,
      scriptureRefs: item.scriptureRefs ?? [],
      reflectionPrompt: item.reflectionPrompt,
      captionModeration: await moderateItem(uid, item),
    },
  })));
  await postRef.set({ mediaItems: moderated, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
  return { postId: data.postId, mediaCount: moderated.length };
});

export const processPostMediaCaptionModeration = onDocumentWritten("posts/{postId}", async (event) => {
  const after = event.data?.after;
  if (!after?.exists) return;

  const data = after.data() ?? {};
  const uid = typeof data.authorId === "string" ? data.authorId : "";
  const mediaItems = Array.isArray(data.mediaItems) ? data.mediaItems : [];
  if (!uid || mediaItems.length === 0) return;

  const result = await deriveModerationForPostMedia(event.params.postId, uid, mediaItems);
  if (!result.changed) return;

  await after.ref.set({
    mediaItems: result.items,
    mediaCaptionModeration: {
      status: result.rejectedCount > 0 ? "rejected" : "approved",
      rejectedCount: result.rejectedCount,
      checkedAt: admin.firestore.FieldValue.serverTimestamp(),
      source: "processPostMediaCaptionModeration",
    },
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
});

export const generateAltText = onCall({ enforceAppCheck: true, timeoutSeconds: 20, secrets: [anthropicApiKey] }, async (request) => {
  requireAuth(request);
  const data = request.data ?? {};
  const mediaType = data.type === "video" ? "video" : "photo";
  let altText = await describeMediaWithVision(typeof data.url === "string" ? data.url : undefined, mediaType) ??
    `Describe this ${mediaType} clearly for someone using VoiceOver.`;
  const apiKey = anthropicApiKey.value();
  if (apiKey) {
    try {
      const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
          model: CLAUDE_ALT_TEXT_MODEL,
          max_tokens: 80,
          temperature: 0.2,
          messages: [{
            role: "user",
            content: `Write concise accessibility alt text for a ${mediaType}. Do not mention that you cannot see the media. Return one sentence only. Media URL or storage hint: ${typeof data.url === "string" ? data.url.slice(0, 180) : "unavailable"}`,
          }],
        }),
      });
      if (response.ok) {
        const body = await response.json() as { content?: Array<{ text?: string }> };
        const generated = body.content?.map((part) => part.text ?? "").join(" ").trim();
        if (generated) altText = generated.slice(0, MEDIA_CAPTION_LIMITS.altText);
      }
    } catch {
      // Fail soft: alt text is a suggestion only and remains user-editable.
    }
  }
  return { altText, suggestion: altText };
});

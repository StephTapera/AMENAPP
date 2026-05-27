import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import vision from "@google-cloud/vision";

const db = admin.firestore();
const storage = admin.storage();
const visionClient = new vision.ImageAnnotatorClient();

const MAX_PROFILE_BANNER_BYTES = 8 * 1024 * 1024;
const ALLOWED_CONTENT_TYPES = new Set([
  "image/jpeg",
  "image/jpg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif",
]);

const HIGH_RISK_VALUES = new Set(["LIKELY", "VERY_LIKELY"]);
const HUMAN_REVIEW_VALUES = new Set(["POSSIBLE"]);

type ProfileBanner = {
  id?: string;
  ownerUid?: string;
  storagePath?: string;
  status?: string;
};

type ModerationDecision = {
  status: "approved" | "pending" | "rejected";
  reason: string;
  labels?: Record<string, string>;
};

function assertString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new functions.https.HttpsError("invalid-argument", `Missing ${field}`);
  }
  return value.trim();
}

function safeSearchValue(value: unknown): string {
  return typeof value === "string" ? value : "UNKNOWN";
}

async function moderateImage(bucketName: string, storagePath: string): Promise<ModerationDecision> {
  const [result] = await visionClient.safeSearchDetection(`gs://${bucketName}/${storagePath}`);
  const safeSearch = result.safeSearchAnnotation;
  const labels = {
    adult: safeSearchValue(safeSearch?.adult),
    racy: safeSearchValue(safeSearch?.racy),
    violence: safeSearchValue(safeSearch?.violence),
    medical: safeSearchValue(safeSearch?.medical),
    spoof: safeSearchValue(safeSearch?.spoof),
  };

  if (HIGH_RISK_VALUES.has(labels.adult) || HIGH_RISK_VALUES.has(labels.racy) || HIGH_RISK_VALUES.has(labels.violence)) {
    return { status: "rejected", reason: "safe_search_high_risk", labels };
  }

  if (HUMAN_REVIEW_VALUES.has(labels.adult) || HUMAN_REVIEW_VALUES.has(labels.racy) || HUMAN_REVIEW_VALUES.has(labels.violence)) {
    return { status: "pending", reason: "safe_search_human_review", labels };
  }

  return { status: "approved", reason: "safe_search_clear", labels };
}

export const finalizeProfileBannerUpload = functions
  .runWith({ enforceAppCheck: true, timeoutSeconds: 60, memory: "512MB" })
  .https.onCall(async (data, context) => {
    const uid = context.auth?.uid;
    if (!uid) {
      throw new functions.https.HttpsError("unauthenticated", "Auth required");
    }

    if (context.app == undefined) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "The function must be called from an App Check verified app."
      );
    }

    const bannerId = assertString(data?.bannerId, "bannerId");
    const userRef = db.collection("users").doc(uid);
    const snap = await userRef.get();
    const banner = snap.get("profileBanner") as ProfileBanner | undefined;

    if (!banner || banner.id !== bannerId || banner.ownerUid !== uid) {
      throw new functions.https.HttpsError("not-found", "Pending profile banner not found");
    }

    if (banner.status !== "pending") {
      return { ok: true, status: banner.status, reason: "already_finalized" };
    }

    const storagePath = assertString(banner.storagePath, "storagePath");
    const expectedPrefix = `profileBanners/${uid}/`;
    if (!storagePath.startsWith(expectedPrefix)) {
      await userRef.update({
        "profileBanner.status": "rejected",
        "profileBanner.moderationReason": "storage_path_owner_mismatch",
        "profileBanner.updatedAt": admin.firestore.FieldValue.serverTimestamp(),
      });
      return { ok: false, status: "rejected", reason: "storage_path_owner_mismatch" };
    }

    const bucket = storage.bucket();
    const file = bucket.file(storagePath);
    const [exists] = await file.exists();
    if (!exists) {
      throw new functions.https.HttpsError("not-found", "Uploaded banner file was not found");
    }

    const [metadata] = await file.getMetadata();
    const size = Number(metadata.size ?? 0);
    const contentType = metadata.contentType ?? "";

    if (size <= 0 || size > MAX_PROFILE_BANNER_BYTES || !ALLOWED_CONTENT_TYPES.has(contentType)) {
      await userRef.update({
        "profileBanner.status": "rejected",
        "profileBanner.moderationReason": "invalid_file_metadata",
        "profileBanner.updatedAt": admin.firestore.FieldValue.serverTimestamp(),
      });
      return { ok: false, status: "rejected", reason: "invalid_file_metadata" };
    }

    const decision = await moderateImage(bucket.name, storagePath);
    const update: Record<string, unknown> = {
      "profileBanner.status": decision.status,
      "profileBanner.moderationReason": decision.reason,
      "profileBanner.safeSearch": decision.labels ?? {},
      "profileBanner.reviewedAt": admin.firestore.FieldValue.serverTimestamp(),
      "profileBanner.updatedAt": admin.firestore.FieldValue.serverTimestamp(),
    };

    if (decision.status === "pending") {
      update["profileBanner.humanReviewQueuedAt"] = admin.firestore.FieldValue.serverTimestamp();
    }

    await userRef.update(update);

    return {
      ok: decision.status === "approved",
      status: decision.status,
      reason: decision.reason,
    };
  });

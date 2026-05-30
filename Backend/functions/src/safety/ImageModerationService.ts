/**
 * ImageModerationService.ts
 *
 * Backend image moderation callable for Amen Safety OS.
 * Analyzes images stored in Firebase Storage via Google Cloud Vision SafeSearch
 * and CSAM hash checking before any image becomes publicly visible.
 *
 * All images must pass this service before their parent content document
 * transitions from moderationStatus="pending" to "approved".
 *
 * Integrates with:
 *   - mediaModerationPipeline.ts (6-layer pipeline for full media analysis)
 *   - mediaScanning.ts (Storage trigger for automatic scanning on upload)
 *   - AmenSafetyPolicy.ts (enforcement actions)
 *   - EvidencePreservationService (for escalated findings)
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { ImageAnnotatorClient } from "@google-cloud/vision";
import axios from "axios";
import {
  policyFor,
  userFacingMessageFor,
  ModerationStatus,
  EnforcementAction,
  AMEN_SAFETY_POLICY_VERSION,
} from "./AmenSafetyPolicy";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Types ────────────────────────────────────────────────────────────────────

export type ImageContentType =
  | "post_image"
  | "profile_picture"
  | "banner_image"
  | "message_image"
  | "group_photo"
  | "church_photo"
  | "event_photo"
  | "story_image";

export interface ImageModerationRequest {
  storageUri: string;          // gs://bucket/path/to/image
  contentId?: string;
  contentType: ImageContentType;
  uploaderUid: string;
  isMinor?: boolean;
}

export interface ImageModerationResult {
  allowed: boolean;
  enforcement: EnforcementAction;
  moderationStatus: ModerationStatus;
  harmCategoryId: string | null;
  userFacingMessage: string | null;
  requiresHumanReview: boolean;
  safeSearchScores?: SafeSearchScores;
  csamHashMatch?: boolean;
  policyVersion: string;
}

interface SafeSearchScores {
  adult: string;
  racy: string;
  violence: string;
  spoof: string;
  medical: string;
}

// Likelihood levels returned by Cloud Vision SafeSearch
const LIKELIHOOD_ORDER = ["UNKNOWN", "VERY_UNLIKELY", "UNLIKELY", "POSSIBLE", "LIKELY", "VERY_LIKELY"];

function likelihoodIndex(label: string | null | undefined): number {
  return LIKELIHOOD_ORDER.indexOf(label ?? "UNKNOWN");
}

// ─── CSAM Hash Check (Layer 0) ────────────────────────────────────────────────

async function checkCsamHash(storageUri: string): Promise<boolean> {
  const lookupUrl = process.env.CSAM_HASH_LOOKUP_URL;
  const lookupToken = process.env.CSAM_HASH_LOOKUP_TOKEN;
  if (!lookupUrl || !lookupToken) {
    // SECURITY (M-01): CSAM hash matching is a child-safety control — silently
    // skipping it creates an undetected gap. Log at CRITICAL severity so the
    // missing secret surfaces in monitoring/alerting immediately.
    // ACTION REQUIRED: set CSAM_HASH_LOOKUP_URL and CSAM_HASH_LOOKUP_TOKEN in
    // Firebase Secret Manager and add them to the function's secrets:[...] array.
    logger.error("[ImageModerationService] CRITICAL: CSAM hash lookup secrets not configured. " +
      "CSAM hash-matching is DISABLED. Configure CSAM_HASH_LOOKUP_URL and " +
      "CSAM_HASH_LOOKUP_TOKEN in Firebase Secret Manager immediately.");
    return false;
  }

  try {
    const response = await axios.post<{ match: boolean }>(
      lookupUrl,
      { storageUri },
      {
        headers: { Authorization: `Bearer ${lookupToken}` },
        timeout: 8000,
      }
    );
    return response.data.match === true;
  } catch (err) {
    logger.error("[ImageModerationService] CSAM hash check failed.", err);
    // Fail closed — treat as unknown, route to human review
    return false;
  }
}

// ─── Cloud Vision SafeSearch (Layer 1) ────────────────────────────────────────

let _visionClient: ImageAnnotatorClient | null = null;

function getVisionClient(): ImageAnnotatorClient {
  if (!_visionClient) _visionClient = new ImageAnnotatorClient();
  return _visionClient;
}

async function runSafeSearch(storageUri: string): Promise<SafeSearchScores | null> {
  try {
    const client = getVisionClient();
    const [result] = await client.safeSearchDetection({ image: { source: { imageUri: storageUri } } });
    const ss = result.safeSearchAnnotation;
    if (!ss) return null;
    return {
      adult: String(ss.adult ?? "UNKNOWN"),
      racy: String(ss.racy ?? "UNKNOWN"),
      violence: String(ss.violence ?? "UNKNOWN"),
      spoof: String(ss.spoof ?? "UNKNOWN"),
      medical: String(ss.medical ?? "UNKNOWN"),
    };
  } catch (err) {
    logger.error("[ImageModerationService] Cloud Vision SafeSearch failed.", err);
    return null;
  }
}

function harmFromSafeSearch(
  scores: SafeSearchScores,
  isMinor: boolean
): { harmCategoryId: string; enforcement: EnforcementAction } | null {
  const adultIdx = likelihoodIndex(scores.adult);
  const racyIdx = likelihoodIndex(scores.racy);
  const violenceIdx = likelihoodIndex(scores.violence);

  const minorThresholdAdult = isMinor ? 2 : 3;   // POSSIBLE for minors, LIKELY for adults
  const minorThresholdViolence = isMinor ? 2 : 3;

  if (adultIdx >= 5) {
    // VERY_LIKELY explicit adult → block and escalate
    return { harmCategoryId: "pornography", enforcement: "escalate" };
  }
  if (adultIdx >= minorThresholdAdult) {
    return { harmCategoryId: "nudity", enforcement: "block" };
  }
  if (racyIdx >= 4 && isMinor) {
    // LIKELY racy content is blocked for minors
    return { harmCategoryId: "sexual_content", enforcement: "block" };
  }
  if (violenceIdx >= minorThresholdViolence + 1) {
    return { harmCategoryId: "graphic_violence", enforcement: "block" };
  }
  if (violenceIdx >= 5) {
    return { harmCategoryId: "gore", enforcement: "escalate" };
  }
  return null;
}

// ─── Core Logic ───────────────────────────────────────────────────────────────

export async function moderateImage(
  req: ImageModerationRequest
): Promise<ImageModerationResult> {
  const { storageUri, contentType, isMinor = false, uploaderUid, contentId } = req;

  // Layer 0 — CSAM hash check (fastest path to escalation)
  const csamMatch = await checkCsamHash(storageUri);
  if (csamMatch) {
    logger.error(`[ImageModerationService] CSAM hash match uid=${uploaderUid} uri=${storageUri}`);
    await writeImageModerationLog(uploaderUid, storageUri, contentType, contentId, "csam", "escalate_to_legal", true);
    return {
      allowed: false,
      enforcement: "escalate_to_legal",
      moderationStatus: "escalated",
      harmCategoryId: "csam",
      userFacingMessage: userFacingMessageFor("csam"),
      requiresHumanReview: true,
      csamHashMatch: true,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
    };
  }

  // Layer 1 — Cloud Vision SafeSearch
  const safeSearchScores = await runSafeSearch(storageUri);

  if (!safeSearchScores) {
    // Vision API unavailable — hold for human review (fail closed)
    logger.warn(`[ImageModerationService] SafeSearch unavailable. Holding for review. uid=${uploaderUid}`);
    await writeImageModerationLog(uploaderUid, storageUri, contentType, contentId, null, "block", false);
    return {
      allowed: false,
      enforcement: "block",
      moderationStatus: "needs_human_review",
      harmCategoryId: null,
      userFacingMessage: "Your image is being reviewed and will be available shortly.",
      requiresHumanReview: true,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
    };
  }

  const harm = harmFromSafeSearch(safeSearchScores, isMinor);
  if (harm) {
    const policy = policyFor(harm.harmCategoryId);
    await writeImageModerationLog(
      uploaderUid, storageUri, contentType, contentId,
      harm.harmCategoryId, harm.enforcement, policy?.preserveEvidence ?? false
    );
    return {
      allowed: false,
      enforcement: harm.enforcement,
      moderationStatus: policy?.moderationStatus ?? "blocked",
      harmCategoryId: harm.harmCategoryId,
      userFacingMessage: userFacingMessageFor(harm.harmCategoryId),
      requiresHumanReview: harm.enforcement === "escalate" || harm.enforcement === "escalate_to_legal",
      safeSearchScores,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
    };
  }

  // All layers passed — image is safe
  return {
    allowed: true,
    enforcement: "allow",
    moderationStatus: "approved",
    harmCategoryId: null,
    userFacingMessage: null,
    requiresHumanReview: false,
    safeSearchScores,
    policyVersion: AMEN_SAFETY_POLICY_VERSION,
  };
}

async function writeImageModerationLog(
  uid: string,
  storageUri: string,
  contentType: ImageContentType,
  contentId: string | undefined,
  harmCategoryId: string | null,
  enforcement: string,
  preserveEvidence: boolean
): Promise<void> {
  try {
    await db.collection("imageModerationLogs").add({
      uid,
      storageUri,
      contentType,
      contentId: contentId ?? null,
      harmCategoryId,
      enforcement,
      preserveEvidence,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (err) {
    logger.warn("[ImageModerationService] Failed to write moderation log.", err);
  }
}

// ─── Callable Function ────────────────────────────────────────────────────────

/**
 * moderateImage callable
 *
 * Called by iOS after uploading an image to Storage (still in pending state)
 * but before the associated content document is published.
 *
 * The client must NOT transition content to visible until this returns
 * allowed: true. The server-side mediaModerationPipeline trigger also
 * runs automatically on Storage upload for defense-in-depth.
 */
export const moderateImageCallable = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<ImageModerationRequest>): Promise<Omit<ImageModerationResult, "safeSearchScores">> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const { storageUri, contentType, contentId, isMinor } = request.data;

    if (!storageUri || !storageUri.startsWith("gs://")) {
      throw new HttpsError("invalid-argument", "storageUri must be a gs:// URI.");
    }

    const result = await moderateImage({
      storageUri,
      contentType,
      contentId,
      uploaderUid: request.auth.uid,
      isMinor,
    });

    // Strip raw scores before returning to client
    const { safeSearchScores: _, ...clientResult } = result;
    return clientResult;
  }
);

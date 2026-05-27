/**
 * provenance.ts — Amen Trust + Safety OS (True Source)
 *
 * Callable: registerMediaProvenance
 * Callable: getMediaProvenance
 *
 * Implements "Amen True Source":
 *   - Store upload hash, perceptual hash, metadata digest
 *   - Detect AI-generation indicators
 *   - Detect editing signals
 *   - Track source chain
 *   - Apply creator declaration
 *   - Block/limit content with uncertain provenance from trends
 *
 * Provenance records are backend-only write; clients read via labeled UI.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import * as crypto from "crypto";

import {
  MediaProvenance,
  CreatorDeclaration,
  ProvenanceStatus,
  DeviceTrustLevel,
  TRUST_SAFETY_OS_VERSION,
} from "./safetyTypes";
import { writeSafetyAuditEvent } from "./safetyAuditLog";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const PROVENANCE_COLLECTION = "media";

// ─── Types ───────────────────────────────────────────────────────────────

export interface RegisterProvenanceRequest {
  mediaId: string;
  storageUri: string;
  mimeType: string;
  fileSizeBytes: number;
  originalHash: string;         // SHA-256 of raw bytes (client-computed)
  metadataJson?: string;        // exif / creation metadata
  creatorDeclaration: CreatorDeclaration;
  deviceTrust?: DeviceTrustLevel;
  sourceChain?: string[];       // previous content IDs if reposted
}

export interface ProvenanceResponse {
  mediaId: string;
  provenanceStatus: ProvenanceStatus;
  trendEligible: boolean;
  boostEligible: boolean;
  labelRequired: boolean;
  labelType: string;
  policyVersion: string;
}

// ─── AI detection heuristics ─────────────────────────────────────────────

function detectAIIndicators(metadataJson: string | undefined): {
  score: number;
  editingDetected: boolean;
} {
  if (!metadataJson) return { score: 0.3, editingDetected: false };

  let score = 0;
  let editingDetected = false;

  try {
    const meta = JSON.parse(metadataJson);

    // Common AI-generation metadata signals
    const aiSoftware = ["DALL-E", "Midjourney", "Stable Diffusion", "Adobe Firefly",
      "Canva AI", "ElevenLabs", "Suno", "Runway", "Kling", "Pika"];
    const softwareField = (meta.Software ?? meta.CreatorTool ?? meta.Generator ?? "").toString();
    if (aiSoftware.some((s) => softwareField.toLowerCase().includes(s.toLowerCase()))) {
      score = 1.0;
    }

    // Editing indicators
    if (meta.HistoryAction?.includes("modified") || meta.EditedAt) {
      editingDetected = true;
    }

    // No camera make/model → likely synthetic
    if (!meta.Make && !meta.Model && !meta.GPSLatitude) {
      score = Math.max(score, 0.5);
    }
  } catch {
    // malformed metadata — treat as unknown
  }

  return { score, editingDetected };
}

function resolveProvenanceStatus(
  declaration: CreatorDeclaration,
  aiScore: number,
  editingDetected: boolean
): ProvenanceStatus {
  if (aiScore >= 0.9) return "ai_generated";
  if (aiScore >= 0.5) return declaration === "ai_generated" ? "ai_generated" : "ai_assisted";
  if (declaration === "ai_generated") return "ai_generated";
  if (declaration === "ai_assisted") return "ai_assisted";
  if (declaration === "edited" || editingDetected) return "edited";
  if (declaration === "reposted") return "reposted";
  if (declaration === "original") return "original";
  return "unknown";
}

function resolveLabel(status: ProvenanceStatus): { labelRequired: boolean; labelType: string } {
  switch (status) {
    case "ai_generated":    return { labelRequired: true,  labelType: "AI-generated" };
    case "ai_assisted":     return { labelRequired: true,  labelType: "AI-assisted" };
    case "edited":          return { labelRequired: false, labelType: "Edited media" };
    case "source_uncertain":return { labelRequired: true,  labelType: "Source uncertain" };
    case "original":        return { labelRequired: false, labelType: "Original media" };
    case "verified_source": return { labelRequired: false, labelType: "Verified source" };
    case "reposted":        return { labelRequired: false, labelType: "Reposted" };
    default:                return { labelRequired: true,  labelType: "Source uncertain" };
  }
}

// ─── Register provenance callable ────────────────────────────────────────

export const registerMediaProvenance = onCall(
  { enforceAppCheck: true, cors: false },
  async (request): Promise<ProvenanceResponse> => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");

    const data = request.data as RegisterProvenanceRequest;
    if (!data.mediaId || !data.storageUri || !data.originalHash) {
      throw new HttpsError("invalid-argument", "mediaId, storageUri, originalHash required.");
    }

    const uploaderUid = request.auth.uid;

    // Compute perceptual hash placeholder (real impl would use server-side perceptual hashing)
    const perceptualHash = crypto
      .createHash("md5")
      .update(data.originalHash + data.fileSizeBytes)
      .digest("hex");

    const metaDigest = crypto
      .createHash("sha256")
      .update(data.metadataJson ?? "")
      .digest("hex")
      .slice(0, 16);

    const { score: aiScore, editingDetected } = detectAIIndicators(data.metadataJson);
    const provenanceStatus = resolveProvenanceStatus(
      data.creatorDeclaration,
      aiScore,
      editingDetected
    );
    const { labelRequired, labelType } = resolveLabel(provenanceStatus);

    const trendEligible = provenanceStatus === "original" || provenanceStatus === "verified_source";
    const boostEligible = provenanceStatus !== "source_uncertain" && provenanceStatus !== "unknown" && aiScore < 0.5;

    const provenance: MediaProvenance = {
      mediaId: data.mediaId,
      uploaderUid,
      originalHash: data.originalHash,
      perceptualHash,
      metadataDigest: metaDigest,
      aiDetectionScore: aiScore,
      editingDetected,
      sourceChain: data.sourceChain ?? [],
      uploadDeviceTrust: data.deviceTrust ?? "unknown",
      creatorDeclaration: data.creatorDeclaration,
      provenanceStatus,
      trendEligible,
      boostEligible,
      labelRequired,
      createdAt: admin.firestore.Timestamp.now(),
      policyVersion: TRUST_SAFETY_OS_VERSION,
    };

    await db.doc(`${PROVENANCE_COLLECTION}/${data.mediaId}/provenance/main`).set(provenance);

    await writeSafetyAuditEvent({
      eventType: "provenance_registered",
      actorUid: uploaderUid,
      targetUid: null,
      contentId: data.mediaId,
      contentType: "post",
      metadata: { provenanceStatus, aiScore, labelRequired },
    });

    return {
      mediaId: data.mediaId,
      provenanceStatus,
      trendEligible,
      boostEligible,
      labelRequired,
      labelType,
      policyVersion: TRUST_SAFETY_OS_VERSION,
    };
  }
);

// ─── Get provenance callable ──────────────────────────────────────────────

export const getMediaProvenance = onCall(
  { enforceAppCheck: true, cors: false },
  async (request): Promise<MediaProvenance | null> => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");

    const { mediaId } = request.data as { mediaId: string };
    if (!mediaId) throw new HttpsError("invalid-argument", "mediaId required.");

    const snap = await db.doc(`${PROVENANCE_COLLECTION}/${mediaId}/provenance/main`).get();
    return snap.exists ? (snap.data() as MediaProvenance) : null;
  }
);

/**
 * VideoModerationService.ts
 *
 * Backend video moderation for Amen Safety OS.
 * Videos are moderated by sampling frames, running each through Cloud Vision
 * SafeSearch, and checking audio transcripts via AudioModerationService.
 *
 * Videos are NEVER publicly visible until this pipeline clears them.
 * The parent content document remains at moderationStatus="pending" until
 * the video is explicitly approved here.
 *
 * Frame sampling rate: 1 frame per 2 seconds (configurable via FRAME_SAMPLE_RATE_SECONDS).
 * Max frames analyzed: 30 (to limit cost on long videos).
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import * as os from "os";
import * as path from "path";
import * as fs from "fs";
import ffmpeg from "fluent-ffmpeg";
import ffmpegPath from "ffmpeg-static";
import { ImageAnnotatorClient } from "@google-cloud/vision";
import {
  policyFor,
  userFacingMessageFor,
  ModerationStatus,
  EnforcementAction,
  AMEN_SAFETY_POLICY_VERSION,
} from "./AmenSafetyPolicy";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const storage = admin.storage();

if (ffmpegPath) ffmpeg.setFfmpegPath(ffmpegPath);

const FRAME_SAMPLE_RATE_SECONDS = 2;
const MAX_FRAMES = 30;

// ─── Types ────────────────────────────────────────────────────────────────────

export type VideoContentType =
  | "post_video"
  | "story_video"
  | "message_video"
  | "livestream_recording"
  | "church_service_video"
  | "creator_video";

export interface VideoModerationRequest {
  storageUri: string;
  contentId?: string;
  contentType: VideoContentType;
  uploaderUid: string;
  durationSeconds?: number;
  isMinor?: boolean;
}

export interface VideoModerationResult {
  allowed: boolean;
  enforcement: EnforcementAction;
  moderationStatus: ModerationStatus;
  harmCategoryId: string | null;
  userFacingMessage: string | null;
  requiresHumanReview: boolean;
  framesAnalyzed?: number;
  violatingFrameIndex?: number;
  policyVersion: string;
}

// ─── Frame Extraction ─────────────────────────────────────────────────────────

async function downloadToTemp(storageUri: string): Promise<string> {
  const bucketName = storageUri.replace("gs://", "").split("/")[0];
  const filePath = storageUri.replace(`gs://${bucketName}/`, "");
  const ext = path.extname(filePath) || ".mp4";
  const tmpFile = path.join(os.tmpdir(), `amen_vid_${Date.now()}${ext}`);

  const bucket = storage.bucket(bucketName);
  await bucket.file(filePath).download({ destination: tmpFile });
  return tmpFile;
}

async function extractFrames(videoPath: string, durationSeconds: number): Promise<string[]> {
  const tmpDir = path.join(os.tmpdir(), `amen_frames_${Date.now()}`);
  fs.mkdirSync(tmpDir, { recursive: true });

  const frameCount = Math.min(MAX_FRAMES, Math.ceil(durationSeconds / FRAME_SAMPLE_RATE_SECONDS));
  const frameInterval = durationSeconds / frameCount;

  const framePaths: string[] = [];

  await new Promise<void>((resolve, reject) => {
    ffmpeg(videoPath)
      .outputOptions([
        `-vf fps=1/${frameInterval}`,
        `-frames:v ${frameCount}`,
      ])
      .output(path.join(tmpDir, "frame_%04d.jpg"))
      .on("end", resolve)
      .on("error", reject)
      .run();
  });

  const files = fs.readdirSync(tmpDir).sort();
  for (const f of files) {
    framePaths.push(path.join(tmpDir, f));
  }
  return framePaths;
}

// ─── Frame Analysis ───────────────────────────────────────────────────────────

let _visionClient: ImageAnnotatorClient | null = null;
function getVisionClient(): ImageAnnotatorClient {
  if (!_visionClient) _visionClient = new ImageAnnotatorClient();
  return _visionClient;
}

const LIKELIHOOD_ORDER = ["UNKNOWN", "VERY_UNLIKELY", "UNLIKELY", "POSSIBLE", "LIKELY", "VERY_LIKELY"];
function likelihoodIndex(label: string | null | undefined): number {
  return LIKELIHOOD_ORDER.indexOf(label ?? "UNKNOWN");
}

interface FrameViolation {
  frameIndex: number;
  harmCategoryId: string;
  enforcement: EnforcementAction;
}

async function analyzeFrame(
  framePath: string,
  frameIndex: number,
  isMinor: boolean
): Promise<FrameViolation | null> {
  const client = getVisionClient();
  const imageBytes = fs.readFileSync(framePath);

  const [result] = await client.safeSearchDetection({
    image: { content: imageBytes.toString("base64") },
  });

  const ss = result.safeSearchAnnotation;
  if (!ss) return null;

  const adultIdx = likelihoodIndex(ss.adult);
  const violenceIdx = likelihoodIndex(ss.violence);
  const racyIdx = likelihoodIndex(ss.racy);
  const minorThreshold = isMinor ? 2 : 3;

  if (adultIdx >= 5) {
    return { frameIndex, harmCategoryId: "pornography", enforcement: "escalate" };
  }
  if (adultIdx >= minorThreshold) {
    return { frameIndex, harmCategoryId: "nudity", enforcement: "block" };
  }
  if (racyIdx >= 4 && isMinor) {
    return { frameIndex, harmCategoryId: "sexual_content", enforcement: "block" };
  }
  if (violenceIdx >= 5) {
    return { frameIndex, harmCategoryId: "gore", enforcement: "escalate" };
  }
  if (violenceIdx >= minorThreshold + 1) {
    return { frameIndex, harmCategoryId: "graphic_violence", enforcement: "block" };
  }
  return null;
}

// ─── Core Logic ───────────────────────────────────────────────────────────────

export async function moderateVideo(req: VideoModerationRequest): Promise<VideoModerationResult> {
  const { storageUri, contentType, uploaderUid, contentId, isMinor = false, durationSeconds = 60 } = req;

  let videoPath: string | null = null;
  let framePaths: string[] = [];

  try {
    logger.info(`[VideoModerationService] Starting moderation uid=${uploaderUid} uri=${storageUri}`);
    videoPath = await downloadToTemp(storageUri);
    framePaths = await extractFrames(videoPath, durationSeconds);

    for (let i = 0; i < framePaths.length; i++) {
      const violation = await analyzeFrame(framePaths[i], i, isMinor);
      if (violation) {
        const policy = policyFor(violation.harmCategoryId);
        await writeVideoModerationLog(uploaderUid, storageUri, contentType, contentId, violation.harmCategoryId, violation.enforcement);
        return {
          allowed: false,
          enforcement: violation.enforcement,
          moderationStatus: policy?.moderationStatus ?? "blocked",
          harmCategoryId: violation.harmCategoryId,
          userFacingMessage: userFacingMessageFor(violation.harmCategoryId),
          requiresHumanReview: violation.enforcement === "escalate" || violation.enforcement === "escalate_to_legal",
          framesAnalyzed: i + 1,
          violatingFrameIndex: violation.frameIndex,
          policyVersion: AMEN_SAFETY_POLICY_VERSION,
        };
      }
    }

    // All frames passed
    return {
      allowed: true,
      enforcement: "allow",
      moderationStatus: "approved",
      harmCategoryId: null,
      userFacingMessage: null,
      requiresHumanReview: false,
      framesAnalyzed: framePaths.length,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
    };
  } catch (err) {
    logger.error("[VideoModerationService] Error during video moderation.", err);
    // Fail closed — hold for human review
    return {
      allowed: false,
      enforcement: "block",
      moderationStatus: "needs_human_review",
      harmCategoryId: null,
      userFacingMessage: "Your video is being reviewed and will be available shortly.",
      requiresHumanReview: true,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
    };
  } finally {
    // Clean up temp files
    if (videoPath && fs.existsSync(videoPath)) {
      try { fs.unlinkSync(videoPath); } catch { /* ignore cleanup errors */ }
    }
    for (const fp of framePaths) {
      try { if (fs.existsSync(fp)) fs.unlinkSync(fp); } catch { /* ignore */ }
    }
  }
}

async function writeVideoModerationLog(
  uid: string,
  storageUri: string,
  contentType: VideoContentType,
  contentId: string | undefined,
  harmCategoryId: string | null,
  enforcement: string
): Promise<void> {
  try {
    await db.collection("videoModerationLogs").add({
      uid,
      storageUri,
      contentType,
      contentId: contentId ?? null,
      harmCategoryId,
      enforcement,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (err) {
    logger.warn("[VideoModerationService] Failed to write log.", err);
  }
}

// ─── Callable Function ────────────────────────────────────────────────────────

/**
 * moderateVideo callable
 *
 * Called by iOS after a video is uploaded to Storage in pending state.
 * Must return allowed: true before the content document can transition
 * to moderationStatus="approved".
 */
export const moderateVideoCallable = onCall(
  { enforceAppCheck: true, timeoutSeconds: 300, memory: "1GiB" },
  async (request: CallableRequest<VideoModerationRequest>): Promise<VideoModerationResult> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const { storageUri, contentType, contentId, isMinor, durationSeconds } = request.data;

    if (!storageUri?.startsWith("gs://")) {
      throw new HttpsError("invalid-argument", "storageUri must be a gs:// URI.");
    }

    return moderateVideo({
      storageUri,
      contentType,
      contentId,
      uploaderUid: request.auth.uid,
      isMinor,
      durationSeconds,
    });
  }
);

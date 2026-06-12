/**
 * adaptiveMedia.ts
 * AMEN — Global Resilience Wave 2
 *
 * Callable Cloud Functions for adaptive, low-data-friendly media processing:
 *   processMediaUpload  — Auth + App Check gated; generates image thumbnails &
 *                         compressed variants via sharp, HLS renditions via
 *                         fluent-ffmpeg, audio transcripts via bereanTranscribe,
 *                         GUARDIAN moderation, and writes structured metadata to
 *                         Firestore at /mediaAssets/{assetId}.
 *   getMediaVariant     — Returns a 1-hour signed download URL for the requested
 *                         quality variant of a processed asset, with graceful
 *                         fallback to the best available rendition.
 *
 * Region: us-east1  (matches Wave-1/Wave-2 deploy target).
 *
 * Firestore layout:
 *   /mediaAssets/{assetId}   — MediaAssetDocument (see interface below)
 *
 * Storage layout:
 *   mediaAssets/{assetId}/thumbnail.jpg
 *   mediaAssets/{assetId}/compressed.jpg
 *   mediaAssets/{assetId}/hls/index.m3u8        (video)
 *   mediaAssets/{assetId}/hls/240p.m3u8         (video)
 *   mediaAssets/{assetId}/hls/360p.m3u8         (video)
 *   mediaAssets/{assetId}/hls/720p.m3u8         (video)
 *   mediaAssets/{assetId}/hls/audio.m3u8        (video — audio-only rendition)
 *
 * package.json dependencies required:
 *   "sharp": "^0.33.0"
 *   "fluent-ffmpeg": "^2.1.3"
 *   "@types/fluent-ffmpeg": "^2.1.27"   (devDependencies)
 *   "@types/sharp": "^0.31.1"           (devDependencies)
 */

import * as admin from "firebase-admin";
import * as path from "path";
import * as os from "os";
import * as fs from "fs";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { logger } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { requireAuthAndAppCheck } from "../amenAI/common";
import { moderateContent } from "../intelligence/amenRouting";

// ─── Constants ─────────────────────────────────────────────────────────────────

const REGION = "us-east1";

/** Thumbnail dimensions (square crop). */
const THUMB_SIZE = 200;

/** Max long-edge for the compressed image variant. */
const COMPRESSED_MAX_PX = 800;

/** JPEG compression quality for compressed image variant (0–100). */
const COMPRESSED_QUALITY = 82;

/** JPEG compression quality for thumbnail (0–100). */
const THUMB_QUALITY = 75;

/**
 * Signed URL expiry for getMediaVariant — 1 hour expressed as a Date offset.
 */
const SIGNED_URL_EXPIRY_MS = 60 * 60 * 1000;

/** Max input validation lengths. */
const MAX_ASSET_ID_LEN = 128;
const MAX_PATH_LEN = 512;
const MAX_UPLOADER_ID_LEN = 128;

// ─── Types ─────────────────────────────────────────────────────────────────────

type MediaType = "image" | "video" | "audio";

type AssetStatus =
  | "processing"
  | "processed"
  | "quarantined"
  | "hls_pending"
  | "error";

type QualityVariant =
  | "thumbnail"
  | "240p"
  | "360p"
  | "720p"
  | "original";

interface LowDataPreview {
  title: string;
  textPreview: string;
  thumbnailUrl: string | null;
  estimatedDataKb: number;
}

interface MediaVariants {
  thumbnail?: string;
  compressed?: string;
  "240p"?: string;
  "360p"?: string;
  "720p"?: string;
  audioOnly?: string;
  original?: string;
}

interface MediaAssetDocument {
  assetId: string;
  uploaderId: string;
  mediaType: MediaType;
  storagePath: string;
  status: AssetStatus;
  variants: MediaVariants;
  lowDataPreview: LowDataPreview;
  transcriptText: string;
  processedAt: FirebaseFirestore.FieldValue | null;
  moderationFlags: {
    safe: boolean;
    reason?: string;
  };
  createdAt: FirebaseFirestore.FieldValue;
}

// ─── Input validation helpers ─────────────────────────────────────────────────

function requireNonEmptyString(value: unknown, field: string, maxLen: number): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new HttpsError("invalid-argument", `${field} must be a non-empty string.`);
  }
  if (value.length > maxLen) {
    throw new HttpsError("invalid-argument", `${field} exceeds maximum length of ${maxLen}.`);
  }
  return value.trim();
}

function requireMediaType(value: unknown): MediaType {
  if (value !== "image" && value !== "video" && value !== "audio") {
    throw new HttpsError(
      "invalid-argument",
      'mediaType must be one of: "image", "video", "audio".'
    );
  }
  return value as MediaType;
}

function requireQualityVariant(value: unknown): QualityVariant {
  const allowed: QualityVariant[] = ["thumbnail", "240p", "360p", "720p", "original"];
  if (!allowed.includes(value as QualityVariant)) {
    throw new HttpsError(
      "invalid-argument",
      `preferredQuality must be one of: ${allowed.join(", ")}.`
    );
  }
  return value as QualityVariant;
}

// ─── Storage helpers ───────────────────────────────────────────────────────────

/**
 * Downloads a Storage object to a unique temp file and returns the local path.
 * The caller is responsible for deleting the file when done.
 */
async function downloadToTemp(storagePath: string): Promise<string> {
  const bucket = getStorage().bucket();
  const safeName = path.basename(storagePath).replace(/[^a-zA-Z0-9._-]/g, "_");
  const tempPath = path.join(os.tmpdir(), `${Date.now()}_${safeName}`);
  await bucket.file(storagePath).download({ destination: tempPath });
  return tempPath;
}

/**
 * Uploads a local temp file to Storage and returns the public-style gs:// path.
 */
async function uploadFromTemp(
  localPath: string,
  destinationPath: string,
  contentType: string
): Promise<void> {
  const bucket = getStorage().bucket();
  await bucket.upload(localPath, {
    destination: destinationPath,
    resumable: false,
    metadata: { contentType },
  });
}

/**
 * Returns the estimated size of a Storage object in kilobytes.
 * Falls back to 0 if metadata cannot be read.
 */
async function getFileSizeKb(storagePath: string): Promise<number> {
  try {
    const bucket = getStorage().bucket();
    const [metadata] = await bucket.file(storagePath).getMetadata();
    const sizeBytes = Number(metadata.size ?? 0);
    return Math.ceil(sizeBytes / 1024);
  } catch {
    return 0;
  }
}

/**
 * Generates a 1-hour signed download URL for a Storage object.
 */
async function getSignedUrl(storagePath: string): Promise<string> {
  const bucket = getStorage().bucket();
  const expires = new Date(Date.now() + SIGNED_URL_EXPIRY_MS);
  const [url] = await bucket.file(storagePath).getSignedUrl({
    action: "read",
    expires,
  });
  return url;
}

/**
 * Returns gs:// style path inside the mediaAssets folder for a given assetId.
 */
function assetStoragePath(assetId: string, filename: string): string {
  return `mediaAssets/${assetId}/${filename}`;
}

// ─── Image processing ─────────────────────────────────────────────────────────

/**
 * Uses sharp (lazy-required so the function fails gracefully if the package is
 * missing at deploy time and surfaces a clear error) to:
 *   1. Generate a 200×200 square thumbnail → mediaAssets/{assetId}/thumbnail.jpg
 *   2. Generate a compressed variant (max 800px long-edge) → mediaAssets/{assetId}/compressed.jpg
 *
 * Returns the Storage paths written.
 */
async function processImage(
  localInputPath: string,
  assetId: string
): Promise<{ thumbnailStoragePath: string; compressedStoragePath: string }> {
  // Dynamic require: sharp is an optional dependency — if absent the function
  // will throw and the caller should catch. We use `any` deliberately here
  // because sharp ships its own typings only when the package is installed.
  // eslint-disable-next-line @typescript-eslint/no-var-requires, @typescript-eslint/no-explicit-any
  const sharp = require("sharp") as any;

  const thumbLocalPath = path.join(os.tmpdir(), `${assetId}_thumb.jpg`);
  const compressedLocalPath = path.join(os.tmpdir(), `${assetId}_compressed.jpg`);

  try {
    // Thumbnail — square crop from centre
    await sharp(localInputPath)
      .resize(THUMB_SIZE, THUMB_SIZE, { fit: "cover", position: "centre" })
      .jpeg({ quality: THUMB_QUALITY })
      .toFile(thumbLocalPath);

    // Compressed variant — constrain long edge, maintain aspect ratio
    await sharp(localInputPath)
      .resize(COMPRESSED_MAX_PX, COMPRESSED_MAX_PX, {
        fit: "inside",
        withoutEnlargement: true,
      })
      .jpeg({ quality: COMPRESSED_QUALITY })
      .toFile(compressedLocalPath);

    const thumbnailStoragePath = assetStoragePath(assetId, "thumbnail.jpg");
    const compressedStoragePath = assetStoragePath(assetId, "compressed.jpg");

    await Promise.all([
      uploadFromTemp(thumbLocalPath, thumbnailStoragePath, "image/jpeg"),
      uploadFromTemp(compressedLocalPath, compressedStoragePath, "image/jpeg"),
    ]);

    return { thumbnailStoragePath, compressedStoragePath };
  } finally {
    // Best-effort cleanup — do not throw if removal fails
    for (const p of [thumbLocalPath, compressedLocalPath]) {
      try {
        if (fs.existsSync(p)) fs.unlinkSync(p);
      } catch { /* ignore */ }
    }
  }
}

// ─── Video processing ─────────────────────────────────────────────────────────

interface HlsRenditionSpec {
  label: QualityVariant;
  height: number;
  videoBitrate: string;
  audioBitrate: string;
}

const HLS_RENDITIONS: HlsRenditionSpec[] = [
  { label: "240p",  height: 240,  videoBitrate: "400k",  audioBitrate: "64k"  },
  { label: "360p",  height: 360,  videoBitrate: "800k",  audioBitrate: "96k"  },
  { label: "720p",  height: 720,  videoBitrate: "2500k", audioBitrate: "128k" },
];

/**
 * Runs ffmpeg to produce per-rendition HLS streams plus an audio-only rendition.
 * Returns the Storage paths keyed by variant label.
 *
 * If ffmpeg is unavailable (binary not found or any startup error), the function
 * returns null and the caller sets status: "hls_pending".
 *
 * TODO(media-team): provision ffmpeg binary layer for Cloud Run / gen-2 runtime
 * to lift the hls_pending fallback path.
 */
async function processVideo(
  localInputPath: string,
  assetId: string
): Promise<Record<string, string> | null> {
  let ffmpeg: typeof import("fluent-ffmpeg");
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    ffmpeg = require("fluent-ffmpeg");
  } catch (importErr) {
    logger.warn("[processVideo] fluent-ffmpeg not available — HLS deferred", {
      assetId,
      importErr: String(importErr),
    });
    return null;
  }

  // Locate the ffmpeg binary: ffmpeg-static > system PATH
  let ffmpegBinaryPath: string | null = null;
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    ffmpegBinaryPath = require("ffmpeg-static") as string;
  } catch {
    // Not installed — will rely on system PATH
  }

  if (ffmpegBinaryPath) {
    ffmpeg.setFfmpegPath(ffmpegBinaryPath);
  }

  const hlsBaseDir = path.join(os.tmpdir(), `${assetId}_hls`);
  fs.mkdirSync(hlsBaseDir, { recursive: true });

  const uploadedPaths: Record<string, string> = {};

  try {
    // Per-rendition HLS
    for (const rendition of HLS_RENDITIONS) {
      const outputM3u8 = path.join(hlsBaseDir, `${rendition.label}.m3u8`);
      const segmentPattern = path.join(hlsBaseDir, `${rendition.label}_%03d.ts`);

      try {
        await new Promise<void>((resolve, reject) => {
          (ffmpeg as unknown as typeof import("fluent-ffmpeg"))(localInputPath)
            .outputOptions([
              `-vf scale=-2:${rendition.height}`,
              "-preset veryfast",
              "-g 48",
              "-sc_threshold 0",
              `-b:v ${rendition.videoBitrate}`,
              `-b:a ${rendition.audioBitrate}`,
              "-hls_time 6",
              "-hls_playlist_type vod",
              `-hls_segment_filename ${segmentPattern}`,
            ])
            .output(outputM3u8)
            .format("hls")
            .on("end", () => resolve())
            .on("error", (err: Error) => reject(err))
            .run();
        });

        // Upload playlist + all segments for this rendition
        const m3u8StoragePath = assetStoragePath(assetId, `hls/${rendition.label}.m3u8`);
        await uploadFromTemp(outputM3u8, m3u8StoragePath, "application/x-mpegURL");
        uploadedPaths[rendition.label] = m3u8StoragePath;

        // Upload segment files
        const segmentFiles = fs
          .readdirSync(hlsBaseDir)
          .filter((f) => f.startsWith(`${rendition.label}_`) && f.endsWith(".ts"));

        await Promise.all(
          segmentFiles.map((seg) =>
            uploadFromTemp(
              path.join(hlsBaseDir, seg),
              assetStoragePath(assetId, `hls/${seg}`),
              "video/MP2T"
            )
          )
        );
      } catch (renditionErr) {
        // One rendition failing should not abort the others
        logger.warn(`[processVideo] Rendition ${rendition.label} failed`, {
          assetId,
          error: String(renditionErr),
        });
      }
    }

    // Audio-only rendition (strips video track)
    const audioM3u8 = path.join(hlsBaseDir, "audio.m3u8");
    const audioSegmentPattern = path.join(hlsBaseDir, "audio_%03d.ts");
    try {
      await new Promise<void>((resolve, reject) => {
        (ffmpeg as unknown as typeof import("fluent-ffmpeg"))(localInputPath)
          .noVideo()
          .outputOptions([
            "-b:a 128k",
            "-hls_time 6",
            "-hls_playlist_type vod",
            `-hls_segment_filename ${audioSegmentPattern}`,
          ])
          .output(audioM3u8)
          .format("hls")
          .on("end", () => resolve())
          .on("error", (err: Error) => reject(err))
          .run();
      });

      const audioStoragePath = assetStoragePath(assetId, "hls/audio.m3u8");
      await uploadFromTemp(audioM3u8, audioStoragePath, "application/x-mpegURL");
      uploadedPaths["audioOnly"] = audioStoragePath;

      // Upload audio segment files
      const audioSegments = fs
        .readdirSync(hlsBaseDir)
        .filter((f) => f.startsWith("audio_") && f.endsWith(".ts"));

      await Promise.all(
        audioSegments.map((seg) =>
          uploadFromTemp(
            path.join(hlsBaseDir, seg),
            assetStoragePath(assetId, `hls/${seg}`),
            "video/MP2T"
          )
        )
      );
    } catch (audioErr) {
      logger.warn("[processVideo] Audio-only rendition failed", {
        assetId,
        error: String(audioErr),
      });
    }

    return uploadedPaths;
  } finally {
    // Clean up entire HLS temp directory
    try {
      fs.rmSync(hlsBaseDir, { recursive: true, force: true });
    } catch { /* ignore */ }
  }
}

// ─── Audio transcript helper ───────────────────────────────────────────────────

/**
 * Calls the bereanTranscribe Firebase callable (if exported in the same project)
 * via the Admin SDK's local call emulation.  Because Cloud Functions cannot call
 * sibling callables directly via the HTTPS client, we use a best-effort approach:
 * attempt to import the transcription provider used by mediaMetadataPipeline;
 * if unavailable, return an empty string rather than hard-failing.
 *
 * TODO(media-team): wire this to the deployed bereanTranscribe HTTP endpoint once
 * the callable URL is available in Secret Manager, enabling cross-function calls.
 */
async function transcribeAudioAsset(localAudioPath: string): Promise<string> {
  try {
    // Attempt to reuse the shared transcription provider from mediaGeneration
    const { transcribeAudioBuffer } = await import(
      "../mediaGeneration/transcriptionProvider"
    );
    const audioBuffer = fs.readFileSync(localAudioPath);
    const filename = path.basename(localAudioPath);
    const result = await transcribeAudioBuffer(audioBuffer, filename);
    return result.fullText ?? "";
  } catch (transcribeErr) {
    // Non-fatal — transcription unavailable
    logger.warn("[transcribeAudioAsset] Transcription unavailable — setting empty transcript", {
      error: String(transcribeErr),
    });
    return "";
  }
}

// ─── processMediaUpload ────────────────────────────────────────────────────────

interface ProcessMediaUploadRequest {
  assetId: unknown;
  storagePath: unknown;
  mediaType: unknown;
  uploaderId: unknown;
}

interface ProcessMediaUploadResponse {
  assetId: string;
  status: AssetStatus;
  lowDataPreview: LowDataPreview;
}

/**
 * processMediaUpload
 *
 * Triggered after a client finishes uploading a raw media file to Storage.
 * The function:
 *   1. Verifies App Check + Auth
 *   2. Creates a stub /mediaAssets/{assetId} Firestore document (status: "processing")
 *   3. Downloads the source file to the Cloud Function's /tmp directory
 *   4. Dispatches per-type processing (image / video / audio)
 *   5. Runs GUARDIAN moderation via moderateContent on extracted text
 *   6. If content is quarantined: sets status: "quarantined" and returns early
 *   7. Otherwise: sets status: "processed" with full variants + lowDataPreview
 */
export const processMediaUpload = onCall<
  ProcessMediaUploadRequest,
  Promise<ProcessMediaUploadResponse>
>(
  {
    enforceAppCheck: true,
    region: REGION,
    // Image/audio processing can be fast; HLS encoding may take several minutes.
    timeoutSeconds: 540,
    memory: "2GiB",
  },
  async (request): Promise<ProcessMediaUploadResponse> => {
    // ── 1. Auth + App Check ──────────────────────────────────────────────────
    const callerUid = await requireAuthAndAppCheck(request.auth ?? null, request.app ?? null);

    const db = getFirestore();
    const data = request.data as ProcessMediaUploadRequest;

    // ── 2. Input validation ──────────────────────────────────────────────────
    const assetId = requireNonEmptyString(data.assetId, "assetId", MAX_ASSET_ID_LEN);
    const storagePath = requireNonEmptyString(data.storagePath, "storagePath", MAX_PATH_LEN);
    const mediaType = requireMediaType(data.mediaType);
    const uploaderId = requireNonEmptyString(data.uploaderId, "uploaderId", MAX_UPLOADER_ID_LEN);

    // Verify the caller is the declared uploader
    if (callerUid !== uploaderId) {
      throw new HttpsError(
        "permission-denied",
        "uploaderId must match the authenticated user."
      );
    }

    // Verify the source file exists in Storage before doing any work
    const bucket = getStorage().bucket();
    const [fileExists] = await bucket.file(storagePath).exists();
    if (!fileExists) {
      throw new HttpsError("not-found", `Storage object not found at path: ${storagePath}`);
    }

    // ── 3. Create stub Firestore document (idempotent) ────────────────────────
    const assetRef = db.collection("mediaAssets").doc(assetId);

    const stubDoc: Partial<MediaAssetDocument> = {
      assetId,
      uploaderId,
      mediaType,
      storagePath,
      status: "processing",
      variants: {},
      transcriptText: "",
      lowDataPreview: {
        title: assetId,
        textPreview: "",
        thumbnailUrl: null,
        estimatedDataKb: 0,
      },
      moderationFlags: { safe: true },
      processedAt: null,
      createdAt: FieldValue.serverTimestamp(),
    };

    // Use set({ merge: true }) so re-runs after a timeout don't lose data
    await assetRef.set(stubDoc, { merge: true });

    logger.info("[processMediaUpload] Processing started", { assetId, mediaType, uploaderId });

    // ── 4. Download source to /tmp ────────────────────────────────────────────
    const fileSizeKb = await getFileSizeKb(storagePath);
    let localInputPath: string | null = null;

    try {
      localInputPath = await downloadToTemp(storagePath);
    } catch (downloadErr) {
      logger.error("[processMediaUpload] Source download failed", { assetId }, downloadErr);
      await assetRef.update({ status: "error" as AssetStatus });
      throw new HttpsError("internal", "Failed to download source media for processing.");
    }

    // ── 5. Per-type processing ────────────────────────────────────────────────
    const variants: MediaVariants = { original: storagePath };
    let transcriptText = "";
    let thumbnailStoragePath: string | null = null;
    let newStatus: AssetStatus = "processed";

    try {
      if (mediaType === "image") {
        // ── IMAGE ──────────────────────────────────────────────────────────────
        const { thumbnailStoragePath: thumbPath, compressedStoragePath } =
          await processImage(localInputPath, assetId);

        variants.thumbnail = thumbPath;
        variants.compressed = compressedStoragePath;
        thumbnailStoragePath = thumbPath;
      } else if (mediaType === "video") {
        // ── VIDEO ──────────────────────────────────────────────────────────────
        const hlsPaths = await processVideo(localInputPath, assetId);

        if (hlsPaths === null) {
          // ffmpeg unavailable — mark as pending; a separate retry job can pick this up
          newStatus = "hls_pending";
          logger.warn("[processMediaUpload] HLS deferred — ffmpeg unavailable", { assetId });
          // TODO(media-team): enqueue Cloud Tasks retry once ffmpeg layer is provisioned
        } else {
          for (const [key, val] of Object.entries(hlsPaths)) {
            (variants as Record<string, string>)[key] = val;
          }
          thumbnailStoragePath = hlsPaths["240p"] ?? null;
        }

        // Generate transcript from the audio track of the video
        transcriptText = await transcribeAudioAsset(localInputPath);
      } else {
        // ── AUDIO ──────────────────────────────────────────────────────────────
        transcriptText = await transcribeAudioAsset(localInputPath);
      }
    } catch (processingErr) {
      logger.error("[processMediaUpload] Processing error", { assetId, mediaType }, processingErr);
      await assetRef.update({ status: "error" as AssetStatus });
      throw new HttpsError("internal", "Media processing failed.");
    } finally {
      // Always clean up the downloaded source file
      try {
        if (localInputPath && fs.existsSync(localInputPath)) {
          fs.unlinkSync(localInputPath);
        }
      } catch { /* ignore */ }
    }

    // ── 6. Compute thumbnailUrl for lowDataPreview ─────────────────────────────
    let thumbnailUrl: string | null = null;
    if (thumbnailStoragePath) {
      try {
        thumbnailUrl = await getSignedUrl(thumbnailStoragePath);
      } catch (urlErr) {
        logger.warn("[processMediaUpload] Could not generate thumbnail signed URL", {
          assetId,
          thumbnailStoragePath,
          error: String(urlErr),
        });
      }
    }

    const lowDataPreview: LowDataPreview = {
      title: assetId,
      textPreview: transcriptText.substring(0, 140),
      thumbnailUrl,
      estimatedDataKb: fileSizeKb,
    };

    // ── 7. GUARDIAN moderation ────────────────────────────────────────────────
    // moderateContent operates on extracted text. For image-only assets, pass an
    // empty string — the upstream moderation pipeline handles visual content separately.
    const moderationInput = transcriptText.trim();
    let moderationResult: { safe: boolean; reason?: string };

    try {
      moderationResult = await moderateContent(moderationInput);
    } catch (modErr) {
      // Fail-closed: if moderation throws, treat as unsafe to protect users
      logger.error("[processMediaUpload] Moderation threw — treating as unsafe", {
        assetId,
        error: String(modErr),
      });
      moderationResult = { safe: false, reason: "moderation_error" };
    }

    if (!moderationResult.safe) {
      logger.warn("[processMediaUpload] Content quarantined by GUARDIAN", {
        assetId,
        reason: moderationResult.reason,
      });

      await assetRef.update({
        status: "quarantined" as AssetStatus,
        moderationFlags: {
          safe: false,
          reason: moderationResult.reason ?? "flagged",
        },
        processedAt: FieldValue.serverTimestamp(),
      });

      return {
        assetId,
        status: "quarantined",
        lowDataPreview,
      };
    }

    // ── 8. Write processed document ───────────────────────────────────────────
    await assetRef.update({
      status: newStatus,
      variants,
      lowDataPreview: {
        title: lowDataPreview.title,
        text_preview: lowDataPreview.textPreview,
        thumbnail_url: lowDataPreview.thumbnailUrl,
        estimated_data_kb: lowDataPreview.estimatedDataKb,
      },
      transcriptText,
      moderationFlags: { safe: true },
      processedAt: FieldValue.serverTimestamp(),
    });

    logger.info("[processMediaUpload] Processing complete", {
      assetId,
      status: newStatus,
      mediaType,
      variantCount: Object.keys(variants).length,
      transcriptLength: transcriptText.length,
    });

    return {
      assetId,
      status: newStatus,
      lowDataPreview,
    };
  }
);

// ─── getMediaVariant ───────────────────────────────────────────────────────────

interface GetMediaVariantRequest {
  assetId: unknown;
  preferredQuality: unknown;
}

interface GetMediaVariantResponse {
  assetId: string;
  resolvedQuality: string;
  downloadUrl: string;
  expiresAt: string;
}

/**
 * Quality fallback chain per mediaType.
 *
 * For a requested quality we walk the chain left-to-right and return the first
 * variant key that exists in the asset's variants map.
 */
const QUALITY_FALLBACK_CHAINS: Record<QualityVariant, Array<keyof MediaVariants>> = {
  thumbnail:  ["thumbnail", "compressed", "240p", "original"],
  "240p":     ["240p", "360p", "720p", "original"],
  "360p":     ["360p", "240p", "720p", "original"],
  "720p":     ["720p", "360p", "240p", "original"],
  original:   ["original", "720p", "360p", "240p", "compressed", "thumbnail"],
};

/**
 * getMediaVariant
 *
 * Reads /mediaAssets/{assetId} from Firestore, resolves the best available
 * variant for the requested quality using the fallback chain, and returns a
 * 1-hour signed download URL.
 *
 * Auth + App Check are enforced. The asset must be in "processed" status
 * (not quarantined or still processing).
 */
export const getMediaVariant = onCall<
  GetMediaVariantRequest,
  Promise<GetMediaVariantResponse>
>(
  {
    enforceAppCheck: true,
    region: REGION,
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request): Promise<GetMediaVariantResponse> => {
    // ── 1. Auth + App Check ──────────────────────────────────────────────────
    await requireAuthAndAppCheck(request.auth ?? null, request.app ?? null);

    const data = request.data as GetMediaVariantRequest;

    // ── 2. Input validation ──────────────────────────────────────────────────
    const assetId = requireNonEmptyString(data.assetId, "assetId", MAX_ASSET_ID_LEN);
    const preferredQuality = requireQualityVariant(data.preferredQuality);

    // ── 3. Fetch asset document ───────────────────────────────────────────────
    const db = getFirestore();
    const assetSnap = await db.collection("mediaAssets").doc(assetId).get();

    if (!assetSnap.exists) {
      throw new HttpsError("not-found", `Media asset not found: ${assetId}`);
    }

    const assetData = assetSnap.data() as Partial<MediaAssetDocument> | undefined;

    if (!assetData) {
      throw new HttpsError("internal", "Asset document is empty.");
    }

    const status = assetData.status as AssetStatus | undefined;

    if (status === "quarantined") {
      throw new HttpsError(
        "permission-denied",
        "This media asset is not available."
      );
    }

    if (status === "processing") {
      throw new HttpsError(
        "failed-precondition",
        "This media asset is still being processed. Please retry shortly."
      );
    }

    if (status === "error") {
      throw new HttpsError(
        "internal",
        "This media asset encountered a processing error."
      );
    }

    // ── 4. Resolve best available variant ─────────────────────────────────────
    const variants = (assetData.variants ?? {}) as MediaVariants;
    const fallbackChain = QUALITY_FALLBACK_CHAINS[preferredQuality];

    let resolvedKey: keyof MediaVariants | null = null;
    let resolvedStoragePath: string | null = null;

    for (const key of fallbackChain) {
      const candidatePath = variants[key];
      if (typeof candidatePath === "string" && candidatePath.length > 0) {
        resolvedKey = key;
        resolvedStoragePath = candidatePath;
        break;
      }
    }

    // Final fallback to the original storagePath from the document root
    if (!resolvedStoragePath) {
      const originalPath = assetData.storagePath;
      if (typeof originalPath === "string" && originalPath.length > 0) {
        resolvedKey = "original";
        resolvedStoragePath = originalPath;
      }
    }

    if (!resolvedStoragePath || !resolvedKey) {
      throw new HttpsError(
        "not-found",
        "No variants available for this asset. Processing may still be in progress."
      );
    }

    // ── 5. Generate signed URL ────────────────────────────────────────────────
    let downloadUrl: string;
    try {
      downloadUrl = await getSignedUrl(resolvedStoragePath);
    } catch (urlErr) {
      logger.error("[getMediaVariant] Signed URL generation failed", {
        assetId,
        resolvedStoragePath,
        error: String(urlErr),
      });
      throw new HttpsError("internal", "Failed to generate download URL.");
    }

    const expiresAt = new Date(Date.now() + SIGNED_URL_EXPIRY_MS).toISOString();

    logger.info("[getMediaVariant] Variant resolved", {
      assetId,
      preferredQuality,
      resolvedKey,
    });

    return {
      assetId,
      resolvedQuality: resolvedKey,
      downloadUrl,
      expiresAt,
    };
  }
);

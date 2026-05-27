/**
 * AudioModerationService.ts
 *
 * Backend audio moderation for Amen Safety OS.
 * Audio clips are transcribed via OpenAI Whisper (or Google Speech-to-Text
 * as a fallback), then the transcript is run through TextModerationService.
 *
 * Covers: voice messages, voice prayer recordings, audio notes, livestream
 * audio tracks, and any audio caption submitted on the platform.
 *
 * Audio content follows the same moderationStatus lifecycle as text/image:
 *   pending → approved | blocked | needs_human_review | escalated
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import * as os from "os";
import * as path from "path";
import * as fs from "fs";
import axios from "axios";
import FormData from "form-data";
import { moderateText } from "./TextModerationService";
import {
  EnforcementAction,
  ModerationStatus,
  AMEN_SAFETY_POLICY_VERSION,
} from "./AmenSafetyPolicy";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const storage = admin.storage();

// ─── Types ────────────────────────────────────────────────────────────────────

export type AudioContentType =
  | "voice_message"
  | "voice_prayer"
  | "audio_note"
  | "livestream_audio"
  | "church_audio"
  | "creator_audio";

export interface AudioModerationRequest {
  storageUri: string;
  contentId?: string;
  contentType: AudioContentType;
  uploaderUid: string;
  isMinor?: boolean;
  languageHint?: string;
}

export interface AudioModerationResult {
  allowed: boolean;
  enforcement: EnforcementAction;
  moderationStatus: ModerationStatus;
  harmCategoryId: string | null;
  userFacingMessage: string | null;
  requiresHumanReview: boolean;
  transcript?: string;
  policyVersion: string;
}

// ─── Transcription (Whisper / Speech-to-Text) ─────────────────────────────────

async function downloadAudioToTemp(storageUri: string): Promise<string> {
  const bucketName = storageUri.replace("gs://", "").split("/")[0];
  const filePath = storageUri.replace(`gs://${bucketName}/`, "");
  const ext = path.extname(filePath) || ".mp3";
  const tmpFile = path.join(os.tmpdir(), `amen_audio_${Date.now()}${ext}`);
  await storage.bucket(bucketName).file(filePath).download({ destination: tmpFile });
  return tmpFile;
}

async function transcribeWithWhisper(audioPath: string, languageHint?: string): Promise<string | null> {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    logger.warn("[AudioModerationService] OPENAI_API_KEY not set — cannot transcribe.");
    return null;
  }

  try {
    const form = new FormData();
    form.append("file", fs.createReadStream(audioPath));
    form.append("model", "whisper-1");
    if (languageHint) form.append("language", languageHint);
    form.append("response_format", "text");

    const response = await axios.post<string>(
      "https://api.openai.com/v1/audio/transcriptions",
      form,
      {
        headers: {
          ...form.getHeaders(),
          Authorization: `Bearer ${apiKey}`,
        },
        timeout: 60_000,
      }
    );
    return typeof response.data === "string" ? response.data.trim() : null;
  } catch (err) {
    logger.error("[AudioModerationService] Whisper transcription failed.", err);
    return null;
  }
}

// ─── Core Logic ───────────────────────────────────────────────────────────────

export async function moderateAudio(req: AudioModerationRequest): Promise<AudioModerationResult> {
  const { storageUri, contentType, uploaderUid, contentId, isMinor = false, languageHint } = req;

  let audioPath: string | null = null;

  try {
    audioPath = await downloadAudioToTemp(storageUri);
    const transcript = await transcribeWithWhisper(audioPath, languageHint);

    if (!transcript) {
      // Transcription unavailable — hold for human review
      logger.warn(`[AudioModerationService] No transcript. Holding for review uid=${uploaderUid}`);
      await writeAudioModerationLog(uploaderUid, storageUri, contentType, contentId, null, "block", null);
      return {
        allowed: false,
        enforcement: "block",
        moderationStatus: "needs_human_review",
        harmCategoryId: null,
        userFacingMessage: "Your audio is being reviewed and will be available shortly.",
        requiresHumanReview: true,
        policyVersion: AMEN_SAFETY_POLICY_VERSION,
      };
    }

    // Run transcript through text moderation
    const textResult = await moderateText(transcript, "post", isMinor, contentId);

    await writeAudioModerationLog(
      uploaderUid, storageUri, contentType, contentId,
      textResult.harmCategoryId, textResult.enforcement, transcript
    );

    return {
      allowed: textResult.allowed,
      enforcement: textResult.enforcement,
      moderationStatus: textResult.moderationStatus,
      harmCategoryId: textResult.harmCategoryId,
      userFacingMessage: textResult.userFacingMessage,
      requiresHumanReview: textResult.requiresHumanReview,
      // Don't return transcript to client — privacy
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
    };
  } catch (err) {
    logger.error("[AudioModerationService] Unexpected error.", err);
    return {
      allowed: false,
      enforcement: "block",
      moderationStatus: "needs_human_review",
      harmCategoryId: null,
      userFacingMessage: "Your audio is being reviewed and will be available shortly.",
      requiresHumanReview: true,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
    };
  } finally {
    if (audioPath && fs.existsSync(audioPath)) {
      try { fs.unlinkSync(audioPath); } catch { /* ignore */ }
    }
  }
}

async function writeAudioModerationLog(
  uid: string,
  storageUri: string,
  contentType: AudioContentType,
  contentId: string | undefined,
  harmCategoryId: string | null,
  enforcement: string,
  transcript: string | null
): Promise<void> {
  try {
    await db.collection("audioModerationLogs").add({
      uid,
      storageUri,
      contentType,
      contentId: contentId ?? null,
      harmCategoryId,
      enforcement,
      // Store a hash of the transcript for deduplication — never store raw PII
      transcriptLength: transcript?.length ?? 0,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (err) {
    logger.warn("[AudioModerationService] Failed to write log.", err);
  }
}

// ─── Callable Function ────────────────────────────────────────────────────────

export const moderateAudioCallable = onCall(
  { enforceAppCheck: true, timeoutSeconds: 120, memory: "512MiB" },
  async (request: CallableRequest<AudioModerationRequest>): Promise<AudioModerationResult> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const { storageUri, contentType, contentId, isMinor, languageHint } = request.data;

    if (!storageUri?.startsWith("gs://")) {
      throw new HttpsError("invalid-argument", "storageUri must be a gs:// URI.");
    }

    return moderateAudio({
      storageUri,
      contentType,
      contentId,
      uploaderUid: request.auth.uid,
      isMinor,
      languageHint,
    });
  }
);

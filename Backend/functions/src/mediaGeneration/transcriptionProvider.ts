/**
 * transcriptionProvider.ts
 *
 * OpenAI Whisper adapter for post-upload video/audio transcription.
 * Returns timed caption cue segments suitable for the AMEN caption model.
 *
 * Provider: OpenAI Whisper-1 (verbose_json response format)
 * Required secret: OPENAI_API_KEY
 *   firebase functions:secrets:set OPENAI_API_KEY
 *
 * Integration point:
 *   Called by mediaMetadataPipeline.ts after a video post is created.
 *   The pipeline checks userEditedMetadata before applying results.
 *
 * Degraded mode:
 *   If OPENAI_API_KEY is not set, transcribeVideoFile() throws
 *   TranscriptionProviderError with code "provider_not_configured".
 *   The pipeline catches this and marks captionsGenerationState = "failed"
 *   without failing the post.
 */

import {defineSecret} from "firebase-functions/params";
import FormData from "form-data";

export const openaiApiKey = defineSecret("OPENAI_API_KEY");

// ─── Types ───────────────────────────────────────────────────────────────────

export interface TranscriptionCue {
    cueId: string;
    startTime: number; // seconds
    endTime: number;   // seconds
    text: string;
}

export interface TranscriptionResult {
    languageCode: string;
    fullText: string;
    cues: TranscriptionCue[];
    durationSeconds: number;
}

export class TranscriptionProviderError extends Error {
    constructor(
        message: string,
        public readonly code:
            | "provider_not_configured"
            | "file_not_found"
            | "provider_error"
            | "unsupported_format"
    ) {
        super(message);
        this.name = "TranscriptionProviderError";
    }
}

// Whisper verbose_json segment shape
interface WhisperSegment {
    id: number;
    start: number;
    end: number;
    text: string;
}

interface WhisperVerboseResponse {
    text: string;
    language: string;
    duration: number;
    segments: WhisperSegment[];
}

// ─── Provider Adapter ────────────────────────────────────────────────────────

/**
 * Transcribes an audio/video file from Firebase Storage using OpenAI Whisper.
 *
 * @param audioBuffer  Raw file bytes (m4a / mp4 / wav)
 * @param mimeType     MIME type hint (e.g. "audio/m4a", "video/mp4")
 * @param language     ISO 639-1 language hint (default "en")
 * @param contextPrompt  Optional domain prompt to improve accuracy
 * @returns            Normalised TranscriptionResult
 */
export async function transcribeAudioBuffer(
    audioBuffer: Buffer,
    mimeType: string = "audio/m4a",
    language: string = "en",
    contextPrompt?: string
): Promise<TranscriptionResult> {
    const apiKey = openaiApiKey.value();
    if (!apiKey) {
        throw new TranscriptionProviderError(
            "OPENAI_API_KEY secret is not configured. " +
            "Run: firebase functions:secrets:set OPENAI_API_KEY",
            "provider_not_configured"
        );
    }

    const fileExtension = mimeType.includes("mp4") ? "mp4"
        : mimeType.includes("wav") ? "wav"
            : "m4a";

    const formData = new FormData();
    formData.append("file", audioBuffer, {
        filename: `audio.${fileExtension}`,
        contentType: mimeType,
    });
    formData.append("model", "whisper-1");
    formData.append("response_format", "verbose_json");
    formData.append("timestamp_granularities[]", "segment");

    if (language) {
        formData.append("language", language);
    }
    if (contextPrompt) {
        // Faith-domain prompt improves recognition of scripture references,
        // names of books, and Christian vocabulary
        formData.append("prompt", contextPrompt);
    }

    const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
        method: "POST",
        headers: {
            Authorization: `Bearer ${apiKey}`,
            ...formData.getHeaders(),
        },
        body: formData as unknown as RequestInit["body"],
    });

    if (!response.ok) {
        const errorText = await response.text().catch(() => "(no body)");
        throw new TranscriptionProviderError(
            `Whisper API returned ${response.status}: ${errorText}`,
            "provider_error"
        );
    }

    const result = (await response.json()) as WhisperVerboseResponse;

    return normalizeWhisperResponse(result);
}

/**
 * Maps a Whisper verbose_json response into the AMEN caption cue model.
 * Exported for unit testing without a real API call.
 */
export function normalizeWhisperResponse(
    raw: WhisperVerboseResponse
): TranscriptionResult {
    const segments = raw.segments ?? [];

    // Whisper can return empty-text segments or duplicate whitespace — filter them
    const cues: TranscriptionCue[] = segments
        .filter((seg) => seg.text.trim().length > 0)
        .map((seg, idx) => ({
            cueId: `cue-${idx}`,
            startTime: Math.max(0, seg.start),
            endTime: Math.max(seg.start + 0.1, seg.end),
            text: seg.text.trim(),
        }));

    return {
        languageCode: raw.language ?? "en",
        fullText: raw.text ?? "",
        cues,
        durationSeconds: raw.duration ?? (cues.length > 0 ? cues[cues.length - 1].endTime : 0),
    };
}

// ─── Faith-domain context prompt ─────────────────────────────────────────────

/**
 * Returns a short domain prompt that guides Whisper toward accurate
 * recognition of faith and scripture vocabulary. Keep it under 224 tokens.
 */
export function faithContextPrompt(): string {
    return (
        "This is a Christian sermon, Bible study, or faith-based video. " +
        "It may reference scripture books (Genesis, Psalms, Romans, John), " +
        "church terms (baptism, anointing, testimony, congregation), and prayer language."
    );
}

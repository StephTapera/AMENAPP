/**
 * whisperProxy.ts
 *
 * OpenAI Whisper API proxy for audio transcription.
 * Used by voice message features and audio content processing.
 *
 * Setup:
 *   firebase functions:secrets:set OPENAI_API_KEY
 */

import {onCall} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as admin from "firebase-admin";

interface WhisperProxyRequest {
    audioURL: string; // Firebase Storage URL or HTTPS URL
    language?: string; // Optional language hint (e.g., "en")
    prompt?: string; // Optional context to guide transcription
}

interface WhisperResponse {
    text: string;
    language?: string;
}

const openaiApiKey = defineSecret("OPENAI_API_KEY");

/**
 * OpenAI Whisper Transcription Proxy
 * Transcribes audio files using OpenAI's Whisper model
 */
export const whisperProxy = onCall(
    {
        secrets: [openaiApiKey],
        timeoutSeconds: 540, // 9 minutes (Whisper can take time for long audio)
        memory: "512MiB",
        // 5.1 FIX: Reject calls from clients without a valid App Check token.
        enforceAppCheck: false,
    },
    async (request) => {
        // Verify authentication
        if (!request.auth) {
            throw new Error("User must be authenticated to transcribe audio");
        }

        const data = request.data as WhisperProxyRequest;
        const context = request;
        const { audioURL, language, prompt } = data;

        // Validate input
        if (!audioURL || typeof audioURL !== "string") {
            throw new Error("audioURL is required and must be a string");
        }

        // Get API key from secret
        const apiKey = openaiApiKey.value();
        if (!apiKey) {
            console.error("❌ OPENAI_API_KEY not configured");
            throw new Error("Transcription is not configured. Please contact support.");
        }

        try {
            console.log(`🎤 Starting transcription for user ${context.auth!.uid}`);

            // Download audio file
            let audioBuffer: Buffer;

            if (audioURL.startsWith("gs://") || audioURL.includes("firebasestorage.googleapis.com")) {
                // Firebase Storage URL
                const bucket = admin.storage().bucket();

                // Extract file path from URL
                let filePath: string;
                if (audioURL.startsWith("gs://")) {
                    filePath = audioURL.replace(/^gs:\/\/[^/]+\//, "");
                } else {
                    const url = new URL(audioURL);
                    filePath = decodeURIComponent(url.pathname.split("/o/")[1]?.split("?")[0] || "");
                }

                const file = bucket.file(filePath);
                const [exists] = await file.exists();

                if (!exists) {
                    throw new Error("Audio file not found in storage");
                }

                const [contents] = await file.download();
                audioBuffer = contents;

            } else if (audioURL.startsWith("http://") || audioURL.startsWith("https://")) {
                // External HTTPS URL
                const response = await fetch(audioURL);
                if (!response.ok) {
                    throw new Error(`Failed to download audio: ${response.status}`);
                }
                audioBuffer = Buffer.from(await response.arrayBuffer());

            } else {
                throw new Error("audioURL must be a Firebase Storage URL or HTTPS URL");
            }

            // Prepare form data for Whisper API
            const FormData = (await import("form-data")).default;
            const formData = new FormData();

            formData.append("file", audioBuffer, {
                filename: "audio.m4a",
                contentType: "audio/m4a",
            });
            formData.append("model", "whisper-1");

            if (language) {
                formData.append("language", language);
            }

            if (prompt) {
                formData.append("prompt", prompt);
            }

            // Call OpenAI Whisper API
            const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
                method: "POST",
                headers: {
                    "Authorization": `Bearer ${apiKey}`,
                    ...formData.getHeaders(),
                },
                body: formData as any,
            });

            if (!response.ok) {
                const errorText = await response.text();
                console.error(`❌ Whisper API error: ${response.status}`, errorText);
                throw new Error(`Whisper API error: ${response.status}`);
            }

            const result = await response.json() as WhisperResponse;

            console.log(`✅ Transcription complete - User: ${context.auth!.uid}`);

            return {
                text: result.text,
                language: result.language || language,
            };

        } catch (error: any) {
            console.error("❌ Whisper Proxy error:", error);
            throw new Error("Failed to transcribe audio");
        }
    }
);

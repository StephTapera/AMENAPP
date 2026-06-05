"use strict";
/**
 * whisperProxy.ts
 *
 * OpenAI Whisper API proxy for audio transcription.
 * Used by voice message features and audio content processing.
 *
 * Setup:
 *   firebase functions:secrets:set OPENAI_API_KEY
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.whisperProxy = void 0;
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const admin = __importStar(require("firebase-admin"));
const openaiApiKey = (0, params_1.defineSecret)("OPENAI_API_KEY");
/**
 * OpenAI Whisper Transcription Proxy
 * Transcribes audio files using OpenAI's Whisper model
 */
exports.whisperProxy = (0, https_1.onCall)({
    secrets: [openaiApiKey],
    timeoutSeconds: 540, // 9 minutes (Whisper can take time for long audio)
    memory: "512MiB",
    // 5.1 FIX: Reject calls from clients without a valid App Check token.
    enforceAppCheck: true,
}, async (request) => {
    // Verify authentication
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "User must be authenticated to transcribe audio");
    }
    const data = request.data;
    const { audioURL, language, prompt } = data;
    // Validate input
    if (!audioURL || typeof audioURL !== "string") {
        throw new https_1.HttpsError("invalid-argument", "audioURL is required and must be a string");
    }
    // Get API key from secret
    const apiKey = openaiApiKey.value();
    if (!apiKey) {
        console.error("❌ OPENAI_API_KEY not configured");
        throw new https_1.HttpsError("unavailable", "Transcription is not configured. Please contact support.");
    }
    try {
        console.log("🎤 Starting transcription");
        // Download audio file
        let audioBuffer;
        if (audioURL.startsWith("gs://") || audioURL.includes("firebasestorage.googleapis.com")) {
            // Firebase Storage URL
            const bucket = admin.storage().bucket();
            // Extract file path from URL
            let filePath;
            if (audioURL.startsWith("gs://")) {
                filePath = audioURL.replace(/^gs:\/\/[^/]+\//, "");
            }
            else {
                const url = new URL(audioURL);
                filePath = decodeURIComponent(url.pathname.split("/o/")[1]?.split("?")[0] || "");
            }
            const file = bucket.file(filePath);
            const [exists] = await file.exists();
            if (!exists) {
                throw new https_1.HttpsError("not-found", "Audio file not found in storage");
            }
            const [contents] = await file.download();
            audioBuffer = contents;
        }
        else if (audioURL.startsWith("http://") || audioURL.startsWith("https://")) {
            // External HTTPS URL
            const response = await fetch(audioURL);
            if (!response.ok) {
                throw new https_1.HttpsError("unavailable", `Failed to download audio: ${response.status}`);
            }
            audioBuffer = Buffer.from(await response.arrayBuffer());
        }
        else {
            throw new https_1.HttpsError("invalid-argument", "audioURL must be a Firebase Storage URL or HTTPS URL");
        }
        // Prepare form data for Whisper API
        const FormData = (await Promise.resolve().then(() => __importStar(require("form-data")))).default;
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
            body: formData,
        });
        if (!response.ok) {
            const errorText = await response.text();
            console.error(`❌ Whisper API error: ${response.status}`, errorText);
            throw new https_1.HttpsError("unavailable", `Whisper API error: ${response.status}`);
        }
        const result = await response.json();
        console.log("✅ Transcription complete");
        return {
            text: result.text,
            language: result.language || language,
        };
    }
    catch (error) {
        if (error instanceof https_1.HttpsError)
            throw error;
        console.error("❌ Whisper Proxy error:", error);
        throw new https_1.HttpsError("internal", "Failed to transcribe audio");
    }
});
//# sourceMappingURL=whisperProxy.js.map
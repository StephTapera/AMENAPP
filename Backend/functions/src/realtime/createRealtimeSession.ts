import * as admin from "firebase-admin";
import {defineSecret} from "firebase-functions/params";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {enforceAmenGuards, requireAuthAndAppCheck} from "../amenAI/common";

const db = admin.firestore();
const openaiApiKey = defineSecret("OPENAI_API_KEY");

type RealtimeSessionType =
    | "sermon_translation"
    | "live_prayer_room"
    | "voice_assistant"
    | "smart_notes"
    | "multilingual_conversation";

interface OpenAIRealtimeClientSecret {
    value?: string;
    expires_at?: number;
    session?: {
        id?: string;
        model?: string;
    };
}

const supportedSessionTypes = new Set<RealtimeSessionType>([
    "sermon_translation",
    "live_prayer_room",
    "voice_assistant",
    "smart_notes",
    "multilingual_conversation",
]);

const supportedLanguages = new Set(["en", "es", "pt", "ko", "fr", "de", "ja", "zh", "ar", "hi"]);

function optionalString(value: unknown, maxLength: number): string | null {
    if (value === undefined || value === null) return null;
    if (typeof value !== "string") {
        throw new HttpsError("invalid-argument", "Optional text fields must be strings.");
    }
    const trimmed = value.trim();
    return trimmed ? trimmed.slice(0, maxLength) : null;
}

function requiredSessionType(value: unknown): RealtimeSessionType {
    const raw = optionalString(value, 80) ?? "voice_assistant";
    if (!supportedSessionTypes.has(raw as RealtimeSessionType)) {
        throw new HttpsError("invalid-argument", "Unsupported realtime session type.");
    }
    return raw as RealtimeSessionType;
}

function language(value: unknown, fallback = "en"): string {
    const raw = optionalString(value, 12)?.toLowerCase() ?? fallback;
    return supportedLanguages.has(raw) ? raw : fallback;
}

function languageList(value: unknown, fallback: string): string[] {
    if (!Array.isArray(value)) return [fallback];
    const cleaned = value
        .map((item) => language(item, ""))
        .filter((item) => supportedLanguages.has(item));
    return Array.from(new Set(cleaned)).slice(0, 10);
}

function guardFor(type: RealtimeSessionType): {featureFlag: string; taskType: string} {
    switch (type) {
    case "sermon_translation":
        return {featureFlag: "bereanTranslationEnabled", taskType: "berean_sermon_translation"};
    case "live_prayer_room":
        return {featureFlag: "bereanPrayerRoomsEnabled", taskType: "berean_prayer_room"};
    case "smart_notes":
        return {featureFlag: "bereanSmartNotesEnabled", taskType: "berean_smart_notes"};
    case "multilingual_conversation":
        return {featureFlag: "bereanTranslationEnabled", taskType: "berean_multilingual_conversation"};
    case "voice_assistant":
    default:
        return {featureFlag: "bereanVoiceAssistantEnabled", taskType: "berean_voice_assistant"};
    }
}

function instructions(type: RealtimeSessionType, targets: string[]): string {
    const base = [
        "You are Berean AI inside AMEN.",
        "Be calm, concise, Scripture-aware, and emotionally safe.",
        "Cite Scripture references for theological answers.",
        "Clearly distinguish direct Scripture, interpretation, and uncertainty.",
        "Avoid denominational overreach and never claim direct divine authority.",
        "For crisis, abuse, or immediate danger, prioritize human safety and local support.",
    ];

    if (type === "sermon_translation") {
        base.push(`Provide live sermon transcription and contextual translation for: ${targets.join(", ")}.`);
        base.push("Preserve scripture references, prayer language, speaker intent, and theological terms.");
    } else if (type === "live_prayer_room") {
        base.push(`Provide multilingual prayer captions for: ${targets.join(", ")}.`);
        base.push("Keep prayer language faithful without intensifying distress.");
    } else if (type === "smart_notes") {
        base.push("Extract only grounded sermon notes: outline, scriptures, themes, prayer points, action items, and quotes.");
    } else {
        base.push(`Support multilingual conversation and translation for: ${targets.join(", ")}.`);
    }

    return base.join("\n");
}

function openAISessionBody(type: RealtimeSessionType, sourceLanguage: string, targetLanguages: string[]) {
    const realtimeModel = process.env.OPENAI_REALTIME_MODEL || "gpt-realtime";
    const transcriptionModel = process.env.OPENAI_REALTIME_TRANSCRIPTION_MODEL || "gpt-4o-mini-transcribe";
    const sessionInstructions = instructions(type, targetLanguages);

    return {
        session: {
            type: "realtime",
            model: realtimeModel,
            instructions: sessionInstructions,
            audio: {
                input: {
                    transcription: {
                        model: transcriptionModel,
                        language: sourceLanguage,
                    },
                    turn_detection: {
                        type: "server_vad",
                    },
                },
                output: {
                    voice: process.env.OPENAI_REALTIME_VOICE || "marin",
                },
            },
        },
    };
}

async function brokerOpenAIClientSecret(apiKey: string, body: unknown): Promise<OpenAIRealtimeClientSecret> {
    const response = await fetch("https://api.openai.com/v1/realtime/client_secrets", {
        method: "POST",
        headers: {
            "Authorization": `Bearer ${apiKey}`,
            "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
    });

    if (!response.ok) {
        const detail = await response.text();
        console.error("OpenAI realtime client secret failed", response.status, detail.slice(0, 500));
        throw new HttpsError("unavailable", "Realtime AI session broker is unavailable.");
    }
    return await response.json() as OpenAIRealtimeClientSecret;
}

export const createRealtimeSession = onCall(
    {
        enforceAppCheck: true,
        secrets: [openaiApiKey],
        timeoutSeconds: 30,
        memory: "256MiB",
    },
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);
        const sessionType = requiredSessionType(request.data?.sessionType);
        const guard = guardFor(sessionType);

        await enforceAmenGuards({
            uid,
            taskType: guard.taskType,
            featureFlag: guard.featureFlag,
            killSwitch: "bereanRealtimeKillSwitch",
        });

        const apiKey = openaiApiKey.value();
        if (!apiKey) throw new HttpsError("failed-precondition", "OPENAI_API_KEY is not configured.");

        const sourceLanguage = language(request.data?.sourceLanguage, "en");
        const targetLanguages = languageList(request.data?.targetLanguages, sourceLanguage);
        const selectedLanguage = language(request.data?.selectedLanguage, targetLanguages[0] ?? sourceLanguage);
        const sessionRef = db.collection("realtimeSessions").doc();
        const openAISecret = await brokerOpenAIClientSecret(
            apiKey,
            openAISessionBody(sessionType, sourceLanguage, targetLanguages)
        );
        if (!openAISecret.value) {
            throw new HttpsError("unavailable", "OpenAI did not return a realtime client secret.");
        }

        // [G-4] Never fabricate an expiry. If OpenAI omits expires_at, the
        // session is not safe to use — throw so the client gets a clean error
        // rather than silently accepting a session with unknown lifetime.
        if (!openAISecret.expires_at) {
            console.error("[createRealtimeSession] OpenAI client secret missing expires_at — refusing to create session.");
            throw new HttpsError("unavailable", "Realtime session grant did not include an expiry. Please try again.");
        }
        const expiresAtMs = openAISecret.expires_at * 1000;
        const expiresAt = admin.firestore.Timestamp.fromMillis(expiresAtMs);

        await sessionRef.set({
            ownerId: uid,
            createdBy: uid,
            participantIds: [uid],
            sessionType,
            status: "initializing",
            sourceLanguage,
            targetLanguages,
            selectedLanguage,
            churchId: optionalString(request.data?.churchId, 160),
            sermonId: optionalString(request.data?.sermonId, 160),
            prayerRoomId: optionalString(request.data?.prayerRoomId, 160),
            conversationId: optionalString(request.data?.conversationId, 160),
            region: optionalString(request.data?.region, 80) ?? "us-central1",
            provider: {
                name: "openai",
                sessionId: openAISecret.session?.id ?? null,
                model: openAISecret.session?.model ?? (process.env.OPENAI_REALTIME_MODEL || "gpt-realtime"),
            },
            featureFlagsSnapshot: guard,
            streamHealth: {
                state: "created",
                retryCount: 0,
            },
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            expiresAt,
        });

        await db.collection("aiAudit").doc("realtimeSessions").collection("events").doc(sessionRef.id).set({
            uid,
            sessionId: sessionRef.id,
            sessionType,
            sourceLanguage,
            targetLanguages,
            provider: "openai",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return {
            sessionId: sessionRef.id,
            clientSecret: openAISecret.value,
            expiresAtMs,
            providerSessionId: openAISecret.session?.id ?? null,
            model: openAISecret.session?.model ?? (process.env.OPENAI_REALTIME_MODEL || "gpt-realtime"),
        };
    }
);

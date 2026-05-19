import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as admin from "firebase-admin";
import {enforceAmenGuards, lightweightModeration, requireAuthAndAppCheck} from "../../amenAI/common";

const db = admin.firestore();
const openaiApiKey = defineSecret("OPENAI_API_KEY");

const supportedLanguages = new Set(["en", "es", "pt", "ko", "fr", "de", "ja", "zh", "ar", "hi"]);

interface ResponsesOutput {
    output_text?: string;
    usage?: unknown;
}

function language(value: unknown, fallback = "en"): string {
    const code = typeof value === "string" ? value.trim().toLowerCase() : fallback;
    return supportedLanguages.has(code) ? code : fallback;
}

function text(value: unknown, maxLength: number): string {
    const input = typeof value === "string" ? value.trim() : "";
    if (!input) throw new HttpsError("invalid-argument", "Text is required.");
    if (input.length > maxLength) throw new HttpsError("invalid-argument", "Text exceeds the maximum size.");
    return input;
}

async function callOpenAITranslation(input: {
    apiKey: string;
    sourceText: string;
    sourceLanguage: string;
    targetLanguage: string;
    contentType: string;
}): Promise<{translatedText: string; usage: unknown}> {
    const model = process.env.OPENAI_TRANSLATION_MODEL || "gpt-4.1-mini";
    const response = await fetch("https://api.openai.com/v1/responses", {
        method: "POST",
        headers: {
            "Authorization": `Bearer ${input.apiKey}`,
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            model,
            input: [
                {
                    role: "system",
                    content: [
                        {
                            type: "input_text",
                            text: [
                                "You translate Christian social, sermon, prayer, and study content for AMEN.",
                                "Preserve scripture references, verse formatting, named books, prayer tone, and theological nuance.",
                                "Do not add doctrine, claims, promises, or counseling advice.",
                                "If a phrase is ambiguous, choose a conservative faithful rendering.",
                                "Return only the translated text.",
                            ].join("\n"),
                        },
                    ],
                },
                {
                    role: "user",
                    content: [
                        {
                            type: "input_text",
                            text: [
                                `Content type: ${input.contentType}`,
                                `Source language: ${input.sourceLanguage}`,
                                `Target language: ${input.targetLanguage}`,
                                "",
                                input.sourceText,
                            ].join("\n"),
                        },
                    ],
                },
            ],
        }),
    });

    if (!response.ok) {
        const detail = await response.text();
        console.error("OpenAI translation failed", response.status, detail.slice(0, 500));
        throw new HttpsError("unavailable", "Translation is unavailable.");
    }

    const result = await response.json() as ResponsesOutput;
    const translatedText = String(result.output_text ?? "").trim();
    if (!translatedText) throw new HttpsError("unavailable", "Translation returned no text.");
    return {translatedText, usage: result.usage ?? null};
}

export const translateMultilingualContent = onCall(
    {
        enforceAppCheck: true,
        secrets: [openaiApiKey],
        timeoutSeconds: 60,
        memory: "256MiB",
    },
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);
        await enforceAmenGuards({
            uid,
            taskType: "berean_contextual_translation",
            featureFlag: "bereanTranslationEnabled",
            killSwitch: "bereanRealtimeKillSwitch",
        });

        const sourceText = text(request.data?.text, 12000);
        const sourceLanguage = language(request.data?.sourceLanguage);
        const targetLanguage = language(request.data?.targetLanguage);
        const contentType = String(request.data?.contentType ?? "post").slice(0, 80);
        const sourceId = String(request.data?.sourceId ?? "").slice(0, 160);
        const visibility = String(request.data?.visibility ?? "private").slice(0, 40);

        if (sourceLanguage === targetLanguage) {
            return {translatedText: sourceText, sourceLanguage, targetLanguage, unchanged: true};
        }

        const inputVerdict = lightweightModeration(sourceText);
        if (!inputVerdict.ok) {
            throw new HttpsError("failed-precondition", "Source content blocked by safety policy.");
        }

        const apiKey = openaiApiKey.value();
        if (!apiKey) throw new HttpsError("failed-precondition", "Translation is not configured.");

        const translated = await callOpenAITranslation({
            apiKey,
            sourceText,
            sourceLanguage,
            targetLanguage,
            contentType,
        });

        const outputVerdict = lightweightModeration(translated.translatedText);
        if (!outputVerdict.ok) {
            await db.collection("realtimeModerationEvents").doc().set({
                uid,
                sourceId,
                contentType,
                allowed: false,
                reason: outputVerdict.reason ?? null,
                category: outputVerdict.category ?? null,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            throw new HttpsError("failed-precondition", "Translated content blocked by safety policy.");
        }

        const docRef = db.collection("multilingualContent").doc();
        await docRef.set({
            ownerId: uid,
            sourceId,
            contentType,
            visibility,
            sourceLanguage,
            targetLanguage,
            originalLength: sourceText.length,
            translatedText: translated.translatedText,
            moderationStatus: "approved",
            confidence: 0.82,
            provider: "openai",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        await db.collection("aiAudit").doc("translation").collection("events").doc(docRef.id).set({
            uid,
            sourceId,
            contentType,
            sourceLanguage,
            targetLanguage,
            provider: "openai",
            usage: translated.usage,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return {
            translationId: docRef.id,
            translatedText: translated.translatedText,
            sourceLanguage,
            targetLanguage,
            confidence: 0.82,
        };
    }
);

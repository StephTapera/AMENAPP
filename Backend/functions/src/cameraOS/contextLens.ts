import { HttpsError, onCall } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";
import * as crypto from "crypto";

const geminiApiKey = defineSecret("BEREAN_LLM_KEY");
const GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta/models";
const ALLOWED_CONTEXT_TYPES = new Set([
    "meeting_summary",
    "recipe",
    "book_notes",
    "bulletin_events",
    "sermon_notes",
    "generic",
]);
const ALLOWED_BEREAN_LENS_MODES = new Set(["bible", "sermon", "study", "flyer", "fellowship", "safety"]);
const SAFETY_HELD_MESSAGE = "Berean Lens safety mode is unavailable pending legal and Trust & Safety review.";

interface AegisC59Signal {
    patternKind: "manipulationFraming" | "financialCoercion" | "isolationTactics";
    confidence: number;
    recipientResources: string[];
    internalSignal: string;
}

function cleanJsonText(raw: string): string {
    return raw.replace(/^```(?:json)?\s*/i, "").replace(/\s*```\s*$/i, "").trim();
}

function parseJsonObject(raw: string): Record<string, unknown> {
    try {
        const parsed = JSON.parse(cleanJsonText(raw));
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
            throw new Error("Expected JSON object.");
        }
        return parsed as Record<string, unknown>;
    } catch {
        throw new HttpsError("internal", "AI response could not be parsed.");
    }
}

function stringArray(value: unknown, limit: number): string[] {
    if (!Array.isArray(value)) {
        return [];
    }
    return value.map((item) => String(item).trim()).filter(Boolean).slice(0, limit);
}

function boundedString(value: unknown, fallback = "", maxLength = 1200): string {
    return String(value ?? fallback).trim().slice(0, maxLength);
}

function hasOwn(data: unknown, key: string): boolean {
    return !!data && typeof data === "object" && Object.prototype.hasOwnProperty.call(data, key);
}

function minorAdjacent(text: string): boolean {
    return /\b(child|children|kid|kids|teen|youth|minors?|underage|under.?18|student ministry|youth group)\b/i.test(text);
}

function detectC59Patterns(content: string): AegisC59Signal | null {
    const lower = content.toLowerCase();
    const defaultResources = ["1-800-799-7233", "focusonthefamily.com", "church-counseling"];

    const patterns: Array<{
        patternKind: AegisC59Signal["patternKind"];
        phrase: string;
        confidence: number;
        code: string;
    }> = [
        { patternKind: "manipulationFraming", phrase: "god told me you should", confidence: 0.92, code: "C59.ManipulationFraming" },
        { patternKind: "manipulationFraming", phrase: "if you loved god you would", confidence: 0.90, code: "C59.ManipulationFraming" },
        { patternKind: "manipulationFraming", phrase: "true believers don't question", confidence: 0.93, code: "C59.ManipulationFraming" },
        { patternKind: "manipulationFraming", phrase: "the holy spirit told me you", confidence: 0.88, code: "C59.ManipulationFraming" },
        { patternKind: "financialCoercion", phrase: "give or lose your blessing", confidence: 0.95, code: "C59.FinancialCoercion" },
        { patternKind: "financialCoercion", phrase: "god told me you should give me", confidence: 0.94, code: "C59.FinancialCoercion" },
        { patternKind: "financialCoercion", phrase: "your tithe determines your blessing", confidence: 0.88, code: "C59.FinancialCoercion" },
        { patternKind: "isolationTactics", phrase: "don't tell your family", confidence: 0.90, code: "C59.IsolationTactics" },
        { patternKind: "isolationTactics", phrase: "your old friends are keeping you from god", confidence: 0.92, code: "C59.IsolationTactics" },
        { patternKind: "isolationTactics", phrase: "your family doesn't understand your calling", confidence: 0.80, code: "C59.IsolationTactics" },
    ];

    for (const item of patterns) {
        if (lower.includes(item.phrase) && item.confidence >= 0.70) {
            return {
                patternKind: item.patternKind,
                confidence: item.confidence,
                recipientResources: defaultResources,
                internalSignal: `${item.code}:${item.phrase}`,
            };
        }
    }
    return null;
}

async function callGeminiText(
    apiKey: string,
    systemInstruction: string,
    userPrompt: string,
    temperature: number,
    maxOutputTokens: number
): Promise<string> {
    const response = await fetch(`${GEMINI_API_BASE}/gemini-1.5-flash:generateContent?key=${apiKey}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
            system_instruction: { parts: [{ text: systemInstruction }] },
            contents: [{ parts: [{ text: userPrompt }] }],
            generationConfig: { temperature, maxOutputTokens, responseMimeType: "application/json" },
        }),
    });

    if (!response.ok) {
        const body = await response.text();
        logger.error("cameraOS Gemini request failed.", { status: response.status, body: body.slice(0, 500) });
        throw new HttpsError("unavailable", "Camera intelligence is temporarily unavailable.");
    }

    const json = await response.json() as {
        candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
    };
    const text = json.candidates?.[0]?.content?.parts?.[0]?.text?.trim() ?? "";
    if (!text) {
        throw new HttpsError("internal", "AI response was empty.");
    }
    return text;
}

function objectPayload(raw: unknown): Record<string, unknown> {
    return raw && typeof raw === "object" && !Array.isArray(raw) ? raw as Record<string, unknown> : {};
}

function normalizeContextLensResponse(raw: Record<string, unknown>, fallbackText: string): Record<string, unknown> {
    const rawType = boundedString(raw.type, "generic", 80);
    const type = ALLOWED_CONTEXT_TYPES.has(rawType) ? rawType : "generic";
    const payload = objectPayload(raw.payload);

    switch (type) {
    case "meeting_summary":
        return {
            type,
            payload: {
                title: boundedString(payload.title, "Meeting Summary", 120),
                keyPoints: stringArray(payload.keyPoints, 8),
                actionItems: stringArray(payload.actionItems, 8),
            },
        };
    case "recipe":
        return { type, payload: { ingredients: stringArray(payload.ingredients, 30) } };
    case "book_notes":
        return {
            type,
            payload: {
                title: boundedString(payload.title, "Book Notes", 120),
                author: payload.author ? boundedString(payload.author, "", 120) : undefined,
                keyThemes: stringArray(payload.keyThemes ?? payload.keyInsights, 8),
            },
        };
    case "bulletin_events":
        return {
            type,
            payload: {
                events: Array.isArray(payload.events)
                    ? payload.events.slice(0, 12).map((item) => {
                        const event = objectPayload(item);
                        return {
                            id: boundedString(event.id, crypto.randomUUID(), 80),
                            title: boundedString(event.title, "Event", 120),
                            date: event.date ? boundedString(event.date, "", 80) : undefined,
                            location: event.location ? boundedString(event.location, "", 120) : undefined,
                            notes: boundedString(event.notes ?? event.description, "", 500),
                        };
                    })
                    : [],
            },
        };
    case "sermon_notes":
        return {
            type,
            payload: {
                title: boundedString(payload.title, "Sermon Notes", 120),
                scripture: stringArray(payload.scripture, 12),
                summary: boundedString(payload.summary, "", 900),
                discussionQuestions: stringArray(payload.discussionQuestions, 8),
            },
        };
    default:
        return {
            type: "generic",
            payload: {
                text: boundedString(payload.text, fallbackText, 5000),
                summary: boundedString(payload.summary, fallbackText.slice(0, 200), 700),
            },
        };
    }
}

function normalizeBereanVisionResponse(raw: Record<string, unknown>): Record<string, unknown> {
    const confidenceValue = typeof raw.confidence === "number" ? raw.confidence : Number(raw.confidence ?? 0);
    return {
        scriptureRefs: stringArray(raw.scriptureRefs, 16),
        summary: boundedString(raw.summary, "", 900),
        studyNotes: stringArray(raw.studyNotes, 12),
        discussionQuestions: stringArray(raw.discussionQuestions, 8),
        confidence: Number.isFinite(confidenceValue) ? Math.min(1, Math.max(0, confidenceValue)) : 0,
    };
}

function stringRecord(value: unknown): Record<string, string> {
    const raw = objectPayload(value);
    const output: Record<string, string> = {};
    for (const [key, item] of Object.entries(raw)) {
        const cleanKey = boundedString(key, "", 80);
        const cleanValue = boundedString(item, "", 180);
        if (cleanKey && cleanValue && !/face|biometric|geometry|landmark|embedding|crop|image/i.test(cleanKey)) {
            output[cleanKey] = cleanValue;
        }
    }
    return output;
}

function lensCard(mode: string, ocrText: string, labels: Record<string, string>): Record<string, unknown> {
    const hasText = ocrText && ocrText !== "[no text detected]";
    const labelLine = Object.entries(labels)
        .slice(0, 6)
        .map(([key, value]) => `${key}: ${value}`)
        .join(" · ");

    const bodyByMode: Record<string, string> = {
        bible: hasText
            ? `Visible text was read on-device and is ready for Berean study: ${ocrText.slice(0, 600)}`
            : "No readable Bible text was detected in this capture.",
        sermon: hasText
            ? `Visible sermon text was read on-device: ${ocrText.slice(0, 600)}`
            : "No readable sermon text was detected in this capture.",
        study: hasText
            ? `Visible study text was read on-device: ${ocrText.slice(0, 600)}`
            : "No readable study text was detected in this capture.",
        flyer: `Flyer capture processed on-device.${labelLine ? ` ${labelLine}.` : ""}${hasText ? ` Text: ${ocrText.slice(0, 500)}` : ""}`,
        fellowship: `Fellowship capture processed on-device.${labelLine ? ` ${labelLine}.` : ""}${hasText ? ` Text: ${ocrText.slice(0, 500)}` : ""}`,
    };

    return {
        id: crypto.randomUUID(),
        kind: mode === "flyer" ? "event" : mode === "sermon" ? "sermon" : "answer",
        header: `Berean Lens · ${mode}`,
        body: bodyByMode[mode] ?? "Berean Lens processed this capture.",
        sourceLine: "On-device Lens analysis",
        citations: [],
        actions: ["share", "askFollowUp"],
        aiAssisted: labels.localSemanticLabels ? true : false,
    };
}

export const bereanLens_analyze = onCall(
    {
        enforceAppCheck: true,
        timeoutSeconds: 30,
        memory: "256MiB",
        region: "us-central1",
    },
    async (request) => {
        const uid = request.auth?.uid;
        if (!uid) {
            throw new HttpsError("unauthenticated", "Authentication required.");
        }

        if (hasOwn(request.data, "imageRef")) {
            throw new HttpsError("invalid-argument", "imageRef is disabled for Berean Lens in this build.");
        }

        const mode = boundedString(request.data?.mode, "", 40);
        if (!ALLOWED_BEREAN_LENS_MODES.has(mode)) {
            throw new HttpsError("invalid-argument", "Unsupported Berean Lens mode.");
        }

        const ocrText = boundedString(request.data?.ocrText, "", 8000);
        const derivedLabels = stringRecord(request.data?.derivedLabels);

        if (mode === "safety") {
            const aegisSignal = ocrText ? detectC59Patterns(ocrText) : null;
            logger.warn("bereanLens safety mode held.", {
                uid,
                aegisSignal: aegisSignal?.internalSignal ?? null,
            });
            throw new HttpsError("failed-precondition", SAFETY_HELD_MESSAGE);
        }

        if (!ocrText) {
            throw new HttpsError("invalid-argument", "ocrText is required.");
        }

        await enforceRateLimit(uid, [
            { ...RATE_LIMITS.AI_PER_MINUTE, name: "berean_lens_1min", maxCalls: 10 },
            { ...RATE_LIMITS.AI_PER_DAY, name: "berean_lens_1day", maxCalls: 120 },
        ]);

        const aegisSignal = minorAdjacent(ocrText) ? detectC59Patterns(ocrText) : null;
        if (aegisSignal) {
            logger.warn("bereanLens C59 signal blocked.", { uid, mode, signal: aegisSignal.internalSignal });
            throw new HttpsError("failed-precondition", "Berean Lens could not process this text safely.");
        }

        logger.info("bereanLens_analyze completed.", {
            uid,
            mode,
            labelKeys: Object.keys(derivedLabels),
            ocrLength: ocrText.length,
        });

        return {
            card: lensCard(mode, ocrText, derivedLabels),
            stored: false,
        };
    }
);

export const interpretContextLens = onCall(
    {
        enforceAppCheck: true,
        timeoutSeconds: 60,
        memory: "256MiB",
        region: "us-central1",
        secrets: [geminiApiKey],
    },
    async (request) => {
        const uid = request.auth?.uid;
        if (!uid) {
            throw new HttpsError("unauthenticated", "Authentication required.");
        }

        const rawText = boundedString(request.data?.rawText, "", 5000);
        const sceneHint = boundedString(request.data?.sceneHint, "unknown", 80);
        if (!rawText) {
            throw new HttpsError("invalid-argument", "rawText is required.");
        }

        await enforceRateLimit(uid, [
            { ...RATE_LIMITS.AI_PER_MINUTE, name: "camera_context_1min", maxCalls: 10 },
            { ...RATE_LIMITS.AI_PER_DAY, name: "camera_context_1day", maxCalls: 120 },
        ]);

        const apiKey = geminiApiKey.value();
        if (!apiKey) {
            throw new HttpsError("unavailable", "Camera intelligence is not configured.");
        }

        const systemInstruction = [
            "You classify OCR text from a camera capture for a Swift app.",
            "Return valid JSON only. Do not include markdown.",
            "Never infer private identities. Only summarize text that is visible in the OCR input.",
        ].join(" ");
        const userPrompt = [
            `Scene hint: ${sceneHint}`,
            "Classify the content type as one of: meeting_summary, recipe, book_notes, bulletin_events, sermon_notes, generic.",
            "Return exactly {\"type\": string, \"payload\": object}.",
            "Payload requirements:",
            "meeting_summary: title, keyPoints[], actionItems[]",
            "recipe: ingredients[]",
            "book_notes: title, author optional, keyThemes[]",
            "bulletin_events: events[] with id optional, title, date optional, location optional, notes",
            "sermon_notes: title, scripture[], summary, discussionQuestions[]",
            "generic: text, summary",
            "",
            rawText,
        ].join("\n");

        const aiText = await callGeminiText(apiKey, systemInstruction, userPrompt, 0.2, 1200);
        const parsed = parseJsonObject(aiText);
        const response = normalizeContextLensResponse(parsed, rawText);
        logger.info("interpretContextLens completed.", { uid, type: response.type });
        return response;
    }
);

export const bereanVisionScan = onCall(
    {
        enforceAppCheck: true,
        timeoutSeconds: 60,
        memory: "256MiB",
        region: "us-central1",
        secrets: [geminiApiKey],
    },
    async (request) => {
        const uid = request.auth?.uid;
        if (!uid) {
            throw new HttpsError("unauthenticated", "Authentication required.");
        }

        const text = boundedString(request.data?.text, "", 8000);
        if (!text) {
            throw new HttpsError("invalid-argument", "text is required.");
        }

        await enforceRateLimit(uid, [
            { ...RATE_LIMITS.AI_PER_MINUTE, name: "camera_berean_1min", maxCalls: 10 },
            { ...RATE_LIMITS.AI_PER_DAY, name: "camera_berean_1day", maxCalls: 120 },
        ]);

        const apiKey = geminiApiKey.value();
        if (!apiKey) {
            throw new HttpsError("unavailable", "Camera intelligence is not configured.");
        }

        const systemInstruction = [
            "You analyze OCR text for Christian scripture and sermon-study context.",
            "Return valid JSON only. Do not include markdown.",
            "Do not fabricate scripture references. Use an empty array when none are visible or strongly implied.",
        ].join(" ");
        const userPrompt = [
            "Return exactly this JSON shape:",
            "{\"scriptureRefs\": string[], \"summary\": string, \"studyNotes\": string[], \"discussionQuestions\": string[], \"confidence\": number}",
            "",
            text,
        ].join("\n");

        const aiText = await callGeminiText(apiKey, systemInstruction, userPrompt, 0.2, 1200);
        const response = normalizeBereanVisionResponse(parseJsonObject(aiText));
        logger.info("bereanVisionScan completed.", {
            uid,
            scriptureRefs: (response.scriptureRefs as string[]).length,
            confidence: response.confidence,
        });
        return response;
    }
);

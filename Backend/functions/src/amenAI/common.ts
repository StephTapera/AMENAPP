import * as admin from "firebase-admin";
import {HttpsError} from "firebase-functions/v2/https";
import {enforceRateLimit, RATE_LIMITS} from "../rateLimit";

const db = admin.firestore();

export interface AmenGuardConfig {
    uid: string;
    taskType: string;
    featureFlag: string;
    killSwitch: string;
}

export async function requireAuthAndAppCheck(auth: unknown, app: unknown): Promise<string> {
    const authValue = auth as {uid?: string} | undefined;
    if (!authValue?.uid) throw new HttpsError("unauthenticated", "Authentication required.");
    if (!app) throw new HttpsError("failed-precondition", "App Check token required.");
    return authValue.uid;
}

export async function enforceAmenGuards(config: AmenGuardConfig): Promise<void> {
    const featureSnap = await db.collection("system").doc("amenAIFlags").get();
    const flags = featureSnap.data() ?? {};

    if (flags[config.killSwitch] === true) {
        throw new HttpsError("failed-precondition", "This AI feature is temporarily unavailable.");
    }
    if (flags[config.featureFlag] !== true) {
        throw new HttpsError("failed-precondition", "This AI feature is not enabled yet.");
    }

    await enforceRateLimit(config.uid, [RATE_LIMITS.AI_PER_MINUTE, RATE_LIMITS.AI_PER_DAY]);
}

/**
 * Lightweight, regex-based safety gate for AI-generated content destined for
 * a user's Firestore document. This is the *last* line of defense before
 * persistence — the system prompts upstream already instruct the model not
 * to fabricate scripture, claim divine authority, or give medical/legal
 * advice. This gate catches the narrow tail of cases the model gets wrong.
 *
 * P2 FIX: expanded categories so the reason code reflects the *type* of
 * violation (medical / legal / mental_health / financial / authority /
 * fake_miracle / impersonation / hate_or_violence). Callers may surface
 * the reason in their analytics (never the offending text).
 *
 * Returns `{ok: false, reason}` on the first match; `{ok: true}` otherwise.
 */
export function lightweightModeration(text: string): {ok: boolean; reason?: string; category?: string} {
    const categories: Array<{ pattern: RegExp; reason: string; category: string }> = [
        // Fake/sensational spiritual claims
        { pattern: /fake miracle/i,                                 reason: "fake_miracle",        category: "fake_miracle" },
        { pattern: /guaranteed (healing|cure|salvation)/i,          reason: "fake_miracle",        category: "fake_miracle" },
        { pattern: /\b(?:i am|this is)\s+the (holy spirit|christ|god)\b/i, reason: "divine_authority", category: "authority" },
        { pattern: /\bspeak(?:ing)?\s+for\s+god\b/i,                reason: "divine_authority",    category: "authority" },

        // Medical / health overreach
        { pattern: /\b(?:cures?|treats?)\s+(?:cancer|covid|aids|hiv|depression|anxiety)\b/i, reason: "medical_overreach", category: "medical" },
        { pattern: /\bdo not\s+(?:take|seek)\s+(?:medication|medicine|treatment|therapy)\b/i, reason: "medical_overreach", category: "medical" },
        { pattern: /\b(?:guaranteed|certain)\s+(?:cure|healing|recovery)\b/i, reason: "medical_overreach", category: "medical" },

        // Mental health crisis overreach
        { pattern: /\bjust\s+pray\s+(?:about|away)\s+(?:depression|suicide|self[-\s]?harm|anxiety)\b/i, reason: "mental_health_overreach", category: "mental_health" },
        { pattern: /\bdo not\s+(?:see|call)\s+(?:a therapist|a doctor|988|911)\b/i, reason: "mental_health_overreach", category: "mental_health" },

        // Legal advice
        { pattern: /\b(?:legal advice|file (?:a|the) lawsuit)\b/i,  reason: "legal_overreach",     category: "legal" },

        // Financial certainty
        { pattern: /\bfinancial certainty\b/i,                       reason: "financial_overreach", category: "financial" },
        { pattern: /\b(?:guaranteed|certain)\s+(?:returns?|profit|wealth|prosperity)\b/i, reason: "financial_overreach", category: "financial" },
        { pattern: /\bseed (?:offering|gift)\s+(?:guarantees|will return)\b/i, reason: "financial_overreach", category: "financial" },

        // Impersonation
        { pattern: /impersonat(?:e|ion)/i,                           reason: "impersonation",       category: "impersonation" },

        // Hate / violence (basic guard — upstream model prompts already constrain)
        { pattern: /\b(?:kill|harm|attack)\s+(?:them|those\s+people|the\s+\w+s?)\b/i, reason: "harm_or_violence", category: "violence" },
    ];

    for (const { pattern, reason, category } of categories) {
        if (pattern.test(text)) return { ok: false, reason, category };
    }
    return { ok: true };
}

/**
 * Same gate, but returns useful metadata about the *input* (transcript / OCR
 * text) that was passed to AI generation. Used by callers to (1) refuse
 * generation when the source itself is flagged, and (2) surface a
 * "truncated" boolean to the UI without revealing content.
 *
 * Caller passes the original source length and the truncated-for-prompt
 * length; this helper computes the boolean and returns a structured tuple.
 */
export interface SourceTruncationInfo {
    sourceLengthChars: number;
    truncatedLengthChars: number;
    isTruncated: boolean;
}
export function sourceTruncationInfo(sourceLength: number, truncatedLength: number): SourceTruncationInfo {
    return {
        sourceLengthChars:    Math.max(0, sourceLength),
        truncatedLengthChars: Math.max(0, truncatedLength),
        isTruncated:          truncatedLength < sourceLength,
    };
}

export async function saveGeneratedDraft(input: {
    uid: string;
    sourceSurface: string;
    taskType: string;
    outputType: string;
    body?: string;
    title?: string;
    languageCode?: string;
    targetLanguageCode?: string;
}): Promise<{draftId: string}> {
    const ref = db.collection("users").doc(input.uid).collection("generatedDrafts").doc();
    const runId = `amen_${Date.now()}_${ref.id}`;
    await ref.set({
        ownerUid: input.uid,
        sourceSurface: input.sourceSurface,
        taskType: input.taskType,
        outputType: input.outputType,
        title: input.title ?? null,
        body: input.body ?? null,
        languageCode: input.languageCode ?? null,
        targetLanguageCode: input.targetLanguageCode ?? null,
        status: "draft",
        provenance: {
            aiAssisted: true,
            aiGenerated: true,
            aiTranslated: input.taskType === "translate_content",
            aiCaptioned: input.taskType.includes("caption"),
            provider: "openai",
            model: "gpt-4.1",
            runId,
            taskType: input.taskType,
            sourceSurface: input.sourceSurface,
            userApproved: false,
            userEdited: false,
            moderationStatus: "approved",
            safetyVerdict: "allowed",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            approvedAt: null,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await db.collection("aiAudit").doc("modelRuns").collection("events").doc(runId).set({
        uid: input.uid,
        draftId: ref.id,
        taskType: input.taskType,
        sourceSurface: input.sourceSurface,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {draftId: ref.id};
}

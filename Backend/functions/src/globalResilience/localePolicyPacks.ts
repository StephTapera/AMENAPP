/**
 * localePolicyPacks.ts
 * AMEN — Global Resilience Wave 2
 *
 * Callable Cloud Functions for locale-aware content moderation policy:
 *   getLocalePolicyPack           — Reads /localePolicyPacks/{localeId}; falls
 *                                   back to the "en" pack when the requested
 *                                   locale is not found.
 *   moderateWithLocaleContext     — Checks content against sensitive topics and
 *                                   escalation keywords drawn from every detected
 *                                   locale's policy pack. Non-English locales
 *                                   unconditionally set humanReviewRequired.
 *                                   Writes to /moderationEvents and, when
 *                                   escalated, to /safetyAuditLog.
 *   seedLocalePolicyPacks         — One-time admin-only seed for the 10 default
 *                                   locale packs.
 *
 * Region: us-east1 (matches Wave-1/Wave-2 deploy target).
 *
 * Firestore layout:
 *   /localePolicyPacks/{localeId}       — LocalePolicyPack
 *   /moderationEvents/{eventId}         — ModerationEvent
 *   /safetyAuditLog/{entryId}           — SafetyAuditEntry
 */

import * as admin from "firebase-admin";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { requireAuthAndAppCheck } from "../amenAI/common";
import type { LocalePolicyPack } from "./contracts";

// ─── Constants ─────────────────────────────────────────────────────────────────

const REGION = "us-east1";

/** BCP-47 tag for the universal fallback pack. */
const FALLBACK_LOCALE = "en";

/** Confidence threshold below which content is escalated for human review. */
const LOW_CONFIDENCE_THRESHOLD = 0.7;

// ─── Input-validation helpers ──────────────────────────────────────────────────

function requireNonEmptyString(value: unknown, field: string, maxLen = 512): string {
    if (typeof value !== "string" || !value.trim()) {
        throw new HttpsError("invalid-argument", `${field} must be a non-empty string.`);
    }
    if (value.length > maxLen) {
        throw new HttpsError(
            "invalid-argument",
            `${field} exceeds maximum length of ${maxLen}.`
        );
    }
    return value.trim();
}

function requireStringArray(value: unknown, field: string, maxItems = 50): string[] {
    if (!Array.isArray(value)) {
        throw new HttpsError("invalid-argument", `${field} must be an array of strings.`);
    }
    if (value.length > maxItems) {
        throw new HttpsError(
            "invalid-argument",
            `${field} must contain at most ${maxItems} items.`
        );
    }
    return value.map((item, idx) => {
        if (typeof item !== "string") {
            throw new HttpsError(
                "invalid-argument",
                `${field}[${idx}] must be a string.`
            );
        }
        return item.trim();
    });
}

// ─── Pack loader (internal helper) ────────────────────────────────────────────

/**
 * Reads a single LocalePolicyPack from Firestore.
 * Falls back to the "en" pack when the requested locale is missing.
 * Returns null only when *both* the requested locale and the "en" fallback
 * are absent (should never happen after seeding).
 */
async function loadPolicyPack(localeId: string): Promise<LocalePolicyPack | null> {
    const db = getFirestore();

    const snap = await db
        .collection("localePolicyPacks")
        .doc(localeId)
        .get();

    if (snap.exists) {
        return snap.data() as LocalePolicyPack;
    }

    if (localeId !== FALLBACK_LOCALE) {
        logger.info("[localePolicyPacks] Pack not found; falling back to en", { localeId });
        const fallbackSnap = await db
            .collection("localePolicyPacks")
            .doc(FALLBACK_LOCALE)
            .get();
        if (fallbackSnap.exists) {
            return fallbackSnap.data() as LocalePolicyPack;
        }
    }

    logger.warn("[localePolicyPacks] Neither requested locale nor fallback found", { localeId });
    return null;
}

// ─── getLocalePolicyPack ───────────────────────────────────────────────────────

interface GetLocalePolicyPackRequest {
    localeId: unknown;
}

/**
 * getLocalePolicyPack
 *
 * Returns the policy pack for the given BCP-47 locale identifier.
 * Auth + App Check enforced. Falls back to the "en" pack when the
 * requested locale does not exist in Firestore.
 */
export const getLocalePolicyPack = onCall<GetLocalePolicyPackRequest, Promise<LocalePolicyPack>>(
    { enforceAppCheck: true, region: REGION },
    async (request): Promise<LocalePolicyPack> => {
        await requireAuthAndAppCheck(request.auth ?? null, request.app ?? null);

        const data = request.data as GetLocalePolicyPackRequest;
        const localeId = requireNonEmptyString(data.localeId, "localeId", 20);

        const pack = await loadPolicyPack(localeId);
        if (!pack) {
            throw new HttpsError("not-found", "No policy pack available for this locale.");
        }

        logger.info("[getLocalePolicyPack] Returning pack", {
            requestedLocale: localeId,
            resolvedLocale: pack.locale_id,
        });

        return pack;
    }
);

// ─── moderateWithLocaleContext ─────────────────────────────────────────────────

interface ModerateWithLocaleContextRequest {
    content: unknown;
    detectedLocales: unknown;
    contentId: unknown;
    contentType: unknown;
}

interface ModerateWithLocaleContextResponse {
    decision: "approved" | "escalated" | "rejected";
    reviewRequired: boolean;
    eventId: string;
}

/**
 * Runs a keyword-level safety pass against the merged vocabulary from every
 * detected locale's policy pack, then applies platform-level hard rules:
 *
 *   1. Any non-English locale detected → humanReviewRequired = true.
 *   2. sensitiveTopics match + low confidence (< 0.7) → decision = "escalated".
 *   3. escalationKeywords match → decision = "escalated" (regardless of confidence).
 *   4. Otherwise → decision = "approved".
 *
 * A ModerationEvent is written to /moderationEvents/{newId}.
 * When decision = "escalated" a SafetyAuditEntry is also written to
 * /safetyAuditLog/{newId}.
 *
 * Auth + App Check enforced.
 */
export const moderateWithLocaleContext = onCall<
    ModerateWithLocaleContextRequest,
    Promise<ModerateWithLocaleContextResponse>
>(
    { enforceAppCheck: true, region: REGION },
    async (request): Promise<ModerateWithLocaleContextResponse> => {
        await requireAuthAndAppCheck(request.auth ?? null, request.app ?? null);

        const db = getFirestore();
        const data = request.data as ModerateWithLocaleContextRequest;

        // ── 1. Input validation ──────────────────────────────────────────────
        const content = requireNonEmptyString(data.content, "content", 50_000);
        const detectedLocales = requireStringArray(data.detectedLocales, "detectedLocales");
        const contentId = requireNonEmptyString(data.contentId, "contentId", 256);
        const contentType = requireNonEmptyString(data.contentType, "contentType", 64);

        if (detectedLocales.length === 0) {
            throw new HttpsError("invalid-argument", "detectedLocales must contain at least one locale.");
        }

        // ── 2. Load policy packs for every detected locale ───────────────────
        const packPromises = detectedLocales.map((locale) => loadPolicyPack(locale));
        const packs = (await Promise.all(packPromises)).filter(
            (p): p is LocalePolicyPack => p !== null
        );

        // ── 3. Merge vocabularies from all packs ─────────────────────────────
        const allSensitiveTopics: string[] = [];
        const allEscalationKeywords: string[] = [];

        for (const pack of packs) {
            allSensitiveTopics.push(...pack.sensitive_topics);
            allEscalationKeywords.push(...pack.escalation_keywords);
        }

        const normalizedContent = content.toLowerCase();

        // ── 4. Hard rule: any non-English locale → human review required ──────
        const hasNonEnglishLocale = detectedLocales.some(
            (locale) => locale !== FALLBACK_LOCALE && !locale.startsWith("en")
        );

        // ── 5. Keyword matching ───────────────────────────────────────────────
        const matchedSensitiveTopics = allSensitiveTopics.filter((topic) =>
            normalizedContent.includes(topic.toLowerCase())
        );

        const matchedEscalationKeywords = allEscalationKeywords.filter((kw) =>
            normalizedContent.includes(kw.toLowerCase())
        );

        // ── 6. Score & confidence simulation ─────────────────────────────────
        //      A simple heuristic: more sensitive-topic matches lower confidence.
        const baseConfidence = matchedSensitiveTopics.length === 0 ? 0.95 : 0.85;
        const confidencePenalty = Math.min(matchedSensitiveTopics.length * 0.08, 0.4);
        const confidence = Math.max(0, baseConfidence - confidencePenalty);

        // ── 7. Decision logic ─────────────────────────────────────────────────
        let decision: "approved" | "escalated" | "rejected";

        if (matchedEscalationKeywords.length > 0) {
            decision = "escalated";
        } else if (confidence < LOW_CONFIDENCE_THRESHOLD) {
            decision = "escalated";
        } else {
            decision = "approved";
        }

        const humanReviewRequired = hasNonEnglishLocale || decision === "escalated";

        // ── 8. Write /moderationEvents/{newId} ────────────────────────────────
        const eventRef = db.collection("moderationEvents").doc();
        const eventId = eventRef.id;

        const moderationEvent = {
            contentId,
            contentType,
            locales: detectedLocales,
            decision,
            confidence,
            reviewRequired: humanReviewRequired,
            matchedSensitiveTopics,
            matchedEscalationKeywords,
            createdAt: FieldValue.serverTimestamp(),
        };

        if (decision === "escalated") {
            // ── 9. Atomic batch: moderationEvent + safetyAuditLog entry ──────
            const auditRef = db.collection("safetyAuditLog").doc();

            const safetyAuditEntry = {
                contentId,
                contentType,
                locales: detectedLocales,
                reason: "locale_moderation_escalation",
                confidence,
                matchedSensitiveTopics,
                matchedEscalationKeywords,
                humanReviewRequired,
                eventId,
                createdAt: FieldValue.serverTimestamp(),
            };

            const batch = db.batch();
            batch.set(eventRef, moderationEvent);
            batch.set(auditRef, safetyAuditEntry);
            await batch.commit();

            logger.info("[moderateWithLocaleContext] Escalated — audit log written", {
                contentId,
                contentType,
                detectedLocales,
                confidence,
                matchedSensitiveTopics,
                matchedEscalationKeywords,
                eventId,
                auditId: auditRef.id,
            });
        } else {
            await eventRef.set(moderationEvent);

            logger.info("[moderateWithLocaleContext] Approved", {
                contentId,
                contentType,
                detectedLocales,
                confidence,
                eventId,
            });
        }

        return { decision, reviewRequired: humanReviewRequired, eventId };
    }
);

// ─── seedLocalePolicyPacks ────────────────────────────────────────────────────

interface SeedLocalePolicyPacksRequest {
    _confirm?: unknown;
}

interface SeedLocalePolicyPacksResponse {
    seeded: string[];
    skipped: string[];
}

/**
 * seedLocalePolicyPacks
 *
 * One-time idempotent seed that creates default LocalePolicyPack documents for
 * 10 locales. Requires an `admin` custom claim — will throw permission-denied
 * if the caller lacks this claim.
 *
 * Documents are created only when they do not already exist (set with merge:false
 * using batch.create so existing packs are never overwritten).
 *
 * Supported locales: en, es, fr, pt, yo, sw, zh, ko, hi, ar
 */
export const seedLocalePolicyPacks = onCall<SeedLocalePolicyPacksRequest, Promise<SeedLocalePolicyPacksResponse>>(
    { enforceAppCheck: true, region: REGION },
    async (request): Promise<SeedLocalePolicyPacksResponse> => {
        const callerUid = await requireAuthAndAppCheck(request.auth ?? null, request.app ?? null);

        // ── Require admin custom claim ────────────────────────────────────────
        const callerRecord = await admin.auth().getUser(callerUid);
        const claims = callerRecord.customClaims ?? {};
        if (claims["admin"] !== true) {
            throw new HttpsError(
                "permission-denied",
                "seedLocalePolicyPacks requires the admin custom claim."
            );
        }

        const db = getFirestore();

        // ── Default packs ─────────────────────────────────────────────────────
        const defaultPacks: LocalePolicyPack[] = [
            {
                locale_id: "en",
                sensitive_topics: [
                    "suicide",
                    "self-harm",
                    "abuse",
                    "violence",
                    "hate speech",
                    "explicit content",
                    "heresy",
                    "cult recruitment",
                    "false prophecy",
                    "financial exploitation",
                ],
                escalation_keywords: [],
                human_review_required: false,
                safety_threshold: 0.7,
            },
            {
                locale_id: "es",
                sensitive_topics: [
                    "suicidio",
                    "autolesión",
                    "abuso",
                    "violencia",
                    "discurso de odio",
                    "contenido explícito",
                    "herejía",
                    "reclutamiento de sectas",
                    "falsa profecía",
                    "explotación financiera",
                ],
                escalation_keywords: [],
                human_review_required: true,
                safety_threshold: 0.75,
            },
            {
                locale_id: "fr",
                sensitive_topics: [
                    "suicide",
                    "automutilation",
                    "abus",
                    "violence",
                    "discours haineux",
                    "contenu explicite",
                    "hérésie",
                    "recrutement sectaire",
                    "fausse prophétie",
                    "exploitation financière",
                ],
                escalation_keywords: [],
                human_review_required: true,
                safety_threshold: 0.75,
            },
            {
                locale_id: "pt",
                sensitive_topics: [
                    "suicídio",
                    "automutilação",
                    "abuso",
                    "violência",
                    "discurso de ódio",
                    "conteúdo explícito",
                    "heresia",
                    "recrutamento de seitas",
                    "falsa profecia",
                    "exploração financeira",
                ],
                escalation_keywords: [],
                human_review_required: true,
                safety_threshold: 0.75,
            },
            {
                locale_id: "yo",
                sensitive_topics: [
                    "igbẹmi ara ẹni",
                    "ipalara ara ẹni",
                    "ilokulo",
                    "iwa-ipa",
                    "ọrọ ikorira",
                    "ẹsẹ eke",
                    "asọtẹlẹ eke",
                    "jegudujera owo",
                    "egbe agabagebe",
                ],
                escalation_keywords: [],
                human_review_required: true,
                safety_threshold: 0.8,
            },
            {
                locale_id: "sw",
                sensitive_topics: [
                    "kujiua",
                    "kujidhuru",
                    "unyanyasaji",
                    "vurugu",
                    "chuki",
                    "maudhui ya ngono",
                    "uzushi",
                    "udanganyifu wa dini",
                    "unabii wa uongo",
                    "unyonyaji wa fedha",
                ],
                escalation_keywords: [],
                human_review_required: true,
                safety_threshold: 0.8,
            },
            {
                locale_id: "zh",
                sensitive_topics: [
                    "自杀",
                    "自残",
                    "虐待",
                    "暴力",
                    "仇恨言论",
                    "露骨内容",
                    "异端",
                    "邪教招募",
                    "假预言",
                    "财务剥削",
                ],
                escalation_keywords: [],
                human_review_required: true,
                safety_threshold: 0.8,
            },
            {
                locale_id: "ko",
                sensitive_topics: [
                    "자살",
                    "자해",
                    "학대",
                    "폭력",
                    "혐오 발언",
                    "성인 콘텐츠",
                    "이단",
                    "사이비 종교 모집",
                    "거짓 예언",
                    "재정적 착취",
                ],
                escalation_keywords: [],
                human_review_required: true,
                safety_threshold: 0.8,
            },
            {
                locale_id: "hi",
                sensitive_topics: [
                    "आत्महत्या",
                    "आत्म-नुकसान",
                    "दुर्व्यवहार",
                    "हिंसा",
                    "घृणास्पद भाषण",
                    "स्पष्ट सामग्री",
                    "विधर्म",
                    "पंथ भर्ती",
                    "झूठी भविष्यवाणी",
                    "वित्तीय शोषण",
                ],
                escalation_keywords: [],
                human_review_required: true,
                safety_threshold: 0.8,
            },
            {
                locale_id: "ar",
                sensitive_topics: [
                    "انتحار",
                    "إيذاء النفس",
                    "إساءة",
                    "عنف",
                    "خطاب كراهية",
                    "محتوى صريح",
                    "هرطقة",
                    "تجنيد طائفي",
                    "نبوة كاذبة",
                    "استغلال مالي",
                ],
                escalation_keywords: [],
                human_review_required: true,
                safety_threshold: 0.8,
            },
        ];

        // ── Check which docs already exist, then write missing ones ──────────
        const existingSnaps = await Promise.all(
            defaultPacks.map((pack) =>
                db.collection("localePolicyPacks").doc(pack.locale_id).get()
            )
        );

        const toCreate: LocalePolicyPack[] = [];
        const skipped: string[] = [];

        defaultPacks.forEach((pack, idx) => {
            if (existingSnaps[idx].exists) {
                skipped.push(pack.locale_id);
            } else {
                toCreate.push(pack);
            }
        });

        if (toCreate.length > 0) {
            const batch = db.batch();
            for (const pack of toCreate) {
                const ref = db.collection("localePolicyPacks").doc(pack.locale_id);
                batch.set(ref, {
                    ...pack,
                    created_at: FieldValue.serverTimestamp(),
                });
            }
            await batch.commit();
        }

        const seeded = toCreate.map((p) => p.locale_id);

        logger.info("[seedLocalePolicyPacks] Seed complete", {
            callerUid,
            seeded,
            skipped,
        });

        return { seeded, skipped };
    }
);

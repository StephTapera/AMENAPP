"use strict";
// capabilities/scripture/callables.ts — Scripture Intelligence callables (Wave 1: Lane B)
//
// scripture_detectReferences — auth required, no App Check (fast, free, used in Notes)
// scripture_getVerses        — auth required, App Check enforced (external API)
// scripture_searchVerses     — auth required, no App Check (UX search)
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
exports.scripture_searchVerses = exports.scripture_getVerses = exports.scripture_detectReferences = void 0;
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const params_1 = require("firebase-functions/params");
const referenceParser_1 = require("./referenceParser");
const API_BIBLE_KEY = (0, params_1.defineSecret)("API_BIBLE_KEY");
// API.Bible BSB bible ID (same as used in sanctuary/index.ts)
const BIBLE_IDS = {
    BSB: "de4e12af7f28f599-02",
    WEB: "9879dbb7cfe39e4d-04",
    KJV: "de4e12af7f28f599-01",
};
const VALID_TRANSLATIONS = ["BSB", "WEB", "KJV"];
const CACHE_TTL_MS = 90 * 24 * 60 * 60 * 1000; // 90 days
// ── Helpers ───────────────────────────────────────────────────────────────────
function requireAuth(request) {
    const uid = request.auth?.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Must be signed in.");
    return uid;
}
async function fetchVerseFromApiBible(osisRef, translation) {
    const key = API_BIBLE_KEY.value();
    if (!key) {
        logger.warn("[CAP/scripture] API_BIBLE_KEY not configured");
        return null;
    }
    const bibleId = BIBLE_IDS[translation] ?? BIBLE_IDS.BSB;
    const url = `https://api.scripture.api.bible/v1/bibles/${bibleId}/passages/${encodeURIComponent(osisRef)}?content-type=text&include-notes=false&include-titles=false&include-chapter-numbers=false&include-verse-numbers=false`;
    try {
        const response = await fetch(url, {
            headers: { "api-key": key },
        });
        if (!response.ok) {
            logger.warn("[CAP/scripture] API.Bible returned non-200", {
                osisRef,
                status: response.status,
            });
            return null;
        }
        const json = (await response.json());
        const raw = json.data?.content ?? "";
        // Strip HTML tags and normalize whitespace
        return raw.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim() || null;
    }
    catch (err) {
        logger.warn("[CAP/scripture] API.Bible fetch failed", { osisRef, error: String(err) });
        return null;
    }
}
function osisRefToDisplay(osisRef) {
    // Convert "Rom.6.1-Rom.6.4" → "Rom 6:1-4" style display
    // Simple conversion: replace dots with spaces/colons
    const parts = osisRef.split("-");
    if (parts.length === 1) {
        // Single ref: "Rom.6.1" → "Rom 6:1" or "Rom.6" → "Rom 6"
        const tokens = parts[0].split(".");
        if (tokens.length === 3)
            return `${tokens[0]} ${tokens[1]}:${tokens[2]}`;
        if (tokens.length === 2)
            return `${tokens[0]} ${tokens[1]}`;
        return parts[0];
    }
    // Range: "Rom.6.1-Rom.6.4"
    const startTokens = parts[0].split(".");
    const endTokens = parts[1].split(".");
    if (startTokens.length === 3 && endTokens.length === 3) {
        if (startTokens[0] === endTokens[0] && startTokens[1] === endTokens[1]) {
            // Same book + chapter
            return `${startTokens[0]} ${startTokens[1]}:${startTokens[2]}-${endTokens[2]}`;
        }
        // Cross-chapter
        return `${startTokens[0]} ${startTokens[1]}:${startTokens[2]}-${endTokens[1]}:${endTokens[2]}`;
    }
    return osisRef;
}
// ── scripture_detectReferences ────────────────────────────────────────────────
exports.scripture_detectReferences = (0, https_1.onCall)({ enforceAppCheck: false }, // fast, free, must work in Notes without App Check
async (request) => {
    requireAuth(request);
    const body = request.data;
    if (!Array.isArray(body.blocks) || body.blocks.length === 0) {
        throw new https_1.HttpsError("invalid-argument", "blocks must be a non-empty array.");
    }
    if (body.blocks.length > 50) {
        throw new https_1.HttpsError("invalid-argument", "blocks must not exceed 50 items.");
    }
    for (let i = 0; i < body.blocks.length; i++) {
        const block = body.blocks[i];
        if (!block || typeof block.blockId !== "string" || typeof block.text !== "string") {
            throw new https_1.HttpsError("invalid-argument", `blocks[${i}] must have blockId and text strings.`);
        }
    }
    logger.info("[CAP/scripture] detectReferences", { blockCount: body.blocks.length });
    const rawDetections = (0, referenceParser_1.detectReferencesInBlocks)(body.blocks);
    // Flatten range: { start, end } → range_start / range_end
    // The frozen Swift contract (CapabilityModels.swift CodingKeys) expects
    // top-level snake_case keys, not a nested range object.
    const detections = rawDetections.map((d) => ({
        blockId: d.blockId,
        range_start: d.range.start,
        range_end: d.range.end,
        osisRef: d.osisRef,
        display: d.display,
    }));
    return { detections };
});
// ── scripture_getVerses ───────────────────────────────────────────────────────
exports.scripture_getVerses = (0, https_1.onCall)({
    enforceAppCheck: true,
    secrets: [API_BIBLE_KEY],
}, async (request) => {
    requireAuth(request);
    const body = request.data;
    if (!Array.isArray(body.osisRefs) || body.osisRefs.length === 0) {
        throw new https_1.HttpsError("invalid-argument", "osisRefs must be a non-empty array.");
    }
    if (body.osisRefs.length > 20) {
        throw new https_1.HttpsError("invalid-argument", "osisRefs must not exceed 20 items.");
    }
    const translation = body.translation && VALID_TRANSLATIONS.includes(body.translation)
        ? body.translation
        : "BSB";
    logger.info("[CAP/scripture] getVerses", {
        refCount: body.osisRefs.length,
        translation,
    });
    const db = (0, firestore_1.getFirestore)();
    const verses = [];
    for (const osisRef of body.osisRefs) {
        if (typeof osisRef !== "string" || !osisRef)
            continue;
        // Check cache first
        const cacheRef = db.doc(`scriptureCache/${translation}/${osisRef}`);
        const cacheSnap = await cacheRef.get();
        if (cacheSnap.exists) {
            const cacheData = cacheSnap.data();
            // Check expiry
            const expiresAt = cacheData.expiresAt;
            if (expiresAt && expiresAt.toMillis() > Date.now()) {
                verses.push({
                    osisRef,
                    text: cacheData.text ?? "",
                    translation,
                    display: cacheData.display ?? osisRefToDisplay(osisRef),
                });
                continue;
            }
        }
        // Cache miss or expired — fetch from API.Bible
        const text = await fetchVerseFromApiBible(osisRef, translation);
        const display = osisRefToDisplay(osisRef);
        if (text) {
            const now = Date.now();
            // Cache the result for 90 days
            await cacheRef.set({
                text,
                translation,
                osisRef,
                display,
                cachedAt: firestore_1.FieldValue.serverTimestamp(),
                expiresAt: firestore_1.Timestamp.fromMillis(now + CACHE_TTL_MS),
            });
        }
        verses.push({
            osisRef,
            text: text ?? `[Verse text not available for ${osisRef}]`,
            translation,
            display,
        });
    }
    return { verses };
});
// ── scripture_searchVerses ────────────────────────────────────────────────────
exports.scripture_searchVerses = (0, https_1.onCall)({ enforceAppCheck: false }, async (request) => {
    requireAuth(request);
    const body = request.data;
    const query = String(body.query ?? "").trim();
    if (!query || query.length > 200) {
        throw new https_1.HttpsError("invalid-argument", "query must be 1-200 chars.");
    }
    const rawLimit = Number(body.limit ?? 5);
    const limit = Math.min(Math.max(1, rawLimit), 10);
    logger.info("[CAP/scripture] searchVerses", { queryLength: query.length, limit });
    const db = (0, firestore_1.getFirestore)();
    // First: try to parse query as a direct scripture reference
    const directRefs = (0, referenceParser_1.parseRefs)(query);
    if (directRefs.length > 0) {
        // It's a direct reference — look up the verses
        const translation = "BSB";
        const results = [];
        for (const ref of directRefs.slice(0, limit)) {
            // Check cache
            const cacheRef = db.doc(`scriptureCache/${translation}/${ref.osisRef}`);
            const cacheSnap = await cacheRef.get();
            let text = null;
            if (cacheSnap.exists) {
                const expiresAt = cacheSnap.data()?.expiresAt;
                if (expiresAt && expiresAt.toMillis() > Date.now()) {
                    text = cacheSnap.data()?.text ?? null;
                }
            }
            if (!text) {
                text = await fetchVerseFromApiBible(ref.osisRef, translation);
                if (text) {
                    await cacheRef.set({
                        text,
                        translation,
                        osisRef: ref.osisRef,
                        display: ref.display,
                        cachedAt: firestore_1.FieldValue.serverTimestamp(),
                        expiresAt: firestore_1.Timestamp.fromMillis(Date.now() + CACHE_TTL_MS),
                    });
                }
            }
            results.push({
                osisRef: ref.osisRef,
                display: ref.display,
                snippet: (text ?? `[${ref.display} — verse text not available]`).slice(0, 120),
            });
        }
        return { results };
    }
    // Not a direct reference — keyword search.
    // Try scriptureCatalog collection if it exists.
    const catalogSnap = await db
        .collection("scriptureCatalog")
        .limit(1)
        .get();
    if (!catalogSnap.empty) {
        // scriptureCatalog exists — do simple keyword search
        const queryLower = query.toLowerCase();
        const keywords = queryLower.split(/\s+/).filter((k) => k.length > 2);
        if (keywords.length === 0) {
            return { results: [] };
        }
        // Firestore doesn't support full-text search, so we fetch a reasonable
        // sample and filter client-side. This is a degraded path; production
        // should use Algolia/Pinecone.
        const allSnap = await db
            .collection("scriptureCatalog")
            .limit(200)
            .get();
        const scored = [];
        for (const doc of allSnap.docs) {
            const data = doc.data();
            const textLower = String(data.text ?? "").toLowerCase();
            const hits = keywords.filter((kw) => textLower.includes(kw)).length;
            if (hits > 0) {
                scored.push({ doc: data, score: hits / keywords.length, id: doc.id });
            }
        }
        scored.sort((a, b) => b.score - a.score);
        const results = scored.slice(0, limit).map((item) => ({
            osisRef: item.doc.osisRef ?? item.id,
            display: item.doc.display ?? osisRefToDisplay(item.doc.osisRef ?? item.id),
            snippet: String(item.doc.text ?? "").slice(0, 120),
        }));
        return { results };
    }
    // No scriptureCatalog and not a direct reference — return empty with note
    logger.info("[CAP/scripture] searchVerses: no catalog index and query is not a reference", { query });
    return { results: [] };
});

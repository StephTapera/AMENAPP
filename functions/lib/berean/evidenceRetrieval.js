"use strict";
/**
 * berean/evidenceRetrieval.ts — Retrieval Layer (Layer 2)
 * Berean Trust Architecture · Layer 2 · Version: v1
 *
 * Responsibilities:
 *   1. Retrieve scripture chunks via API.Bible (scripture.api.bible)
 *   2. Retrieve theology corpus chunks from Firestore "bereanTheologyCorpus"
 *   3. Retrieve church data from Firestore "churches"
 *   4. Retrieve user-specific notes and saved verses (authenticated only)
 *   5. Fan-out retrieval in parallel based on intentClasses
 *   6. Deduplicate, sort by score, return top maxChunks
 *
 * Feature flag gate: featureFlags/trustArchitecture → evidenceRetrieval === true
 * All API keys sourced from process.env (Firebase secrets) — never hard-coded.
 *
 * NOTE: Pinecone is not in package.json. Vector similarity search falls back to
 * Firestore keyword/field matching. To enable semantic search install
 * @pinecone-database/pinecone and swap retrieveScripture's inner implementation.
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.retrieveScripture = retrieveScripture;
exports.retrieveTheology = retrieveTheology;
exports.retrieveChurchData = retrieveChurchData;
exports.retrieveUserData = retrieveUserData;
exports.retrieveEvidence = retrieveEvidence;
const axios_1 = __importDefault(require("axios"));
// ── CONSTANTS ─────────────────────────────────────────────────────────────────
const DEFAULT_MAX_CHUNKS = 10;
const SCRIPTURE_MAX = 5;
const THEOLOGY_MAX = 3;
const CHURCH_MAX = 3;
const USER_NOTES_MAX = 3;
const USER_VERSES_MAX = 3;
/** Bible IDs used by API.Bible for BSB, WEB, KJV respectively. */
const TRANSLATION_IDS = {
    BSB: "bba9f40183526463-01", // Berean Standard Bible
    WEB: "9879dbb7cfe39e4d-04", // World English Bible
    KJV: "de4e12af7f28f599-02", // King James Version
};
// ── HELPER: sanitise Firestore field path query words ─────────────────────────
/**
 * Split a free-text query into lowercase words suitable for Firestore keyword
 * matching. Strips punctuation, removes stop-words, limits to 5 tokens to stay
 * within Firestore composite-query limits.
 */
function queryWords(query) {
    const stopWords = new Set(["the", "a", "an", "is", "in", "of", "and", "or", "to", "for"]);
    return query
        .toLowerCase()
        .replace(/[^a-z0-9\s]/g, " ")
        .split(/\s+/)
        .filter((w) => w.length > 1 && !stopWords.has(w))
        .slice(0, 5);
}
// ── RETRIEVER 1: SCRIPTURE via API.Bible ──────────────────────────────────────
/**
 * retrieveScripture — searches API.Bible for query across provided translations.
 * Returns up to SCRIPTURE_MAX chunks, scored by result position (first = highest).
 */
async function retrieveScripture(query, translations = ["BSB", "WEB", "KJV"]) {
    const apiKey = process.env.BIBLE_API_KEY;
    if (!apiKey) {
        console.warn("retrieveScripture: BIBLE_API_KEY is not set — returning empty");
        return [];
    }
    const chunks = [];
    const seen = new Set();
    for (const translation of translations) {
        if (chunks.length >= SCRIPTURE_MAX)
            break;
        const bibleId = TRANSLATION_IDS[translation];
        if (!bibleId) {
            console.warn(`retrieveScripture: unknown translation "${translation}" — skipping`);
            continue;
        }
        try {
            const response = await axios_1.default.get("https://api.scripture.api.bible/v1/bibles/" + bibleId + "/search", {
                headers: { "api-key": apiKey },
                params: {
                    query,
                    limit: SCRIPTURE_MAX,
                    sort: "relevance",
                },
                timeout: 8000,
            });
            // API.Bible search response shape:
            // { data: { verses: [{ id, orgId, bibleId, bookId, chapterId, verseCount, reference, text }] } }
            const verses = response.data?.data?.verses ?? response.data?.data?.passages ?? [];
            for (const verse of verses) {
                if (chunks.length >= SCRIPTURE_MAX)
                    break;
                const chunkId = `scripture-${verse.id ?? verse.reference}-${translation}`;
                if (seen.has(chunkId))
                    continue;
                seen.add(chunkId);
                const rawText = typeof verse.text === "string"
                    ? verse.text.replace(/<[^>]+>/g, "").trim() // strip HTML tags
                    : String(verse.text ?? "");
                // Score descends by insertion order within a translation; cross-translation
                // ordering puts BSB first (most accurate for Christian formation context).
                const translationBonus = translations.indexOf(translation) === 0 ? 0.1 : 0;
                const positionScore = 1.0 - (chunks.length * 0.05) + translationBonus;
                chunks.push({
                    chunkId,
                    source: "scripture",
                    content: rawText,
                    citation: `${verse.reference} (${translation})`,
                    retrievalScore: Math.min(Math.max(positionScore, 0.1), 1.0),
                    metadata: {
                        translation,
                        bibleId,
                        verseId: verse.id ?? "",
                        bookId: verse.bookId ?? "",
                        chapterId: verse.chapterId ?? "",
                    },
                });
            }
        }
        catch (err) {
            // Non-fatal: log and continue with next translation.
            console.warn(`retrieveScripture: error fetching ${translation} —`, err instanceof Error ? err.message : String(err));
        }
    }
    return chunks;
}
// ── RETRIEVER 2: THEOLOGY CORPUS via Firestore ────────────────────────────────
/**
 * retrieveTheology — keyword-searches Firestore "bereanTheologyCorpus".
 * Expected document fields: title, content, source, denomination, relevance (number).
 * Returns up to THEOLOGY_MAX chunks.
 */
async function retrieveTheology(query, db) {
    const chunks = [];
    try {
        // Primary: order by numeric relevance field, let Firestore return top docs.
        // The calling indexer is expected to pre-compute `relevance` during ingest.
        const snap = await db
            .collection("bereanTheologyCorpus")
            .orderBy("relevance", "desc")
            .limit(THEOLOGY_MAX * 4) // over-fetch then client-filter by keyword presence
            .get();
        if (snap.empty)
            return chunks;
        const words = queryWords(query);
        const scoredDocs = [];
        for (const doc of snap.docs) {
            const data = doc.data();
            const haystack = [
                String(data["title"] ?? ""),
                String(data["content"] ?? ""),
                String(data["source"] ?? ""),
                String(data["denomination"] ?? ""),
            ]
                .join(" ")
                .toLowerCase();
            // Simple TF-style score: count keyword hits / total keywords
            const hitCount = words.filter((w) => haystack.includes(w)).length;
            const baseRelevance = typeof data["relevance"] === "number" ? data["relevance"] : 0.5;
            const score = words.length > 0
                ? (hitCount / words.length) * 0.6 + baseRelevance * 0.4
                : baseRelevance;
            scoredDocs.push({ score, doc });
        }
        scoredDocs
            .sort((a, b) => b.score - a.score)
            .slice(0, THEOLOGY_MAX)
            .forEach(({ score, doc }) => {
            const data = doc.data();
            const title = String(data["title"] ?? doc.id);
            const source = String(data["source"] ?? "Unknown Source");
            chunks.push({
                chunkId: `theology-${doc.id}`,
                source: "theology",
                content: String(data["content"] ?? ""),
                citation: `${title} — ${source}`,
                retrievalScore: Math.min(Math.max(score, 0.1), 1.0),
                metadata: {
                    docId: doc.id,
                    title,
                    source,
                    denomination: data["denomination"] ?? "",
                },
            });
        });
    }
    catch (err) {
        console.warn("retrieveTheology: Firestore error —", err instanceof Error ? err.message : String(err));
    }
    return chunks;
}
// ── RETRIEVER 3: CHURCH DATA via Firestore ────────────────────────────────────
/**
 * retrieveChurchData — searches Firestore "churches" by matching name_lower
 * against words in the query. Returns up to CHURCH_MAX chunks.
 *
 * Expected document fields: name, name_lower, denomination, city, state, website.
 */
async function retrieveChurchData(query, userId, db) {
    const chunks = [];
    const words = queryWords(query);
    if (words.length === 0)
        return chunks;
    // Firestore doesn't support full-text; use >= / < range on the first keyword
    // and client-filter for subsequent words.
    const primaryWord = words[0];
    try {
        const snap = await db
            .collection("churches")
            .where("name_lower", ">=", primaryWord)
            .where("name_lower", "<=", primaryWord + "")
            .limit(CHURCH_MAX * 4)
            .get();
        const remainingWords = words.slice(1);
        const scored = [];
        for (const doc of snap.docs) {
            const data = doc.data();
            const nameLower = String(data["name_lower"] ?? "");
            const haystack = [
                nameLower,
                String(data["denomination"] ?? ""),
                String(data["city"] ?? ""),
                String(data["state"] ?? ""),
            ]
                .join(" ")
                .toLowerCase();
            const hitCount = remainingWords.filter((w) => haystack.includes(w)).length;
            const score = words.length > 1 ? (1 + hitCount) / words.length : 1.0;
            scored.push({ score, doc });
        }
        scored
            .sort((a, b) => b.score - a.score)
            .slice(0, CHURCH_MAX)
            .forEach(({ score, doc }) => {
            const data = doc.data();
            const name = String(data["name"] ?? doc.id);
            const city = String(data["city"] ?? "");
            const state = String(data["state"] ?? "");
            const denomination = String(data["denomination"] ?? "");
            const locationStr = [city, state].filter(Boolean).join(", ");
            const citation = [name, denomination, locationStr].filter(Boolean).join(" · ");
            chunks.push({
                chunkId: `church-${doc.id}`,
                source: "church",
                content: [
                    `Name: ${name}`,
                    denomination ? `Denomination: ${denomination}` : "",
                    locationStr ? `Location: ${locationStr}` : "",
                    data["website"] ? `Website: ${data["website"]}` : "",
                ]
                    .filter(Boolean)
                    .join("\n"),
                citation,
                retrievalScore: Math.min(Math.max(score, 0.1), 1.0),
                metadata: {
                    churchId: doc.id,
                    name,
                    denomination,
                    city,
                    state,
                    website: data["website"] ?? "",
                    requestingUserId: userId,
                },
            });
        });
    }
    catch (err) {
        console.warn("retrieveChurchData: Firestore error —", err instanceof Error ? err.message : String(err));
    }
    return chunks;
}
// ── RETRIEVER 4: USER DATA via Firestore ──────────────────────────────────────
/**
 * retrieveUserData — fetches the authenticated user's berean notes and saved
 * verses. Returns empty array if userId is absent (unauthenticated caller).
 *
 * Paths:
 *   users/{userId}/bereanNotes    — fields: content, title, timestamp
 *   users/{userId}/savedVerses    — fields: text, reference, translation, savedAt
 */
async function retrieveUserData(query, userId, db) {
    // CRITICAL: only retrieve if userId is authenticated (non-empty)
    if (!userId || userId.trim() === "") {
        return [];
    }
    const chunks = [];
    const words = queryWords(query);
    // Helper: score a document's text against query words.
    function keywordScore(haystack) {
        if (words.length === 0)
            return 0.5;
        const lower = haystack.toLowerCase();
        const hits = words.filter((w) => lower.includes(w)).length;
        return hits / words.length;
    }
    try {
        // Fetch berean notes (most recent first)
        const notesSnap = await db
            .collection("users")
            .doc(userId)
            .collection("bereanNotes")
            .orderBy("timestamp", "desc")
            .limit(USER_NOTES_MAX * 3)
            .get();
        const scoredNotes = [];
        for (const doc of notesSnap.docs) {
            const data = doc.data();
            const haystack = [
                String(data["title"] ?? ""),
                String(data["content"] ?? ""),
            ].join(" ");
            scoredNotes.push({ score: keywordScore(haystack), doc });
        }
        scoredNotes
            .sort((a, b) => b.score - a.score)
            .slice(0, USER_NOTES_MAX)
            .forEach(({ score, doc }) => {
            const data = doc.data();
            const title = String(data["title"] ?? "Berean Note");
            const content = String(data["content"] ?? "");
            chunks.push({
                chunkId: `userData-note-${userId}-${doc.id}`,
                source: "userData",
                content,
                citation: `Your note: "${title}"`,
                retrievalScore: Math.min(Math.max(score, 0.1), 1.0),
                metadata: {
                    type: "bereanNote",
                    noteId: doc.id,
                    title,
                    userId,
                    timestamp: data["timestamp"] ?? null,
                },
            });
        });
    }
    catch (err) {
        console.warn("retrieveUserData/bereanNotes: Firestore error —", err instanceof Error ? err.message : String(err));
    }
    try {
        // Fetch saved verses
        const versesSnap = await db
            .collection("users")
            .doc(userId)
            .collection("savedVerses")
            .limit(USER_VERSES_MAX * 3)
            .get();
        const scoredVerses = [];
        for (const doc of versesSnap.docs) {
            const data = doc.data();
            const haystack = [
                String(data["text"] ?? ""),
                String(data["reference"] ?? ""),
            ].join(" ");
            scoredVerses.push({ score: keywordScore(haystack), doc });
        }
        scoredVerses
            .sort((a, b) => b.score - a.score)
            .slice(0, USER_VERSES_MAX)
            .forEach(({ score, doc }) => {
            const data = doc.data();
            const reference = String(data["reference"] ?? "");
            const translation = String(data["translation"] ?? "");
            const text = String(data["text"] ?? "");
            const citation = translation
                ? `${reference} (${translation}) — Saved verse`
                : `${reference} — Saved verse`;
            chunks.push({
                chunkId: `userData-verse-${userId}-${doc.id}`,
                source: "userData",
                content: text,
                citation,
                retrievalScore: Math.min(Math.max(score, 0.1), 1.0),
                metadata: {
                    type: "savedVerse",
                    verseId: doc.id,
                    reference,
                    translation,
                    userId,
                    savedAt: data["savedAt"] ?? null,
                },
            });
        });
    }
    catch (err) {
        console.warn("retrieveUserData/savedVerses: Firestore error —", err instanceof Error ? err.message : String(err));
    }
    return chunks;
}
// ── MAIN EXPORT: retrieveEvidence ─────────────────────────────────────────────
/**
 * retrieveEvidence — fan-out retrieval entry point.
 *
 * Routing logic:
 *   - 'Bible' in intentClasses  → retrieveScripture
 *   - 'Church' in intentClasses → retrieveChurchData
 *   - 'Theology' in intentClasses → retrieveTheology
 *   - any intent, userId present → retrieveUserData (always included when authenticated)
 *
 * Post-processing: deduplicate by chunkId, sort by retrievalScore desc,
 * return top maxChunks (default 10).
 *
 * Feature flag gate: Firestore "featureFlags/trustArchitecture" → evidenceRetrieval === true.
 * Returns empty chunks (not an error) if the flag is off.
 */
async function retrieveEvidence(req, db) {
    const startMs = performance.now();
    // ── 1. Feature flag gate ────────────────────────────────────────────────────
    try {
        const flagSnap = await db.doc("featureFlags/trustArchitecture").get();
        const flags = flagSnap.exists ? (flagSnap.data() ?? {}) : {};
        if (flags["evidenceRetrieval"] !== true) {
            return { chunks: [], retrievalMs: Math.round(performance.now() - startMs) };
        }
    }
    catch (err) {
        // If we can't read the flag, fail open for retrieval (non-safety path).
        console.warn("retrieveEvidence: could not read feature flag —", err instanceof Error ? err.message : String(err));
    }
    const { query, intentClasses, userId, maxChunks = DEFAULT_MAX_CHUNKS } = req;
    const intentsLower = intentClasses.map((i) => i.toLowerCase());
    // ── 2. Build the set of retriever promises to fan out ───────────────────────
    const retrievalPromises = [];
    const wantsBible = intentsLower.some((i) => i.includes("bible") || i === "scripture");
    const wantsChurch = intentsLower.some((i) => i.includes("church") || i === "church");
    const wantsTheology = intentsLower.some((i) => i.includes("theolog") || i === "theology" || i === "doctrine");
    if (wantsBible) {
        retrievalPromises.push(retrieveScripture(query, ["BSB", "WEB", "KJV"]));
    }
    if (wantsChurch) {
        retrievalPromises.push(retrieveChurchData(query, userId, db));
    }
    if (wantsTheology) {
        retrievalPromises.push(retrieveTheology(query, db));
    }
    // Always include user data when an authenticated userId is present
    if (userId && userId.trim() !== "") {
        retrievalPromises.push(retrieveUserData(query, userId, db));
    }
    // ── 3. Fan out in parallel ──────────────────────────────────────────────────
    // Use allSettled so one failing retriever never blocks the others.
    const results = await Promise.allSettled(retrievalPromises);
    // ── 4. Collect, deduplicate, sort, truncate ─────────────────────────────────
    const allChunks = [];
    const seenIds = new Set();
    for (const result of results) {
        if (result.status === "fulfilled") {
            for (const chunk of result.value) {
                if (!seenIds.has(chunk.chunkId)) {
                    seenIds.add(chunk.chunkId);
                    allChunks.push(chunk);
                }
            }
        }
        else {
            console.warn("retrieveEvidence: a retriever rejected —", result.reason instanceof Error
                ? result.reason.message
                : String(result.reason));
        }
    }
    allChunks.sort((a, b) => b.retrievalScore - a.retrievalScore);
    const topChunks = allChunks.slice(0, maxChunks);
    const retrievalMs = Math.round(performance.now() - startMs);
    return { chunks: topChunks, retrievalMs };
}

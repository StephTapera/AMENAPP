"use strict";
/**
 * onPostCreated.ts
 *
 * 5.3 HIGH FIX: Post creation finalizer.
 *
 * WHY THIS EXISTS:
 *   Posts written directly from the client skip content moderation entirely.
 *   Any authenticated user can publish a post with arbitrary text without
 *   server-side review. There is also no server-authoritative status transition,
 *   meaning the client controls whether a post is "published".
 *
 * WHAT THIS DOES:
 *   1. Text moderation — detects prohibited content patterns. Zero-tolerance
 *      categories (CSAM keywords) immediately hold the post and suspend the
 *      author. Non-zero-tolerance categories queue for human review and still
 *      publish with a "flagged_published" status.
 *   2. Status transition — transitions status from 'publishing' → 'published'
 *      (or 'flagged_published') and stamps publishedAt via server timestamp.
 *      Clients should write status: 'publishing'; this function completes
 *      the transition, preventing clients from self-asserting 'published'.
 *   3. Algolia indexing — indexes the post in the "posts" Algolia index so
 *      it is immediately discoverable in search. Uses the same ALGOLIA_APP_ID
 *      and ALGOLIA_ADMIN_KEY secret as deleteAlgoliaUser.ts.
 *
 * Feed fanout for followers-only posts is already handled by the
 * onPostCreateFeed trigger in feedBuilder.ts.
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
exports.finalizePostOnCreate = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const v2_1 = require("firebase-functions/v2");
const params_1 = require("firebase-functions/params");
const admin = __importStar(require("firebase-admin"));
const db = admin.firestore();
// ─── Constants ────────────────────────────────────────────────────────────────
// Must match the App ID in deleteAlgoliaUser.ts and AlgoliaConfig.swift.
const ALGOLIA_APP_ID = "182SCN7O9S";
const ALGOLIA_WRITE_KEY_SECRET = "ALGOLIA_ADMIN_KEY";
const algoliaAdminKey = (0, params_1.defineSecret)(ALGOLIA_WRITE_KEY_SECRET);
// ─── Text Moderation ─────────────────────────────────────────────────────────
//
// Server-side prohibited pattern detection. Each entry has:
//   category   — label written to the moderation queue and post document
//   patterns   — list of RegExp patterns; any match triggers the entry
//   autoBan    — true = hold post + suspend account; false = flag + queue only
//
// This is a first-pass heuristic layer. For production, supplement with:
//   - Cloud Natural Language API content classification
//   - OpenAI moderation endpoint (for posts with images, use mediaScanning.ts)
//
const PROHIBITED_PATTERNS = [
    {
        // Zero-tolerance: CSAM keywords — immediate hold + account suspension
        category: "csam_keywords",
        patterns: [
            /\bcsam\b/i,
            /\bchild.?porn/i,
            /\bchild.?exploit/i,
            /\bloli\b/i,
        ],
        autoBan: true,
    },
    {
        // Hate speech — flagged, queued for human review, still published
        category: "hate_speech",
        patterns: [
            /\bn[i1]gg[ae3]r\b/i,
            /\bk[i1]ke\b/i,
            /\bfagg[o0]t\b/i,
        ],
        autoBan: false,
    },
    {
        // Self-harm / crisis language — flagged, queued for pastoral/crisis review
        category: "self_harm",
        patterns: [
            /\bwant.{0,10}(to\s+)?kill\s+(my\s*self|myself)\b/i,
            /\bsuic[i1]de\b/i,
            /\bend\s+(my\s+)?life\b/i,
        ],
        autoBan: false,
    },
];
function runTextModeration(text) {
    for (const entry of PROHIBITED_PATTERNS) {
        for (const pattern of entry.patterns) {
            if (pattern.test(text)) {
                return { flagged: true, category: entry.category, autoBan: entry.autoBan };
            }
        }
    }
    return { flagged: false, category: null, autoBan: false };
}
// ─── Algolia Helpers ──────────────────────────────────────────────────────────
async function getAlgoliaAdminKey() {
    const key = algoliaAdminKey.value();
    return key || null;
}
async function algoliaIndexPost(postId, record, adminKey) {
    const url = `https://${ALGOLIA_APP_ID}.algolia.net/1/indexes/posts/${encodeURIComponent(postId)}`;
    const response = await fetch(url, {
        method: "PUT",
        headers: {
            "X-Algolia-Application-Id": ALGOLIA_APP_ID,
            "X-Algolia-API-Key": adminKey,
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ ...record, objectID: postId }),
    });
    if (!response.ok) {
        const body = await response.text();
        throw new Error(`Algolia PUT posts/${postId} failed: ${response.status} ${body}`);
    }
}
// ─── Trigger ──────────────────────────────────────────────────────────────────
exports.finalizePostOnCreate = (0, firestore_1.onDocumentCreated)({ document: "posts/{postId}", secrets: [algoliaAdminKey] }, async (event) => {
    const postId = event.params.postId;
    const snap = event.data;
    if (!snap)
        return;
    const data = snap.data();
    if (!data) {
        v2_1.logger.error(`[onPostCreated] Empty snapshot for post ${postId}`);
        return;
    }
    const authorId = data.authorId ?? "";
    // Support both 'content' (new schema) and 'text' (legacy schema) fields.
    const content = data.content ?? data.text ?? "";
    if (!authorId) {
        v2_1.logger.warn(`[onPostCreated] Post ${postId} has no authorId — skipping`);
        return;
    }
    // ── 1. Text moderation ────────────────────────────────────────────────
    const modResult = runTextModeration(content);
    if (modResult.flagged) {
        v2_1.logger.warn(`[onPostCreated] Post ${postId} by ${authorId} flagged — ` +
            `category=${modResult.category}, autoBan=${modResult.autoBan}`);
        if (modResult.autoBan) {
            // Zero-tolerance: hold the post and suspend the account.
            // A human reviewer must explicitly re-enable the account.
            try {
                await db.collection("posts").doc(postId).update({
                    status: "moderation_hold",
                    moderationCategory: modResult.category,
                    moderationHeldAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
            catch (e) {
                v2_1.logger.error(`[onPostCreated] Failed to hold post ${postId}`, e);
            }
            await db.collection("moderationQueue").add({
                type: "post_text_auto_ban",
                postId,
                authorId,
                category: modResult.category,
                priority: "immediate",
                policyVersion: "2026-04-16",
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            try {
                await admin.auth().updateUser(authorId, { disabled: true });
                v2_1.logger.warn(`[onPostCreated] Author ${authorId} suspended — post ${postId} ` +
                    `matched category=${modResult.category}`);
            }
            catch (e) {
                v2_1.logger.error(`[onPostCreated] Failed to suspend author ${authorId}`, e);
            }
            // Do not publish or index the post.
            return;
        }
        // Non-zero-tolerance: queue for human review, continue to publish.
        await db.collection("moderationQueue").add({
            type: "post_text_flagged",
            postId,
            authorId,
            category: modResult.category,
            priority: modResult.category === "self_harm" ? "high" : "standard",
            policyVersion: "2026-04-16",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
    // ── 2. Status transition: publishing → published ───────────────────────
    //
    // Clients should write the post with status: 'publishing'. This function
    // is the sole server-authoritative path to status: 'published'.
    // Posts already written as 'published' by legacy clients also receive
    // the publishedAt timestamp if missing.
    const currentStatus = data.status ?? "published";
    const finalStatus = modResult.flagged ? "flagged_published" : "published";
    if (currentStatus === "publishing" || !data.publishedAt) {
        try {
            await db.collection("posts").doc(postId).update({
                status: finalStatus,
                publishedAt: admin.firestore.FieldValue.serverTimestamp(),
                ...(modResult.category ? { moderationCategory: modResult.category } : {}),
            });
        }
        catch (e) {
            v2_1.logger.error(`[onPostCreated] Failed to update status for post ${postId}`, e);
        }
    }
    // ── 3. Algolia indexing ───────────────────────────────────────────────
    //
    // Only index posts that passed moderation (not auto-banned, not on hold).
    // Flagged-but-published posts are indexed with a "flagged" tag so they
    // can be filtered out of public search results if needed.
    const algoliaKey = await getAlgoliaAdminKey();
    if (algoliaKey) {
        const record = {
            postId,
            authorId,
            // Cap indexed content to keep Algolia record size manageable.
            // Full content is available via Firestore; Algolia is search-only.
            content: content.slice(0, 500),
            category: data.category ?? null,
            topicTag: data.topicTag ?? null,
            visibility: data.visibility ?? "everyone",
            isPublic: (data.visibility ?? "everyone") === "everyone",
            createdAt: data.createdAt
                ? data.createdAt.toMillis?.() ?? Date.now()
                : Date.now(),
            _tags: modResult.flagged ? ["flagged"] : [],
        };
        try {
            await algoliaIndexPost(postId, record, algoliaKey);
            v2_1.logger.info(`[onPostCreated] Indexed post ${postId} in Algolia`);
        }
        catch (e) {
            // Non-fatal: Algolia failure does not block post publication.
            // The post is live in Firestore; it will be missing from search
            // until a re-index job runs. Log for ops monitoring.
            v2_1.logger.error(`[onPostCreated] Algolia index failed for post ${postId} — ` +
                `search unavailable for this post until re-indexed`, e);
        }
    }
    else {
        v2_1.logger.warn(`[onPostCreated] ${ALGOLIA_WRITE_KEY_SECRET} not configured — ` +
            `post ${postId} not indexed. Set it with: ` +
            `firebase functions:secrets:set ${ALGOLIA_WRITE_KEY_SECRET}`);
    }
    v2_1.logger.info(`[onPostCreated] Finalized post ${postId} — ` +
        `status=${finalStatus}, flagged=${modResult.flagged}, category=${modResult.category}`);
});
//# sourceMappingURL=onPostCreated.js.map
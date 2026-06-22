"use strict";
/**
 * Berean Trust Architecture — Firebase Callable Exports
 * Layer 1–6 pipeline wired as HTTPS callables (gen-2).
 *
 * All callables require Firebase Auth. App Check is enforced (failOpen: false)
 * on the pipeline callable; other callables carry the same posture via options.
 *
 * Feature flag document: featureFlags/trustArchitecture
 * Firestore collections: see firestore.rules §bereanTrustArchitecture block
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
exports.verifyScriptureText = exports.bereanRunEvals = exports.bereanSubmitFeedback = exports.bereanDeleteAllMemory = exports.bereanUpdateMemory = exports.bereanToggleMemoryLock = exports.bereanDeleteMemory = exports.bereanGetMemory = exports.bereanConstitutionalPipeline = void 0;
const functions = __importStar(require("firebase-functions/v2/https"));
const admin = __importStar(require("firebase-admin"));
const constitutionalPipeline_1 = require("./constitutionalPipeline");
const memoryStore_1 = require("./memoryStore");
const feedbackCapture_1 = require("./feedbackCapture");
const evalFramework_1 = require("./evalFramework");
const evalTestCases_1 = require("./evalTestCases");
const db = admin.firestore();
// ── Feature flag helper ────────────────────────────────────────────────────────
async function isFlagEnabled(flag) {
    const doc = await db.doc('featureFlags/trustArchitecture').get();
    return doc.data()?.[flag] === true;
}
// ── 1. bereanConstitutionalPipeline ───────────────────────────────────────────
// Runs the full 7-stage constitutional pipeline for a user query.
// Requires: auth, App Check enforced.
// Input:  { query: string, sessionId: string, mode?: string, conversationHistory?: object[] }
// Output: { response: string, traceId: string, trustScore?: number }
exports.bereanConstitutionalPipeline = functions.onCall({
    enforceAppCheck: true,
    region: 'us-east1',
    secrets: ['ANTHROPIC_API_KEY', 'GEMINI_API_KEY', 'BIBLE_API_KEY'],
}, async (request) => {
    if (!request.auth) {
        throw new functions.HttpsError('unauthenticated', 'Authentication required.');
    }
    const uid = request.auth.uid;
    const { query, sessionId, mode, conversationHistory } = request.data;
    if (!query || typeof query !== 'string' || query.trim().length === 0) {
        throw new functions.HttpsError('invalid-argument', 'query must be a non-empty string.');
    }
    if (!sessionId || typeof sessionId !== 'string') {
        throw new functions.HttpsError('invalid-argument', 'sessionId is required.');
    }
    const output = await (0, constitutionalPipeline_1.runBereanPipeline)({
        userId: uid,
        query,
        sessionId,
        mode: mode ?? 'Ask',
        conversationHistory: conversationHistory ?? [],
    }, db);
    return { response: output.response, traceId: output.trace.traceId, trustScore: output.response.trustScore };
});
// ── 2. bereanGetMemory ────────────────────────────────────────────────────────
// Returns Berean memory entries for the authenticated user.
// Input:  { categories?: string[] }
// Output: { entries: MemoryEntry[] }
exports.bereanGetMemory = functions.onCall({ enforceAppCheck: true, region: 'us-east1' }, async (request) => {
    if (!request.auth) {
        throw new functions.HttpsError('unauthenticated', 'Authentication required.');
    }
    const uid = request.auth.uid;
    const { categories } = (request.data ?? {});
    const entries = await (0, memoryStore_1.readMemory)({ userId: uid, categories }, db);
    return { entries };
});
// ── 3. bereanDeleteMemory ─────────────────────────────────────────────────────
// Deletes a single memory entry for the authenticated user.
// Input:  { entryId: string }
exports.bereanDeleteMemory = functions.onCall({ enforceAppCheck: true, region: 'us-east1' }, async (request) => {
    if (!request.auth) {
        throw new functions.HttpsError('unauthenticated', 'Authentication required.');
    }
    const uid = request.auth.uid;
    const { entryId } = request.data;
    if (!entryId || typeof entryId !== 'string') {
        throw new functions.HttpsError('invalid-argument', 'entryId is required.');
    }
    await (0, memoryStore_1.deleteMemory)(uid, entryId, db);
    return { success: true };
});
// ── 4. bereanToggleMemoryLock ─────────────────────────────────────────────────
// Locks or unlocks a memory entry to prevent AI modification.
// Input:  { entryId: string, locked: boolean }
exports.bereanToggleMemoryLock = functions.onCall({ enforceAppCheck: true, region: 'us-east1' }, async (request) => {
    if (!request.auth) {
        throw new functions.HttpsError('unauthenticated', 'Authentication required.');
    }
    const uid = request.auth.uid;
    const { entryId, locked } = request.data;
    if (!entryId || typeof entryId !== 'string') {
        throw new functions.HttpsError('invalid-argument', 'entryId is required.');
    }
    if (typeof locked !== 'boolean') {
        throw new functions.HttpsError('invalid-argument', 'locked must be a boolean.');
    }
    await (0, memoryStore_1.lockMemory)(uid, entryId, locked, db);
    return { success: true, locked };
});
// ── 5. bereanUpdateMemory ─────────────────────────────────────────────────────
// Updates the content of a memory entry. Only editable (unlocked) entries may
// be updated. The content field is the only client-mutable field — all
// provenance, category, and lock fields are server-authoritative.
// Input:  { entryId: string, content: string }
exports.bereanUpdateMemory = functions.onCall({ enforceAppCheck: true, region: 'us-east1' }, async (request) => {
    if (!request.auth) {
        throw new functions.HttpsError('unauthenticated', 'Authentication required.');
    }
    const uid = request.auth.uid;
    const { entryId, content } = request.data;
    if (!entryId || typeof entryId !== 'string') {
        throw new functions.HttpsError('invalid-argument', 'entryId is required.');
    }
    if (!content || typeof content !== 'string' || content.trim().length === 0) {
        throw new functions.HttpsError('invalid-argument', 'content must be a non-empty string.');
    }
    const ref = db.doc(`users/${uid}/bereanMemory/${entryId}`);
    const snap = await ref.get();
    if (!snap.exists) {
        throw new functions.HttpsError('not-found', 'Memory entry not found.');
    }
    if (snap.data()?.locked === true) {
        throw new functions.HttpsError('failed-precondition', 'This memory entry is locked and cannot be edited. Unlock it first.');
    }
    await ref.update({ content, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    return { success: true };
});
// ── 6. bereanDeleteAllMemory ──────────────────────────────────────────────────
// Deletes ALL memory entries for the authenticated user (GDPR / Right to Erasure).
// Locked entries are also deleted when the user explicitly requests full erasure.
exports.bereanDeleteAllMemory = functions.onCall({ enforceAppCheck: true, region: 'us-east1' }, async (request) => {
    if (!request.auth) {
        throw new functions.HttpsError('unauthenticated', 'Authentication required.');
    }
    const uid = request.auth.uid;
    await (0, memoryStore_1.deleteAllUserMemory)(uid, db);
    return { success: true };
});
// ── 7. bereanSubmitFeedback ───────────────────────────────────────────────────
// Captures thumbs-up / thumbs-down feedback on a pipeline response.
// Input:  { traceId: string, sessionId: string, rating: 'positive' | 'negative', comment?: string }
exports.bereanSubmitFeedback = functions.onCall({ enforceAppCheck: true, region: 'us-east1' }, async (request) => {
    if (!request.auth) {
        throw new functions.HttpsError('unauthenticated', 'Authentication required.');
    }
    const uid = request.auth.uid;
    const { traceId, sessionId, rating, comment } = request.data;
    if (!traceId || typeof traceId !== 'string') {
        throw new functions.HttpsError('invalid-argument', 'traceId is required.');
    }
    if (!sessionId || typeof sessionId !== 'string') {
        throw new functions.HttpsError('invalid-argument', 'sessionId is required.');
    }
    if (rating !== 'positive' && rating !== 'negative') {
        throw new functions.HttpsError('invalid-argument', 'rating must be "positive" or "negative".');
    }
    const feedbackId = await (0, feedbackCapture_1.submitFeedback)({ userId: uid, traceId, sessionId, rating: rating, comment }, db);
    return { success: true, feedbackId };
});
// ── 8. bereanRunEvals ─────────────────────────────────────────────────────────
// Runs the full eval suite across all categories and returns pass rates + gate check.
// Admin-only (user document must have admin: true in Firestore).
// Returns: { results: EvalResults, gateCheck: DeploymentGateResult }
exports.bereanRunEvals = functions.onCall({
    enforceAppCheck: true,
    region: 'us-east1',
    timeoutSeconds: 540,
    memory: '2GiB',
    secrets: ['ANTHROPIC_API_KEY', 'GEMINI_API_KEY', 'BIBLE_API_KEY'],
}, async (request) => {
    if (!request.auth) {
        throw new functions.HttpsError('unauthenticated', 'Authentication required.');
    }
    // Admin role check — user document must have admin: true
    const userDoc = await db.doc(`users/${request.auth.uid}`).get();
    if (userDoc.data()?.admin !== true) {
        throw new functions.HttpsError('permission-denied', 'Only admin users may run the eval suite.');
    }
    // EVAL_TEST_CASES is Record<EvalCategory, EvalTest[]> — run each category suite.
    const suiteResults = await Promise.all(Object.keys(evalTestCases_1.EVAL_TEST_CASES).map((category) => (0, evalFramework_1.runEvalSuite)(category, evalTestCases_1.EVAL_TEST_CASES[category], async (input) => {
        const out = await (0, constitutionalPipeline_1.runBereanPipeline)({ userId: 'eval-system', query: input, sessionId: 'eval', mode: 'Ask', conversationHistory: [] }, db);
        return out.response.answer;
    }, db)));
    const results = suiteResults;
    const gateCheck = (0, evalFramework_1.checkDeploymentGate)(results);
    // Persist eval run for audit trail
    await db.collection('bereanEvalRuns').doc(Date.now().toString()).set({
        runAt: admin.firestore.FieldValue.serverTimestamp(),
        triggeredBy: request.auth.uid,
        results,
        gateCheck,
    });
    return { results, gateCheck };
});
// ── 9. verifyScriptureText ────────────────────────────────────────────────────
// Verifies AI-produced scripture text against canonical Bible text.
// Resolution order: Firestore cache (bibleVerses) → API.Bible REST API.
// Input:  { references: Array<{ ref, claimedText, translation }> } (max 20)
// Output: { results: Array<{ ref, verdict, canonicalText?, similarity? }> }
// Fail-secure: any error → "unresolvable" (never "verified" on error).
var apiBibleVerification_1 = require("./apiBibleVerification");
Object.defineProperty(exports, "verifyScriptureText", { enumerable: true, get: function () { return apiBibleVerification_1.verifyScriptureText; } });

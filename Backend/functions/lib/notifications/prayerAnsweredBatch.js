"use strict";
/**
 * notifications/prayerAnsweredBatch.ts
 *
 * 5.4 FIX: Firestore trigger that processes a single prayer-answered
 * notification batch in its own Cloud Function invocation.
 *
 * onPrayerAnswered (onSocialEvent.ts) writes one batch document per
 * 100 supporters to prayerAnsweredJobs/{prayerId}/batches/{index}.
 * This trigger fires for each batch document, processes ≤100 supporters
 * via the shared processCandidate pipeline, and marks the batch complete.
 *
 * Fan-out architecture:
 *   onPrayerAnswered trigger (1 invocation)
 *     → writes N batch docs  (N = ceil(supporters / 100))
 *     → each doc triggers this function (N parallel invocations)
 *     → each invocation processes ≤100 supporters
 *
 * Each invocation completes in seconds, not minutes — eliminating the
 * timeout risk that existed when all 5,000+ supporters were processed
 * sequentially in a single function call.
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
exports.processPrayerAnsweredBatch = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const types_1 = require("./types");
const helpers_1 = require("./helpers");
const onSocialEvent_1 = require("./onSocialEvent");
const db = admin.firestore();
exports.processPrayerAnsweredBatch = (0, firestore_1.onDocumentCreated)("prayerAnsweredJobs/{prayerId}/batches/{batchIndex}", async (event) => {
    const snap = event.data;
    if (!snap)
        return;
    const job = snap.data();
    if (!job)
        return;
    const { prayerId, authorId, actorName, actorUsername, actorProfileImageURL, supporterIds } = job;
    if (!prayerId || !authorId || !Array.isArray(supporterIds) || supporterIds.length === 0) {
        await snap.ref.update({ status: "skipped_invalid" });
        return;
    }
    const routes = (0, helpers_1.buildRoutes)(types_1.NotificationType.PrayerAnswered, {
        prayerId,
        actorId: authorId,
    });
    const candidates = supporterIds.map((supporterId) => ({
        recipientId: supporterId,
        type: types_1.NotificationType.PrayerAnswered,
        actorId: authorId,
        actorName: actorName ?? "",
        actorUsername: actorUsername ?? "",
        actorProfileImageURL: actorProfileImageURL ?? null,
        postId: null,
        commentId: null,
        parentCommentId: null,
        conversationId: null,
        prayerId,
        noteId: null,
        commentText: null,
        ...routes,
    }));
    // Process all supporters in this batch in parallel.
    // Each batch is ≤100 entries — safe for a single invocation.
    await Promise.all(candidates.map((c) => (0, onSocialEvent_1.processCandidate)(c)));
    // Mark batch complete for observability / idempotency.
    await snap.ref.update({
        status: "completed",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
});
//# sourceMappingURL=prayerAnsweredBatch.js.map
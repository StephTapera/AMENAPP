"use strict";
/**
 * DiscipleshipTrackerService.ts
 *
 * Records and retrieves discipleship events; generates follow-up prompts;
 * surfaces growth path suggestions. All operations are fire-and-forget from
 * the caller's perspective — failures are logged but never block a response.
 *
 * Privacy constraints:
 *  - Growth data is private to the user
 *  - Leaders can only see shared data with explicit user consent
 *  - No public spiritual scores or leaderboards
 *  - Growth paths are invitations; never auto-activated
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
exports.recordDiscipleshipEvent = recordDiscipleshipEvent;
exports.createFollowUpPrompt = createFollowUpPrompt;
exports.getRecentEvents = getRecentEvents;
const admin = __importStar(require("firebase-admin"));
const uuid_1 = require("uuid");
// ---------------------------------------------------------------------------
// Event Recording
// ---------------------------------------------------------------------------
/**
 * Records a discipleship event for a user.
 * Non-blocking — callers do not await this.
 */
async function recordDiscipleshipEvent(userId, eventType, options = {}) {
    const db = admin.firestore();
    const eventId = (0, uuid_1.v4)();
    const event = {
        id: eventId,
        userId,
        eventType,
        passageId: options.passageId,
        passageReference: options.passageReference,
        bereanSessionId: options.bereanSessionId,
        note: options.note,
        occurredAt: admin.firestore.Timestamp.now(),
    };
    await db
        .collection("users")
        .doc(userId)
        .collection("discipleshipEvents")
        .doc(eventId)
        .set(event);
    // Increment session counter on profile
    await db
        .collection("users")
        .doc(userId)
        .collection("discipleshipProfile")
        .doc(userId)
        .set({
        totalStudySessions: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.Timestamp.now(),
        lastStudiedBook: options.passageReference
            ? extractBookFromReference(options.passageReference)
            : admin.firestore.FieldValue.delete(),
    }, { merge: true });
}
// ---------------------------------------------------------------------------
// Follow-Up Prompt Generation
// ---------------------------------------------------------------------------
/**
 * Creates a follow-up prompt after a study session.
 * Stored for later surfacing by the notification system.
 */
async function createFollowUpPrompt(userId, sourceSessionId, passageReference, promptText, scheduledDelayHours = 24) {
    const db = admin.firestore();
    const promptId = (0, uuid_1.v4)();
    const scheduledFor = admin.firestore.Timestamp.fromDate(new Date(Date.now() + scheduledDelayHours * 60 * 60 * 1000));
    const prompt = {
        id: promptId,
        userId,
        promptText,
        sourceSessionId,
        passageReference,
        scheduledFor,
        status: "pending",
        createdAt: admin.firestore.Timestamp.now(),
        dismissedAt: undefined,
        engagedAt: undefined,
    };
    await db
        .collection("users")
        .doc(userId)
        .collection("followUpPrompts")
        .doc(promptId)
        .set(prompt);
}
// ---------------------------------------------------------------------------
// Recent Event Fetcher (for AI context window)
// ---------------------------------------------------------------------------
/**
 * Fetches the user's most recent discipleship events for use as context
 * in the AI's generation call.
 */
async function getRecentEvents(userId, limit = 10) {
    try {
        const db = admin.firestore();
        const snapshot = await db
            .collection("users")
            .doc(userId)
            .collection("discipleshipEvents")
            .orderBy("occurredAt", "desc")
            .limit(limit)
            .get();
        return snapshot.docs.map((d) => d.data());
    }
    catch {
        return [];
    }
}
// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function extractBookFromReference(reference) {
    // "John 3:16" → "John", "1 Corinthians 13:4" → "1 Corinthians"
    const match = reference.match(/^([1-3]?\s?[A-Za-z]+(?:\s[A-Za-z]+)?)/);
    return match ? match[1].trim() : reference.split(" ")[0];
}
//# sourceMappingURL=DiscipleshipTrackerService.js.map
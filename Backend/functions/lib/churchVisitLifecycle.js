"use strict";
/**
 * churchVisitLifecycle.ts
 * AMENAPP Cloud Functions — Church Visit Lifecycle Orchestration
 *
 * Functions:
 *   onChurchInteractionAttended    — Triggered when phase transitions to "attended".
 *                                    Schedules follow-up prompt tasks and sends FCM.
 *   onChurchInteractionReflected   — Triggered when phase transitions to "reflected".
 *                                    Schedules the Day-3 return decision prompt.
 *   scheduleChurchFollowUpPrompt   — Callable used by ChurchFollowUpEngine to queue
 *                                    server-side follow-up scheduling.
 *
 * Privacy: all writes are scoped to users/{uid}/churchInteractions/{churchId}.
 * No community-facing visibility is added.
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
exports.scheduleChurchFollowUpPrompt = exports.onChurchInteractionReflected = exports.onChurchInteractionAttended = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const https_1 = require("firebase-functions/v2/https");
const db = admin.firestore();
const messaging = admin.messaging();
// ---------------------------------------------------------------------------
// MARK: - onChurchInteractionAttended
// Trigger: users/{uid}/churchInteractions/{churchId} updated with phase=attended
// ---------------------------------------------------------------------------
exports.onChurchInteractionAttended = (0, firestore_1.onDocumentUpdated)("users/{uid}/churchInteractions/{churchId}", async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after)
        return;
    // Only react to phase transitions into "attended"
    if (before.phase === after.phase || after.phase !== "attended")
        return;
    const uid = event.params.uid;
    const churchId = event.params.churchId;
    const churchName = after.church_name ?? "your church";
    // Write a follow-up schedule record
    const followUpRef = db
        .collection("users")
        .doc(uid)
        .collection("churchFollowUps")
        .doc(churchId);
    await followUpRef.set({
        churchId,
        churchName,
        attendedAt: after.attended_at ?? admin.firestore.Timestamp.now(),
        scheduledSteps: [0, 1, 2], // sameDay, nextDay, dayThree
        completedSteps: [],
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    // Send same-day FCM nudge (3h delay simulated via scheduled function)
    await sendFollowUpNotification(uid, churchName, "sameDay", churchId);
});
// ---------------------------------------------------------------------------
// MARK: - onChurchInteractionReflected
// Trigger: users/{uid}/churchInteractions/{churchId} updated with phase=reflected
// ---------------------------------------------------------------------------
exports.onChurchInteractionReflected = (0, firestore_1.onDocumentUpdated)("users/{uid}/churchInteractions/{churchId}", async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after)
        return;
    if (before.phase === after.phase || after.phase !== "reflected")
        return;
    const uid = event.params.uid;
    const churchId = event.params.churchId;
    const churchName = after.church_name ?? "your church";
    // Mark sameDay and nextDay steps as triggered (reflected means user engaged)
    await db
        .collection("users")
        .doc(uid)
        .collection("churchFollowUps")
        .doc(churchId)
        .set({
        completedSteps: admin.firestore.FieldValue.arrayUnion(0, 1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    // Schedule Day-3 follow-up notification (return decision prompt)
    const day3Date = new Date(Date.now() + 3 * 86400000);
    await scheduleFollowUpTask(uid, churchId, churchName, "dayThree", day3Date);
});
// ---------------------------------------------------------------------------
// MARK: - scheduleChurchFollowUpPrompt (Callable)
// Called by ChurchFollowUpEngine when completing a step client-side.
// ---------------------------------------------------------------------------
exports.scheduleChurchFollowUpPrompt = (0, https_1.onCall)({ enforceAppCheck: false }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Must be signed in.");
    const { churchId, churchName, step } = request.data;
    if (!churchId || !churchName || !step) {
        throw new https_1.HttpsError("invalid-argument", "churchId, churchName, and step are required.");
    }
    const offsetDays = { sameDay: 0, nextDay: 1, dayThree: 3 };
    const daysOffset = offsetDays[step] ?? 0;
    const fireDate = new Date(Date.now() + daysOffset * 86400000);
    await scheduleFollowUpTask(uid, churchId, churchName, step, fireDate);
    return { success: true, step, scheduledAt: fireDate.toISOString() };
});
// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------
async function sendFollowUpNotification(uid, churchName, step, churchId) {
    // Get user's FCM token from Firestore
    const userDoc = await db.collection("users").doc(uid).get();
    const fcmToken = userDoc.data()?.fcmToken;
    if (!fcmToken)
        return;
    const messages = {
        sameDay: {
            title: `How was ${churchName}?`,
            body: "Take a moment to capture your thoughts from today's service.",
        },
        nextDay: {
            title: `Still thinking about ${churchName}?`,
            body: "What from Sunday's service is still on your heart?",
        },
        dayThree: {
            title: `Ready to go back to ${churchName}?`,
            body: "Would you like to return, connect, or share your experience?",
        },
    };
    const msg = messages[step];
    if (!msg)
        return;
    try {
        await messaging.send({
            token: fcmToken,
            notification: { title: msg.title, body: msg.body },
            data: {
                type: "church_follow_up",
                churchId,
                step,
                click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
            apns: {
                payload: {
                    aps: {
                        sound: "default",
                        category: "CHURCH_FOLLOW_UP",
                    },
                },
            },
        });
    }
    catch (error) {
        console.error(`[churchLifecycle] FCM error for uid=${uid} step=${step}:`, error);
    }
}
async function scheduleFollowUpTask(uid, churchId, churchName, step, fireDate) {
    // Store the scheduled follow-up in Firestore for audit / client sync
    await db
        .collection("users")
        .doc(uid)
        .collection("churchFollowUps")
        .doc(churchId)
        .set({
        [`scheduled_${step}`]: admin.firestore.Timestamp.fromDate(fireDate),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
}
//# sourceMappingURL=churchVisitLifecycle.js.map
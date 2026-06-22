"use strict";
// capabilities/prayerOS/scheduled.ts — Prayer OS follow-up sweep (Wave 1: Lane B)
//
// prayerOS_followUpSweep: Cloud Scheduler trigger every 15 minutes.
// Finds prayer cards with due followUps/reminders and queues notifications.
//
// Notification strategy: writes to users/{uid}/notificationQueue/{autoId}
// which the existing notification consumer picks up. This avoids building
// a parallel FCM path.
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
exports.prayerOS_followUpSweep = void 0;
const scheduler_1 = require("firebase-functions/v2/scheduler");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
// Deep link base for prayer cards
const DEEP_LINK_BASE = "amen://capabilities/prayer-os/card";
exports.prayerOS_followUpSweep = (0, scheduler_1.onSchedule)({
    schedule: "every 15 minutes",
    timeZone: "UTC",
}, async () => {
    const db = (0, firestore_1.getFirestore)();
    const now = firestore_1.Timestamp.now();
    let processed = 0;
    let skipped = 0;
    // ── Follow-Up Sweep ──────────────────────────────────────────────────────
    // Query collection group for cards that have any followUp entries.
    // Firestore cannot query inside arrays directly, so we fetch cards where
    // followUps is non-empty and filter in memory for due pending items.
    //
    // We limit to 500 documents per sweep to bound execution time at 15-minute
    // interval. Cards not processed this cycle will be caught in the next sweep.
    const followUpSnap = await db
        .collectionGroup("prayerCards")
        .where("status", "in", ["active", "answered"])
        .limit(500)
        .get();
    const followUpBatch = db.batch();
    let batchCount = 0;
    for (const cardDoc of followUpSnap.docs) {
        const data = cardDoc.data();
        const followUps = Array.isArray(data.followUps) ? data.followUps : [];
        const uid = cardDoc.ref.parent.parent?.id;
        if (!uid)
            continue;
        let cardUpdated = false;
        const updatedFollowUps = [...followUps];
        for (let i = 0; i < updatedFollowUps.length; i++) {
            const fu = updatedFollowUps[i];
            // Skip already-prompted or done/dismissed follow-ups
            if (fu.status !== "pending") {
                skipped++;
                continue;
            }
            // Check if due
            if (!fu.dueAt || fu.dueAt.toMillis() > now.toMillis()) {
                continue;
            }
            // Idempotency: mark as "prompted" before queuing notification
            updatedFollowUps[i] = { ...fu, status: "prompted" };
            cardUpdated = true;
            // Queue notification for existing notification consumer
            const queueRef = db.collection(`users/${uid}/notificationQueue`).doc();
            followUpBatch.set(queueRef, {
                type: "prayerFollowUp",
                cardId: cardDoc.id,
                cardPath: cardDoc.ref.path,
                followUpIndex: i,
                dueAt: fu.dueAt,
                deepLink: `${DEEP_LINK_BASE}/${cardDoc.id}`,
                createdAt: firestore_1.FieldValue.serverTimestamp(),
            });
            batchCount++;
            processed++;
        }
        if (cardUpdated) {
            followUpBatch.update(cardDoc.ref, {
                followUps: updatedFollowUps,
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            });
            batchCount++;
        }
        // Commit in chunks of 400 to stay under Firestore 500-operation batch limit
        if (batchCount >= 400) {
            await followUpBatch.commit();
            batchCount = 0;
        }
    }
    if (batchCount > 0) {
        await followUpBatch.commit();
    }
    // ── Reminder Sweep ───────────────────────────────────────────────────────
    // Find cards with reminders whose nextFireAt <= now
    const reminderSnap = await db
        .collectionGroup("prayerCards")
        .where("status", "==", "active")
        .limit(500)
        .get();
    const reminderBatch = db.batch();
    let reminderBatchCount = 0;
    let remindersProcessed = 0;
    for (const cardDoc of reminderSnap.docs) {
        const data = cardDoc.data();
        const reminders = Array.isArray(data.reminders) ? data.reminders : [];
        const uid = cardDoc.ref.parent.parent?.id;
        if (!uid || reminders.length === 0)
            continue;
        let cardUpdated = false;
        const updatedReminders = [...reminders];
        for (let i = 0; i < updatedReminders.length; i++) {
            const reminder = updatedReminders[i];
            if (!reminder.nextFireAt || reminder.nextFireAt.toMillis() > now.toMillis()) {
                continue;
            }
            // Queue reminder notification
            const queueRef = db.collection(`users/${uid}/notificationQueue`).doc();
            reminderBatch.set(queueRef, {
                type: "prayerReminder",
                cardId: cardDoc.id,
                cardPath: cardDoc.ref.path,
                reminderIndex: i,
                scheduledFor: reminder.nextFireAt,
                deepLink: `${DEEP_LINK_BASE}/${cardDoc.id}`,
                createdAt: firestore_1.FieldValue.serverTimestamp(),
            });
            reminderBatchCount++;
            remindersProcessed++;
            // Advance nextFireAt based on rrule. A full rrule parser is not available
            // in this module — we use a simple heuristic: advance by 7 days for weekly
            // patterns, 24h for daily, 30 days for monthly. The iOS app holds the
            // authoritative rrule schedule and will re-sync nextFireAt on next open.
            const nextFireMs = computeNextFireMs(reminder.rrule, reminder.nextFireAt.toMillis());
            updatedReminders[i] = {
                ...reminder,
                nextFireAt: firestore_1.Timestamp.fromMillis(nextFireMs),
            };
            cardUpdated = true;
        }
        if (cardUpdated) {
            reminderBatch.update(cardDoc.ref, {
                reminders: updatedReminders,
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            });
            reminderBatchCount++;
        }
        if (reminderBatchCount >= 400) {
            await reminderBatch.commit();
            reminderBatchCount = 0;
        }
    }
    if (reminderBatchCount > 0) {
        await reminderBatch.commit();
    }
    logger.info("[CAP/prayerOS] followUpSweep complete", {
        followUpsProcessed: processed,
        followUpsSkipped: skipped,
        remindersProcessed,
    });
});
// ── Helpers ──────────────────────────────────────────────────────────────────
/**
 * Compute next fire timestamp from an rrule string.
 * This is a lightweight heuristic — the authoritative scheduler is iOS.
 * Advances by:
 *   FREQ=DAILY    → +1 day
 *   FREQ=WEEKLY   → +7 days
 *   FREQ=MONTHLY  → +30 days
 *   FREQ=YEARLY   → +365 days
 *   (default)     → +7 days
 */
function computeNextFireMs(rrule, currentMs) {
    const upper = (rrule ?? "").toUpperCase();
    const MS_DAY = 24 * 60 * 60 * 1000;
    if (upper.includes("FREQ=DAILY"))
        return currentMs + MS_DAY;
    if (upper.includes("FREQ=WEEKLY"))
        return currentMs + 7 * MS_DAY;
    if (upper.includes("FREQ=MONTHLY"))
        return currentMs + 30 * MS_DAY;
    if (upper.includes("FREQ=YEARLY"))
        return currentMs + 365 * MS_DAY;
    // Default: weekly
    return currentMs + 7 * MS_DAY;
}

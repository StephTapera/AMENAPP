/**
 * createBlock.ts
 *
 * WHY THIS EXISTS:
 *   A block involves two separate Firestore stores:
 *     1. blockedUsers/{blockerId}_{blockedId}  (top-level)
 *        — read by antiHarassmentEnforcement.ts to prevent message delivery
 *     2. users/{blockerId}/blockedUsers/{blockedId}  (subcollection)
 *        — read by Firestore security rules (callerIsBlockedByAuthor) and
 *          triggers blockRelationshipCleanup on create
 *
 *   If the client writes to the subcollection but the network drops before
 *   writing the top-level doc, the block is partial: Firestore rules will
 *   enforce the block at the rules layer, but antiHarassmentEnforcement will
 *   keep delivering messages to the blocked user because the enforcement CF
 *   only reads the top-level collection.
 *
 * THIS FUNCTION writes both locations in a single Firestore batch (atomic).
 * The blockRelationshipCleanup trigger fires automatically on subcollection
 * create, removing follows and restricting shared conversations as before.
 *
 * MIGRATION:
 *   BlockService.swift should be updated to call this function instead of
 *   writing directly to users/{uid}/blockedUsers. Once the callable is in
 *   production, block direct client writes by setting:
 *     match /users/{userId}/blockedUsers/{blockedId} { allow write: if false; }
 *   in Firestore rules (after confirming all clients use this callable).
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

export const createBlock = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Must be signed in to block a user."
        );
    }

    if (context.app == undefined) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "The function must be called from an App Check verified app."
        );
    }

    const blockerId = context.auth.uid;
    const blockedId: unknown = data?.blockedId;

    if (typeof blockedId !== "string" || blockedId.trim() === "") {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "blockedId must be a non-empty string."
        );
    }

    if (blockerId === blockedId) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Cannot block yourself."
        );
    }

    const now = admin.firestore.FieldValue.serverTimestamp();

    // Atomic batch: write to both stores simultaneously.
    const batch = db.batch();

    // Store 1 — top-level (read by antiHarassmentEnforcement.ts)
    // Doc ID convention: "{blockerId}_{blockedId}"
    const topLevelRef = db
        .collection("blockedUsers")
        .doc(`${blockerId}_${blockedId}`);
    batch.set(topLevelRef, { blockerId, blockedId, createdAt: now }, { merge: true });

    // Store 2 — subcollection (read by Firestore rules + triggers blockRelationshipCleanup)
    const subRef = db
        .collection("users")
        .doc(blockerId)
        .collection("blockedUsers")
        .doc(blockedId);
    batch.set(subRef, { blockedId, createdAt: now }, { merge: true });

    await batch.commit();

    functions.logger.info(
        `[createBlock] ${blockerId} blocked ${blockedId} — both stores written atomically`
    );

    return { success: true };
});

// ─── createUnblock ────────────────────────────────────────────────────────────
//
// Removes block from both stores atomically. Mirror of createBlock.

export const createUnblock = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Must be signed in to unblock a user."
        );
    }

    if (context.app == undefined) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "The function must be called from an App Check verified app."
        );
    }

    const blockerId = context.auth.uid;
    const blockedId: unknown = data?.blockedId;

    if (typeof blockedId !== "string" || blockedId.trim() === "") {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "blockedId must be a non-empty string."
        );
    }

    const batch = db.batch();

    batch.delete(db.collection("blockedUsers").doc(`${blockerId}_${blockedId}`));
    batch.delete(
        db.collection("users").doc(blockerId).collection("blockedUsers").doc(blockedId)
    );

    await batch.commit();

    functions.logger.info(
        `[createUnblock] ${blockerId} unblocked ${blockedId} — both stores cleared atomically`
    );

    return { success: true };
});

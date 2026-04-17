/**
 * antiHarassmentEnforcement.ts
 *
 * Server-side enforcement of anti-harassment restrictions for direct messages.
 *
 * WHY THIS EXISTS (CRITICAL-1 from Trust/Safety Audit):
 *   The client-side AntiHarassmentEngine writes userRestrictions and enforcementHistory
 *   documents to Firestore, but message sends are written directly to Firestore from the
 *   client. A motivated bad actor can bypass the Swift MessageSafetyGateway by writing
 *   messages through the Firestore SDK or REST API while their account is restricted.
 *
 * APPROACH — Firestore onCreate trigger on messages subcollection:
 *   Triggers on every new message written to conversations/{conversationId}/messages/{messageId}.
 *   Reads the sender's active restrictions and, if any apply to the recipient pair, deletes
 *   the message immediately and writes a "blocked" notice back to the sender's subcollection.
 *   This makes enforcement unconditional regardless of the write path.
 *
 * RESTRICTIONS CHECKED (mirrors AntiHarassmentEngine.RestrictionType):
 *   - messaging    : sender cannot DM anyone (platform-wide messaging freeze)
 *   - dm_freeze    : sender's DM capability is frozen
 *   - no_contact   : sender cannot contact a specific target user
 *
 * BLOCK CHECK:
 *   If the recipient has blocked the sender (blockedUsers collection), the message is
 *   also deleted — this is a belt-and-suspenders check since Firestore rules should
 *   already prevent writes across a block, but rule misconfigurations do happen.
 *
 * ESCALATION:
 *   If the sender is already at the CRITICAL harassment tier (determined by enforcement
 *   history in the last 30 days), the attempt itself is recorded as an additional
 *   violation to build the pattern record for human review.
 */

import * as functions from "firebase-functions"; // kept for helper-level logger usage
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";
import { getServerSafetyFlags } from "./serverFeatureFlags";

const db = admin.firestore();

// ─── Constants ───────────────────────────────────────────────────────────────

/**
 * Restriction types that block all DM sends (platform-wide).
 * Must match AntiHarassmentEngine.RestrictionType raw values.
 */
const MESSAGING_BLOCK_TYPES = new Set(["messaging", "dm_freeze"]);

/** The restriction type for per-target no-contact orders. */
const NO_CONTACT_TYPE = "no_contact";

/** Collection where per-user restrictions are stored. */
const RESTRICTIONS_COLLECTION = "userRestrictions";

/** Collection where enforcement history is stored. */
const ENFORCEMENT_COLLECTION = "enforcementHistory";

/** Collection where blocked-user pairs are stored. */
const BLOCKED_USERS_COLLECTION = "blockedUsers";

/**
 * How many critical/severe violations in 30 days trigger escalation recording
 * for a send-while-restricted attempt.
 */
const CRITICAL_VIOLATION_THRESHOLD = 1;
const SEVERE_VIOLATION_THRESHOLD = 2;

// ─── Types ───────────────────────────────────────────────────────────────────

interface RestrictionDoc {
    userId: string;
    type: string;
    reason: string;
    endDate: admin.firestore.Timestamp;
    targetUserId?: string;
}

interface EnforcementViolationSeverity {
    critical: number;
    severe: number;
    moderate: number;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Checks whether a user is subject to a platform-wide messaging freeze
 * (restriction type "messaging" or "dm_freeze" that has not yet expired).
 */
async function hasMessagingFreeze(senderId: string): Promise<RestrictionDoc | null> {
    const now = admin.firestore.Timestamp.now();

    // Check each blocking type — we stop at the first active one found.
    for (const restrictionType of MESSAGING_BLOCK_TYPES) {
        const docId = `${senderId}_${restrictionType}`;
        const snap = await db.collection(RESTRICTIONS_COLLECTION).doc(docId).get();

        if (!snap.exists) continue;

        const data = snap.data() as RestrictionDoc | undefined;
        if (!data) continue;

        // If the restriction has not expired, return it.
        if (data.endDate && data.endDate.toMillis() > now.toMillis()) {
            return data;
        }

        // Restriction expired — clean up lazily (fire-and-forget, non-blocking).
        snap.ref.delete().catch(() => { /* best-effort cleanup */ });
    }

    return null;
}

/**
 * Checks whether a user has an active no-contact order against a specific recipient.
 * Doc ID format: "{senderId}_no_contact_{recipientId}"
 */
async function hasNoContactOrder(senderId: string, recipientId: string): Promise<RestrictionDoc | null> {
    const now = admin.firestore.Timestamp.now();
    const docId = `${senderId}_${NO_CONTACT_TYPE}_${recipientId}`;

    const snap = await db.collection(RESTRICTIONS_COLLECTION).doc(docId).get();
    if (!snap.exists) return null;

    const data = snap.data() as RestrictionDoc | undefined;
    if (!data) return null;

    if (data.endDate && data.endDate.toMillis() > now.toMillis()) {
        return data;
    }

    // Expired — clean up lazily.
    snap.ref.delete().catch(() => { /* best-effort cleanup */ });
    return null;
}

/**
 * Returns true if recipientId has blocked senderId.
 * This is a belt-and-suspenders check — Firestore rules should already gate this.
 *
 * Uses a deterministic doc ID ({recipientId}_{senderId}) for an O(1) point-read
 * instead of a collection query scan.
 */
async function isBlockedByRecipient(senderId: string, recipientId: string): Promise<boolean> {
    // Block documents are stored with ID "{blocker}_{blocked}".
    const docId = `${recipientId}_${senderId}`;
    const snap = await db.collection(BLOCKED_USERS_COLLECTION).doc(docId).get();
    return snap.exists;
}

/**
 * Counts recent enforcement violations by severity level.
 * Used to detect if a send-while-restricted attempt should trigger escalation.
 */
async function getRecentViolationCounts(
    senderId: string,
    days: number
): Promise<EnforcementViolationSeverity> {
    const cutoffDate = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
    const cutoff = admin.firestore.Timestamp.fromDate(cutoffDate);

    const snap = await db
        .collection(ENFORCEMENT_COLLECTION)
        .where("userId", "==", senderId)
        .where("timestamp", ">=", cutoff)
        .limit(200)
        .get();

    const counts: EnforcementViolationSeverity = { critical: 0, severe: 0, moderate: 0 };

    for (const doc of snap.docs) {
        const data = doc.data();
        const violation: string = data.violation ?? "";

        // These severity assignments mirror PolicyViolation.severity in the Swift client.
        // Critical: childSafety, sexualExploitation, incitement, threatOfViolence
        // Severe:   sexualContent, harassment, hateSpeech, spam_aggressive, misinformation_dangerous
        if (
            violation === "child_safety" ||
            violation === "sexual_exploitation" ||
            violation === "incitement" ||
            violation === "threat_of_violence"
        ) {
            counts.critical++;
        } else if (
            violation === "sexual_content" ||
            violation === "harassment" ||
            violation === "hate_speech" ||
            violation === "spam_aggressive" ||
            violation === "misinformation_dangerous"
        ) {
            counts.severe++;
        } else {
            counts.moderate++;
        }
    }

    return counts;
}

/**
 * Records a blocked send attempt in the enforcement history collection.
 * This builds the pattern record used by shouldEscalateEnforcement() and
 * detectHarassmentPattern() on the client.
 */
async function recordBlockedSendAttempt(
    senderId: string,
    recipientId: string,
    conversationId: string,
    messageId: string,
    blockReason: string
): Promise<void> {
    const idempotencyKey = `${messageId}_send_blocked`;

    // Idempotency: skip if this message was already recorded (retry safety).
    const existing = await db
        .collection(ENFORCEMENT_COLLECTION)
        .where("idempotencyKey", "==", idempotencyKey)
        .limit(1)
        .get();

    if (!existing.empty) return;

    const recordId = db.collection(ENFORCEMENT_COLLECTION).doc().id;

    await db.collection(ENFORCEMENT_COLLECTION).doc(recordId).set({
        id: recordId,
        userId: senderId,
        violation: "harassment",            // Attempting contact while restricted = harassment
        action: "message_blocked",          // Custom action for send-while-restricted
        contentId: messageId,
        contentType: "message",
        surface: "dm",
        targetUserId: recipientId,
        conversationId,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        confidence: 1.0,                    // Restriction-based block — deterministic
        source: "server_enforcement",
        modelVersion: null,
        ruleIdsMatched: ["server_restriction_check"],
        policyVersion: "2026-03-06",
        idempotencyKey,
        blockReason,
    });
}

/**
 * Writes a "blocked send" notification to the sender's notifications subcollection
 * so the app can show the user why their message wasn't delivered.
 *
 * NOTE: This writes to the sender's own notifications — they are the user affected.
 */
async function notifySenderOfBlock(
    senderId: string,
    blockReason: string,
    restrictionType: string
): Promise<void> {
    const humanReadable: Record<string, string> = {
        messaging:      "Your messaging capability is temporarily restricted.",
        dm_freeze:      "Your direct messaging is currently frozen.",
        no_contact:     "You have an active no-contact order for this user.",
        blocked:        "You cannot message this user.",
    };

    const body = humanReadable[restrictionType] ?? "This message could not be delivered.";

    await db
        .collection("users")
        .doc(senderId)
        .collection("notifications")
        .add({
            type: "system_message_blocked",
            userId: senderId,
            toUserId: senderId,
            title: "Message Not Delivered",
            body,
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            data: { restrictionType, blockReason },
        });
}

// ─── Cloud Function ───────────────────────────────────────────────────────────

/**
 * Firestore onCreate trigger: enforceMessageRestrictions
 *
 * Fires whenever a new message document is created in any conversation's
 * messages subcollection. Checks the sender's active restrictions and
 * deletes the message if any apply, making enforcement unconditional.
 *
 * The trigger is path-wildcard based — it fires for both 1:1 DMs and group
 * chats. Group chat messages are also checked because platform-wide messaging
 * freezes (e.g. for CSAM violations) must block all surfaces.
 */
export const enforceMessageRestrictions = onDocumentCreated(
    "conversations/{conversationId}/messages/{messageId}",
    async (event) => {
        const { conversationId, messageId } = event.params;
        const snap = event.data;
        if (!snap) return;
        const data = snap.data();

        if (!data) {
            functions.logger.warn(
                `[AntiHarassment] Message ${messageId} has no data — skipping.`
            );
            return;
        }

        const senderId: string = data.senderId ?? "";
        if (!senderId) {
            functions.logger.warn(
                `[AntiHarassment] Message ${messageId} missing senderId — skipping.`
            );
            return;
        }

        // ── 0. Server-side flag gate (CRITICAL-3) ─────────────────────────
        // Read enforcement-enabled flag from Firestore, NOT from the client request.
        // Defaults to true (enforcement ON) if the document is missing or unreadable.
        const flags = await getServerSafetyFlags();
        if (!flags.messagingBlockEnforcementEnabled || !flags.antiHarassmentV2Enabled) {
            functions.logger.info(
                `[AntiHarassment] Enforcement skipped — ` +
                `messagingBlockEnforcementEnabled=${flags.messagingBlockEnforcementEnabled}, ` +
                `antiHarassmentV2Enabled=${flags.antiHarassmentV2Enabled}`
            );
            return;
        }

        // ── 1. Check platform-wide messaging freeze ───────────────────────
        const messagingFreeze = await hasMessagingFreeze(senderId);
        if (messagingFreeze) {
            functions.logger.info(
                `[AntiHarassment] Deleting message ${messageId} — sender ${senderId} ` +
                `has active ${messagingFreeze.type} restriction.`
            );

            await snap.ref.delete();

            // Notify sender (fire-and-forget; non-fatal if it fails).
            await notifySenderOfBlock(senderId, messagingFreeze.reason, messagingFreeze.type)
                .catch((err) => functions.logger.error("[AntiHarassment] notifySenderOfBlock failed", err));

            // Record the blocked attempt for pattern tracking.
            const recipientId = data.recipientId ?? "";
            await recordBlockedSendAttempt(
                senderId,
                recipientId,
                conversationId,
                messageId,
                `Active ${messagingFreeze.type} restriction`
            ).catch((err) => functions.logger.error("[AntiHarassment] recordBlockedSendAttempt failed", err));

            return;
        }

        // ── 2. Get recipient for per-target checks ────────────────────────
        // For 1:1 DMs: fetch the conversation to find the recipient.
        // For group chats: only the platform-wide freeze (step 1) applies.
        const conversationSnap = await db
            .collection("conversations")
            .doc(conversationId)
            .get();

        if (!conversationSnap.exists) return;

        const convoData = conversationSnap.data() ?? {};
        const isGroup: boolean = convoData.isGroup === true;
        const participantIds: string[] = convoData.participantIds ?? [];

        // For group chats, check if any active no-contact order covers any participant.
        // A user with a no-contact order against a specific person must not be able
        // to reach them via a group chat either.
        if (isGroup) {
            const otherParticipants = participantIds.filter((id) => id !== senderId);
            for (const participantId of otherParticipants) {
                const noContactGroup = await hasNoContactOrder(senderId, participantId);
                if (noContactGroup) {
                    functions.logger.info(
                        `[AntiHarassment] Deleting group message ${messageId} — sender ${senderId} ` +
                        `has no-contact order against participant ${participantId}.`
                    );

                    await snap.ref.delete();

                    await notifySenderOfBlock(senderId, noContactGroup.reason, NO_CONTACT_TYPE)
                        .catch((err) => functions.logger.error("[AntiHarassment] notifySenderOfBlock failed", err));

                    await recordBlockedSendAttempt(
                        senderId,
                        participantId,
                        conversationId,
                        messageId,
                        `Active no-contact order (group chat, participant ${participantId})`
                    ).catch((err) => functions.logger.error("[AntiHarassment] recordBlockedSendAttempt failed", err));

                    return;
                }
            }
            // No no-contact violations found for this group message — allow.
            return;
        }

        const recipientId = participantIds.find((id) => id !== senderId) ?? "";

        if (!recipientId) {
            functions.logger.warn(
                `[AntiHarassment] Could not determine recipient for conversation ${conversationId}`
            );
            return;
        }

        // ── 3. Check no-contact order ─────────────────────────────────────
        const noContact = await hasNoContactOrder(senderId, recipientId);
        if (noContact) {
            functions.logger.info(
                `[AntiHarassment] Deleting message ${messageId} — sender ${senderId} ` +
                `has no-contact order against ${recipientId}.`
            );

            await snap.ref.delete();

            await notifySenderOfBlock(senderId, noContact.reason, NO_CONTACT_TYPE)
                .catch((err) => functions.logger.error("[AntiHarassment] notifySenderOfBlock failed", err));

            await recordBlockedSendAttempt(
                senderId,
                recipientId,
                conversationId,
                messageId,
                "Active no-contact order"
            ).catch((err) => functions.logger.error("[AntiHarassment] recordBlockedSendAttempt failed", err));

            return;
        }

        // ── 4. Belt-and-suspenders: check if recipient has blocked sender ─
        const blocked = await isBlockedByRecipient(senderId, recipientId);
        if (blocked) {
            functions.logger.info(
                `[AntiHarassment] Deleting message ${messageId} — ` +
                `${senderId} is blocked by ${recipientId}.`
            );

            await snap.ref.delete();

            await notifySenderOfBlock(senderId, "Recipient has blocked you", "blocked")
                .catch((err) => functions.logger.error("[AntiHarassment] notifySenderOfBlock failed", err));

            // Record the breach attempt — attempting contact after being blocked is a violation.
            await recordBlockedSendAttempt(
                senderId,
                recipientId,
                conversationId,
                messageId,
                "Sender is blocked by recipient"
            ).catch((err) => functions.logger.error("[AntiHarassment] recordBlockedSendAttempt failed", err));

            return;
        }

        // ── 5. DM mention cap ─────────────────────────────────────────────
        // Prevent mention-bombing inside DMs (same cap as public comments).
        const messageText: string = data.text ?? data.content ?? "";
        const dmMentionCount = (messageText.match(/@\w+/g) ?? []).length;
        if (dmMentionCount > 5) {
            functions.logger.info(
                `[AntiHarassment] Deleting DM ${messageId} — ${dmMentionCount} mentions exceeds cap of 5.`
            );
            await snap.ref.delete();
            await notifySenderOfBlock(
                senderId,
                "Messages may not contain more than 5 mentions.",
                "mention_cap"
            ).catch(() => { /* best-effort */ });
            return;
        }

        // ── 6. Escalation check for persistent offenders ──────────────────
        // If the sender has a history of critical/severe violations in the last 30 days
        // but no current restriction, check if this send should trigger a queue review.
        // We do NOT block the message here — this is a monitoring path.
        try {
            const counts = await getRecentViolationCounts(senderId, 30);

            if (
                counts.critical >= CRITICAL_VIOLATION_THRESHOLD ||
                counts.severe >= SEVERE_VIOLATION_THRESHOLD
            ) {
                functions.logger.warn(
                    `[AntiHarassment] User ${senderId} has ${counts.critical} critical / ` +
                    `${counts.severe} severe violations in 30 days — flagging for review.`
                );

                // Write to moderation queue for human review (non-blocking, fire-and-forget).
                db.collection("moderationQueue").add({
                    type: "high_risk_sender_dm",
                    senderId,
                    recipientId,
                    conversationId,
                    messageId,
                    violationCounts: counts,
                    priority: counts.critical >= CRITICAL_VIOLATION_THRESHOLD ? "high" : "medium",
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    policyVersion: "2026-03-06",
                }).catch((err) => functions.logger.error("[AntiHarassment] moderationQueue write failed", err));
            }
        } catch (err) {
            // Non-fatal — escalation check must not block message delivery.
            functions.logger.error("[AntiHarassment] Escalation check error (non-fatal)", err);
        }
    });

// ─── Comment Mention Cap ─────────────────────────────────────────────────────

/**
 * Section-13 FIX: Server-side enforcement of the 5-mention cap on comments.
 *
 * A client-side cap in AntiHarassmentEngine.swift can be bypassed by posting
 * directly through the Firestore SDK or REST API. This trigger enforces the cap
 * unconditionally: any comment with more than 5 @mentions is deleted immediately
 * and a moderation record is written for the author.
 *
 * The cap mirrors AntiHarassmentEngine.maxMentionsPerPost (5) so both layers
 * agree on the threshold. Adjust MAX_MENTIONS_PER_COMMENT if the client value changes.
 */
const MAX_MENTIONS_PER_COMMENT = 5;

export const enforceCommentMentionCap = onDocumentCreated("comments/{commentId}", async (event) => {
    const commentId = event.params.commentId;
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    if (!data) return;

    const text: string = data.text ?? data.content ?? "";
    const mentionCount = (text.match(/@\w+/g) ?? []).length;

    if (mentionCount <= MAX_MENTIONS_PER_COMMENT) return;

    const authorId: string = data.authorId ?? data.userId ?? "";

    logger.info(
            `[CommentMentionCap] Deleting comment ${commentId} — ` +
            `${mentionCount} mentions exceeds cap of ${MAX_MENTIONS_PER_COMMENT} (author: ${authorId})`
        );

    // Delete the comment unconditionally.
    await snap.ref.delete();

    // Write a moderation record so the author's mention abuse is trackable.
    if (authorId) {
        await db.collection("enforcementHistory").add({
            userId: authorId,
            violation: "mention_spam",
            action: "comment_deleted",
            contentId: commentId,
            contentType: "comment",
            surface: "comments",
            mentionCount,
            cap: MAX_MENTIONS_PER_COMMENT,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            confidence: 1.0,
            source: "server_enforcement",
            policyVersion: "2026-04-16",
        }).catch((err) =>
            logger.error("[CommentMentionCap] enforcementHistory write failed", err)
        );
    }
});

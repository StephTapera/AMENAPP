/**
 * messaging.ts
 * AMEN — Global Resilience Wave 1
 *
 * Callable Cloud Functions for resilient global messaging:
 *   sendMessageGlobal  — Auth + App Check gated, idempotent message write with
 *                        pre-delivery hold gate, block-check, and privacy-aware
 *                        FCM push.
 *   getThreadOfflineCache — Returns the last 50 messages in a thread for
 *                           offline-first clients.
 *
 * Region: us-central1.
 *
 * Firestore layout:
 *   /threads/{threadId}/messages/{messageId}
 *   /threads/{threadId}/processedIdempotencyKeys/{idempotencyKey}
 *   /devices/{uid}/capability_profiles/{deviceId}   — DeviceCapabilityProfile
 *   /trust_profiles/{userId}                         — TrustProfile
 *   /blockedUsers/{uidA_uidB}                        — block edge docs
 *   /moderationQueue                                 — held messages awaiting review
 *
 * H-3 Pre-delivery hold gate (status lifecycle):
 *   "sent"           — message passed screening; FCM push delivered to recipient
 *   "pending_review" — elevated-risk content; held from recipient until human
 *                      review; sender informed via response; no FCM push to recipient
 *
 * Fail-closed: if screenMessageBody throws for any reason, the message is held
 * (pending_review) rather than silently allowed through.
 */

import * as admin from "firebase-admin";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { requireAuthAndAppCheck, lightweightModeration } from "../amenAI/common";
import { isBlocked } from "../aclHelper";
import type { DmRiskLevel } from "./contracts";

// ─── Constants ────────────────────────────────────────────────────────────────

const REGION = "us-central1";

/** Max body text chars echoed in push notification preview. */
const FCM_BODY_PREVIEW_MAX = 50;

/** Max messages returned by getThreadOfflineCache. */
const OFFLINE_CACHE_LIMIT = 50;

/** Idempotency key TTL in milliseconds (7 days). */
const IDEMPOTENCY_TTL_MS = 7 * 24 * 60 * 60 * 1000;

// ─── Input validation helpers ─────────────────────────────────────────────────

function requireNonEmptyString(value: unknown, field: string, maxLen = 1024): string {
    if (typeof value !== "string" || !value.trim()) {
        throw new HttpsError("invalid-argument", `${field} must be a non-empty string.`);
    }
    if (value.length > maxLen) {
        throw new HttpsError("invalid-argument", `${field} exceeds maximum length of ${maxLen}.`);
    }
    return value.trim();
}

function optionalNonEmptyString(value: unknown, maxLen = 1024): string | null {
    if (value === undefined || value === null) return null;
    if (typeof value !== "string") {
        throw new HttpsError("invalid-argument", "Optional string fields must be strings.");
    }
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed.slice(0, maxLen) : null;
}

function parseClientTimestamp(value: unknown): number | null {
    if (typeof value === "number" && Number.isFinite(value)) return value;
    if (typeof value === "string") {
        const parsed = Date.parse(value);
        return Number.isFinite(parsed) ? parsed : null;
    }
    return null;
}

// ─── Pre-delivery content screening ──────────────────────────────────────────
//
// Two-tier keyword lists for DM-specific content.
//
// Crisis tier: language indicating the sender or recipient may be in danger.
//   A sent message with these keywords is held from the recipient, queued for
//   human review, and the sender receives a "pending_review" status.
//   This gives safety moderators the opportunity to escalate or connect
//   the involved parties with resources.
//
// High-risk tier: content that is strongly correlated with harassment,
//   sexual coercion, or targeted threats in private messaging contexts.
//   Same hold behavior as crisis tier.
//
// CONSERVATIVE BY DESIGN: some entries (e.g. "overdose") will produce false
// positives in benign contexts. The hold is not a punishment — the message
// is queued for review and released if it is benign. Fail-closed is the
// explicit requirement for this gate (H-3).
//
// lightweightModeration() from amenAI/common is additionally called on the
// full body to catch categories that are relevant to DMs but not covered by
// the keyword lists (impersonation, spiritual coercion, financial exploitation).
// If lightweightModeration() throws for any reason, the message is held.

const DM_CRISIS_KEYWORDS: string[] = [
    "end it", "end my life", "kill myself", "want to die", "can't go on",
    "cannot go on", "no reason to live", "take my life", "don't want to be here",
    "dont want to be here", "going to hurt myself", "hurt myself", "self harm",
    "self-harm", "cut myself", "overdose", "suicidal", "suicide",
];

const DM_HIGH_RISK_KEYWORDS: string[] = [
    "send nudes", "send pics", "send photos", "sexting",
    "i'll kill you", "ill kill you", "you're dead", "youre dead",
    "going to find you", "know where you live",
];

/**
 * screenMessageBody
 *
 * Runs the DM-specific keyword check followed by lightweightModeration().
 *
 * Returns { hold: true, reason } when the message should be withheld from the
 * recipient, or { hold: false, reason: "" } when it can be delivered.
 *
 * FAIL-CLOSED: any exception from lightweightModeration() produces hold=true
 * with reason="moderation_error". The caller must treat an exception from
 * screenMessageBody itself the same way (caller is required to default to hold).
 */
export function screenMessageBody(text: string): { hold: boolean; reason: string } {
    const lower = text.toLowerCase();

    for (const kw of DM_CRISIS_KEYWORDS) {
        if (lower.includes(kw)) return { hold: true, reason: "crisis_language" };
    }

    for (const kw of DM_HIGH_RISK_KEYWORDS) {
        if (lower.includes(kw)) return { hold: true, reason: "high_risk_content" };
    }

    // Secondary pass: catch categories not covered by keyword lists.
    try {
        const lwm = lightweightModeration(text);
        if (!lwm.ok) {
            return { hold: true, reason: lwm.reason ?? "policy_violation" };
        }
    } catch (_err) {
        // lightweightModeration threw — fail closed.
        return { hold: true, reason: "moderation_error" };
    }

    return { hold: false, reason: "" };
}

// ─── sendMessageGlobal ────────────────────────────────────────────────────────

interface SendMessageGlobalRequest {
    threadId: unknown;
    recipientId: unknown;
    bodyText?: unknown;
    mediaAssetId?: unknown;
    idempotencyKey: unknown;
    clientTimestamp?: unknown;
}

interface SendMessageGlobalResponse {
    messageId: string;
    status: "sent" | "pending_review";
    /** Set only when status="pending_review". Explains the hold to the sender; never shown to recipient. */
    holdReason?: string;
}

/**
 * sendMessageGlobal
 *
 * Server-authoritative DM send with:
 *   1. Auth + App Check enforcement
 *   2. Idempotency (7-day TTL key in /threads/{threadId}/processedIdempotencyKeys)
 *   3. Block relationship check (bidirectional, via aclHelper)
 *   4. Pre-delivery hold gate (H-3): screenMessageBody() before write
 *   5. Firestore write to /threads/{threadId}/messages/{newId}
 *      - status field: "sent" | "pending_review"
 *      - Held messages are also enqueued in /moderationQueue for human review
 *   6. Privacy-aware FCM push (suppressed for held messages):
 *        - sharedDeviceMode=true OR dmRiskLevel="high" → neutral payload
 *        - otherwise → senderName + body preview
 */
export const sendMessageGlobal = onCall<SendMessageGlobalRequest, Promise<SendMessageGlobalResponse>>(
    { enforceAppCheck: true, region: REGION },
    async (request): Promise<SendMessageGlobalResponse> => {
        // ── 1. Auth + App Check ──────────────────────────────────────────────
        const senderUid = await requireAuthAndAppCheck(request.auth ?? null, request.app ?? null);

        const db = getFirestore();

        // ── 2. Input validation ──────────────────────────────────────────────
        const data = request.data as SendMessageGlobalRequest;
        const threadId = requireNonEmptyString(data.threadId, "threadId", 128);
        const recipientId = requireNonEmptyString(data.recipientId, "recipientId", 128);
        const idempotencyKey = requireNonEmptyString(data.idempotencyKey, "idempotencyKey", 256);
        const bodyText = optionalNonEmptyString(data.bodyText, 10_000);
        const mediaAssetId = optionalNonEmptyString(data.mediaAssetId, 256);
        const clientTimestamp = parseClientTimestamp(data.clientTimestamp);

        // At least one of bodyText or mediaAssetId must be present.
        if (!bodyText && !mediaAssetId) {
            throw new HttpsError(
                "invalid-argument",
                "At least one of bodyText or mediaAssetId is required."
            );
        }

        // Sender cannot message themselves.
        if (senderUid === recipientId) {
            throw new HttpsError("invalid-argument", "Cannot send a message to yourself.");
        }

        // ── 3. Idempotency check ─────────────────────────────────────────────
        const idempotencyRef = db
            .collection("threads")
            .doc(threadId)
            .collection("processedIdempotencyKeys")
            .doc(idempotencyKey);

        const existingKeySnap = await idempotencyRef.get();
        if (existingKeySnap.exists) {
            const existing = existingKeySnap.data() ?? {};
            const cachedMessageId = existing.messageId as string | undefined;
            if (cachedMessageId) {
                logger.info("[sendMessageGlobal] Idempotent replay", {
                    senderUid,
                    threadId,
                    idempotencyKey,
                    cachedMessageId,
                });
                return { messageId: cachedMessageId, status: "sent" };
            }
        }

        // ── 4. Block check ───────────────────────────────────────────────────
        const blocked = await isBlocked(senderUid, recipientId);
        if (blocked) {
            logger.warn("[sendMessageGlobal] Block relationship detected", {
                senderUid,
                recipientId,
                threadId,
            });
            throw new HttpsError(
                "permission-denied",
                "You cannot send a message to this user."
            );
        }

        // ── 5. Pre-delivery hold gate (H-3) ─────────────────────────────────
        // Evaluate message body before writing to Firestore.
        // If screening throws for any reason we default to hold (fail-closed).
        // Media-only messages (no bodyText) are not screened here; they go
        // through the existing mediaModerationPipeline after upload.
        type DeliveryStatus = "sent" | "pending_review";
        let deliveryStatus: DeliveryStatus = "sent";
        let holdReason: string | undefined;

        if (bodyText) {
            let screening: { hold: boolean; reason: string };
            try {
                screening = screenMessageBody(bodyText);
            } catch (_screenErr) {
                // screenMessageBody itself threw — fail closed.
                screening = { hold: true, reason: "moderation_error" };
                logger.error("[sendMessageGlobal] screenMessageBody threw (fail-closed hold)", {
                    senderUid,
                    threadId,
                });
            }

            if (screening.hold) {
                deliveryStatus = "pending_review";
                holdReason = screening.reason;
                logger.info("[sendMessageGlobal] Message held for pre-delivery review", {
                    senderUid,
                    recipientId,
                    threadId,
                    holdReason,
                });
            }
        }

        // ── 6. Write message ─────────────────────────────────────────────────
        const threadRef = db.collection("threads").doc(threadId);
        const messageRef = threadRef.collection("messages").doc();
        const messageId = messageRef.id;

        const messagePayload: Record<string, unknown> = {
            messageId,
            threadId,
            senderId: senderUid,
            recipientId,
            bodyText: bodyText ?? null,
            mediaAssetId: mediaAssetId ?? null,
            idempotencyKey,
            clientTimestamp: clientTimestamp !== null
                ? Timestamp.fromMillis(clientTimestamp)
                : null,
            serverTimestamp: FieldValue.serverTimestamp(),
            // deliveryStatus controls recipient visibility (Firestore rules read this field).
            // "pending_review" messages are not visible to the recipient.
            status: deliveryStatus,
            ...(holdReason !== undefined ? { holdReason } : {}),
        };

        const now = Date.now();
        const expiresAt = Timestamp.fromMillis(now + IDEMPOTENCY_TTL_MS);

        const idempotencyPayload = {
            messageId,
            processedAt: FieldValue.serverTimestamp(),
            expiresAt,
        };

        // Atomic batch: message doc + idempotency key doc.
        const batch = db.batch();
        batch.set(messageRef, messagePayload);
        batch.set(idempotencyRef, idempotencyPayload);
        await batch.commit();

        logger.info("[sendMessageGlobal] Message written", {
            senderUid,
            recipientId,
            threadId,
            messageId,
            deliveryStatus,
        });

        // ── 7. Enqueue held messages for human review ────────────────────────
        // Non-blocking. Failure to enqueue must not fail the callable — the message
        // is already written with status="pending_review" and is safe.
        if (deliveryStatus === "pending_review") {
            db.collection("moderationQueue").add({
                type: "dm_pre_delivery_hold",
                senderId: senderUid,
                recipientId,
                threadId,
                messageId,
                holdReason,
                priority: holdReason === "crisis_language" ? "high" : "medium",
                createdAt: FieldValue.serverTimestamp(),
                policyVersion: "2026-06-16",
            }).catch((err) =>
                logger.error("[sendMessageGlobal] moderationQueue write failed (non-fatal)", err)
            );
        }

        // ── 8. FCM push — suppressed for held messages ───────────────────────
        // The recipient must never receive a notification about a message that
        // has not yet been cleared for delivery.
        if (deliveryStatus === "sent") {
            try {
                await sendFcmPush({
                    senderUid,
                    recipientId,
                    messageId,
                    threadId,
                    bodyText,
                });
            } catch (fcmErr) {
                logger.error(
                    "[sendMessageGlobal] FCM push failed (non-fatal)",
                    { senderUid, recipientId, messageId },
                    fcmErr
                );
            }
        }

        return {
            messageId,
            status: deliveryStatus,
            ...(holdReason !== undefined ? { holdReason } : {}),
        };
    }
);

// ─── FCM push helper ──────────────────────────────────────────────────────────

interface FcmPushParams {
    senderUid: string;
    recipientId: string;
    messageId: string;
    threadId: string;
    bodyText: string | null;
}

/**
 * Reads the recipient's device record (sharedDeviceMode) and trust profile
 * (dmRiskLevel), then sends an FCM push with the appropriate privacy level.
 *
 * Privacy rules:
 *   - sharedDeviceMode === true  → neutral payload (no sender name / content)
 *   - dmRiskLevel === "high"     → neutral payload
 *   - otherwise                  → include senderName + first 50 chars of bodyText
 *
 * Only called when deliveryStatus === "sent". Held messages never trigger FCM.
 */
async function sendFcmPush(params: FcmPushParams): Promise<void> {
    const { senderUid, recipientId, messageId, threadId, bodyText } = params;
    const db = getFirestore();

    // Fetch sender's display name for the push notification.
    const senderDoc = await db.collection("users").doc(senderUid).get();
    const senderData = senderDoc.data() ?? {};
    const senderName: string =
        (senderData.displayName as string | undefined) ??
        (senderData.username as string | undefined) ??
        "Someone";

    // Fetch recipient's device record (most recently updated capability profile).
    let sharedDeviceMode = false;
    try {
        const deviceSnap = await db
            .collection("devices")
            .doc(recipientId)
            .collection("capability_profiles")
            .orderBy("updated_at", "desc")
            .limit(1)
            .get();

        if (!deviceSnap.empty) {
            const deviceData = deviceSnap.docs[0].data();
            sharedDeviceMode = deviceData.shared_device_mode === true;
        }
    } catch (deviceErr) {
        // Non-fatal — default to false (more informative push).
        logger.warn("[sendMessageGlobal] Could not read device capability profile", { recipientId }, deviceErr);
    }

    // Fetch recipient's trust profile for dmRiskLevel.
    let dmRiskLevel: DmRiskLevel = "low";
    try {
        const trustSnap = await db.collection("trust_profiles").doc(recipientId).get();
        if (trustSnap.exists) {
            const trustData = trustSnap.data() ?? {};
            const raw = trustData.dm_risk_level as string | undefined;
            if (raw === "low" || raw === "medium" || raw === "high" || raw === "blocked") {
                dmRiskLevel = raw;
            }
        }
    } catch (trustErr) {
        // Non-fatal — default to "low".
        logger.warn("[sendMessageGlobal] Could not read trust profile", { recipientId }, trustErr);
    }

    // P1-I: Check whether the recipient has muted the sender.
    // Muted users must not generate push notifications to the muting user.
    try {
        const muteDoc = await db
            .collection("users").doc(recipientId)
            .collection("mutedUsers").doc(senderUid).get();
        if (muteDoc.exists) {
            logger.info("[sendMessageGlobal] Recipient has muted sender — suppressing push", { recipientId, senderUid });
            return;
        }
    } catch (muteErr) {
        // Non-fatal — if mute check fails, fall through and deliver the push.
        logger.warn("[sendMessageGlobal] Could not check mute status (non-fatal)", { recipientId, senderUid }, muteErr);
    }

    // Fetch recipient's FCM token.
    const recipientDoc = await db.collection("users").doc(recipientId).get();
    const recipientData = recipientDoc.data() ?? {};
    const fcmToken: string | undefined =
        (recipientData.fcmToken as string | undefined) ??
        (recipientData.pushToken as string | undefined);

    if (!fcmToken) {
        logger.info("[sendMessageGlobal] No FCM token for recipient — skipping push", { recipientId });
        return;
    }

    // Build notification payload based on privacy flags.
    const useNeutralPayload = sharedDeviceMode || dmRiskLevel === "high";

    const notificationPayload: admin.messaging.Notification = useNeutralPayload
        ? { title: "AMEN", body: "New private message" }
        : {
            title: senderName,
            body: bodyText
                ? bodyText.substring(0, FCM_BODY_PREVIEW_MAX)
                : "Sent you a message",
        };

    const message: admin.messaging.Message = {
        token: fcmToken,
        notification: notificationPayload,
        data: {
            type: "dm",
            threadId,
            messageId,
        },
        apns: {
            payload: {
                aps: {
                    sound: "default",
                    badge: 1,
                    // content-available: 1 enables background delivery on iOS.
                    "content-available": 1,
                    // mutable-content: 1 allows the iOS Notification Service Extension
                    // to modify the notification before display (e.g. decrypt body).
                    "mutable-content": 1,
                },
            },
        },
    };

    await admin.messaging().send(message);

    logger.info("[sendMessageGlobal] FCM push sent", {
        recipientId,
        messageId,
        neutralPayload: useNeutralPayload,
    });
}

// ─── getThreadOfflineCache ────────────────────────────────────────────────────

interface GetThreadOfflineCacheRequest {
    threadId: unknown;
    since?: unknown;
}

interface ThreadMessage {
    messageId: string;
    threadId: string;
    senderId: string;
    recipientId: string;
    bodyText: string | null;
    mediaAssetId: string | null;
    idempotencyKey: string;
    clientTimestamp: Timestamp | null;
    serverTimestamp: Timestamp | null;
    status: string;
}

interface GetThreadOfflineCacheResponse {
    messages: ThreadMessage[];
    count: number;
}

/**
 * getThreadOfflineCache
 *
 * Returns the last 50 messages in a thread, ordered newest-first.
 * Optional `since` timestamp (millis or ISO string) filters to messages
 * written after that point (useful for incremental sync).
 *
 * Auth + App Check required. Thread participant membership is verified
 * by checking that the caller's UID appears as either senderId or recipientId
 * in the first message fetched, or that they are listed in the thread document.
 *
 * Messages with status="pending_review" are included in the response for
 * the sender (so they can see "under review" state in their own thread view),
 * but the iOS client is responsible for filtering them out of the recipient's
 * message list until the status changes to "sent".
 */
export const getThreadOfflineCache = onCall<
    GetThreadOfflineCacheRequest,
    Promise<GetThreadOfflineCacheResponse>
>(
    { enforceAppCheck: true, region: REGION },
    async (request): Promise<GetThreadOfflineCacheResponse> => {
        // ── 1. Auth + App Check ──────────────────────────────────────────────
        const callerUid = await requireAuthAndAppCheck(request.auth ?? null, request.app ?? null);

        const db = getFirestore();

        // ── 2. Input validation ──────────────────────────────────────────────
        const data = request.data as GetThreadOfflineCacheRequest;
        const threadId = requireNonEmptyString(data.threadId, "threadId", 128);

        let sinceTimestamp: Timestamp | null = null;
        if (data.since !== undefined && data.since !== null) {
            const sinceMillis = parseClientTimestamp(data.since);
            if (sinceMillis !== null) {
                sinceTimestamp = Timestamp.fromMillis(sinceMillis);
            }
        }

        // ── 3. Verify thread participant membership ──────────────────────────
        const threadRef = db.collection("threads").doc(threadId);
        const threadSnap = await threadRef.get();

        if (!threadSnap.exists) {
            throw new HttpsError("not-found", "Thread not found.");
        }

        const threadData = threadSnap.data() ?? {};
        const participantIds: string[] = Array.isArray(threadData.participantIds)
            ? (threadData.participantIds as unknown[]).filter(
                (id): id is string => typeof id === "string"
            )
            : [];

        // If participantIds is not stored on the thread doc, fall through to
        // checking individual message ownership (handled below after fetch).
        const participantsKnown = participantIds.length > 0;
        if (participantsKnown && !participantIds.includes(callerUid)) {
            throw new HttpsError(
                "permission-denied",
                "You are not a participant in this thread."
            );
        }

        // ── 4. Query messages ────────────────────────────────────────────────
        let query = threadRef
            .collection("messages")
            .orderBy("serverTimestamp", "desc")
            .limit(OFFLINE_CACHE_LIMIT);

        if (sinceTimestamp) {
            query = query.where("serverTimestamp", ">", sinceTimestamp);
        }

        const messagesSnap = await query.get();

        // ── 5. Participant check via message ownership (fallback) ────────────
        // If thread doc has no participantIds, verify caller owns or is recipient
        // of at least one message in the result set.
        if (!participantsKnown && !messagesSnap.empty) {
            const hasAccess = messagesSnap.docs.some((doc) => {
                const d = doc.data();
                return d.senderId === callerUid || d.recipientId === callerUid;
            });
            if (!hasAccess) {
                throw new HttpsError(
                    "permission-denied",
                    "You are not a participant in this thread."
                );
            }
        }

        // ── 6. Shape response ────────────────────────────────────────────────
        const messages: ThreadMessage[] = messagesSnap.docs.map((doc) => {
            const d = doc.data();
            return {
                messageId: (d.messageId as string | undefined) ?? doc.id,
                threadId: (d.threadId as string | undefined) ?? threadId,
                senderId: (d.senderId as string | undefined) ?? "",
                recipientId: (d.recipientId as string | undefined) ?? "",
                bodyText: (d.bodyText as string | null | undefined) ?? null,
                mediaAssetId: (d.mediaAssetId as string | null | undefined) ?? null,
                idempotencyKey: (d.idempotencyKey as string | undefined) ?? "",
                clientTimestamp:
                    d.clientTimestamp instanceof Timestamp ? d.clientTimestamp : null,
                serverTimestamp:
                    d.serverTimestamp instanceof Timestamp ? d.serverTimestamp : null,
                status: (d.status as string | undefined) ?? "sent",
            };
        });

        logger.info("[getThreadOfflineCache] Returning messages", {
            callerUid,
            threadId,
            count: messages.length,
        });

        return { messages, count: messages.length };
    }
);

/**
 * messaging.ts
 * AMEN — Global Resilience Wave 1
 *
 * Callable Cloud Functions for resilient global messaging:
 *   sendMessageGlobal  — Auth + App Check gated, idempotent message write with
 *                        block-check and privacy-aware FCM push.
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
 */

import * as admin from "firebase-admin";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { requireAuthAndAppCheck } from "../amenAI/common";
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
    status: "sent";
}

/**
 * sendMessageGlobal
 *
 * Server-authoritative DM send with:
 *   1. Auth + App Check enforcement
 *   2. Idempotency (7-day TTL key in /threads/{threadId}/processedIdempotencyKeys)
 *   3. Block relationship check (bidirectional, via aclHelper)
 *   4. Firestore write to /threads/{threadId}/messages/{newId}
 *   5. Privacy-aware FCM push:
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

        // ── 5. Write message ─────────────────────────────────────────────────
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
            status: "sent",
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
        });

        // ── 6. FCM push (non-blocking — failure must not fail the callable) ──
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

        return { messageId, status: "sent" };
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
 */
async function sendFcmPush(params: FcmPushParams): Promise<void> {
    const { senderUid, recipientId, messageId, threadId, bodyText } = params;
    const db = getFirestore();

    // 6a. Fetch sender's display name for the push notification.
    const senderDoc = await db.collection("users").doc(senderUid).get();
    const senderData = senderDoc.data() ?? {};
    const senderName: string =
        (senderData.displayName as string | undefined) ??
        (senderData.username as string | undefined) ??
        "Someone";

    // 6b. Fetch recipient's device record (most recently updated capability profile).
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

    // 6c. Fetch recipient's trust profile for dmRiskLevel.
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

    // 6d. Fetch recipient's FCM token.
    const recipientDoc = await db.collection("users").doc(recipientId).get();
    const recipientData = recipientDoc.data() ?? {};
    const fcmToken: string | undefined =
        (recipientData.fcmToken as string | undefined) ??
        (recipientData.pushToken as string | undefined);

    if (!fcmToken) {
        logger.info("[sendMessageGlobal] No FCM token for recipient — skipping push", { recipientId });
        return;
    }

    // 6e. Build notification payload based on privacy flags.
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

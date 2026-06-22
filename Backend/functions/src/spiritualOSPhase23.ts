import { defineSecret } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import { enforceRateLimit, RATE_LIMITS } from "./rateLimit";

const db = getFirestore();
const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

type HubItemType =
    | "message"
    | "prayerRequest"
    | "churchNoteMention"
    | "bereanAnswer"
    | "groupInvite"
    | "eventInvite"
    | "mentorResponse"
    | "testimony";

type AssistantQueryType = "text" | "voice" | "vision";

const HUB_ITEM_TYPES = new Set<HubItemType>([
    "message",
    "prayerRequest",
    "churchNoteMention",
    "bereanAnswer",
    "groupInvite",
    "eventInvite",
    "mentorResponse",
    "testimony",
]);

function requireAuthUser(requestUid: string | undefined, payloadUserId: unknown): string {
    if (!requestUid) {
        throw new HttpsError("unauthenticated", "Sign in required.");
    }
    if (typeof payloadUserId !== "string" || payloadUserId.length === 0) {
        throw new HttpsError("invalid-argument", "userId is required.");
    }
    if (payloadUserId !== requestUid) {
        throw new HttpsError("permission-denied", "Cannot access another user's Spiritual OS data.");
    }
    return requestUid;
}

async function requireSpiritualOSEnabled(): Promise<void> {
    const snap = await db.collection("serverFeatureFlags").doc("spiritualOS").get();
    if (!snap.exists || snap.data()?.enabled !== true) {
        throw new HttpsError("failed-precondition", "Spiritual OS server functions are disabled.");
    }
}

function pageSizeValue(value: unknown): number {
    if (typeof value !== "number" || !Number.isFinite(value)) {
        return 20;
    }
    return Math.max(1, Math.min(30, Math.floor(value)));
}

function boolValue(value: unknown, fallback = false): boolean {
    return typeof value === "boolean" ? value : fallback;
}

function stringValue(value: unknown, maxLength: number, fallback = ""): string {
    if (typeof value !== "string") {
        return fallback;
    }
    const trimmed = value.trim();
    if (!trimmed) {
        return fallback;
    }
    return trimmed.slice(0, maxLength);
}

function timestampMillis(value: unknown): number {
    if (value instanceof Timestamp) {
        return value.toMillis();
    }
    if (typeof value === "object" && value && "toMillis" in value && typeof value.toMillis === "function") {
        return value.toMillis();
    }
    if (typeof value === "number") {
        return value;
    }
    return Date.now();
}

export const spiritualOSGetHubItems = onCall(
    { enforceAppCheck: true, maxInstances: 50, timeoutSeconds: 10 },
    async (request) => {
        const uid = requireAuthUser(request.auth?.uid, request.data?.userId);
        await requireSpiritualOSEnabled();
        await enforceRateLimit(uid, [RATE_LIMITS.SUGGEST_PER_MINUTE, RATE_LIMITS.SUGGEST_PER_DAY]);

        const pageSize = pageSizeValue(request.data?.pageSize);
        const filterType = stringValue(request.data?.filterType, 40);
        const cursor = stringValue(request.data?.cursor ?? request.data?.lastItemId, 160);

        let query = db
            .collection("spiritualOS_hub")
            .doc(uid)
            .collection("items")
            .where("isArchived", "==", false)
            .orderBy("createdAt", "desc")
            .limit(pageSize + 1);

        if (filterType && HUB_ITEM_TYPES.has(filterType as HubItemType)) {
            query = db
                .collection("spiritualOS_hub")
                .doc(uid)
                .collection("items")
                .where("isArchived", "==", false)
                .where("type", "==", filterType)
                .orderBy("createdAt", "desc")
                .limit(pageSize + 1);
        }

        if (cursor) {
            const cursorDoc = await db
                .collection("spiritualOS_hub")
                .doc(uid)
                .collection("items")
                .doc(cursor)
                .get();
            if (cursorDoc.exists) {
                query = query.startAfter(cursorDoc);
            }
        }

        const snap = await query.get();
        const docs = snap.docs.slice(0, pageSize);
        const hasMore = snap.docs.length > pageSize;

        return {
            items: docs.map((doc) => {
                const data = doc.data();
                const type = HUB_ITEM_TYPES.has(data.type) ? data.type : "message";
                return {
                    id: doc.id,
                    itemId: doc.id,
                    type,
                    tag: stringValue(data.tag, 32, type),
                    title: stringValue(data.title, 80, "Amen Hub"),
                    preview: stringValue(data.preview, 160),
                    senderUid: stringValue(data.senderUid, 128),
                    senderName: stringValue(data.senderName, 80),
                    senderAvatar: stringValue(data.senderAvatar, 500),
                    sourceRef: stringValue(data.sourceRef, 500, "amen://home"),
                    isPinned: boolValue(data.isPinned),
                    isRead: boolValue(data.isRead),
                    createdAt: timestampMillis(data.createdAt),
                };
            }),
            hasMore,
            nextCursor: hasMore ? docs[docs.length - 1]?.id ?? null : null,
        };
    }
);

export const spiritualOSPinHubItem = onCall(
    { enforceAppCheck: true, maxInstances: 50, timeoutSeconds: 10 },
    async (request) => {
        const uid = requireAuthUser(request.auth?.uid, request.data?.userId);
        await requireSpiritualOSEnabled();
        await enforceRateLimit(uid, [RATE_LIMITS.SUGGEST_PER_MINUTE]);

        const itemId = stringValue(request.data?.itemId, 160);
        if (!itemId) {
            throw new HttpsError("invalid-argument", "itemId is required.");
        }
        const isPinned = boolValue(request.data?.isPinned ?? request.data?.pinned);

        await db
            .collection("spiritualOS_hub")
            .doc(uid)
            .collection("items")
            .doc(itemId)
            .update({
                isPinned,
                updatedAt: FieldValue.serverTimestamp(),
            });

        return { success: true };
    }
);

export const spiritualOSUpdateContextState = onCall(
    { enforceAppCheck: true, maxInstances: 50, timeoutSeconds: 10 },
    async (request) => {
        const uid = requireAuthUser(request.auth?.uid, request.data?.userId);
        await requireSpiritualOSEnabled();
        await enforceRateLimit(uid, [RATE_LIMITS.SUGGEST_PER_MINUTE, RATE_LIMITS.SUGGEST_PER_DAY]);

        await db.collection("spiritualOS_context").doc(uid).set(
            {
                userId: uid,
                mode: stringValue(request.data?.mode, 40, "default"),
                timeOfDay: stringValue(request.data?.timeOfDay, 40, "morning"),
                isSundayChurchTime: boolValue(request.data?.isSundayChurchTime),
                isNearChurch: boolValue(request.data?.isNearChurch),
                isDriving: boolValue(request.data?.isDriving),
                isTraveling: boolValue(request.data?.isTraveling),
                userPermissions: {
                    locationEnabled: boolValue(request.data?.userPermissions?.locationEnabled),
                    motionEnabled: boolValue(request.data?.userPermissions?.motionEnabled),
                    geofenceOptIn: boolValue(request.data?.userPermissions?.geofenceOptIn),
                    audioAutoPlay: boolValue(request.data?.userPermissions?.audioAutoPlay),
                },
                lastUpdated: FieldValue.serverTimestamp(),
            },
            { merge: true }
        );

        return { success: true };
    }
);

export const spiritualOSCleanupContextOnLogout = onCall(
    { enforceAppCheck: true, maxInstances: 50, timeoutSeconds: 10 },
    async (request) => {
        const uid = requireAuthUser(request.auth?.uid, request.data?.userId);
        await requireSpiritualOSEnabled();
        await enforceRateLimit(uid, [RATE_LIMITS.SUGGEST_PER_MINUTE]);

        await db.collection("spiritualOS_context").doc(uid).delete();
        return { success: true };
    }
);

export const spiritualOSAssistant = onCall(
    { enforceAppCheck: true, maxInstances: 20, timeoutSeconds: 30, secrets: [anthropicApiKey] },
    async (request) => {
        const uid = requireAuthUser(request.auth?.uid, request.data?.userId);
        await requireSpiritualOSEnabled();
        await enforceRateLimit(uid, [RATE_LIMITS.AI_PER_MINUTE, RATE_LIMITS.AI_PER_DAY]);

        const query = stringValue(request.data?.query, 1000);
        const queryType = stringValue(request.data?.queryType, 12, "text") as AssistantQueryType;
        const surfaceContext = stringValue(request.data?.surfaceContext, 40, "assistantBar");
        const contextMode = stringValue(request.data?.contextMode, 40, "default");
        if (!query) {
            throw new HttpsError("invalid-argument", "query is required.");
        }
        if (!["text", "voice", "vision"].includes(queryType)) {
            throw new HttpsError("invalid-argument", "Unsupported queryType.");
        }
        if (queryType === "vision") {
            const imageBase64 = stringValue(request.data?.imageBase64, 2_800_000);
            if (!imageBase64) {
                throw new HttpsError("invalid-argument", "imageBase64 is required for vision queries.");
            }
        }

        const apiKey = anthropicApiKey.value();
        if (!apiKey) {
            throw new HttpsError("unavailable", "Berean Assistant is not configured.");
        }

        const response = await fetch("https://api.anthropic.com/v1/messages", {
            method: "POST",
            headers: {
                "content-type": "application/json",
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
            },
            body: JSON.stringify({
                model: "claude-3-5-haiku-20241022",
                max_tokens: 420,
                temperature: 0.3,
                system:
                    "You are Berean inside AMEN. Answer briefly, gently, and formation-first. " +
                    "Do not create guilt, streak pressure, public comparison, or engagement bait. " +
                    "If scripture is referenced, name the reference. If uncertain, say so.",
                messages: [
                    {
                        role: "user",
                        content:
                            `Surface: ${surfaceContext}\nContext mode: ${contextMode}\n` +
                            `Query type: ${queryType}\nQuestion: ${query}`,
                    },
                ],
            }),
        });

        if (!response.ok) {
            throw new HttpsError("unavailable", "Berean Assistant is temporarily unavailable.");
        }

        const body = (await response.json()) as {
            content?: Array<{ type?: string; text?: string }>;
        };
        const answer = body.content?.find((part) => part.type === "text")?.text?.trim() ?? "";
        if (!answer) {
            throw new HttpsError("internal", "Berean Assistant returned an empty response.");
        }

        return {
            answer,
            sources: [],
            suggestedFollowUps: [
                "Show me a passage",
                "Help me pray this",
                "Make this practical",
            ],
            aiDisclosureLabel: "Berean AI",
        };
    }
);

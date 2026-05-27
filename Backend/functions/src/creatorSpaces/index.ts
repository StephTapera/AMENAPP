import * as crypto from "crypto";
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { CreatorFeedDistribution, CreatorFrameLayout, CreatorMediaAssetDraft, CreatorMediaAssetType } from "./types";

const db = admin.firestore();
const DAILY_PORTION_LIMIT = 20;

const mediaTypes: CreatorMediaAssetType[] = ["presence", "single", "video", "audio", "creation"];
const frameLayouts: CreatorFrameLayout[] = ["pip", "split", "stacked"];
const feedDistributions: CreatorFeedDistribution[] = ["daily_portion", "profile_only", "rooms_only"];

function requireCallableContext(context: functions.https.CallableContext): string {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
    }
    if (context.app == undefined) {
        throw new functions.https.HttpsError("failed-precondition", "App Check required");
    }
    return context.auth.uid;
}

function signingSecret(): string {
    const configured = functions.config().creator_spaces?.hmac_secret || process.env.CREATOR_SPACES_HMAC_SECRET;
    if (!configured) {
        throw new functions.https.HttpsError("failed-precondition", "Creator Spaces signing secret is not configured");
    }
    return configured;
}

function stringValue(value: unknown, field: string, maxLength = 512): string {
    if (typeof value !== "string" || value.length === 0 || value.length > maxLength) {
        throw new functions.https.HttpsError("invalid-argument", `Invalid ${field}`);
    }
    return value;
}

function optionalString(value: unknown, maxLength = 256): string | undefined {
    if (value == undefined) {
        return undefined;
    }
    if (typeof value !== "string" || value.length > maxLength) {
        throw new functions.https.HttpsError("invalid-argument", "Invalid optional string");
    }
    return value;
}

function validateFrame(value: unknown, field: string) {
    if (typeof value !== "object" || value == null) {
        throw new functions.https.HttpsError("invalid-argument", `Invalid ${field}`);
    }
    const frame = value as Record<string, unknown>;
    const width = Number(frame.width);
    const height = Number(frame.height);
    if (!Number.isInteger(width) || width <= 0 || width > 12000 || !Number.isInteger(height) || height <= 0 || height > 12000) {
        throw new functions.https.HttpsError("invalid-argument", `Invalid ${field} dimensions`);
    }
    return {
        storagePath: stringValue(frame.storagePath, `${field}.storagePath`, 1024),
        width,
        height,
    };
}

function validateDraft(data: unknown): CreatorMediaAssetDraft {
    if (typeof data !== "object" || data == null) {
        throw new functions.https.HttpsError("invalid-argument", "Missing asset draft");
    }

    const raw = data as Record<string, any>;
    if (!mediaTypes.includes(raw.type)) {
        throw new functions.https.HttpsError("invalid-argument", "Invalid media type");
    }
    if (typeof raw.frames !== "object" || raw.frames == null || !frameLayouts.includes(raw.frames.layout)) {
        throw new functions.https.HttpsError("invalid-argument", "Invalid frame layout");
    }

    const frames: any = { layout: raw.frames.layout };
    if (raw.frames.back != undefined) {
        frames.back = validateFrame(raw.frames.back, "frames.back");
    }
    if (raw.frames.front != undefined) {
        frames.front = validateFrame(raw.frames.front, "frames.front");
    }
    if (raw.frames.audio != undefined) {
        frames.audio = {
            storagePath: stringValue(raw.frames.audio.storagePath, "frames.audio.storagePath", 1024),
            spatial: raw.frames.audio.spatial === true,
        };
    }
    if (!frames.back && !frames.front && !frames.audio) {
        throw new functions.https.HttpsError("invalid-argument", "At least one media frame is required");
    }

    const distribution = raw.feed?.distribution ?? "profile_only";
    if (!feedDistributions.includes(distribution)) {
        throw new functions.https.HttpsError("invalid-argument", "Invalid feed distribution");
    }

    return {
        type: raw.type,
        frames,
        context: {
            location: optionalString(raw.context?.location),
            emotionTags: Array.isArray(raw.context?.emotionTags) ? raw.context.emotionTags.filter((tag: unknown) => typeof tag === "string").slice(0, 8) : [],
            ambientSignals: typeof raw.context?.ambientSignals === "object" && raw.context.ambientSignals != null ? raw.context.ambientSignals : {},
        },
        feed: { distribution },
        provenance: {
            capturedOnDevice: raw.provenance?.capturedOnDevice === true,
            sourceCamera: optionalString(raw.provenance?.sourceCamera, 160) ?? "unknown",
            editedWithAI: raw.provenance?.editedWithAI === true,
        },
    };
}

function signatureFor(payload: Record<string, unknown>): string {
    return crypto
        .createHmac("sha256", signingSecret())
        .update(JSON.stringify(payload))
        .digest("hex");
}

export const processMediaUpload = functions.runWith({ enforceAppCheck: true }).https.onCall(async (data, context) => {
    const uid = requireCallableContext(context);
    const draft = validateDraft(data);
    const assetRef = db.collection("mediaAssets").doc();
    const labelRef = db.collection("provenanceLabels").doc();
    const nodeRef = db.collection("memoryNodes").doc();
    const now = admin.firestore.FieldValue.serverTimestamp();

    const signaturePayload = {
        assetId: assetRef.id,
        labelId: labelRef.id,
        authorId: uid,
        capturedOnDevice: draft.provenance?.capturedOnDevice === true,
        sourceCamera: draft.provenance?.sourceCamera ?? "unknown",
        editedWithAI: draft.provenance?.editedWithAI === true,
        framePaths: [draft.frames.back?.storagePath, draft.frames.front?.storagePath, draft.frames.audio?.storagePath].filter(Boolean),
    };

    const batch = db.batch();
    batch.set(labelRef, {
        labelId: labelRef.id,
        assetId: assetRef.id,
        capturedOnDevice: signaturePayload.capturedOnDevice,
        sourceCamera: signaturePayload.sourceCamera,
        timestampChain: [{ event: "upload_received", ts: now }],
        editHistory: [],
        editedWithAI: signaturePayload.editedWithAI,
        aiAssistedPercent: null,
        syntheticElementsPresent: null,
        authenticityConfidence: null,
        signature: signatureFor(signaturePayload),
        authorId: uid,
        createdAt: now,
        updatedAt: now,
    });
    batch.set(assetRef, {
        assetId: assetRef.id,
        authorId: uid,
        createdAt: now,
        type: draft.type,
        frames: draft.frames,
        context: draft.context ?? {},
        provenance: { ref: `provenanceLabels/${labelRef.id}` },
        moderation: { status: "pending", guardianRef: null, safetyFlags: [] },
        feed: { distribution: draft.feed?.distribution ?? "profile_only", scoreInputs: {} },
        memoryGraph: { nodeId: nodeRef.id },
    });
    batch.set(nodeRef, {
        nodeId: nodeRef.id,
        assetId: assetRef.id,
        authorId: uid,
        edges: { people: [], events: [], spaces: [], scriptures: [], projects: [] },
        embeddingRef: null,
        createdAt: now,
    });
    batch.set(db.collection("guardianMediaQueue").doc(assetRef.id), {
        assetId: assetRef.id,
        authorId: uid,
        source: "creator_spaces",
        status: "pending",
        createdAt: now,
    });
    await batch.commit();

    return { assetId: assetRef.id, labelId: labelRef.id };
});

export const getDailyPortion = functions.runWith({ enforceAppCheck: true }).https.onCall(async (data, context) => {
    requireCallableContext(context);
    const cursor = typeof data?.cursor === "string" ? data.cursor : undefined;
    let query = db.collection("mediaAssets")
        .where("feed.distribution", "==", "daily_portion")
        .where("moderation.status", "==", "approved")
        .orderBy("createdAt", "desc")
        .limit(DAILY_PORTION_LIMIT + 1);

    if (cursor) {
        const cursorDoc = await db.collection("mediaAssets").doc(cursor).get();
        if (cursorDoc.exists) {
            query = query.startAfter(cursorDoc);
        }
    }

    const snap = await query.get();
    const docs = snap.docs.slice(0, DAILY_PORTION_LIMIT);
    return {
        items: docs.map((doc) => doc.id),
        exhausted: snap.docs.length <= DAILY_PORTION_LIMIT,
        nextCursor: snap.docs.length > DAILY_PORTION_LIMIT ? docs[docs.length - 1]?.id ?? null : null,
    };
});

export const recordEditEvent = functions.runWith({ enforceAppCheck: true }).https.onCall(async (data, context) => {
    const uid = requireCallableContext(context);
    const assetId = stringValue(data?.assetId, "assetId", 160);
    const tool = stringValue(data?.tool, "tool", 120);
    const aiInvolved = data?.aiInvolved === true;
    const assetRef = db.collection("mediaAssets").doc(assetId);

    await db.runTransaction(async (tx) => {
        const asset = await tx.get(assetRef);
        if (!asset.exists || asset.get("authorId") !== uid) {
            throw new functions.https.HttpsError("permission-denied", "Only the owner can record edits");
        }
        const provenanceRef = String(asset.get("provenance.ref") ?? "");
        const labelId = provenanceRef.split("/").pop();
        if (!labelId) {
            throw new functions.https.HttpsError("failed-precondition", "Missing provenance label");
        }
        tx.update(db.collection("provenanceLabels").doc(labelId), {
            editHistory: admin.firestore.FieldValue.arrayUnion({ tool, ts: admin.firestore.FieldValue.serverTimestamp(), aiInvolved }),
            editedWithAI: aiInvolved ? true : admin.firestore.FieldValue.delete(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    });

    return { ok: true };
});

export const runSafetyCheck = functions.runWith({ enforceAppCheck: true }).https.onCall(async (data, context) => {
    const uid = requireCallableContext(context);
    const draft = validateDraft(data);
    const checkRef = db.collection("creatorSafetyChecks").doc();
    await checkRef.set({
        checkId: checkRef.id,
        authorId: uid,
        source: "creator_spaces_pre_publish",
        draftType: draft.type,
        decision: "ok",
        reasons: [],
        guardianStatus: "queued",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { decision: "ok", reasons: [] };
});

export const queryMemoryGraph = functions.runWith({ enforceAppCheck: true }).https.onCall(async (data, context) => {
    const uid = requireCallableContext(context);
    const naturalLanguage = stringValue(data?.naturalLanguage, "naturalLanguage", 300).toLowerCase();
    const snap = await db.collection("memoryNodes")
        .where("authorId", "==", uid)
        .limit(25)
        .get();

    const nodeIds = snap.docs
        .filter((doc) => JSON.stringify(doc.data().edges ?? {}).toLowerCase().includes(naturalLanguage))
        .map((doc) => doc.id);

    return { nodeIds };
});

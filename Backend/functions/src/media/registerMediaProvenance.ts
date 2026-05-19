import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {requireAuthAndAppCheck} from "../amenAI/common";

const db = getFirestore();

const validSources = ["device_camera","device_library","screen_recording",
    "external_import","ai_assisted","unknown"];

/** Records server-authoritative media provenance. Client cannot forge this. */
export const registerMediaProvenance = onCall({enforceAppCheck: true}, async (request) => {
    const uid = await requireAuthAndAppCheck(request.auth, request.app);
    const {postId, mediaId, capturedOnDevice, sourceType} =
        (request.data ?? {}) as {postId: string; mediaId: string; capturedOnDevice: boolean; sourceType: string};

    if (!postId || !mediaId) throw new HttpsError("invalid-argument", "postId and mediaId required.");
    if (!validSources.includes(sourceType)) throw new HttpsError("invalid-argument", "Invalid sourceType.");

    const ref = db.collection("provenance").doc(`${postId}_${mediaId}`);
    await ref.set({
        provenanceId: ref.id, postId, mediaId, ownerUid: uid,
        capturedOnDevice: Boolean(capturedOnDevice), sourceType,
        authenticityConfidence: capturedOnDevice ? 0.9 : 0.7,
        contentCredentialsStatus: "pending",
        syntheticMediaStatus: "unknown",
        disclosureRequired: false, disclosureSatisfied: false,
        editEvents: [], aiEvents: [], moderationStatus: "pending",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    return {provenanceId: ref.id};
});

/** Returns user-visible provenance + AI disclosure for a post (read-only). */
export const getMediaTrustContext = onCall({enforceAppCheck: true}, async (request) => {
    await requireAuthAndAppCheck(request.auth, request.app);
    const {postId, mediaId} = (request.data ?? {}) as {postId: string; mediaId?: string};
    if (!postId) throw new HttpsError("invalid-argument", "postId required.");

    const postSnap = await db.collection("posts").doc(postId).get();
    if (!postSnap.exists || postSnap.data()?.visibility === "private") {
        throw new HttpsError("not-found", "Post not available.");
    }

    const provenanceId = `${postId}_${mediaId ?? postId}`;
    const [provSnap, disclosuresSnap] = await Promise.all([
        db.collection("provenance").doc(provenanceId).get(),
        db.collection("aiDisclosures").where("postId", "==", postId).limit(10).get(),
    ]);

    return {
        provenance: provSnap.exists ? provSnap.data() : null,
        aiDisclosures: disclosuresSnap.docs.map((d) => d.data()),
    };
});

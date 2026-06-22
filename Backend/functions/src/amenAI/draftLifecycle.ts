import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {enforceRateLimit, RATE_LIMITS} from "../rateLimit";
import {requireAuthAndAppCheck} from "./common";

const db = admin.firestore();

async function ownedDraft(uid: string, draftId: string) {
    const ref = db.collection("users").doc(uid).collection("generatedDrafts").doc(draftId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Draft not found.");
    return {ref, data: snap.data()!};
}

export const approveGeneratedDraft = onCall({enforceAppCheck: true}, async (request) => {
    const uid = await requireAuthAndAppCheck(request.auth, request.app);
    const draftId = String(request.data?.draftId ?? "").trim();
    const {ref, data} = await ownedDraft(uid, draftId);
    if (!["draft", "editing"].includes(data.status)) throw new HttpsError("failed-precondition", "Draft is not approvable.");
    if (data.ownerUid !== uid) throw new HttpsError("permission-denied", "You do not own this draft.");
    if ((data.provenance?.moderationStatus ?? "") !== "approved") {
        throw new HttpsError("failed-precondition", "Draft moderation not approved.");
    }

    const destination = String(request.data?.destination ?? "").trim();
    const destinationId = String(request.data?.destinationId ?? "").trim();

    await ref.set({
        status: "approved",
        provenance: {...data.provenance, userApproved: true, approvedAt: admin.firestore.FieldValue.serverTimestamp()},
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    if (destination && destinationId) {
        await db.collection("users").doc(uid).collection("approvedOutputs").doc().set({
            draftId,
            destination,
            destinationId,
            content: {
                title: data.title ?? null,
                body: data.body ?? null,
                mediaUrl: data.mediaUrl ?? null,
            },
            provenance: data.provenance ?? {},
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }

    await db.collection("aiAudit").doc("approvalEvents").collection("events").add({uid, draftId, action: "approved", createdAt: admin.firestore.FieldValue.serverTimestamp()});
    return {ok: true};
});

export const rejectGeneratedDraft = onCall({enforceAppCheck: true}, async (request) => {
    const uid = await requireAuthAndAppCheck(request.auth, request.app);
    const draftId = String(request.data?.draftId ?? "").trim();
    const {ref} = await ownedDraft(uid, draftId);
    await ref.set({status: "rejected", updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    await db.collection("aiAudit").doc("approvalEvents").collection("events").add({uid, draftId, action: "rejected", createdAt: admin.firestore.FieldValue.serverTimestamp()});
    return {ok: true};
});

export const editGeneratedDraft = onCall({enforceAppCheck: true}, async (request) => {
    const uid = await requireAuthAndAppCheck(request.auth, request.app);
    const draftId = String(request.data?.draftId ?? "").trim();
    const body = String(request.data?.body ?? "").trim();
    const {ref, data} = await ownedDraft(uid, draftId);
    if (!["draft", "editing"].includes(data.status)) throw new HttpsError("failed-precondition", "Draft is not editable.");
    if (data.ownerUid !== uid) throw new HttpsError("permission-denied", "You do not own this draft.");
    await ref.set({body, status: "editing", "provenance.userEdited": true, updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    return {ok: true};
});

export const regenerateGeneratedDraft = onCall({enforceAppCheck: true}, async (request) => {
    const uid = await requireAuthAndAppCheck(request.auth, request.app);
    await enforceRateLimit(uid, [RATE_LIMITS.AI_PER_MINUTE]);
    const draftId = String(request.data?.draftId ?? "").trim();
    const {data} = await ownedDraft(uid, draftId);
    if (data.ownerUid !== uid) throw new HttpsError("permission-denied", "You do not own this draft.");
    const nextRef = db.collection("users").doc(uid).collection("generatedDrafts").doc();
    await nextRef.set({...data, status: "draft", parentDraftId: draftId, createdAt: admin.firestore.FieldValue.serverTimestamp(), updatedAt: admin.firestore.FieldValue.serverTimestamp()});
    return {draftId: nextRef.id};
});

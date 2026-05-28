import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

const db = admin.firestore();

// ── Helpers ──────────────────────────────────────────────────────────────────

async function assertCommunityAdmin(
    communityId: string,
    uid: string
): Promise<void> {
    const memberSnap = await db
        .collection("communities").doc(communityId)
        .collection("members").doc(uid)
        .get();
    if (!memberSnap.exists) {
        throw new HttpsError("permission-denied", "Not a member of this community.");
    }
    const role = memberSnap.data()?.role as string | undefined;
    if (role !== "owner" && role !== "admin") {
        throw new HttpsError("permission-denied", "Admin or owner role required.");
    }
}

// ── createCommunity ───────────────────────────────────────────────────────────

export const createCommunity = onCall(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");

    const { name, handle, avatarURL } = request.data as {
        name: string;
        handle: string;
        avatarURL?: string;
    };

    if (!name || !handle) {
        throw new HttpsError("invalid-argument", "name and handle are required.");
    }

    // Rate limit: max 3 communities per userId.
    const existing = await db
        .collection("communities")
        .where("ownerUserId", "==", uid)
        .limit(3)
        .get();
    if (existing.size >= 3) {
        throw new HttpsError("resource-exhausted", "Maximum of 3 communities per account.");
    }

    // Validate handle uniqueness.
    const handleQuery = await db
        .collection("communities")
        .where("handle", "==", handle)
        .limit(1)
        .get();
    if (!handleQuery.empty) {
        throw new HttpsError("already-exists", "That handle is already taken.");
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const communityRef = db.collection("communities").doc();

    await db.runTransaction(async (tx) => {
        tx.set(communityRef, {
            name,
            handle,
            avatarURL: avatarURL ?? null,
            ownerUserId: uid,
            stripeConnectAccountId: null,
            createdAt: now,
        });

        tx.set(communityRef.collection("members").doc(uid), {
            role: "owner",
            joinedAt: now,
        });
    });

    logger.info("[createCommunity] Created", { communityId: communityRef.id, uid });
    return { communityId: communityRef.id };
});

// ── linkCommunity ─────────────────────────────────────────────────────────────

export const linkCommunity = onCall(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");

    const { sourceCommunityId, targetCommunityId, scope } = request.data as {
        sourceCommunityId: string;
        targetCommunityId: string;
        scope: string;
    };

    if (!sourceCommunityId || !targetCommunityId || !scope) {
        throw new HttpsError("invalid-argument", "sourceCommunityId, targetCommunityId and scope required.");
    }

    await assertCommunityAdmin(sourceCommunityId, uid);

    // Verify both communities exist.
    const [sourceSnap, targetSnap] = await Promise.all([
        db.collection("communities").doc(sourceCommunityId).get(),
        db.collection("communities").doc(targetCommunityId).get(),
    ]);
    if (!sourceSnap.exists) throw new HttpsError("not-found", "Source community not found.");
    if (!targetSnap.exists) throw new HttpsError("not-found", "Target community not found.");

    const now = admin.firestore.FieldValue.serverTimestamp();
    const linkRef = db
        .collection("communities").doc(sourceCommunityId)
        .collection("links").doc();

    // Write symmetrically: source community's links subcollection uses
    // the canonical doc; target's subcollection mirrors with inverted ids.
    const sourceLinkDoc = {
        otherCommunityId: targetCommunityId,
        otherCommunityName: targetSnap.data()?.name ?? "",
        otherCommunityAvatarURL: targetSnap.data()?.avatarURL ?? null,
        status: "pending",
        scope,
        createdBy: uid,
        createdAt: now,
        updatedAt: now,
    };

    const mirrorRef = db
        .collection("communities").doc(targetCommunityId)
        .collection("links").doc(linkRef.id);

    const mirrorLinkDoc = {
        otherCommunityId: sourceCommunityId,
        otherCommunityName: sourceSnap.data()?.name ?? "",
        otherCommunityAvatarURL: sourceSnap.data()?.avatarURL ?? null,
        status: "pending",
        scope,
        createdBy: uid,
        createdAt: now,
        updatedAt: now,
    };

    await db.runTransaction(async (tx) => {
        tx.set(linkRef, sourceLinkDoc);
        tx.set(mirrorRef, mirrorLinkDoc);
    });

    logger.info("[linkCommunity] Link created", {
        linkId: linkRef.id, sourceCommunityId, targetCommunityId,
    });
    return { linkId: linkRef.id };
});

// ── acceptCommunityLink ───────────────────────────────────────────────────────

export const acceptCommunityLink = onCall(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");

    const { targetCommunityId, linkId } = request.data as {
        targetCommunityId: string;
        linkId: string;
    };

    await assertCommunityAdmin(targetCommunityId, uid);

    // The mirror doc on the target tells us the source community.
    const mirrorRef = db
        .collection("communities").doc(targetCommunityId)
        .collection("links").doc(linkId);
    const mirrorSnap = await mirrorRef.get();
    if (!mirrorSnap.exists) throw new HttpsError("not-found", "Link not found.");
    if (mirrorSnap.data()?.status !== "pending") {
        throw new HttpsError("failed-precondition", "Link is not in pending state.");
    }

    const sourceCommunityId = mirrorSnap.data()?.otherCommunityId as string;
    const sourceRef = db
        .collection("communities").doc(sourceCommunityId)
        .collection("links").doc(linkId);

    const now = admin.firestore.FieldValue.serverTimestamp();

    await db.runTransaction(async (tx) => {
        tx.update(mirrorRef, { status: "active", updatedAt: now });
        tx.update(sourceRef, { status: "active", updatedAt: now });
    });

    // Fan-out: update sharedWith on spaces whose scope matches this link.
    const scope = mirrorSnap.data()?.scope as string;
    if (scope && scope.startsWith("space/")) {
        const spaceId = scope.replace("space/", "");
        await db.collection("spaces").doc(spaceId).update({
            sharedWith: admin.firestore.FieldValue.arrayUnion(targetCommunityId),
        });
    }

    logger.info("[acceptCommunityLink] Link accepted", { linkId, targetCommunityId });
    return { success: true };
});

// ── revokeCommunityLink ───────────────────────────────────────────────────────

export const revokeCommunityLink = onCall(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");

    const { communityId, linkId } = request.data as {
        communityId: string;
        linkId: string;
    };

    await assertCommunityAdmin(communityId, uid);

    const linkRef = db
        .collection("communities").doc(communityId)
        .collection("links").doc(linkId);
    const linkSnap = await linkRef.get();
    if (!linkSnap.exists) throw new HttpsError("not-found", "Link not found.");

    const otherCommunityId = linkSnap.data()?.otherCommunityId as string;
    const scope = linkSnap.data()?.scope as string;

    const mirrorRef = db
        .collection("communities").doc(otherCommunityId)
        .collection("links").doc(linkId);

    const now = admin.firestore.FieldValue.serverTimestamp();

    await db.runTransaction(async (tx) => {
        // Status flip only — never delete link docs.
        tx.update(linkRef, { status: "revoked", updatedAt: now });
        tx.update(mirrorRef, { status: "revoked", updatedAt: now });
    });

    // Remove otherCommunityId from sharedWith on affected spaces.
    if (scope && scope.startsWith("space/")) {
        const spaceId = scope.replace("space/", "");
        await db.collection("spaces").doc(spaceId).update({
            sharedWith: admin.firestore.FieldValue.arrayRemove(otherCommunityId),
        });

        // Set external members' access to "none" (does NOT delete member docs).
        const externalMembers = await db
            .collection("spaces").doc(spaceId)
            .collection("members")
            .where("homeCommunityId", "==", otherCommunityId)
            .get();

        const batch = db.batch();
        for (const doc of externalMembers.docs) {
            batch.update(doc.ref, { access: "none" });
        }
        await batch.commit();
    }

    logger.info("[revokeCommunityLink] Link revoked", { linkId, communityId });
    return { success: true };
});

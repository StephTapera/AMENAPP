"use strict";
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
exports.monitorGroupLinkHealth = exports.manageGroupLink = exports.adminRespondToJoinRequest = exports.requestJoinViaLink = exports.joinGroupViaLink = exports.evaluateJoinViaLink = exports.fetchGroupLinkPreview = exports.createGroupWithLink = void 0;
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const admin = __importStar(require("firebase-admin"));
const crypto = __importStar(require("crypto"));
const db = admin.firestore();
// ─── Dynamic Link Constants ─────────────────────────────────────────
const AUTO_THROTTLE_THRESHOLD = 50; // After this many joins, switch to approval mode
const VELOCITY_WINDOW_MS = 5 * 60 * 1000; // 5-minute window for velocity checks
const VELOCITY_SPIKE_THRESHOLD = 15; // Joins in the velocity window that trigger auto-pause
const INACTIVITY_HOURS = 24; // Disable link after this many hours with no activity
// ─── Helpers ─────────────────────────────────────────────────────────
function generateSecureToken() {
    return crypto.randomBytes(24).toString("base64url");
}
async function isBlocked(userId, targetId) {
    const [blockA, blockB] = await Promise.all([
        db.collection("users").doc(userId).collection("blockedUsers").doc(targetId).get(),
        db.collection("users").doc(targetId).collection("blockedUsers").doc(userId).get(),
    ]);
    return blockA.exists || blockB.exists;
}
// ─── Dynamic Link Helpers ────────────────────────────────────────────
async function recordJoinEvent(conversationId, linkId, userId) {
    await db
        .collection("conversations")
        .doc(conversationId)
        .collection("groupLinks")
        .doc(linkId)
        .collection("joinEvents")
        .add({
        userId,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        timestampMs: Date.now(),
    });
}
async function getRecentJoinCount(conversationId, linkId) {
    const cutoff = Date.now() - VELOCITY_WINDOW_MS;
    const snap = await db
        .collection("conversations")
        .doc(conversationId)
        .collection("groupLinks")
        .doc(linkId)
        .collection("joinEvents")
        .where("timestampMs", ">=", cutoff)
        .get();
    return snap.size;
}
async function maybeAutoThrottle(conversationId, linkId, currentJoinCount, currentJoinMode) {
    if (currentJoinMode !== "open")
        return false;
    if (currentJoinCount < AUTO_THROTTLE_THRESHOLD)
        return false;
    const linkRef = db
        .collection("conversations")
        .doc(conversationId)
        .collection("groupLinks")
        .doc(linkId);
    await linkRef.update({
        joinMode: "approval_required",
        autoThrottledAt: admin.firestore.FieldValue.serverTimestamp(),
        autoThrottleReason: `Auto-switched to approval after ${currentJoinCount} joins`,
    });
    return true;
}
async function maybeAntiRaidPause(conversationId, linkId) {
    const recentCount = await getRecentJoinCount(conversationId, linkId);
    if (recentCount < VELOCITY_SPIKE_THRESHOLD)
        return false;
    const linkRef = db
        .collection("conversations")
        .doc(conversationId)
        .collection("groupLinks")
        .doc(linkId);
    await linkRef.update({
        status: "paused",
        pausedAt: admin.firestore.FieldValue.serverTimestamp(),
        pauseReason: `Anti-raid: ${recentCount} joins in ${VELOCITY_WINDOW_MS / 60000}min window`,
    });
    const convoSnap = await db.collection("conversations").doc(conversationId).get();
    if (convoSnap.exists) {
        const convo = convoSnap.data();
        const adminIds = convo.adminIds || [];
        const notifBatch = db.batch();
        for (const adminId of adminIds) {
            const notifRef = db.collection("notifications").doc();
            notifBatch.set(notifRef, {
                recipientId: adminId,
                type: "group_link_raid_detected",
                title: "Invite Link Paused",
                body: `Your invite link for "${convo.groupName || "Group"}" was auto-paused due to unusual join activity (${recentCount} joins in 5 min)`,
                conversationId,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                isRead: false,
            });
        }
        await notifBatch.commit();
    }
    return true;
}
// ─── 1. createGroupWithLink ──────────────────────────────────────────
exports.createGroupWithLink = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Auth required");
    }
    if (!request.app) {
        throw new https_1.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    const data = request.data;
    const uid = request.auth.uid;
    const groupName = String(data.groupName || "").trim();
    if (!groupName || groupName.length > 100) {
        throw new https_1.HttpsError("invalid-argument", "Group name is required (max 100 chars)");
    }
    const purpose = data.purpose || "general";
    const joinMode = data.joinMode || "open";
    const safetyTier = data.safetyTier || "standard";
    const memberLimit = data.memberLimit ?? null;
    const expirationDays = data.expirationDays ?? null;
    const expirationHours = data.expirationHours ?? null;
    const conversationRef = db.collection("conversations").doc();
    const now = admin.firestore.FieldValue.serverTimestamp();
    const participantIds = [uid, ...(data.participantIds || [])];
    const uniqueParticipants = [...new Set(participantIds)];
    await conversationRef.set({
        participantIds: uniqueParticipants,
        participantNames: {},
        isGroup: true,
        groupName: groupName,
        groupDescription: "",
        adminIds: [uid],
        createdBy: uid,
        createdAt: now,
        updatedAt: now,
        lastMessage: "Group created",
        lastMessageTimestamp: now,
        lastSenderId: uid,
        isArchived: false,
        pinnedBy: [],
        mutedBy: [],
        purpose: purpose,
    });
    const token = generateSecureToken();
    let expiresAt = null;
    if (expirationHours && expirationHours > 0 && expirationHours < 24) {
        expiresAt = admin.firestore.Timestamp.fromDate(new Date(Date.now() + expirationHours * 60 * 60 * 1000));
    }
    else if (expirationDays && expirationDays > 0) {
        expiresAt = admin.firestore.Timestamp.fromDate(new Date(Date.now() + expirationDays * 24 * 60 * 60 * 1000));
    }
    const linkRef = conversationRef.collection("groupLinks").doc();
    const linkData = {
        conversationId: conversationRef.id,
        token,
        createdBy: uid,
        createdAt: now,
        status: "active",
        expiresAt,
        memberLimit: memberLimit,
        joinCount: 0,
        joinMode,
        safetyTier,
    };
    const batch = db.batch();
    batch.set(linkRef, linkData);
    batch.set(db.collection("groupLinkTokens").doc(token), {
        conversationId: conversationRef.id,
        linkId: linkRef.id,
        createdAt: now,
    });
    await batch.commit();
    return {
        ok: true,
        conversationId: conversationRef.id,
        linkId: linkRef.id,
        token,
        shareURL: `https://amenapp.com/group/join?token=${token}`,
    };
});
// ─── 2. fetchGroupLinkPreview ────────────────────────────────────────
exports.fetchGroupLinkPreview = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Auth required");
    }
    if (!request.app) {
        throw new https_1.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    const data = request.data;
    const token = String(data?.token || "").trim();
    if (!token) {
        throw new https_1.HttpsError("invalid-argument", "Token required");
    }
    const tokenDoc = await db.collection("groupLinkTokens").doc(token).get();
    if (!tokenDoc.exists) {
        throw new https_1.HttpsError("not-found", "Invalid or expired link");
    }
    const { conversationId, linkId } = tokenDoc.data();
    const linkSnap = await db
        .collection("conversations")
        .doc(conversationId)
        .collection("groupLinks")
        .doc(linkId)
        .get();
    if (!linkSnap.exists) {
        throw new https_1.HttpsError("not-found", "Link not found");
    }
    const link = linkSnap.data();
    const convoSnap = await db.collection("conversations").doc(conversationId).get();
    const convo = convoSnap.data() || {};
    return {
        ok: true,
        preview: {
            groupName: convo.groupName || "Group",
            memberCount: (convo.participantIds || []).length,
            purpose: convo.purpose || "general",
            joinMode: link.joinMode || "open",
            safetyTier: link.safetyTier || "standard",
            status: link.status || "active",
            createdByName: null,
        },
    };
});
// ─── 3. evaluateJoinViaLink ──────────────────────────────────────────
exports.evaluateJoinViaLink = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Auth required");
    }
    if (!request.app) {
        throw new https_1.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    const data = request.data;
    const uid = request.auth.uid;
    const token = String(data?.token || "").trim();
    if (!token) {
        throw new https_1.HttpsError("invalid-argument", "Token required");
    }
    const tokenDoc = await db.collection("groupLinkTokens").doc(token).get();
    if (!tokenDoc.exists) {
        return { outcome: "expired", reason: "Invalid or expired link" };
    }
    const { conversationId, linkId } = tokenDoc.data();
    const [linkSnap, convoSnap] = await Promise.all([
        db.collection("conversations").doc(conversationId).collection("groupLinks").doc(linkId).get(),
        db.collection("conversations").doc(conversationId).get(),
    ]);
    if (!linkSnap.exists || !convoSnap.exists) {
        return { outcome: "expired", reason: "Group or link no longer exists" };
    }
    const link = linkSnap.data();
    const convo = convoSnap.data();
    if (link.status === "disabled")
        return { outcome: "disabled", reason: "Link disabled by admin" };
    if (link.status === "paused")
        return { outcome: "paused", reason: "Link temporarily paused" };
    if (link.expiresAt) {
        const expiry = link.expiresAt.toDate ? link.expiresAt.toDate() : new Date(link.expiresAt);
        if (expiry < new Date())
            return { outcome: "expired", reason: "Link has expired" };
    }
    const currentMembers = (convo.participantIds || []).length;
    if (link.memberLimit && currentMembers >= link.memberLimit) {
        return { outcome: "full", reason: "Group is at capacity" };
    }
    if ((convo.participantIds || []).includes(uid)) {
        return { outcome: "already_member", conversationId, reason: "You are already in this group" };
    }
    const adminIds = convo.adminIds || [];
    for (const adminId of adminIds) {
        if (await isBlocked(uid, adminId)) {
            return { outcome: "blocked", reason: "Unable to join this group" };
        }
    }
    const removedMembers = convo.removedMembers || [];
    if (removedMembers.includes(uid)) {
        return { outcome: "blocked", reason: "You were previously removed from this group" };
    }
    if (link.safetyTier === "strict") {
        const userDoc = await db.collection("users").doc(uid).get();
        if (userDoc.exists) {
            const createdAt = userDoc.data()?.createdAt;
            if (createdAt) {
                const accountAge = Date.now() - (createdAt.toDate ? createdAt.toDate() : new Date(createdAt)).getTime();
                const ONE_DAY = 24 * 60 * 60 * 1000;
                if (accountAge < ONE_DAY) {
                    return { outcome: "blocked", reason: "Account too new for this group's safety requirements" };
                }
            }
        }
    }
    if (link.joinMode === "approval_required" || link.joinMode === "restricted") {
        const wasAutoThrottled = !!link.autoThrottledAt;
        return {
            outcome: "request_required",
            conversationId,
            reason: wasAutoThrottled
                ? "This group now requires approval to join"
                : "Admin approval required to join",
        };
    }
    return { outcome: "allowed", conversationId, reason: null };
});
// ─── 4. joinGroupViaLink ─────────────────────────────────────────────
exports.joinGroupViaLink = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Auth required");
    }
    if (!request.app) {
        throw new https_1.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    const data = request.data;
    const uid = request.auth.uid;
    const token = String(data?.token || "").trim();
    if (!token) {
        throw new https_1.HttpsError("invalid-argument", "Token required");
    }
    const tokenDoc = await db.collection("groupLinkTokens").doc(token).get();
    if (!tokenDoc.exists) {
        throw new https_1.HttpsError("not-found", "Invalid or expired link");
    }
    const { conversationId, linkId } = tokenDoc.data();
    const [linkSnap, convoSnap] = await Promise.all([
        db.collection("conversations").doc(conversationId).collection("groupLinks").doc(linkId).get(),
        db.collection("conversations").doc(conversationId).get(),
    ]);
    if (!linkSnap.exists || !convoSnap.exists) {
        throw new https_1.HttpsError("not-found", "Group or link no longer exists");
    }
    const link = linkSnap.data();
    const convo = convoSnap.data();
    if (link.status !== "active") {
        throw new https_1.HttpsError("failed-precondition", "Link is not active");
    }
    if ((convo.participantIds || []).includes(uid)) {
        return { ok: true, conversationId, alreadyMember: true };
    }
    if (link.memberLimit) {
        const currentCount = (convo.participantIds || []).length;
        if (currentCount >= link.memberLimit) {
            throw new https_1.HttpsError("resource-exhausted", "Group is at capacity");
        }
    }
    const userDoc = await db.collection("users").doc(uid).get();
    const displayName = userDoc.data()?.username || userDoc.data()?.displayName || "Someone";
    const batch = db.batch();
    batch.update(db.collection("conversations").doc(conversationId), {
        participantIds: admin.firestore.FieldValue.arrayUnion(uid),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessage: `${displayName} joined via link`,
        lastMessageTimestamp: admin.firestore.FieldValue.serverTimestamp(),
        lastSenderId: uid,
    });
    batch.update(db.collection("conversations").doc(conversationId).collection("groupLinks").doc(linkId), {
        joinCount: admin.firestore.FieldValue.increment(1),
        lastJoinAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    const messageRef = db.collection("conversations").doc(conversationId).collection("messages").doc();
    batch.set(messageRef, {
        text: `${displayName} joined via invite link`,
        senderId: "system",
        senderName: "System",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        type: "system",
    });
    await batch.commit();
    await recordJoinEvent(conversationId, linkId, uid);
    const newJoinCount = (link.joinCount || 0) + 1;
    const throttled = await maybeAutoThrottle(conversationId, linkId, newJoinCount, link.joinMode || "open");
    const raidPaused = await maybeAntiRaidPause(conversationId, linkId);
    const adminIds = convo.adminIds || [];
    const notifBatch = db.batch();
    for (const adminId of adminIds) {
        if (adminId === uid)
            continue;
        const notifRef = db.collection("notifications").doc();
        notifBatch.set(notifRef, {
            recipientId: adminId,
            type: "group_member_joined",
            title: "New Group Member",
            body: `${displayName} joined "${convo.groupName || "Group"}" via invite link`,
            conversationId,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            isRead: false,
        });
    }
    await notifBatch.commit();
    return {
        ok: true,
        conversationId,
        alreadyMember: false,
        autoThrottled: throttled,
        raidPaused: raidPaused,
    };
});
// ─── 5. requestJoinViaLink ───────────────────────────────────────────
exports.requestJoinViaLink = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Auth required");
    }
    if (!request.app) {
        throw new https_1.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    const data = request.data;
    const uid = request.auth.uid;
    const token = String(data?.token || "").trim();
    if (!token) {
        throw new https_1.HttpsError("invalid-argument", "Token required");
    }
    const tokenDoc = await db.collection("groupLinkTokens").doc(token).get();
    if (!tokenDoc.exists) {
        throw new https_1.HttpsError("not-found", "Invalid or expired link");
    }
    const { conversationId } = tokenDoc.data();
    const convoSnap = await db.collection("conversations").doc(conversationId).get();
    if (!convoSnap.exists) {
        throw new https_1.HttpsError("not-found", "Group not found");
    }
    const existingReq = await db
        .collection("conversations")
        .doc(conversationId)
        .collection("joinRequests")
        .where("requesterId", "==", uid)
        .where("status", "==", "pending")
        .limit(1)
        .get();
    if (!existingReq.empty) {
        return { ok: true, alreadyRequested: true };
    }
    const userDoc = await db.collection("users").doc(uid).get();
    const displayName = userDoc.data()?.username || userDoc.data()?.displayName || "Someone";
    const requestRef = db
        .collection("conversations")
        .doc(conversationId)
        .collection("joinRequests")
        .doc();
    await requestRef.set({
        requesterId: uid,
        requesterName: displayName,
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    const convo = convoSnap.data();
    const adminIds = convo.adminIds || [];
    const notifBatch = db.batch();
    for (const adminId of adminIds) {
        const notifRef = db.collection("notifications").doc();
        notifBatch.set(notifRef, {
            recipientId: adminId,
            type: "group_join_request",
            title: "Join Request",
            body: `${displayName} wants to join "${convo.groupName || "Group"}"`,
            conversationId,
            requestId: requestRef.id,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            isRead: false,
        });
    }
    await notifBatch.commit();
    return { ok: true, alreadyRequested: false, requestId: requestRef.id };
});
// ─── 6. adminRespondToJoinRequest ────────────────────────────────────
exports.adminRespondToJoinRequest = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Auth required");
    }
    if (!request.app) {
        throw new https_1.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    const data = request.data;
    const uid = request.auth.uid;
    const conversationId = String(data?.conversationId || "").trim();
    const requestId = String(data?.requestId || "").trim();
    const approve = data?.approve === true;
    const reason = String(data?.reason || "").trim();
    if (!conversationId || !requestId) {
        throw new https_1.HttpsError("invalid-argument", "conversationId and requestId required");
    }
    const convoSnap = await db.collection("conversations").doc(conversationId).get();
    if (!convoSnap.exists) {
        throw new https_1.HttpsError("not-found", "Conversation not found");
    }
    const convo = convoSnap.data();
    const adminIds = convo.adminIds || [];
    if (!adminIds.includes(uid)) {
        throw new https_1.HttpsError("permission-denied", "Only admins can respond to join requests");
    }
    const requestRef = db
        .collection("conversations")
        .doc(conversationId)
        .collection("joinRequests")
        .doc(requestId);
    const requestSnap = await requestRef.get();
    if (!requestSnap.exists) {
        throw new https_1.HttpsError("not-found", "Request not found");
    }
    const joinRequest = requestSnap.data();
    if (joinRequest.status !== "pending") {
        return { ok: true, alreadyHandled: true };
    }
    const requesterId = joinRequest.requesterId;
    const requesterName = joinRequest.requesterName || "Someone";
    if (approve) {
        const batch = db.batch();
        batch.update(requestRef, {
            status: "approved",
            respondedBy: uid,
            respondedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        batch.update(db.collection("conversations").doc(conversationId), {
            participantIds: admin.firestore.FieldValue.arrayUnion(requesterId),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            lastMessage: `${requesterName} was approved to join`,
            lastMessageTimestamp: admin.firestore.FieldValue.serverTimestamp(),
            lastSenderId: "system",
        });
        const msgRef = db.collection("conversations").doc(conversationId).collection("messages").doc();
        batch.set(msgRef, {
            text: `${requesterName} was approved and joined the group`,
            senderId: "system",
            senderName: "System",
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            type: "system",
        });
        const notifRef = db.collection("notifications").doc();
        batch.set(notifRef, {
            recipientId: requesterId,
            type: "group_join_approved",
            title: "Request Approved",
            body: `Your request to join "${convo.groupName || "Group"}" was approved`,
            conversationId,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            isRead: false,
        });
        await batch.commit();
    }
    else {
        const batch = db.batch();
        batch.update(requestRef, {
            status: "denied",
            respondedBy: uid,
            respondedAt: admin.firestore.FieldValue.serverTimestamp(),
            denyReason: reason || null,
        });
        const notifRef = db.collection("notifications").doc();
        batch.set(notifRef, {
            recipientId: requesterId,
            type: "group_join_denied",
            title: "Request Declined",
            body: `Your request to join "${convo.groupName || "Group"}" was declined`,
            conversationId,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            isRead: false,
        });
        await batch.commit();
    }
    return { ok: true, approved: approve };
});
// ─── 7. manageGroupLink ──────────────────────────────────────────────
exports.manageGroupLink = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Auth required");
    }
    if (!request.app) {
        throw new https_1.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    const data = request.data;
    const uid = request.auth.uid;
    const conversationId = String(data?.conversationId || "").trim();
    const linkId = String(data?.linkId || "").trim();
    const action = String(data?.action || "").trim();
    if (!conversationId || !linkId || !action) {
        throw new https_1.HttpsError("invalid-argument", "conversationId, linkId, and action required");
    }
    const convoSnap = await db.collection("conversations").doc(conversationId).get();
    if (!convoSnap.exists) {
        throw new https_1.HttpsError("not-found", "Conversation not found");
    }
    const convo = convoSnap.data();
    if (!(convo.adminIds || []).includes(uid)) {
        throw new https_1.HttpsError("permission-denied", "Only admins can manage group links");
    }
    const linkRef = db
        .collection("conversations")
        .doc(conversationId)
        .collection("groupLinks")
        .doc(linkId);
    const linkSnap = await linkRef.get();
    if (!linkSnap.exists) {
        throw new https_1.HttpsError("not-found", "Link not found");
    }
    const link = linkSnap.data();
    switch (action) {
        case "pause":
            await linkRef.update({ status: "paused" });
            return { ok: true, status: "paused" };
        case "resume":
            await linkRef.update({ status: "active" });
            return { ok: true, status: "active" };
        case "disable": {
            const batch = db.batch();
            batch.update(linkRef, { status: "disabled" });
            if (link.token) {
                batch.delete(db.collection("groupLinkTokens").doc(link.token));
            }
            await batch.commit();
            return { ok: true, status: "disabled" };
        }
        case "regenerate": {
            const newToken = generateSecureToken();
            const newLinkRef = db
                .collection("conversations")
                .doc(conversationId)
                .collection("groupLinks")
                .doc();
            const batch = db.batch();
            batch.update(linkRef, { status: "disabled" });
            if (link.token) {
                batch.delete(db.collection("groupLinkTokens").doc(link.token));
            }
            const now = admin.firestore.FieldValue.serverTimestamp();
            batch.set(newLinkRef, {
                conversationId,
                token: newToken,
                createdBy: uid,
                createdAt: now,
                status: "active",
                expiresAt: link.expiresAt || null,
                memberLimit: link.memberLimit || null,
                joinCount: 0,
                joinMode: link.joinMode || "open",
                safetyTier: link.safetyTier || "standard",
            });
            batch.set(db.collection("groupLinkTokens").doc(newToken), {
                conversationId,
                linkId: newLinkRef.id,
                createdAt: now,
            });
            await batch.commit();
            return {
                ok: true,
                newLinkId: newLinkRef.id,
                newToken,
                shareURL: `https://amenapp.com/group/join?token=${newToken}`,
            };
        }
        default:
            throw new https_1.HttpsError("invalid-argument", `Unknown action: ${action}`);
    }
});
// ─── 8. monitorGroupLinkHealth (Scheduled) ──────────────────────────
exports.monitorGroupLinkHealth = (0, scheduler_1.onSchedule)({ schedule: "every 60 minutes" }, async () => {
    const now = Date.now();
    const inactivityCutoff = new Date(now - INACTIVITY_HOURS * 60 * 60 * 1000);
    const tokenSnaps = await db.collection("groupLinkTokens").get();
    let disabledCount = 0;
    let expiredCount = 0;
    for (const tokenDoc of tokenSnaps.docs) {
        const { conversationId, linkId } = tokenDoc.data();
        if (!conversationId || !linkId)
            continue;
        const linkRef = db
            .collection("conversations")
            .doc(conversationId)
            .collection("groupLinks")
            .doc(linkId);
        const linkSnap = await linkRef.get();
        if (!linkSnap.exists) {
            await tokenDoc.ref.delete();
            continue;
        }
        const link = linkSnap.data();
        if (link.status === "disabled")
            continue;
        if (link.expiresAt) {
            const expiry = link.expiresAt.toDate
                ? link.expiresAt.toDate()
                : new Date(link.expiresAt);
            if (expiry < new Date()) {
                await linkRef.update({ status: "disabled", disabledReason: "expired" });
                await tokenDoc.ref.delete();
                expiredCount++;
                continue;
            }
        }
        if (link.status === "active" && !link.expiresAt) {
            const lastActivity = link.lastJoinAt
                ? (link.lastJoinAt.toDate ? link.lastJoinAt.toDate() : new Date(link.lastJoinAt))
                : (link.createdAt?.toDate ? link.createdAt.toDate() : null);
            if (lastActivity && lastActivity < inactivityCutoff) {
                await linkRef.update({
                    status: "disabled",
                    disabledReason: `Auto-disabled after ${INACTIVITY_HOURS}h inactivity`,
                    disabledAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                await tokenDoc.ref.delete();
                if (link.createdBy) {
                    await db.collection("notifications").add({
                        recipientId: link.createdBy,
                        type: "group_link_auto_disabled",
                        title: "Invite Link Expired",
                        body: `Your invite link was auto-disabled after ${INACTIVITY_HOURS} hours of inactivity. You can regenerate it anytime.`,
                        conversationId,
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        isRead: false,
                    });
                }
                disabledCount++;
            }
        }
    }
    console.log(`monitorGroupLinkHealth: disabled ${disabledCount} inactive, ${expiredCount} expired links`);
});
//# sourceMappingURL=groupLinks.js.map
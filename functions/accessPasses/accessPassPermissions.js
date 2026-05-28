"use strict";
// accessPassPermissions.ts — Admin and creator permission checks
//
// Verifies that the calling user is authorized to create/manage a pass
// for the specified target type and ID.
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
exports.verifyAdminForTarget = verifyAdminForTarget;
exports.verifyPassAdmin = verifyPassAdmin;
exports.verifyRequestAdmin = verifyRequestAdmin;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions"));
const db = admin.firestore();
/**
 * Verify that uid is an admin/owner/creator for the given target.
 * Throws HttpsError("permission-denied") if not authorized.
 */
async function verifyAdminForTarget(uid, targetType, targetId) {
    switch (targetType) {
        case "church":
            await verifyChurchAdmin(uid, targetId);
            break;
        case "organization":
            await verifyOrgAdmin(uid, targetId);
            break;
        case "smallGroup":
            await verifyGroupAdmin(uid, targetId);
            break;
        case "space":
            await verifySpaceAdmin(uid, targetId);
            break;
        case "discussion":
            await verifyDiscussionAdmin(uid, targetId);
            break;
        case "event":
            await verifyEventAdmin(uid, targetId);
            break;
        case "sermonNotes":
            await verifySermonNotesAdmin(uid, targetId);
            break;
        case "prayerRoom":
            await verifyPrayerRoomAdmin(uid, targetId);
            break;
        default:
            throw new functions.https.HttpsError("permission-denied", "unknown-target-type");
    }
}
async function verifyChurchAdmin(uid, churchId) {
    const snap = await db.collection("churches").doc(churchId).get();
    if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "church-not-found");
    }
    const data = snap.data();
    const isOwner = data.ownerUserId === uid;
    const isAdmin = (data.adminUserIds ?? []).includes(uid);
    const isModerator = (data.moderatorUserIds ?? []).includes(uid);
    if (!isOwner && !isAdmin && !isModerator) {
        throw new functions.https.HttpsError("permission-denied", "not-church-admin");
    }
}
async function verifyOrgAdmin(uid, orgId) {
    const snap = await db.collection("organizations").doc(orgId).get();
    if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "org-not-found");
    }
    const data = snap.data();
    const isOwner = data.ownerUserId === uid;
    const isAdmin = (data.adminUserIds ?? []).includes(uid);
    if (!isOwner && !isAdmin) {
        throw new functions.https.HttpsError("permission-denied", "not-org-admin");
    }
}
async function verifyGroupAdmin(uid, groupId) {
    const memberRef = db.collection("groupLinks").doc(groupId).collection("members").doc(uid);
    const snap = await memberRef.get();
    if (!snap.exists || !snap.data()?.isAdmin) {
        throw new functions.https.HttpsError("permission-denied", "not-group-admin");
    }
}
async function verifySpaceAdmin(uid, spaceId) {
    const snap = await db.collection("spaces").doc(spaceId).get();
    if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "space-not-found");
    }
    const data = snap.data();
    if (data.createdByUid !== uid && !(data.adminUids ?? []).includes(uid)) {
        throw new functions.https.HttpsError("permission-denied", "not-space-admin");
    }
}
async function verifyDiscussionAdmin(uid, discussionId) {
    const snap = await db.collection("discussions").doc(discussionId).get();
    if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "discussion-not-found");
    }
    const data = snap.data();
    if (data.authorId !== uid) {
        throw new functions.https.HttpsError("permission-denied", "not-discussion-owner");
    }
}
async function verifyEventAdmin(uid, eventId) {
    const snap = await db.collection("events").doc(eventId).get();
    if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "event-not-found");
    }
    const data = snap.data();
    const isOrganizer = data.organizerUid === uid;
    const isAdmin = (data.adminUids ?? []).includes(uid);
    if (!isOrganizer && !isAdmin) {
        throw new functions.https.HttpsError("permission-denied", "not-event-admin");
    }
}
async function verifySermonNotesAdmin(uid, notesId) {
    const snap = await db.collection("sermonNotes").doc(notesId).get();
    if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "sermon-notes-not-found");
    }
    const data = snap.data();
    if (data.authorId !== uid && data.churchId) {
        // Also allow church admins to manage sermon note passes
        try {
            await verifyChurchAdmin(uid, data.churchId);
        }
        catch {
            throw new functions.https.HttpsError("permission-denied", "not-sermon-notes-admin");
        }
    }
    else if (data.authorId !== uid) {
        throw new functions.https.HttpsError("permission-denied", "not-sermon-notes-admin");
    }
}
async function verifyPrayerRoomAdmin(uid, roomId) {
    const snap = await db.collection("prayerRooms").doc(roomId).get();
    if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "prayer-room-not-found");
    }
    const data = snap.data();
    if (data.hostUid !== uid && !(data.adminUids ?? []).includes(uid)) {
        throw new functions.https.HttpsError("permission-denied", "not-prayer-room-admin");
    }
}
/** Verify uid is the creator/pass owner. */
async function verifyPassAdmin(uid, accessPassId) {
    const passSnap = await db.collection("accessPasses").doc(accessPassId).get();
    if (!passSnap.exists) {
        throw new functions.https.HttpsError("not-found", "pass-not-found");
    }
    const pass = passSnap.data();
    if (pass.createdByUid !== uid) {
        // Also check if they're admin for the target
        try {
            await verifyAdminForTarget(uid, pass.targetType, pass.targetId);
        }
        catch {
            throw new functions.https.HttpsError("permission-denied", "not-pass-admin");
        }
    }
}
/** Verify uid is admin for the target referenced by a request. */
async function verifyRequestAdmin(uid, requestId) {
    const reqSnap = await db.collection("accessRequests").doc(requestId).get();
    if (!reqSnap.exists) {
        throw new functions.https.HttpsError("not-found", "request-not-found");
    }
    const req = reqSnap.data();
    await verifyAdminForTarget(uid, req.targetType, req.targetId);
}
//# sourceMappingURL=accessPassPermissions.js.map
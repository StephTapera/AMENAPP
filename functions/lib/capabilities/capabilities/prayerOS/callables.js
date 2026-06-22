"use strict";
// capabilities/prayerOS/callables.ts — Prayer OS callables (Wave 1: Lane B)
//
// Four App-Check-enforced callables:
//   prayerOS_createCard   — create a prayer card with optional dedupe
//   prayerOS_updateCard   — patch fields on an existing card
//   prayerOS_listCards    — paginated list by status
//   prayerOS_completeFollowUp — mark a followUp done
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
exports.prayerOS_completeFollowUp = exports.prayerOS_listCards = exports.prayerOS_updateCard = exports.prayerOS_createCard = void 0;
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const resolveContextAccess_1 = require("../../contextEngine/resolveContextAccess");
const VALID_CATEGORIES = ["health", "work", "spiritual", "family", "other"];
const VALID_STATUSES = ["active", "answered", "archived"];
// ── Helpers ──────────────────────────────────────────────────────────────────
function requireAuth(request) {
    const uid = request.auth?.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Must be signed in.");
    return uid;
}
function toIso(ts) {
    if (!ts)
        return new Date().toISOString();
    return ts.toDate().toISOString();
}
function docToWire(docId, data) {
    return {
        cardId: docId,
        subject: data.subject ?? { type: "topic", displayName: "" },
        category: data.category ?? "other",
        detail: data.detail ?? "",
        status: data.status ?? "active",
        createdAt: toIso(data.createdAt),
        updatedAt: toIso(data.updatedAt),
        reminders: (data.reminders ?? []).map((r) => ({
            rrule: r.rrule ?? "",
            nextFireAt: toIso(r.nextFireAt),
        })),
        followUps: (data.followUps ?? []).map((f) => ({
            dueAt: toIso(f.dueAt),
            status: f.status ?? "pending",
            note: f.note,
        })),
    };
}
// ── prayerOS_createCard ───────────────────────────────────────────────────────
exports.prayerOS_createCard = (0, https_1.onCall)({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const body = request.data;
    // Validate subject
    if (!body.subject || typeof body.subject !== "object") {
        throw new https_1.HttpsError("invalid-argument", "subject is required.");
    }
    const displayName = String(body.subject.displayName ?? "").trim();
    if (!displayName || displayName.length > 200) {
        throw new https_1.HttpsError("invalid-argument", "subject.displayName must be 1-200 chars.");
    }
    if (!["person", "topic"].includes(body.subject.type ?? "")) {
        throw new https_1.HttpsError("invalid-argument", 'subject.type must be "person" or "topic".');
    }
    // Validate detail
    const detail = String(body.detail ?? "").trim();
    if (!detail || detail.length > 2000) {
        throw new https_1.HttpsError("invalid-argument", "detail must be 1-2000 chars.");
    }
    // Validate category
    if (!VALID_CATEGORIES.includes(body.category)) {
        throw new https_1.HttpsError("invalid-argument", `category must be one of: ${VALID_CATEGORIES.join(", ")}`);
    }
    logger.info("[CAP/prayerOS] createCard", { uid, category: body.category });
    const db = (0, firestore_1.getFirestore)();
    let dedupeWarning;
    // Context dedupe: resolve prayerHistory + messagesMeta access
    try {
        const access = await (0, resolveContextAccess_1.resolveContextAccess)({
            uid,
            capabilityId: "prayer_os",
            sources: ["prayerHistory", "messagesMeta"],
            invocationType: "foreground",
        });
        const prayerHistoryDecision = access.decisions.find((d) => d.source === "prayerHistory");
        if (prayerHistoryDecision?.decision === "allowed") {
            // Check for existing active card with same displayName
            const existing = await db
                .collection(`users/${uid}/prayerCards`)
                .where("subject.displayName", "==", displayName)
                .where("status", "==", "active")
                .limit(1)
                .get();
            if (!existing.empty) {
                const existingDoc = existing.docs[0];
                dedupeWarning = {
                    existingCardId: existingDoc.id,
                    displayName,
                };
            }
        }
    }
    catch (contextErr) {
        // Context resolution failure is non-fatal — proceed without dedupe
        logger.warn("[CAP/prayerOS] context resolution failed, skipping dedupe", {
            uid,
            error: String(contextErr),
        });
    }
    // Build reminders array with Timestamp fields
    const reminders = (body.reminders ?? []).map((r) => ({
        rrule: r.rrule,
        nextFireAt: firestore_1.Timestamp.fromDate(new Date(r.nextFireAt)),
    }));
    // Build followUps array with Timestamp fields
    const followUps = (body.followUps ?? []).map((f) => ({
        dueAt: firestore_1.Timestamp.fromDate(new Date(f.dueAt)),
        status: f.status ?? "pending",
        note: f.note ?? null,
    }));
    const now = firestore_1.FieldValue.serverTimestamp();
    const newDoc = await db.collection(`users/${uid}/prayerCards`).add({
        subject: {
            type: body.subject.type,
            displayName,
            linkedContactRef: body.subject.linkedContactRef ?? null,
        },
        category: body.category,
        detail, // Note: production should encrypt this Tier C field at rest
        status: "active",
        createdAt: now,
        updatedAt: now,
        reminders,
        followUps,
    });
    return { cardId: newDoc.id, dedupeWarning };
});
// ── prayerOS_updateCard ───────────────────────────────────────────────────────
exports.prayerOS_updateCard = (0, https_1.onCall)({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const body = request.data;
    if (typeof body.cardId !== "string" || !body.cardId) {
        throw new https_1.HttpsError("invalid-argument", "cardId is required.");
    }
    if (!body.patch || typeof body.patch !== "object") {
        throw new https_1.HttpsError("invalid-argument", "patch is required.");
    }
    const db = (0, firestore_1.getFirestore)();
    const cardRef = db.doc(`users/${uid}/prayerCards/${body.cardId}`);
    const cardSnap = await cardRef.get();
    if (!cardSnap.exists) {
        throw new https_1.HttpsError("not-found", "Prayer card not found.");
    }
    logger.info("[CAP/prayerOS] updateCard", { uid, cardId: body.cardId });
    // Build update payload — only include fields present in patch
    const update = {
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    };
    const patch = body.patch;
    if (patch.detail !== undefined) {
        const detail = String(patch.detail).trim();
        if (!detail || detail.length > 2000) {
            throw new https_1.HttpsError("invalid-argument", "detail must be 1-2000 chars.");
        }
        update.detail = detail;
    }
    if (patch.category !== undefined) {
        if (!VALID_CATEGORIES.includes(patch.category)) {
            throw new https_1.HttpsError("invalid-argument", `category must be one of: ${VALID_CATEGORIES.join(", ")}`);
        }
        update.category = patch.category;
    }
    if (patch.status !== undefined) {
        if (!VALID_STATUSES.includes(patch.status)) {
            throw new https_1.HttpsError("invalid-argument", `status must be one of: ${VALID_STATUSES.join(", ")}`);
        }
        update.status = patch.status;
    }
    if (patch.reminders !== undefined) {
        update.reminders = patch.reminders.map((r) => ({
            rrule: r.rrule,
            nextFireAt: firestore_1.Timestamp.fromDate(new Date(r.nextFireAt)),
        }));
    }
    if (patch.followUps !== undefined) {
        update.followUps = patch.followUps.map((f) => ({
            dueAt: firestore_1.Timestamp.fromDate(new Date(f.dueAt)),
            status: f.status,
            note: f.note ?? null,
        }));
    }
    await cardRef.update(update);
    const updatedSnap = await cardRef.get();
    const updatedAt = toIso(updatedSnap.data()?.updatedAt);
    return { updatedAt };
});
// ── prayerOS_listCards ────────────────────────────────────────────────────────
exports.prayerOS_listCards = (0, https_1.onCall)({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const body = request.data;
    const status = body.status ?? "active";
    if (!VALID_STATUSES.includes(status)) {
        throw new https_1.HttpsError("invalid-argument", `status must be one of: ${VALID_STATUSES.join(", ")}`);
    }
    const rawPageSize = Number(body.pageSize ?? 20);
    const pageSize = Math.min(Math.max(1, rawPageSize), 50);
    logger.info("[CAP/prayerOS] listCards", { uid, status, pageSize });
    const db = (0, firestore_1.getFirestore)();
    let query = db
        .collection(`users/${uid}/prayerCards`)
        .where("status", "==", status)
        .orderBy("createdAt", "desc")
        .limit(pageSize + 1); // fetch one extra to detect next page
    // Cursor pagination
    if (body.startAfter) {
        const cursorSnap = await db.doc(`users/${uid}/prayerCards/${body.startAfter}`).get();
        if (cursorSnap.exists) {
            query = query.startAfter(cursorSnap);
        }
    }
    const snap = await query.get();
    const docs = snap.docs;
    const hasMore = docs.length > pageSize;
    const pageDocs = hasMore ? docs.slice(0, pageSize) : docs;
    const cards = pageDocs.map((doc) => docToWire(doc.id, doc.data()));
    const nextCursor = hasMore ? pageDocs[pageDocs.length - 1].id : undefined;
    return { cards, nextCursor };
});
// ── prayerOS_completeFollowUp ─────────────────────────────────────────────────
exports.prayerOS_completeFollowUp = (0, https_1.onCall)({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const body = request.data;
    if (typeof body.cardId !== "string" || !body.cardId) {
        throw new https_1.HttpsError("invalid-argument", "cardId is required.");
    }
    if (typeof body.followUpIndex !== "number" || body.followUpIndex < 0) {
        throw new https_1.HttpsError("invalid-argument", "followUpIndex must be a non-negative integer.");
    }
    logger.info("[CAP/prayerOS] completeFollowUp", {
        uid,
        cardId: body.cardId,
        followUpIndex: body.followUpIndex,
    });
    const db = (0, firestore_1.getFirestore)();
    const cardRef = db.doc(`users/${uid}/prayerCards/${body.cardId}`);
    const updatedAt = await db.runTransaction(async (tx) => {
        const cardSnap = await tx.get(cardRef);
        if (!cardSnap.exists) {
            throw new https_1.HttpsError("not-found", "Prayer card not found.");
        }
        const data = cardSnap.data();
        const followUps = Array.isArray(data.followUps) ? [...data.followUps] : [];
        if (body.followUpIndex >= followUps.length) {
            throw new https_1.HttpsError("invalid-argument", `followUpIndex ${body.followUpIndex} is out of bounds (card has ${followUps.length} followUps).`);
        }
        followUps[body.followUpIndex] = {
            ...followUps[body.followUpIndex],
            status: "done",
            note: body.note ?? followUps[body.followUpIndex].note ?? null,
        };
        tx.update(cardRef, {
            followUps,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        return new Date().toISOString(); // approximate; real value from server timestamp
    });
    // Re-fetch to get server timestamp
    const finalSnap = await cardRef.get();
    const finalUpdatedAt = toIso(finalSnap.data()?.updatedAt);
    return { updatedAt: finalUpdatedAt };
});

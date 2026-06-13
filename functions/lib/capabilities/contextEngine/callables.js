"use strict";
// callables.ts — Context Engine callable Cloud Functions (Wave 1: Lane A)
//
// Three callables:
//   contextEngine_getGrants   — Auth required (no App Check — must work in settings UI)
//   contextEngine_setGrant    — Auth required + App Check enforced
//   contextEngine_getAuditLog — Auth required (no App Check — must work in settings UI)
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
exports.contextEngine_getAuditLog = exports.contextEngine_setGrant = exports.contextEngine_getGrants = void 0;
const functions = __importStar(require("firebase-functions/v2/https"));
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
// All valid ContextSource values
const VALID_SOURCES = [
    "calendar",
    "location",
    "contacts",
    "prayerHistory",
    "readingHistory",
    "notesContent",
    "messagesMeta",
    "churchProfile",
];
// All valid ContextPolicy values
const VALID_POLICIES = ["never", "askEveryTime", "whileUsing", "always"];
function isValidSource(s) {
    return VALID_SOURCES.includes(s);
}
function isValidPolicy(p) {
    return VALID_POLICIES.includes(p);
}
// ── contextEngine_getGrants ───────────────────────────────────────────────────
// Returns all 8 current grant states for the authenticated user.
// Missing sources are returned with policy "never" and version 0.
// No App Check enforcement — grants UI must work even if App Check fails.
exports.contextEngine_getGrants = functions.onCall({ enforceAppCheck: false }, async (request) => {
    if (!request.auth) {
        throw new functions.HttpsError("unauthenticated", "Authentication required");
    }
    const uid = request.auth.uid;
    const db = (0, firestore_1.getFirestore)();
    logger.info("[contextEngine] getGrants", { uid });
    // Fetch all docs from the contextGrants subcollection
    const grantsSnap = await db
        .collection(`users/${uid}/contextGrants`)
        .get();
    // Build a map of source → doc data
    const grantMap = new Map();
    for (const doc of grantsSnap.docs) {
        const data = doc.data();
        const source = doc.id;
        if (!isValidSource(source))
            continue;
        grantMap.set(source, {
            source,
            policy: data.policy ?? "never",
            grantedAt: data.grantedAt?.toDate?.()?.toISOString?.() ?? new Date(0).toISOString(),
            updatedAt: data.updatedAt?.toDate?.()?.toISOString?.() ?? new Date(0).toISOString(),
            version: data.version ?? 0,
        });
    }
    // Fill in all 8 sources — missing ones default to "never", version 0
    const epoch = new Date(0).toISOString();
    const grants = VALID_SOURCES.map((source) => {
        return grantMap.get(source) ?? {
            source,
            policy: "never",
            grantedAt: epoch,
            updatedAt: epoch,
            version: 0,
        };
    });
    return { grants };
});
// ── contextEngine_setGrant ────────────────────────────────────────────────────
// Upserts a context grant. Increments version atomically.
// App Check enforced.
exports.contextEngine_setGrant = functions.onCall({ enforceAppCheck: true }, async (request) => {
    if (!request.auth) {
        throw new functions.HttpsError("unauthenticated", "Authentication required");
    }
    const uid = request.auth.uid;
    const body = request.data;
    if (!isValidSource(body.source)) {
        throw new functions.HttpsError("invalid-argument", `source must be one of: ${VALID_SOURCES.join(", ")}`);
    }
    if (!isValidPolicy(body.policy)) {
        throw new functions.HttpsError("invalid-argument", `policy must be one of: ${VALID_POLICIES.join(", ")}`);
    }
    const source = body.source;
    const policy = body.policy;
    const db = (0, firestore_1.getFirestore)();
    const grantRef = db.doc(`users/${uid}/contextGrants/${source}`);
    const now = new Date();
    logger.info("[contextEngine] setGrant", { uid, source, policy });
    await grantRef.set({
        source,
        policy,
        updatedAt: now,
        version: firestore_1.FieldValue.increment(1),
        // Only set grantedAt on first write; merge preserves existing value
        grantedAt: now,
    }, { merge: true });
    // Read back to get the final version number
    const snap = await grantRef.get();
    const data = snap.data();
    return {
        source,
        policy,
        version: data.version,
        updatedAt: now.toISOString(),
    };
});
// ── contextEngine_getAuditLog ─────────────────────────────────────────────────
// Paginated audit log for the authenticated user only.
// No App Check enforcement — must work in settings UI.
exports.contextEngine_getAuditLog = functions.onCall({ enforceAppCheck: false }, async (request) => {
    if (!request.auth) {
        throw new functions.HttpsError("unauthenticated", "Authentication required");
    }
    const uid = request.auth.uid;
    const body = (request.data ?? {});
    const db = (0, firestore_1.getFirestore)();
    // Clamp pageSize: default 20, max 50
    const rawPageSize = typeof body.pageSize === "number" ? body.pageSize : 20;
    const pageSize = Math.min(Math.max(1, rawPageSize), 50);
    const startAfter = typeof body.startAfter === "string" ? body.startAfter : undefined;
    logger.info("[contextEngine] getAuditLog", { uid, pageSize, startAfter });
    let query = db
        .collection(`users/${uid}/contextAuditLog`)
        .orderBy("at", "desc")
        .limit(pageSize);
    if (startAfter) {
        const cursorSnap = await db
            .doc(`users/${uid}/contextAuditLog/${startAfter}`)
            .get();
        if (cursorSnap.exists) {
            query = query.startAfter(cursorSnap);
        }
    }
    const snap = await query.get();
    const entries = snap.docs.map((doc) => {
        const d = doc.data();
        return {
            source: d.source,
            capabilityId: d.capabilityId,
            decision: d.decision,
            requestId: d.requestId,
            at: d.at,
        };
    });
    // nextCursor is the last doc's ID only if the page is full
    const nextCursor = snap.docs.length === pageSize
        ? snap.docs[snap.docs.length - 1].id
        : undefined;
    return { entries, nextCursor };
});

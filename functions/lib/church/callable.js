"use strict";
// callable.ts — Find a Church v2 callables (v2 onCall, us-east1).
//
// Every callable resolves uid / isMinor / preferences SERVER-SIDE from auth and
// clamps/validates client geo. The minor branch (§5.2) and visit-plan mirror
// conditions (§5.3) are enforced IN-FUNCTION here. Nothing trusts client claims.
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
exports.submitChurchClaim = exports.requestChurchVerification = exports.reportChurch = exports.planVisit = exports.recordChurchSearch = exports.toggleSavedChurch = exports.getChurchProfile = exports.searchChurches = exports.assembleChurchDiscovery = void 0;
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const identity_1 = require("./identity");
const geo_1 = require("./geo");
const engine_1 = require("./engine");
const db = (0, firestore_1.getFirestore)();
const OPTS = { enforceAppCheck: true, region: "us-east1" };
function requireAuth(request) {
    const uid = request.auth?.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Must be signed in.");
    return uid;
}
function buildContext(center, radiusMeters, identity) {
    return {
        center,
        radiusMeters: (0, geo_1.clampRadius)(radiusMeters),
        nowMs: Date.now(),
        preferences: identity.preferences,
        isMinor: identity.isMinor,
    };
}
// ── assembleChurchDiscovery ────────────────────────────────────────────────
exports.assembleChurchDiscovery = (0, https_1.onCall)(OPTS, async (request) => {
    const uid = requireAuth(request);
    const data = (request.data ?? {});
    if (!(0, geo_1.isValidCenter)(data.center)) {
        throw new https_1.HttpsError("invalid-argument", "center {lat,lng} required.");
    }
    const radiusMeters = (0, geo_1.clampRadius)(Number(data.radiusMeters ?? 0));
    const filters = Array.isArray(data.filters) ? data.filters : [];
    const identity = await (0, identity_1.resolveIdentity)(uid);
    const ctx = buildContext(data.center, radiusMeters, identity);
    const req = {
        center: data.center, radiusMeters, filters,
        nowIso: typeof data.nowIso === "string" ? data.nowIso : new Date(ctx.nowMs).toISOString(),
        sessionId: typeof data.sessionId === "string" ? data.sessionId : "",
    };
    return (0, engine_1.assembleChurchDiscovery)(req, ctx);
});
// ── searchChurches ─────────────────────────────────────────────────────────
exports.searchChurches = (0, https_1.onCall)(OPTS, async (request) => {
    const uid = requireAuth(request);
    const data = (request.data ?? {});
    if (!(0, geo_1.isValidCenter)(data.center)) {
        throw new https_1.HttpsError("invalid-argument", "center {lat,lng} required.");
    }
    const q = String(data.q ?? "").slice(0, 200);
    const radiusMeters = (0, geo_1.clampRadius)(Number(data.radiusMeters ?? 0));
    const filters = Array.isArray(data.filters) ? data.filters : [];
    const page = Number.isFinite(data.page) ? Math.max(0, Number(data.page)) : 0;
    const identity = await (0, identity_1.resolveIdentity)(uid);
    const ctx = buildContext(data.center, radiusMeters, identity);
    return (0, engine_1.searchChurches)(q, data.center, radiusMeters, filters, page, ctx);
});
// ── getChurchProfile ───────────────────────────────────────────────────────
exports.getChurchProfile = (0, https_1.onCall)(OPTS, async (request) => {
    requireAuth(request);
    const churchId = String((request.data ?? {}).churchId ?? "").trim();
    if (!churchId)
        throw new https_1.HttpsError("invalid-argument", "churchId required.");
    try {
        return await (0, engine_1.getChurchProfile)(churchId);
    }
    catch (e) {
        if (e instanceof Error && e.message === "not-found") {
            throw new https_1.HttpsError("not-found", "Church not found.");
        }
        throw e;
    }
});
// ── toggleSavedChurch ──────────────────────────────────────────────────────
exports.toggleSavedChurch = (0, https_1.onCall)(OPTS, async (request) => {
    const uid = requireAuth(request);
    const data = (request.data ?? {});
    const churchId = String(data.churchId ?? "").trim();
    if (!churchId)
        throw new https_1.HttpsError("invalid-argument", "churchId required.");
    const saved = data.saved === true;
    const ref = db.collection("users").doc(uid).collection("savedChurches").doc(churchId);
    if (saved) {
        await ref.set({ churchId, savedAt: Date.now() });
    }
    else {
        await ref.delete();
    }
    return { saved };
});
// ── recordChurchSearch ─────────────────────────────────────────────────────
exports.recordChurchSearch = (0, https_1.onCall)(OPTS, async (request) => {
    const uid = requireAuth(request);
    const data = (request.data ?? {});
    const term = String(data.term ?? "").trim().slice(0, 200);
    if (!term)
        return;
    const identity = await (0, identity_1.resolveIdentity)(uid);
    // Private-search toggle suppresses writes entirely (§5.1).
    if (identity.preferences?.privateSearch === true)
        return;
    const ref = db.collection("users").doc(uid).collection("churchSearchHistory").doc();
    await ref.set({
        id: ref.id, term,
        resultChurchId: data.resultChurchId ? String(data.resultChurchId) : null,
        searchedAt: Date.now(),
    });
});
// ── planVisit ──────────────────────────────────────────────────────────────
exports.planVisit = (0, https_1.onCall)(OPTS, async (request) => {
    const uid = requireAuth(request);
    const data = (request.data ?? {});
    const churchId = String(data.churchId ?? "").trim();
    if (!churchId)
        throw new https_1.HttpsError("invalid-argument", "churchId required.");
    const plannedForIso = String(data.plannedForIso ?? "").trim();
    if (!plannedForIso)
        throw new https_1.HttpsError("invalid-argument", "plannedForIso required.");
    const identity = await (0, identity_1.resolveIdentity)(uid);
    // Determine mirror eligibility (§5.3): verified church AND opt-in AND non-minor.
    const churchSnap = await db.collection("churches").doc(churchId).get();
    if (!churchSnap.exists)
        throw new https_1.HttpsError("not-found", "Church not found.");
    const church = churchSnap.data();
    const isVerified = church.verification?.status === "verified";
    // HARD minor branch (§5.2): sharedWithChurch is ALWAYS false for minors.
    const sharedWithChurch = !identity.isMinor && isVerified && data.shareWithChurch === true;
    const planRef = db.collection("users").doc(uid).collection("visitPlans").doc();
    const now = Date.now();
    const plan = {
        id: planRef.id,
        churchId,
        serviceTimeId: data.serviceTimeId ? String(data.serviceTimeId) : null,
        plannedForIso,
        partySize: typeof data.partySize === "number" ? data.partySize : null,
        notes: data.notes ? String(data.notes).slice(0, 500) : null,
        sharedWithChurch,
        createdAt: now,
        updatedAt: now,
    };
    await planRef.set(plan);
    // Mirror to the church ONLY when all conditions hold — and never any minor PII.
    if (sharedWithChurch) {
        const intentRef = db.collection("churches").doc(churchId).collection("visitorIntents").doc();
        await intentRef.set({
            id: intentRef.id,
            visitPlanId: planRef.id,
            plannedForIso,
            partySize: plan.partySize,
            createdAt: now,
        });
    }
    return { visitPlanId: planRef.id, sharedWithChurch };
});
// ── reportChurch ───────────────────────────────────────────────────────────
const VALID_REASONS = [
    "misleading_profile", "impersonation", "child_safety_concern",
    "inappropriate_media", "spam", "other",
];
exports.reportChurch = (0, https_1.onCall)(OPTS, async (request) => {
    const uid = requireAuth(request);
    const data = (request.data ?? {});
    const churchId = String(data.churchId ?? "").trim();
    if (!churchId)
        throw new https_1.HttpsError("invalid-argument", "churchId required.");
    const reason = data.reason;
    if (!VALID_REASONS.includes(reason)) {
        throw new https_1.HttpsError("invalid-argument", "Invalid reason.");
    }
    const details = data.details ? String(data.details).slice(0, 1000) : null;
    const isChildSafety = reason === "child_safety_concern";
    const reportRef = db.collection("churchReports").doc();
    await reportRef.set({
        id: reportRef.id,
        churchId,
        reporterUid: uid, // SERVER-stamped, never client-supplied
        reason,
        details,
        state: isChildSafety ? "escalated" : "open",
        createdAt: Date.now(),
    });
    // Routing: child_safety_concern uses the ABSOLUTE-STOP critical path (§5.5) —
    // the canonical moderationQueue critical category, NOT the normal report queue.
    await db.collection("moderationQueue").add({
        type: "church_report",
        churchId,
        reporterUid: uid,
        category: isChildSafety ? "child_safety" : reason,
        priority: isChildSafety ? "critical" : "normal",
        state: isChildSafety ? "pending_crisis" : "pending",
        escalateImmediately: isChildSafety,
        childSafetyEscalated: isChildSafety,
        reportRef: reportRef.path,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
    });
    if (isChildSafety) {
        logger.warn(`[reportChurch] child_safety_concern escalated for church=${churchId}`);
    }
    return { reportId: reportRef.id };
});
// ── requestChurchVerification (org side) ───────────────────────────────────
exports.requestChurchVerification = (0, https_1.onCall)(OPTS, async (request) => {
    const uid = requireAuth(request);
    const data = (request.data ?? {});
    const churchId = String(data.churchId ?? "").trim();
    if (!churchId)
        throw new https_1.HttpsError("invalid-argument", "churchId required.");
    const method = data.method;
    if (method !== "domain" && method !== "doc" && method !== "manual") {
        throw new https_1.HttpsError("invalid-argument", "Invalid method.");
    }
    const ref = db.collection("churchVerificationRequests").doc();
    await ref.set({
        id: ref.id,
        churchId,
        requesterUid: uid, // SERVER-stamped
        method,
        evidenceUrl: data.evidenceUrl ? String(data.evidenceUrl).slice(0, 500) : null,
        status: "pending", // server-managed; client cannot self-verify
        createdAt: Date.now(),
    });
    return { requestId: ref.id };
});
// ── submitChurchClaim (org onboarding) ─────────────────────────────────────
exports.submitChurchClaim = (0, https_1.onCall)(OPTS, async (request) => {
    const uid = requireAuth(request);
    const data = (request.data ?? {});
    const contactEmail = String(data.contactEmail ?? "").trim();
    if (!contactEmail)
        throw new https_1.HttpsError("invalid-argument", "contactEmail required.");
    const role = data.role;
    if (role !== "owner" && role !== "pastor" && role !== "executive_admin" && role !== "editor") {
        throw new https_1.HttpsError("invalid-argument", "Invalid role.");
    }
    const ref = db.collection("churchClaims").doc();
    await ref.set({
        id: ref.id,
        claimantUid: uid, // SERVER-stamped
        churchId: data.churchId ? String(data.churchId) : null,
        proposedName: data.proposedName ? String(data.proposedName).slice(0, 200) : null,
        role,
        contactEmail: contactEmail.slice(0, 320),
        evidenceUrl: data.evidenceUrl ? String(data.evidenceUrl).slice(0, 500) : null,
        status: "pending", // server-managed
        createdAt: Date.now(),
    });
    return { claimId: ref.id };
});

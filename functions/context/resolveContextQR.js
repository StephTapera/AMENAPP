"use strict";
/**
 * resolveContextQR — onCall, enforceAppCheck: true, region us-central1.
 *
 * Resolves a Context QR token to the OWNER'S CURRENT public-visible facets.
 * The token is an opaque identity claim (contains uid + timestamp, NOT facet data).
 * Facets are read LIVE from Firestore at resolve-time — so any visibility change
 * the owner makes is reflected immediately (the QR code itself never becomes stale).
 *
 * SECURITY:
 *   - Only public-visibility, Tier-C/S facets are returned (never Tier-P).
 *   - The caller learns ONLY a display-name and a facet summary — never raw values
 *     that could be used as a dossier. Each entry is a {category, label} pair only.
 *   - Expired tokens (>72 h) are rejected.
 *   - App Check enforced.
 *
 * Input:  { token: string }
 * Output: { displayName: string, publicFacetsSummary: { category, label }[] }
 *
 * Stage-3 deploy batch (Context System CFs) — project amen-5e359, us-central1.
 */
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
exports.resolveContextQR = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const REGION = "us-central1";
const TOKEN_MAX_AGE_MS = 72 * 60 * 60 * 1000; // 72 hours
/** Mirror of ContextTierTable — Tier-P is never exported. */
function tierForCategory(category, key) {
    if (category === "faith_journey" && key.endsWith(".areas_needing_support"))
        return "P";
    const tierC = ["interests", "values", "goals", "skills", "communities", "communication",
        "learning", "current_focus", "work", "faith_journey"];
    if (tierC.includes(category))
        return "C";
    return "P"; // relationships / family / health
}
exports.resolveContextQR = (0, https_1.onCall)({ region: REGION, enforceAppCheck: true, timeoutSeconds: 15 }, async (request) => {
    if (!request.auth?.uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const { token } = request.data;
    if (!token || typeof token !== "string" || token.length < 10) {
        throw new https_1.HttpsError("invalid-argument", "Invalid token.");
    }
    // Token format: base64url(<uid>.<issuedAtMs>) — the QR service builds this on-device.
    // We decode to extract the owner uid and validate freshness.
    let ownerUid;
    let issuedAt;
    try {
        const decoded = Buffer.from(token.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString("utf8");
        const [uid, tsStr] = decoded.split(".");
        ownerUid = uid;
        issuedAt = parseInt(tsStr, 10);
        if (!ownerUid || isNaN(issuedAt))
            throw new Error("malformed");
    }
    catch {
        throw new https_1.HttpsError("invalid-argument", "Malformed token.");
    }
    if (Date.now() - issuedAt > TOKEN_MAX_AGE_MS) {
        throw new https_1.HttpsError("deadline-exceeded", "QR code has expired.");
    }
    const db = admin.firestore();
    // Read the owner's public display name.
    const userDoc = await db.collection("users").doc(ownerUid).get();
    const displayName = userDoc.data()?.displayName ?? "AMEN user";
    // Read ONLY public-visibility, Tier-C/S facets (CONTRACTS §3 server-read invariant).
    const snap = await db
        .collection("contextFacets").doc(ownerUid).collection("facets")
        .where("visibility", "==", "public")
        .where("schemaVersion", "==", 1)
        .limit(20)
        .get();
    const summary = snap.docs
        .filter(d => {
        const tier = tierForCategory(d.data().category ?? "", d.data().key ?? "");
        return tier !== "P"; // defense-in-depth: never return Tier-P
    })
        .map(d => ({
        category: d.data().category,
        label: d.data().label,
        // displaySummary: deliberately omitted — caller gets category + label only,
        // not the raw value (prevents dossier-style enumeration).
    }));
    return { displayName, publicFacetsSummary: summary };
});

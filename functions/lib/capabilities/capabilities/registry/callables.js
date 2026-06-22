"use strict";
// capabilities/registry/callables.ts — Capability Registry callable (Wave 1: Lane B)
//
// capabilityRegistry_list: returns active capabilities for a surface.
// No App Check required — must work in the picker UI before App Check attestation
// completes on first launch.
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
exports.capabilityRegistry_list = void 0;
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const VALID_SURFACES = ["berean", "messages", "notes"];
exports.capabilityRegistry_list = (0, https_1.onCall)({ enforceAppCheck: false }, // picker UI must work without App Check
async (request) => {
    // Auth required
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "Must be signed in.");
    }
    const body = request.data;
    // Validate surface
    if (!body.surface || !VALID_SURFACES.includes(body.surface)) {
        throw new https_1.HttpsError("invalid-argument", `surface must be one of: ${VALID_SURFACES.join(", ")}`);
    }
    const surface = body.surface;
    logger.info("[CAP] capabilityRegistry_list", { uid, surface });
    const db = (0, firestore_1.getFirestore)();
    // Query capabilities where status == "active" AND surfaces array-contains surface
    const snap = await db
        .collection("capabilities")
        .where("status", "==", "active")
        .where("surfaces", "array-contains", surface)
        .get();
    const capabilities = snap.docs.map((doc) => {
        const data = doc.data();
        return {
            id: data.id ?? doc.id,
            displayName: data.displayName ?? "",
            tagline: data.tagline ?? "",
            iconSymbol: data.iconSymbol ?? "",
            surfaces: data.surfaces ?? [],
            requiredContext: data.requiredContext ?? [],
            optionalContext: data.optionalContext ?? [],
            entryFunction: data.entryFunction ?? "",
            minAppVersion: data.minAppVersion ?? "1.0.0",
            status: data.status ?? "active",
            tier: data.tier ?? "free",
        };
    });
    return { capabilities };
});

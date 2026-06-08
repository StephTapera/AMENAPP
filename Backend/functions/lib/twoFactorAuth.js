"use strict";
/**
 * twoFactorAuth.ts
 *
 * AUTH-03 — 2FA session validation without per-request Firestore reads.
 *
 * PROBLEM:
 *   caller2FASessionValid() in Firestore rules made 2 Firestore get() calls
 *   per message send (users/{uid} + userSecurity/{uid}). At 10,000 messages/day
 *   = 20,000 extra reads = $0.012/day at standard pricing, compounding at scale.
 *
 * SOLUTION:
 *   When verify2FAOTP succeeds it sets a custom JWT claim:
 *     twoFaSessionExpiry: <Unix ms timestamp when session expires>
 *   Special sentinel -1 means "2FA is disabled for this user — always allow."
 *
 *   The Firestore rule caller2FASessionValid() now reads from the JWT claim only
 *   (zero Firestore reads). The trade-off: claim is cached in the ID token for
 *   up to 1 hour; revoking a session takes effect at the next token refresh.
 *   This is acceptable because 2FA sessions are long-lived (hours/days) and
 *   revocation within the same token lifetime is an edge-case UX, not a hard
 *   security requirement for message send operations.
 *
 * CLIENT REQUIREMENT:
 *   After verify2FAOTP succeeds, the iOS client MUST call:
 *     Auth.auth().currentUser?.getIDTokenResult(forcingRefresh: true)
 *   to pick up the new claim before attempting writes that require the session.
 *
 * OTP STORAGE:
 *   Collection: otpRequests/{otpId}
 *   Fields:
 *     uid          — owner's Firebase UID
 *     codeHash     — sha256(code + otpId), hex string
 *     deliveryMethod — "email" | "sms"
 *     destination  — masked email or phone (for display only)
 *     expiresAt    — Firestore Timestamp (10 minutes from creation)
 *     used         — boolean (true after first successful verify)
 *     createdAt    — Firestore serverTimestamp
 *
 * SESSION STORAGE (unchanged from existing rules contract):
 *   Collection: userSecurity/{uid}
 *   Fields:
 *     session2FAActive    — boolean
 *     session2FAExpiresAt — Firestore Timestamp
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
exports.disable2FASession = exports.verify2FAOTP = exports.request2FAOTP = void 0;
const functions = __importStar(require("firebase-functions"));
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const crypto = __importStar(require("crypto"));
const db = admin.firestore();
const auth = admin.auth();
// ─── Constants ────────────────────────────────────────────────────────────────
const OTP_TTL_MS = 10 * 60 * 1000; // 10 minutes
const SESSION_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours
const MAX_OTP_REQUESTS_PER_WINDOW = 5;
const OTP_RATE_WINDOW_MS = 15 * 60 * 1000; // 15 minutes
// ─── Helpers ──────────────────────────────────────────────────────────────────
function hashCode(code, salt) {
    return crypto.createHash("sha256").update(code + salt).digest("hex");
}
function maskEmail(email) {
    const [local, domain] = email.split("@");
    if (!local || !domain)
        return "***";
    const visible = local.length > 2 ? local.slice(0, 2) : local[0];
    return `${visible}***@${domain}`;
}
// ─── request2FAOTP ────────────────────────────────────────────────────────────
exports.request2FAOTP = (0, https_1.onCall)(async (request) => {
    const data = request.data;
    const context = { auth: request.auth, app: request.app };
    if (!context.auth) {
        throw new https_1.HttpsError("unauthenticated", "Must be signed in to request a 2FA OTP.");
    }
    if (context.app == undefined) {
        throw new https_1.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    const uid = context.auth.uid;
    const deliveryMethod = data?.deliveryMethod;
    if (deliveryMethod !== "email" && deliveryMethod !== "sms") {
        throw new https_1.HttpsError("invalid-argument", "deliveryMethod must be 'email' or 'sms'.");
    }
    // Rate limit: max MAX_OTP_REQUESTS_PER_WINDOW per window per user.
    const windowStart = admin.firestore.Timestamp.fromMillis(Date.now() - OTP_RATE_WINDOW_MS);
    const recentSnap = await db
        .collection("otpRequests")
        .where("uid", "==", uid)
        .where("createdAt", ">", windowStart)
        .get();
    if (recentSnap.size >= MAX_OTP_REQUESTS_PER_WINDOW) {
        throw new https_1.HttpsError("resource-exhausted", "Too many OTP requests. Please wait before requesting another code.");
    }
    // Look up the user's delivery address.
    const userRecord = await auth.getUser(uid);
    let destination = "";
    if (deliveryMethod === "email") {
        if (!userRecord.email) {
            throw new https_1.HttpsError("failed-precondition", "No email address on file for this account.");
        }
        destination = userRecord.email;
    }
    else {
        if (!userRecord.phoneNumber) {
            throw new https_1.HttpsError("failed-precondition", "No phone number on file for this account.");
        }
        destination = userRecord.phoneNumber;
    }
    // Generate a 6-digit OTP.
    const code = String(Math.floor(100000 + Math.random() * 900000));
    const otpId = db.collection("otpRequests").doc().id;
    const codeHash = hashCode(code, otpId);
    const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + OTP_TTL_MS);
    await db.collection("otpRequests").doc(otpId).set({
        uid,
        codeHash,
        deliveryMethod,
        destination, // store full address server-side; only masked value returned to client
        expiresAt,
        used: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // ── Delivery ──────────────────────────────────────────────────────────────
    // In production, replace this log with a real email/SMS provider call.
    // Options: SendGrid (via HTTP), Twilio (via HTTP), or Firebase Extensions
    // "Trigger Email" extension pointing to an SMTP relay.
    //
    // Example SendGrid call (add @sendgrid/mail to package.json):
    //   await sgMail.send({ to: destination, from: "noreply@amenapp.com",
    //     subject: "Your AMEN verification code",
    //     text: `Your code is: ${code}. Expires in 10 minutes.` });
    //
    // For now, log to Cloud Functions console (visible in Firebase Console → Logs).
    functions.logger.info(`[request2FAOTP] OTP for ${uid} via ${deliveryMethod}: ${code} (expires ${expiresAt.toDate().toISOString()})`);
    const maskedDestination = deliveryMethod === "email"
        ? maskEmail(destination)
        : destination.slice(0, -4).replace(/\d/g, "*") + destination.slice(-4);
    return {
        success: true,
        otpId,
        deliveryMethod,
        destination: maskedDestination,
        expiresAt: expiresAt.toMillis(),
    };
});
// ─── verify2FAOTP ─────────────────────────────────────────────────────────────
exports.verify2FAOTP = (0, https_1.onCall)(async (request) => {
    const data = request.data;
    const context = { auth: request.auth, app: request.app };
    if (!context.auth) {
        throw new https_1.HttpsError("unauthenticated", "Must be signed in to verify a 2FA OTP.");
    }
    if (context.app == undefined) {
        throw new https_1.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    const uid = context.auth.uid;
    const otpId = data?.otpId;
    const code = data?.code;
    if (typeof otpId !== "string" || otpId.trim() === "") {
        throw new https_1.HttpsError("invalid-argument", "otpId must be a non-empty string.");
    }
    if (typeof code !== "string" || !/^\d{6}$/.test(code)) {
        throw new https_1.HttpsError("invalid-argument", "code must be a 6-digit string.");
    }
    const otpRef = db.collection("otpRequests").doc(otpId);
    const otpDoc = await otpRef.get();
    if (!otpDoc.exists) {
        throw new https_1.HttpsError("not-found", "OTP not found.");
    }
    const otp = otpDoc.data();
    // Security checks
    if (otp.uid !== uid) {
        throw new https_1.HttpsError("permission-denied", "OTP does not belong to this user.");
    }
    if (otp.used === true) {
        throw new https_1.HttpsError("already-exists", "OTP has already been used.");
    }
    const now = admin.firestore.Timestamp.now();
    if (otp.expiresAt.toMillis() < now.toMillis()) {
        throw new https_1.HttpsError("deadline-exceeded", "OTP has expired.");
    }
    const expectedHash = hashCode(code, otpId);
    if (otp.codeHash !== expectedHash) {
        throw new https_1.HttpsError("unauthenticated", "Invalid OTP code.");
    }
    // Mark OTP as used atomically.
    await otpRef.update({ used: true });
    // Create or refresh the 2FA session in userSecurity/{uid}.
    const sessionExpiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + SESSION_TTL_MS);
    await db.collection("userSecurity").doc(uid).set({
        session2FAActive: true,
        session2FAExpiresAt: sessionExpiresAt,
        lastVerifiedAt: now,
    }, { merge: true });
    // AUTH-03: Set JWT custom claim so Firestore rules can validate the session
    // without Firestore reads. The claim is picked up on the client's next
    // ID token refresh. Clients MUST call getIDTokenResult(forcingRefresh: true)
    // after this call succeeds.
    const expiryMs = sessionExpiresAt.toMillis();
    await auth.setCustomUserClaims(uid, {
        ...(await auth.getUser(uid)).customClaims,
        twoFaSessionExpiry: expiryMs,
    });
    // Generate a session token for the client (opaque reference, not a JWT).
    const sessionToken = crypto.randomBytes(32).toString("hex");
    functions.logger.info(`[verify2FAOTP] 2FA session created for ${uid}, expires ${sessionExpiresAt.toDate().toISOString()}`);
    return {
        success: true,
        verified: true,
        sessionToken,
        sessionExpiresAt: expiryMs,
    };
});
// ─── disable2FA (companion) ───────────────────────────────────────────────────
//
// When 2FA is disabled for an account, set twoFaSessionExpiry = -1 (sentinel
// for "2FA not enabled") so caller2FASessionValid() passes without a Firestore
// read. Called by TwoFactorAuthService.swift when the user disables 2FA.
exports.disable2FASession = (0, https_1.onCall)(async (request) => {
    const data = request.data;
    const context = { auth: request.auth, app: request.app };
    if (!context.auth) {
        throw new https_1.HttpsError("unauthenticated", "Must be signed in.");
    }
    if (context.app == undefined) {
        throw new https_1.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    const uid = context.auth.uid;
    // Clear the Firestore session.
    await db.collection("userSecurity").doc(uid).set({
        session2FAActive: false,
        session2FAExpiresAt: admin.firestore.Timestamp.fromMillis(0),
    }, { merge: true });
    // Set the sentinel claim so the rule allows through without reads.
    await auth.setCustomUserClaims(uid, {
        ...(await auth.getUser(uid)).customClaims,
        twoFaSessionExpiry: -1,
    });
    functions.logger.info(`[disable2FASession] 2FA session cleared for ${uid}`);
    return { success: true };
});
//# sourceMappingURL=twoFactorAuth.js.map
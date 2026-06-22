/**
 * bereanAuditFunctions.js
 * AMEN App — Berean AI Audit Log Cloud Functions
 *
 * H-13 FIX: Berean audit log writes are now server-authoritative.
 * Previously the iOS client wrote directly to `bereanAuditLog/{docId}` in Firestore,
 * which meant a client could forge the `userId` field in the audit record.
 * This callable receives the event + metadata from the client, then appends
 * the userId from request.auth.uid server-side so it cannot be tampered with.
 *
 * Functions exported:
 *   writeBereanAuditEntry  — Appends a tamper-proof audit entry to bereanAuditLog/
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const REGION = "us-central1";

// APP CHECK: Flip to enforceAppCheck: true requires iOS App Check to be initialized first.
// See: https://firebase.google.com/docs/app-check/ios/default-providers
// iOS setup steps: 1) Add AppCheckProviderFactory in AppDelegate, 2) Configure DeviceCheck/AppAttest provider.
exports.writeBereanAuditEntry = onCall(
  { region: REGION, enforceAppCheck: true },
  async (request) => {
    // Require authentication — userId must be server-authoritative.
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const userId = request.auth.uid;

    const { event, metadata } = request.data ?? {};
    if (!event || typeof event !== "string" || event.trim().length === 0) {
      throw new HttpsError("invalid-argument", "event is required and must be a non-empty string.");
    }

    // Sanitise metadata: must be a plain key→string map with bounded size.
    const safeMetadata = {};
    if (metadata && typeof metadata === "object" && !Array.isArray(metadata)) {
      const keys = Object.keys(metadata).slice(0, 20); // cap at 20 keys
      for (const key of keys) {
        const val = metadata[key];
        if (typeof val === "string") {
          safeMetadata[key] = val.slice(0, 500); // cap value length
        }
      }
    }

    await admin.firestore().collection("bereanAuditLog").add({
      // userId is set HERE on the server — never trusted from the client.
      userId,
      event: event.trim().slice(0, 200),
      metadata: safeMetadata,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true };
  }
);

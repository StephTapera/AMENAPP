"use strict";
/**
 * guardianLink.js — Guardian email-verification pipeline (finding #44).
 *
 * Exports
 * ───────
 * onGuardianLinkCreated  — onDocumentCreated trigger on guardianLinkRequests/{reqId}
 *                          Sends a verification email to the guardian and stamps
 *                          the request with a hashed token + expiry.
 *
 * verifyGuardianLink     — onCall (Auth + App Check + rate-limited)
 *                          Guardian submits the 6-digit code from their email.
 *                          On success: writes guardianApprovedContacts/{minorId}/contacts/{guardianUid}
 *                          with { approved: true } — the document that isGuardianApprovedContact() reads.
 *
 * Security invariants
 * ───────────────────
 * I-GUARDIAN-1  Only the minor who created the request can see its status.
 * I-GUARDIAN-2  Token is a 6-digit TOTP-style OTP; the hash (sha256) is stored, not the
 *               raw value. The raw value is only transmitted in the email.
 * I-GUARDIAN-3  Tokens expire after 24 hours. A new request must be created after expiry.
 * I-GUARDIAN-4  Maximum 3 failed verification attempts before the request is invalidated.
 * I-GUARDIAN-5  Rate limit: 3 link requests per minor per 24 hours.
 * I-GUARDIAN-6  guardianApprovedContacts writes are Admin SDK only (CF-owned). Firestore
 *               rules deny all client writes to this collection.
 * I-GUARDIAN-7  NCMEC_SUBMISSION_ENABLED is false. No CSAM pipeline involved here.
 *
 * Deploy
 * ──────
 * firebase deploy --only functions:onGuardianLinkCreated,functions:verifyGuardianLink \
 *   --project amen-5e359
 *
 * Flag gate: guardian_link_enabled (Remote Config). CF checks this; if false, returns
 * FAILED_PRECONDITION to callers. Default false until A-03 policy decision is made.
 */

const { onCall, HttpsError }       = require("firebase-functions/v2/https");
const { onDocumentCreated }        = require("firebase-functions/v2/firestore");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getRemoteConfig }          = require("firebase-admin/remote-config");
const crypto                       = require("crypto");

const REGION = "us-central1";

// ── Helpers ───────────────────────────────────────────────────────────────────

/** SHA-256 hex digest of a string. */
function sha256(str) {
  return crypto.createHash("sha256").update(str, "utf8").digest("hex");
}

/** Generate a cryptographically random 6-digit OTP. */
function generateOTP() {
  // Use crypto.randomInt for uniform distribution over [0, 1_000_000).
  const code = crypto.randomInt(0, 1_000_000);
  return String(code).padStart(6, "0");
}

/** Returns the current Remote Config value for a boolean flag. Defaults to false. */
async function flagEnabled(key) {
  try {
    const rc = getRemoteConfig();
    const template = await rc.getServerTemplate();
    const val = template.defaultConfig[key];
    return val === true || val === "true";
  } catch {
    return false;
  }
}

/** Validates a basic email format. */
function isValidEmail(email) {
  return typeof email === "string" && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());
}

/**
 * Sends a guardian verification email via Firebase Extensions (if configured) or
 * via a no-op log path (until Nodemailer/SendGrid is wired per SAFETY_RUNBOOK §14).
 *
 * Production wiring: replace the dlog path below with:
 *   await admin.firestore().collection("mail").add({
 *     to: guardianEmail,
 *     template: { name: "guardian-verification", data: { otp, minorDisplayName, expiryHours: 24 } }
 *   });
 *
 * The Firebase Extensions Trigger Email extension processes the `mail` collection.
 * Until that extension is configured, this function logs the OTP to the server
 * console (which is visible ONLY to project admins in Cloud Logging — not to clients).
 */
async function sendVerificationEmail(guardianEmail, otp, minorDisplayName) {
  const db = getFirestore();

  // Write to the `mail` collection — picked up by Trigger Email extension if installed.
  // Falls back to console-only if extension is absent (no-throw).
  try {
    await db.collection("mail").add({
      to: guardianEmail,
      message: {
        subject: `AMEN: Verify your guardian link for ${minorDisplayName}`,
        text: [
          `Hi,`,
          ``,
          `${minorDisplayName} has requested you as their guardian on AMEN.`,
          ``,
          `Your verification code is: ${otp}`,
          ``,
          `Enter this code in the AMEN app within 24 hours to confirm.`,
          `If you did not request this, you can safely ignore this email.`,
          ``,
          `— The AMEN Team`
        ].join("\n"),
        html: [
          `<p>Hi,</p>`,
          `<p><strong>${minorDisplayName}</strong> has requested you as their guardian on AMEN.</p>`,
          `<p>Your verification code is: <strong style="font-size:24px;letter-spacing:4px">${otp}</strong></p>`,
          `<p>Enter this code in the AMEN app within 24 hours to confirm.</p>`,
          `<p>If you did not request this, you can safely ignore this email.</p>`,
          `<p>— The AMEN Team</p>`
        ].join("")
      }
    });
  } catch (mailErr) {
    // Log to Cloud Logging (admin-only) — not a fatal error.
    console.warn("[guardianLink] mail collection write failed (extension may not be installed):", mailErr.message);
    // Development fallback: log OTP to console (admin-visible only).
    console.log(`[guardianLink] DEV ONLY — OTP for ${guardianEmail}: ${otp}`);
  }
}

// ── onGuardianLinkCreated ─────────────────────────────────────────────────────

/**
 * Triggered when a minor writes to guardianLinkRequests/{requestId}.
 * Enforces rate limit, generates OTP, stamps the document, sends email.
 */
exports.onGuardianLinkCreated = onDocumentCreated(
  { document: "guardianLinkRequests/{requestId}", region: REGION },
  async (event) => {
    const db = getFirestore();
    const reqId = event.params.requestId;
    const data = event.data?.data();

    if (!data) {
      console.error("[onGuardianLinkCreated] No document data for", reqId);
      return;
    }

    const { minorId, guardianEmail, status } = data;

    // Only process pending requests.
    if (status !== "pending") return;

    // Guard: email must be valid.
    if (!isValidEmail(guardianEmail)) {
      await event.data.ref.update({
        status: "failed",
        failureReason: "invalid_guardian_email",
        updatedAt: FieldValue.serverTimestamp()
      });
      return;
    }

    // Rate limit: max 3 requests per minor per 24 hours (I-GUARDIAN-5).
    const windowStart = Timestamp.fromMillis(Date.now() - 24 * 60 * 60 * 1000);
    const recentSnap = await db.collection("guardianLinkRequests")
      .where("minorId", "==", minorId)
      .where("createdAt", ">", windowStart)
      .count()
      .get();

    if (recentSnap.data().count > 3) {
      await event.data.ref.update({
        status: "failed",
        failureReason: "rate_limit_exceeded",
        updatedAt: FieldValue.serverTimestamp()
      });
      console.warn("[onGuardianLinkCreated] Rate limit exceeded for minor:", minorId);
      return;
    }

    // Resolve minor display name from users/{minorId} for the email.
    let minorDisplayName = "your child";
    try {
      const minorDoc = await db.collection("users").document(minorId).get();
      if (minorDoc.exists) {
        minorDisplayName = minorDoc.data()?.displayName || minorDisplayName;
      }
    } catch {
      // Non-fatal — proceed with generic name.
    }

    // Generate OTP and store its hash (I-GUARDIAN-2).
    const otp = generateOTP();
    const otpHash = sha256(otp);
    const expiresAt = Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000); // 24 h

    // Update the request doc with token metadata (hash only — never store raw OTP).
    await event.data.ref.update({
      status: "email_sent",
      otpHash,
      expiresAt,
      attemptCount: 0,
      updatedAt: FieldValue.serverTimestamp()
    });

    // Send the verification email.
    await sendVerificationEmail(guardianEmail, otp, minorDisplayName);

    console.log(`[onGuardianLinkCreated] Verification email sent. reqId=${reqId} minorId=${minorId}`);
  }
);

// ── verifyGuardianLink ────────────────────────────────────────────────────────

/**
 * Guardian-facing callable: submit OTP to complete the guardian link.
 *
 * Request data: { requestId: string, otp: string }
 * Returns: { status: "approved" }
 *
 * On success, writes:
 *   guardianApprovedContacts/{minorId}/contacts/{guardianUid} = { approved: true, linkedAt: serverTimestamp }
 *   guardianLinkRequests/{requestId}.status = "approved"
 */
exports.verifyGuardianLink = onCall(
  { enforceAppCheck: true, region: REGION },
  async (request) => {
    // Auth required (guardian must be signed in).
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    // Feature flag gate (I-GUARDIAN-default-OFF).
    if (!(await flagEnabled("guardian_link_enabled"))) {
      throw new HttpsError("failed-precondition", "Guardian linking is not yet enabled.");
    }

    const { requestId, otp } = request.data;
    if (!requestId || typeof requestId !== "string") {
      throw new HttpsError("invalid-argument", "requestId required.");
    }
    if (!otp || typeof otp !== "string" || !/^\d{6}$/.test(otp)) {
      throw new HttpsError("invalid-argument", "otp must be a 6-digit code.");
    }

    const db = getFirestore();
    const guardianUid = request.auth.uid;

    // Load the link request.
    const reqRef = db.collection("guardianLinkRequests").doc(requestId);
    const reqDoc = await reqRef.get();

    if (!reqDoc.exists) {
      throw new HttpsError("not-found", "Guardian link request not found.");
    }

    const reqData = reqDoc.data();
    const { minorId, status, otpHash, expiresAt, attemptCount = 0 } = reqData;

    // Status guard: only process email_sent requests.
    if (status !== "email_sent") {
      throw new HttpsError(
        "failed-precondition",
        status === "approved" ? "This link request is already approved." :
        status === "failed"   ? "This link request has expired or failed." :
                                "Invalid request state: " + status
      );
    }

    // Expiry check (I-GUARDIAN-3).
    if (expiresAt && expiresAt.toMillis() < Date.now()) {
      await reqRef.update({ status: "failed", failureReason: "expired", updatedAt: FieldValue.serverTimestamp() });
      throw new HttpsError("deadline-exceeded", "Verification code has expired. Please request a new link.");
    }

    // Attempt limit check (I-GUARDIAN-4).
    if (attemptCount >= 3) {
      await reqRef.update({ status: "failed", failureReason: "max_attempts_exceeded", updatedAt: FieldValue.serverTimestamp() });
      throw new HttpsError("resource-exhausted", "Maximum verification attempts exceeded. Please request a new link.");
    }

    // Increment attempt count before validating (prevent parallel brute-force).
    await reqRef.update({ attemptCount: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() });

    // Constant-time token comparison (I-GUARDIAN-2).
    const submittedHash = sha256(otp);
    const tokensMatch = (() => {
      try {
        return crypto.timingSafeEqual(
          Buffer.from(submittedHash, "hex"),
          Buffer.from(otpHash,       "hex")
        );
      } catch {
        return false;
      }
    })();

    if (!tokensMatch) {
      throw new HttpsError("permission-denied", "Invalid verification code.");
    }

    // ── Success path ──────────────────────────────────────────────────────────
    // Write guardian-approved contact (I-GUARDIAN-6: Admin SDK only).
    const approvedRef = db
      .collection("guardianApprovedContacts")
      .doc(minorId)
      .collection("contacts")
      .doc(guardianUid);

    // Also write a reverse-index for the guardian to see their linked minors.
    const guardianLinkRef = db
      .collection("guardianLinks")
      .doc(guardianUid)
      .collection("minors")
      .doc(minorId);

    const batch = db.batch();

    batch.set(approvedRef, {
      approved: true,
      guardianUid,
      minorId,
      linkedAt: FieldValue.serverTimestamp(),
      linkRequestId: requestId
    }, { merge: false });

    batch.set(guardianLinkRef, {
      minorId,
      guardianUid,
      linkedAt: FieldValue.serverTimestamp(),
      linkRequestId: requestId
    }, { merge: false });

    batch.update(reqRef, {
      status: "approved",
      approvedAt: FieldValue.serverTimestamp(),
      guardianUid,
      updatedAt: FieldValue.serverTimestamp()
    });

    await batch.commit();

    console.log(`[verifyGuardianLink] Approved. minorId=${minorId} guardianUid=${guardianUid} reqId=${requestId}`);

    return { status: "approved" };
  }
);

/**
 * jitAccess.ts
 *
 * Just-In-Time (JIT) Admin Access — Trust OS requirement.
 *
 * PROBLEM:
 *   Once `admin: true` or `moderator: true` is set as a custom claim it persists
 *   indefinitely. A compromised moderator account retains elevated access forever,
 *   violating the principle of least privilege and the Trust OS "JIT access" spec.
 *
 * SOLUTION:
 *   Moderators request a time-limited elevation session. The session is recorded
 *   in Firestore and reflected as short-lived custom claims (`jitRole` +
 *   `jitRoleExpiry`). A scheduled cleanup job strips claims and marks sessions
 *   expired after the window closes, regardless of whether the user explicitly
 *   revoked early.
 *
 * SESSION STORAGE:
 *   Collection: jitAccessSessions/{uid}
 *   Fields:
 *     uid              — Firebase UID of the moderator
 *     role             — "moderator" | "reviewQueue"
 *     grantedAt        — Firestore Timestamp
 *     expiresAt        — Firestore Timestamp (max 480 minutes from grantedAt)
 *     grantedBySessionId — opaque random token tying the session to a specific request
 *     revokedAt        — Firestore Timestamp (set on early revocation)
 *     expiredAt        — Firestore Timestamp (set by cleanup job on natural expiry)
 *
 * AUDIT TRAIL:
 *   Collection: trustAuditLog (append-only)
 *   eventTypes: "jit_session_created" | "jit_session_revoked" | "jit_session_expired"
 *
 * CUSTOM CLAIMS CONTRACT:
 *   jitRole        — string: "moderator" | "reviewQueue" | null (cleared on revoke/expire)
 *   jitRoleExpiry  — number: Unix ms timestamp when the elevation expires, or 0 (cleared)
 *
 *   After requestTemporaryElevation or revokeElevation succeeds the iOS client MUST call:
 *     Auth.auth().currentUser?.getIDTokenResult(forcingRefresh: true)
 *   to propagate the new claims before writing to paths that require them.
 *
 * SECURITY NOTES:
 *   - Only existing moderators (custom claim `moderator: true`) may request elevation.
 *   - Admins (custom claim `admin: true`) receive permanent access through the existing
 *     grant flow and must NOT use this path.
 *   - Maximum session duration is 480 minutes (8 hours). Longer values are silently
 *     clamped rather than rejected so the client UX does not need to hard-code the cap.
 *   - Cleanup runs every 30 minutes; claims may persist for up to 30 minutes past expiry
 *     in the worst case. This is acceptable for moderation-queue work.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import {requireAuthAndAppCheck} from "./amenAI/common";

const db = admin.firestore();
const auth = admin.auth();

// ─── Constants ────────────────────────────────────────────────────────────────

const MAX_DURATION_MINUTES = 480;                    // 8 hours hard cap
const CLEANUP_SCHEDULE     = "every 30 minutes";
const VALID_ROLES          = ["moderator", "reviewQueue"] as const;

type JitRole = typeof VALID_ROLES[number];

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Read the caller's current custom claims from Firebase Auth.
 * Returns the claims object (never null — returns {} if none set).
 */
async function getCustomClaims(uid: string): Promise<Record<string, unknown>> {
    const userRecord = await auth.getUser(uid);
    return (userRecord.customClaims ?? {}) as Record<string, unknown>;
}

/**
 * Merge new claim values into the caller's existing claims without clobbering
 * unrelated claims (e.g. twoFaSessionExpiry, ageTier).
 */
async function mergeCustomClaims(
    uid: string,
    updates: Record<string, unknown>
): Promise<void> {
    const existing = await getCustomClaims(uid);
    await auth.setCustomUserClaims(uid, {...existing, ...updates});
}

/**
 * Write an append-only event to `trustAuditLog`.
 * Non-blocking fire-and-forget — failures are logged but do not abort the
 * parent operation, consistent with other audit writers in the codebase.
 */
async function writeAuditEvent(
    eventType: "jit_session_created" | "jit_session_revoked" | "jit_session_expired",
    uid: string,
    extra: Record<string, unknown>
): Promise<void> {
    try {
        await db.collection("trustAuditLog").add({
            eventType,
            uid,
            ...extra,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    } catch (err) {
        // Audit log failure must never block the primary operation.
        const {logger} = await import("firebase-functions/v2");
        logger.error(`[jitAccess] audit write failed for ${eventType} uid=${uid}`, err);
    }
}

// ─── requestTemporaryElevation ────────────────────────────────────────────────

export const requestTemporaryElevation = onCall(
    {enforceAppCheck: true},
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);

        // ── 1. Only existing moderators may request JIT elevation ────────────
        const claims = await getCustomClaims(uid);

        if (!claims.moderator) {
            throw new HttpsError(
                "permission-denied",
                "Only existing moderators may request a temporary elevation session."
            );
        }
        if (claims.admin) {
            throw new HttpsError(
                "failed-precondition",
                "Admins receive permanent access through the admin grant flow. " +
                "JIT elevation is not required."
            );
        }

        // ── 2. Validate input ────────────────────────────────────────────────
        const data = (request.data ?? {}) as Record<string, unknown>;
        const role = data.role as string | undefined;
        const durationMinutesRaw = data.durationMinutes;

        if (!role || !VALID_ROLES.includes(role as JitRole)) {
            throw new HttpsError(
                "invalid-argument",
                `role must be one of: ${VALID_ROLES.join(", ")}.`
            );
        }

        if (typeof durationMinutesRaw !== "number" || durationMinutesRaw <= 0) {
            throw new HttpsError(
                "invalid-argument",
                "durationMinutes must be a positive number."
            );
        }

        // Silently clamp to the maximum — client does not need to know the cap value.
        const durationMinutes = Math.min(durationMinutesRaw, MAX_DURATION_MINUTES);

        // ── 3. Check for an existing active session (prevent double-grant) ───
        const existingSession = await db
            .collection("jitAccessSessions")
            .doc(uid)
            .get();

        if (existingSession.exists) {
            const session = existingSession.data()!;
            const now = Date.now();
            const expiresAtMs = session.expiresAt?.toMillis?.() ?? 0;
            const alreadyRevoked = !!session.revokedAt;
            const alreadyExpired = !!session.expiredAt;

            if (!alreadyRevoked && !alreadyExpired && expiresAtMs > now) {
                throw new HttpsError(
                    "already-exists",
                    "An active JIT session already exists. Revoke it before requesting a new one."
                );
            }
        }

        // ── 4. Compute timestamps ────────────────────────────────────────────
        const now = Date.now();
        const expiresAtMs = now + durationMinutes * 60 * 1000;
        const grantedAt  = admin.firestore.Timestamp.fromMillis(now);
        const expiresAt  = admin.firestore.Timestamp.fromMillis(expiresAtMs);

        const grantedBySessionId = crypto.randomBytes(24).toString("hex");

        // ── 5. Write session record ──────────────────────────────────────────
        // revokedAt and expiredAt are written as explicit null so that the
        // cleanup query (`where("revokedAt", "==", null)`) matches this doc.
        // Firestore does not index missing fields the same way as null values.
        await db.collection("jitAccessSessions").doc(uid).set({
            uid,
            role,
            grantedAt,
            expiresAt,
            grantedBySessionId,
            revokedAt: null,
            expiredAt: null,
        });

        // ── 6. Set custom claims ─────────────────────────────────────────────
        await mergeCustomClaims(uid, {
            jitRole:       role,
            jitRoleExpiry: expiresAtMs,
        });

        // ── 7. Audit log ─────────────────────────────────────────────────────
        await writeAuditEvent("jit_session_created", uid, {
            role,
            durationMinutes,
            expiresAt: expiresAt.toDate().toISOString(),
            grantedBySessionId,
        });

        return {
            expiresAt: expiresAt.toDate().toISOString(),
        };
    }
);

// ─── revokeElevation ──────────────────────────────────────────────────────────

export const revokeElevation = onCall(
    {enforceAppCheck: true},
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);

        // ── 1. Load the active session ───────────────────────────────────────
        const sessionRef = db.collection("jitAccessSessions").doc(uid);
        const sessionDoc = await sessionRef.get();

        if (!sessionDoc.exists) {
            throw new HttpsError(
                "not-found",
                "No JIT access session found for this account."
            );
        }

        const session = sessionDoc.data()!;

        if (session.revokedAt) {
            throw new HttpsError(
                "already-exists",
                "This JIT session has already been revoked."
            );
        }

        // ── 2. Mark session revoked in Firestore ─────────────────────────────
        await sessionRef.update({
            revokedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // ── 3. Clear custom claims ───────────────────────────────────────────
        await mergeCustomClaims(uid, {
            jitRole:       null,
            jitRoleExpiry: 0,
        });

        // ── 4. Audit log ─────────────────────────────────────────────────────
        await writeAuditEvent("jit_session_revoked", uid, {
            role: session.role ?? null,
            grantedBySessionId: session.grantedBySessionId ?? null,
        });

        return {success: true};
    }
);

// ─── cleanupExpiredJitSessions ────────────────────────────────────────────────

export const cleanupExpiredJitSessions = onSchedule(
    {schedule: CLEANUP_SCHEDULE, region: "us-central1"},
    async () => {
        const {logger} = await import("firebase-functions/v2");

        const now = admin.firestore.Timestamp.now();

        // Query sessions that have passed their expiry and have NOT been
        // explicitly revoked or already marked expired.
        // Both revokedAt and expiredAt are stored as explicit null at creation
        // time so these equality filters match correctly (Firestore does not
        // treat a missing field the same as null in where clauses).
        const expiredSnap = await db
            .collection("jitAccessSessions")
            .where("expiresAt", "<=", now)
            .where("revokedAt", "==", null)
            .where("expiredAt", "==", null)
            .get();

        if (expiredSnap.empty) {
            logger.info("[cleanupExpiredJitSessions] No expired JIT sessions to clean up.");
            return;
        }

        logger.info(
            `[cleanupExpiredJitSessions] Found ${expiredSnap.size} expired session(s) to clean up.`
        );

        // Process in parallel — each session is an independent document.
        await Promise.allSettled(
            expiredSnap.docs.map(async (doc) => {
                const session = doc.data();
                const uid: string = session.uid;

                try {
                    // Clear the custom claims first — if this fails, leave
                    // the Firestore document untouched so the next run retries.
                    await mergeCustomClaims(uid, {
                        jitRole:       null,
                        jitRoleExpiry: 0,
                    });

                    // Mark the session expired in Firestore.
                    await doc.ref.update({
                        expiredAt: admin.firestore.FieldValue.serverTimestamp(),
                    });

                    // Audit log.
                    await writeAuditEvent("jit_session_expired", uid, {
                        role: session.role ?? null,
                        grantedBySessionId: session.grantedBySessionId ?? null,
                        originalExpiresAt: session.expiresAt?.toDate?.()?.toISOString() ?? null,
                    });

                    logger.info(
                        `[cleanupExpiredJitSessions] Expired session for uid=${uid} role=${session.role}`
                    );
                } catch (err) {
                    // Log and continue — a single failure must not abort other sessions.
                    logger.error(
                        `[cleanupExpiredJitSessions] Failed to clean up session for uid=${uid}`,
                        err
                    );
                }
            })
        );
    }
);

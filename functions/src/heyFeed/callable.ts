// callable.ts — Callable Cloud Functions for Hey Feed NL system

import * as functions from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { parseHeyFeedText } from "./intentParser";
import { expiryFromDuration, MAX_ACTIVE_PREFERENCES_PER_USER } from "./constants";
import { FeedNLPreference } from "./types";

const db = getFirestore();

// ── submitHeyFeedNLRequest ─────────────────────────────────────────────────

export const submitHeyFeedNLRequest = functions.onCall(
  { enforceAppCheck: true // enforceAppCheck: true — requires App Check token; disable locally via FUNCTIONS_EMULATOR env var if needed },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const text = String(request.data?.text ?? "").trim();
    if (!text || text.length < 2) {
      throw new functions.HttpsError("invalid-argument", "Text is required.");
    }
    if (text.length > 500) {
      throw new functions.HttpsError("invalid-argument", "Text too long.");
    }

    const intent = parseHeyFeedText(text);

    if (intent.targets.length === 0) {
      return { ok: false, intent, created: [] };
    }

    const batch = db.batch();
    const created: string[] = [];
    const now = Timestamp.now();

    for (const target of intent.targets) {
      const prefId = `${userId}_${target.id}_${Date.now()}`;
      const ref = db
        .collection("users").doc(userId)
        .collection("feedNLPreferences").doc(prefId);

      const expiry = expiryFromDuration(intent.duration);

      const pref: FeedNLPreference = {
        id: prefId,
        userId,
        action: intent.action,
        targetId: target.id,
        targetLabel: target.label,
        targetType: target.type,
        strength: Math.round(intent.strength * target.confidence * 100) / 100,
        duration: intent.duration,
        source: "nl_input",
        isActive: true,
        isPaused: false,
        createdAt: now,
        expiresAt: expiry ? Timestamp.fromDate(expiry) : null,
      };

      batch.set(ref, pref);
      created.push(prefId);
    }

    // Audit log
    const auditRef = db.collection("users").doc(userId)
      .collection("feedAuditEvents").doc();
    batch.set(auditRef, {
      type: "nl_preference_created",
      originalText: text,
      intent: { action: intent.action, confidence: intent.confidence, duration: intent.duration },
      targetCount: intent.targets.length,
      createdAt: now,
    });

    await batch.commit();
    logger.info(`Hey Feed: created ${created.length} preferences for ${userId}`);

    return { ok: true, intent, created };
  }
);

// ── removeHeyFeedNLPreference ─────────────────────────────────────────────

export const removeHeyFeedNLPreference = functions.onCall(
  { enforceAppCheck: true // enforceAppCheck: true — requires App Check token; disable locally via FUNCTIONS_EMULATOR env var if needed },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const preferenceId = String(request.data?.preferenceId ?? "").trim();
    if (!preferenceId) throw new functions.HttpsError("invalid-argument", "preferenceId required.");

    // Validate ownership
    const ref = db.collection("users").doc(userId)
      .collection("feedNLPreferences").doc(preferenceId);
    const doc = await ref.get();
    if (!doc.exists) throw new functions.HttpsError("not-found", "Preference not found.");
    if (doc.data()?.userId !== userId) {
      throw new functions.HttpsError("permission-denied", "Not your preference.");
    }

    await ref.update({ isActive: false });
    return { ok: true };
  }
);

// ── resetHeyFeedNLPreferences ─────────────────────────────────────────────

export const resetHeyFeedNLPreferences = functions.onCall(
  { enforceAppCheck: true // enforceAppCheck: true — requires App Check token; disable locally via FUNCTIONS_EMULATOR env var if needed },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const snap = await db.collection("users").doc(userId)
      .collection("feedNLPreferences")
      .where("isActive", "==", true)
      .get();

    if (snap.empty) return { ok: true, cleared: 0 };

    const batch = db.batch();
    snap.docs.forEach(doc => batch.update(doc.ref, { isActive: false }));
    await batch.commit();

    return { ok: true, cleared: snap.size };
  }
);

// ── parseHeyFeedIntent (preview only, no write) ───────────────────────────

export const parseHeyFeedIntent = functions.onCall(
  { enforceAppCheck: true // enforceAppCheck: true — requires App Check token; disable locally via FUNCTIONS_EMULATOR env var if needed },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const text = String(request.data?.text ?? "").trim();
    if (!text) throw new functions.HttpsError("invalid-argument", "Text required.");

    const intent = parseHeyFeedText(text);
    return { ok: true, intent };
  }
);

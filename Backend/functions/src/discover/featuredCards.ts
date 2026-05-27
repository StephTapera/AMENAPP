import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const REGION = "us-central1";

// ─── setFeatured ──────────────────────────────────────────────────────────────
// Admin-only callable to create or update a featured card.
// Sets moderationCleared=false; clearFeaturedModeration must be called before
// the card surfaces in the iOS client query.

export const setFeatured = onCall({ region: REGION }, async (req) => {
  if (!req.auth?.token?.["admin"]) {
    throw new HttpsError("permission-denied", "Admin credential required");
  }

  const { id, title, subtitle, badgeLabel, accentHex, imageURL,
          rating, contentRef, order, active } = req.data as {
    id?: string;
    title: string;
    subtitle?: string;
    badgeLabel?: string;
    accentHex?: string;
    imageURL?: string;
    rating?: string;
    contentRef?: { kind: string; refID: string };
    order?: number;
    active?: boolean;
  };

  if (!title) throw new HttpsError("invalid-argument", "title is required");

  const payload: Record<string, unknown> = {
    title,
    subtitle:          subtitle   ?? null,
    badgeLabel:        badgeLabel ?? null,
    accentHex:         accentHex  ?? null,
    imageURL:          imageURL   ?? null,
    rating:            rating     ?? null,
    contentRef:        contentRef ?? null,
    order:             typeof order  === "number" ? order  : 0,
    active:            typeof active === "boolean" ? active : true,
    moderationCleared: false,
    updatedAt:         admin.firestore.FieldValue.serverTimestamp(),
  };

  const db = admin.firestore();
  const ref = id
    ? db.collection("featured").doc(id)
    : db.collection("featured").doc();

  await ref.set(payload, { merge: true });
  return { id: ref.id };
});

// ─── clearFeaturedModeration ──────────────────────────────────────────────────
// Admin-only callable to approve a card after GUARDIAN review.

export const clearFeaturedModeration = onCall({ region: REGION }, async (req) => {
  if (!req.auth?.token?.["admin"]) {
    throw new HttpsError("permission-denied", "Admin credential required");
  }

  const { id } = req.data as { id?: string };
  if (!id) throw new HttpsError("invalid-argument", "id is required");

  const db = admin.firestore();
  await db.collection("featured").doc(id).update({
    moderationCleared: true,
    clearedAt:         admin.firestore.FieldValue.serverTimestamp(),
    clearedBy:         req.auth.uid,
  });

  return { ok: true };
});

// ─── markEngaged ──────────────────────────────────────────────────────────────
// User callable: upserts an entry in users/{uid}/continue.
// Called when the user opens or plays any content item.

const VALID_KINDS = ["post", "ariseVideo", "outpourClip", "study", "verse", "churchNote"] as const;

export const markEngaged = onCall({ region: REGION }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in");

  const { kind, refID, title, accentHex, imageURL } = req.data as {
    kind: string;
    refID: string;
    title?: string;
    accentHex?: string;
    imageURL?: string;
  };

  if (!kind || !refID) {
    throw new HttpsError("invalid-argument", "kind and refID are required");
  }
  if (!VALID_KINDS.includes(kind as typeof VALID_KINDS[number])) {
    throw new HttpsError("invalid-argument", `kind must be one of: ${VALID_KINDS.join(", ")}`);
  }

  const docId = `${kind}_${refID}`;
  const db = admin.firestore();
  await db.collection("users").doc(uid).collection("continue").doc(docId).set({
    contentRef:     { kind, refID },
    title:          title     ?? "",
    accentHex:      accentHex ?? null,
    imageURL:       imageURL  ?? null,
    lastEngagedAt:  admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  return { ok: true };
});

// ─── deleteContinueRow ────────────────────────────────────────────────────────
// User callable: removes one Continue-in-AMEN entry.

export const deleteContinueRow = onCall({ region: REGION }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in");

  const { entryId } = req.data as { entryId?: string };
  if (!entryId) throw new HttpsError("invalid-argument", "entryId is required");

  const db = admin.firestore();
  await db.collection("users").doc(uid).collection("continue").doc(entryId).delete();
  return { ok: true };
});

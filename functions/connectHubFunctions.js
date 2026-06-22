/**
 * connectHubFunctions.js
 * AMEN Connect Hub — callable Cloud Functions
 * Handles: getConnectHubFeed
 *
 * getConnectHubFeed
 *   Aggregates the user's hub feed across all their spaces.
 *   Returns batched, priority-sorted items with living-object metadata.
 *   Care-alert items are always surfaced first; Covenant Circle items bypass digest batching.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

const db = getFirestore();

const MAX_SPACES = 30;
const MAX_MESSAGES_PER_SPACE = 15;
const BATCH_WINDOW_HOURS = 12;

// ── getConnectHubFeed ────────────────────────────────────────────────────────

exports.getConnectHubFeed = onCall({ enforceAppCheck: true, region: "us-east1" }, async (request) => {
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { tabFilter = "all", since } = request.data ?? {};

  const batchCutoff = since
    ? new Timestamp(Math.floor(since / 1000), 0)
    : Timestamp.fromDate(new Date(Date.now() - BATCH_WINDOW_HOURS * 60 * 60 * 1000));

  // Fetch user's spaces
  const spacesSnap = await db.collection("spaces")
    .where("memberIds", "array-contains", userId)
    .limit(MAX_SPACES)
    .get();

  if (spacesSnap.empty) return { items: [], caughtUp: true };

  const allItems = [];

  await Promise.all(spacesSnap.docs.map(async (spaceDoc) => {
    const spaceId = spaceDoc.id;
    const spaceData = spaceDoc.data();
    const spaceName = spaceData.name ?? null;

    let query = db.collection("spaces").doc(spaceId).collection("messages")
      .where("createdAt", ">=", batchCutoff);

    if (tabFilter !== "all") {
      query = query.where("kind", "==", tabFilter);
    }

    query = query.orderBy("createdAt", "desc").limit(MAX_MESSAGES_PER_SPACE);

    const msgSnap = await query.get();

    for (const doc of msgSnap.docs) {
      const d = doc.data();
      const isCareAlert = d.isCareAlert === true;
      const isCC = d.isCovenantCircle === true;

      // Digest batching: non-CC, non-care items are only surfaced after the batch window
      // (the client decides presentation; we still return them for completeness)

      const senderId = d.senderId ?? "";
      const displayName = d.senderDisplayName ?? senderId;
      const initials = displayName
        .split(" ")
        .slice(0, 2)
        .map((w) => w[0] ?? "")
        .join("")
        .toUpperCase();

      const actions = isCareAlert
        ? ["pray", "help", "schedule"]
        : isCC
          ? ["pray", "discuss", "schedule"]
          : ["pray", "discuss"];

      allItems.push({
        id: doc.id,
        kind: d.kind ?? "spaceMessage",
        actorId: senderId,
        actorName: displayName,
        actorInitials: initials,
        preview: (d.text ?? "").slice(0, 280),
        spaceName,
        spaceId,
        timestamp: d.createdAt?.toMillis() ?? Date.now(),
        isRead: false,
        actions,
        isCareAlert,
        isCovenantCircle: isCC,
      });
    }
  }));

  // Care alerts first, then CC, then chronological
  allItems.sort((a, b) => {
    if (a.isCareAlert !== b.isCareAlert) return a.isCareAlert ? -1 : 1;
    if (a.isCovenantCircle !== b.isCovenantCircle) return a.isCovenantCircle ? -1 : 1;
    return b.timestamp - a.timestamp;
  });

  const caughtUp = allItems.length === 0 || allItems.every((i) => i.isRead);

  return { items: allItems, caughtUp };
});

/**
 * spacesLivekitFunctions.js
 * AMEN Spaces — LiveKit token generation
 * Handles: getLivekitToken
 *
 * Setup before deploying:
 *   firebase functions:secrets:set LIVEKIT_API_KEY
 *   firebase functions:secrets:set LIVEKIT_API_SECRET
 *   firebase functions:secrets:set LIVEKIT_URL    (e.g. wss://myproject.livekit.cloud)
 *   npm install livekit-server-sdk
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

const db = getFirestore();

// ── getLivekitToken ───────────────────────────────────────────────────────────

exports.getLivekitToken = onCall({ enforceAppCheck: false }, async (request) => {
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, roomId, displayName } = request.data ?? {};
  if (!spaceId || !roomId || !displayName) {
    throw new HttpsError("invalid-argument", "spaceId, roomId, and displayName are required.");
  }

  const apiKey    = process.env.LIVEKIT_API_KEY;
  const apiSecret = process.env.LIVEKIT_API_SECRET;
  const serverURL = process.env.LIVEKIT_URL;

  if (!apiKey || !apiSecret || !serverURL) {
    throw new HttpsError("failed-precondition",
      "LiveKit secrets not configured. Run: firebase functions:secrets:set LIVEKIT_API_KEY / LIVEKIT_API_SECRET / LIVEKIT_URL");
  }

  // Verify caller has an active entitlement for this space
  const entSnap = await db.collection("spaces").doc(spaceId)
    .collection("entitlements").doc(userId).get();

  // Also allow the host to join without a subscriber entitlement
  const spaceSnap = await db.collection("spaces").doc(spaceId).get();
  const isHost = spaceSnap.data()?.hostUserId === userId;

  if (!isHost && (!entSnap.exists || !entSnap.data()?.isActive)) {
    throw new HttpsError("permission-denied", "Active entitlement required to join a live room.");
  }

  // Verify the room exists and is not ended
  const roomSnap = await db.collection("spaces").doc(spaceId)
    .collection("liveRooms").doc(roomId).get();
  if (!roomSnap.exists) throw new HttpsError("not-found", "Live room not found.");
  if (roomSnap.data()?.state === "ended") {
    throw new HttpsError("failed-precondition", "This live room has ended.");
  }

  // Generate LiveKit access token
  const { AccessToken } = require("livekit-server-sdk");
  const at = new AccessToken(apiKey, apiSecret, {
    identity: userId,
    name: displayName,
    ttl: "4h",
  });
  at.addGrant({
    roomJoin: true,
    room: roomId,
    canPublish: true,
    canSubscribe: true,
    canPublishData: true,
  });
  const token = await at.toJwt();

  // Log the join for analytics
  await db.collection("spaces").doc(spaceId)
    .collection("liveRooms").doc(roomId)
    .collection("tokenLog").add({
      userId, displayName,
      issuedAt: FieldValue.serverTimestamp(),
    });

  return { token, url: serverURL };
});

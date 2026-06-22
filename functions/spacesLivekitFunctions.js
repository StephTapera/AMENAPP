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
const { defineSecret } = require("firebase-functions/params");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

const db = getFirestore();

const livekitApiKey    = defineSecret("LIVEKIT_API_KEY");
const livekitApiSecret = defineSecret("LIVEKIT_API_SECRET");
const livekitUrl       = defineSecret("LIVEKIT_URL");

// ── getLivekitToken ───────────────────────────────────────────────────────────

exports.getLivekitToken = onCall(
  { enforceAppCheck: true, secrets: [livekitApiKey, livekitApiSecret, livekitUrl] },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

    const { spaceId, roomId, displayName } = request.data ?? {};
    if (!spaceId || !roomId || !displayName) {
      throw new HttpsError("invalid-argument", "spaceId, roomId, and displayName are required.");
    }

    const [entSnap, spaceSnap, roomSnap] = await Promise.all([
      db.collection("spaces").doc(spaceId).collection("entitlements").doc(userId).get(),
      db.collection("spaces").doc(spaceId).get(),
      db.collection("spaces").doc(spaceId).collection("liveRooms").doc(roomId).get(),
    ]);

    const isHost = spaceSnap.data()?.hostUserId === userId;
    if (!isHost && (!entSnap.exists || !entSnap.data()?.isActive)) {
      throw new HttpsError("permission-denied", "Active entitlement required to join a live room.");
    }
    if (!roomSnap.exists) throw new HttpsError("not-found", "Live room not found.");
    if (roomSnap.data()?.state === "ended") {
      throw new HttpsError("failed-precondition", "This live room has ended.");
    }

    const { AccessToken } = require("livekit-server-sdk");
    const at = new AccessToken(livekitApiKey.value(), livekitApiSecret.value(), {
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

    // Fire-and-forget analytics log — never blocks token delivery
    db.collection("spaces").doc(spaceId)
      .collection("liveRooms").doc(roomId)
      .collection("tokenLog").add({
        userId, displayName,
        issuedAt: FieldValue.serverTimestamp(),
      }).catch(() => {});

    return { token, url: livekitUrl.value() };
  }
);

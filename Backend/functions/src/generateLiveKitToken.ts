// generateLiveKitToken.ts
// AMEN Connect — LiveKit JWT token generator
//
// Creates a short-lived LiveKit access token for a calling authenticated user.
//
// Required secrets (set via Firebase Functions secrets or environment):
//   firebase functions:secrets:set LIVEKIT_API_KEY
//   firebase functions:secrets:set LIVEKIT_API_SECRET
//   firebase functions:secrets:set LIVEKIT_SERVER_URL  (e.g. wss://myproject.livekit.cloud)
//
// Also exported as getLivekitToken (alias) to match the callable name used by
// AmenLivekitLiveRoomProvider.swift in the iOS client.

import * as functions from "firebase-functions";
import * as crypto from "crypto";

// MARK: - generateLiveKitToken

export const generateLiveKitToken = functions.https.onCall(
    async (data: any, context: functions.https.CallableContext) => {
        if (!context.auth) {
            throw new functions.https.HttpsError(
                "unauthenticated",
                "Must be signed in to join a live room."
            );
        }

        const roomId: string | undefined = data?.roomId ?? data?.spaceId;
        const displayName: string =
            data?.displayName ?? context.auth.token?.name ?? context.auth.uid;

        if (!roomId) {
            throw new functions.https.HttpsError(
                "invalid-argument",
                "roomId is required."
            );
        }

        // Resolve credentials — prefer runtime secrets, fall back to legacy config.
        const cfg = functions.config();
        const apiKey: string | undefined =
            process.env.LIVEKIT_API_KEY ?? cfg?.livekit?.api_key;
        const apiSecret: string | undefined =
            process.env.LIVEKIT_API_SECRET ?? cfg?.livekit?.api_secret;
        const serverUrl: string | undefined =
            process.env.LIVEKIT_SERVER_URL ??
            process.env.LIVEKIT_URL ??
            cfg?.livekit?.server_url ??
            cfg?.livekit?.url;

        if (!apiKey || !apiSecret || !serverUrl) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                "LiveKit credentials are not configured. " +
                    "Set LIVEKIT_API_KEY, LIVEKIT_API_SECRET, and LIVEKIT_SERVER_URL " +
                    "as Firebase Functions secrets."
            );
        }

        // Build a signed LiveKit JWT.
        // Spec: https://docs.livekit.io/reference/server-apis/#creating-tokens
        const now = Math.floor(Date.now() / 1000);
        const expiry = now + 7200; // 2-hour TTL

        const header = Buffer.from(
            JSON.stringify({ alg: "HS256", typ: "JWT" })
        ).toString("base64url");

        const claims = {
            iss: apiKey,
            sub: context.auth.uid,
            iat: now,
            exp: expiry,
            name: displayName,
            video: {
                roomJoin: true,
                room: roomId,
                canPublish: true,
                canSubscribe: true,
            },
        };

        const payload = Buffer.from(JSON.stringify(claims)).toString("base64url");

        const sig = crypto
            .createHmac("sha256", apiSecret)
            .update(`${header}.${payload}`)
            .digest("base64url");

        const token = `${header}.${payload}.${sig}`;

        return {
            token,
            // Return both key names so both versions of the iOS client work:
            //   AmenLivekitLiveRoomProvider expects "url"
            //   AmenLiveKitRoomProvider expects "serverUrl"
            url: serverUrl,
            serverUrl,
        };
    }
);

// Alias used by AmenLivekitLiveRoomProvider.swift (calls "getLivekitToken").
export const getLivekitToken = generateLiveKitToken;

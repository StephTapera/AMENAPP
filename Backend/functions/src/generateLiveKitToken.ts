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
//
// Migrated from Gen-1 to Gen-2 (onCall from firebase-functions/v2/https) to resolve
// the "Cannot set CPU on Gen-1 function" error blocking Backend codebase deploys.

import * as crypto from "crypto";
import { defineSecret } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const livekitApiKey    = defineSecret("LIVEKIT_API_KEY");
const livekitApiSecret = defineSecret("LIVEKIT_API_SECRET");
const livekitServerUrl = defineSecret("LIVEKIT_SERVER_URL");

export const generateLiveKitToken = onCall(
    {
        enforceAppCheck: false, // LiveKit join does not require App Check
        secrets: [livekitApiKey, livekitApiSecret, livekitServerUrl],
    },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Must be signed in to join a live room.");
        }

        const data = request.data as Record<string, unknown>;
        const roomId: string | undefined = (data?.roomId ?? data?.spaceId) as string | undefined;
        const displayName: string =
            (data?.displayName as string) ??
            request.auth.token?.name ??
            request.auth.uid;

        if (!roomId) {
            throw new HttpsError("invalid-argument", "roomId is required.");
        }

        const apiKey    = livekitApiKey.value();
        const apiSecret = livekitApiSecret.value();
        const serverUrl = livekitServerUrl.value();

        if (!apiKey || !apiSecret || !serverUrl) {
            throw new HttpsError(
                "failed-precondition",
                "LiveKit credentials are not configured. " +
                    "Set LIVEKIT_API_KEY, LIVEKIT_API_SECRET, and LIVEKIT_SERVER_URL " +
                    "as Firebase Functions secrets."
            );
        }

        // Build a signed LiveKit JWT.
        // Spec: https://docs.livekit.io/reference/server-apis/#creating-tokens
        const now    = Math.floor(Date.now() / 1000);
        const expiry = now + 7200; // 2-hour TTL

        const header = Buffer.from(
            JSON.stringify({ alg: "HS256", typ: "JWT" })
        ).toString("base64url");

        const claims = {
            iss: apiKey,
            sub: request.auth.uid,
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

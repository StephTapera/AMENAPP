/**
 * ingestion/providers/spotifyProvider.ts
 *
 * Spotify Web API adapter for the Catalog Ingestion Engine.
 *
 * SECURITY RULES:
 *  - Only uses official Spotify Web API endpoints (api.spotify.com/v1)
 *  - NEVER scrapes Spotify HTML pages
 *  - Requires SPOTIFY_CLIENT_ID + SPOTIFY_CLIENT_SECRET (human-provisioned secrets)
 *  - OAuth PKCE flow — creatorId maps to stored token in Firestore
 *  - All ingested items default to reviewState='imported', visibility='private'
 */

import * as admin from "firebase-admin";
import { defineSecret } from "firebase-functions/params";
import type { AuthResult, RawItem, SourceProvider, Work, WorkType } from "./types";

export const SPOTIFY_CLIENT_ID = defineSecret("SPOTIFY_CLIENT_ID");
export const SPOTIFY_CLIENT_SECRET = defineSecret("SPOTIFY_CLIENT_SECRET");

const SPOTIFY_API_BASE = "https://api.spotify.com/v1";
const SPOTIFY_TOKEN_URL = "https://accounts.spotify.com/api/token";

// ─── Token Store (Firestore) ────────────────────────────────────────────────

interface SpotifyTokenRecord {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
  spotifyUserId: string;
}

async function loadToken(creatorId: string): Promise<SpotifyTokenRecord | null> {
  const db = admin.firestore();
  const snap = await db
    .collection("creatorSourceTokens")
    .doc(`${creatorId}_spotify`)
    .get();
  if (!snap.exists) return null;
  return snap.data() as SpotifyTokenRecord;
}

async function saveToken(creatorId: string, record: SpotifyTokenRecord): Promise<void> {
  const db = admin.firestore();
  await db
    .collection("creatorSourceTokens")
    .doc(`${creatorId}_spotify`)
    .set(record, { merge: true });
}

async function refreshAccessToken(refreshToken: string): Promise<{ accessToken: string; expiresAt: number } | null> {
  const clientId = SPOTIFY_CLIENT_ID.value();
  const clientSecret = SPOTIFY_CLIENT_SECRET.value();
  if (!clientId || !clientSecret) return null;

  const credentials = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");
  const response = await fetch(SPOTIFY_TOKEN_URL, {
    method: "POST",
    headers: {
      "Authorization": `Basic ${credentials}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: refreshToken,
    }),
    signal: AbortSignal.timeout(10_000),
  });

  if (!response.ok) return null;

  const data = (await response.json()) as { access_token?: string; expires_in?: number };
  if (!data.access_token) return null;

  return {
    accessToken: data.access_token,
    expiresAt: Date.now() + (data.expires_in ?? 3600) * 1000,
  };
}

async function getValidToken(creatorId: string): Promise<string | null> {
  const record = await loadToken(creatorId);
  if (!record) return null;

  if (Date.now() < record.expiresAt - 60_000) {
    // Token still valid (with 60s buffer)
    return record.accessToken;
  }

  // Refresh
  const refreshed = await refreshAccessToken(record.refreshToken);
  if (!refreshed) return null;

  await saveToken(creatorId, { ...record, ...refreshed });
  return refreshed.accessToken;
}

// ─── Normalize Spotify track → Work ────────────────────────────────────────

function normalizeTrack(creatorId: string, raw: Record<string, unknown>, externalId: string): Work {
  const now = admin.firestore.Timestamp.now();
  const type: WorkType = (raw["type"] as string) === "album" ? "album" : "track";
  const album = raw["album"] as Record<string, unknown> | undefined;
  const images = (album?.["images"] as Array<{ url: string }> | undefined) ?? [];
  const artists = (raw["artists"] as Array<{ name: string }> | undefined) ?? [];
  const externalUrls = (raw["external_urls"] as Record<string, string> | undefined) ?? {};
  const durationMs = raw["duration_ms"] as number | undefined;
  const releaseDate = album?.["release_date"] as string | undefined;

  const topics: string[] = [];
  if (artists.length > 0) topics.push(...artists.map((a) => a.name));

  return {
    creatorId,
    type,
    title: (raw["name"] as string) ?? "Untitled",
    subtitle: artists.map((a) => a.name).join(", ") || undefined,
    description: durationMs
      ? `Duration: ${Math.round(durationMs / 60000)} min`
      : undefined,
    coverUrl: images[0]?.url,
    publishedAt: releaseDate
      ? admin.firestore.Timestamp.fromDate(new Date(releaseDate))
      : null,
    links: [
      {
        kind: "stream",
        platform: "Spotify",
        url: externalUrls["spotify"] ?? `https://open.spotify.com/track/${externalId}`,
      },
    ],
    topics,
    visibility: "private",
    reviewState: "imported",
    verifiedOwnership: false,
    ingestMode: "auto",
    sourceProviderId: "spotify",
    externalId,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    ageTierRestriction: "all",
  };
}

// ─── SpotifyProvider ────────────────────────────────────────────────────────

export const spotifyProvider: SourceProvider = {
  id: "spotify",
  supportsSync: true,

  async authorize(creatorId: string, oauthToken?: string): Promise<AuthResult> {
    if (!oauthToken) {
      return { success: false, error: "oauth_token_required" };
    }

    const clientId = SPOTIFY_CLIENT_ID.value();
    const clientSecret = SPOTIFY_CLIENT_SECRET.value();

    if (!clientId || !clientSecret) {
      return { success: false, error: "spotify_credentials_not_configured" };
    }

    // Exchange authorization code for tokens
    const credentials = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");
    try {
      const response = await fetch(SPOTIFY_TOKEN_URL, {
        method: "POST",
        headers: {
          "Authorization": `Basic ${credentials}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: new URLSearchParams({
          grant_type: "authorization_code",
          code: oauthToken,
          redirect_uri: `https://amen-5e359.web.app/auth/spotify/callback`,
        }),
        signal: AbortSignal.timeout(10_000),
      });

      if (!response.ok) {
        return { success: false, error: "spotify_token_exchange_failed" };
      }

      const data = (await response.json()) as {
        access_token?: string;
        refresh_token?: string;
        expires_in?: number;
      };

      if (!data.access_token || !data.refresh_token) {
        return { success: false, error: "spotify_token_missing" };
      }

      // Verify ownership: get the authenticated user's Spotify profile
      const profileResponse = await fetch(`${SPOTIFY_API_BASE}/me`, {
        headers: { "Authorization": `Bearer ${data.access_token}` },
        signal: AbortSignal.timeout(8_000),
      });

      if (!profileResponse.ok) {
        return { success: false, error: "spotify_profile_fetch_failed" };
      }

      const profile = (await profileResponse.json()) as { id?: string };
      const spotifyUserId = profile.id ?? "";

      const expiresAt = Date.now() + (data.expires_in ?? 3600) * 1000;
      await saveToken(creatorId, {
        accessToken: data.access_token,
        refreshToken: data.refresh_token,
        expiresAt,
        spotifyUserId,
      });

      return {
        success: true,
        accessToken: data.access_token,
        refreshToken: data.refresh_token,
        expiresAt,
      };
    } catch {
      return { success: false, error: "spotify_authorize_network_error" };
    }
  },

  async fetch(creatorId: string, cursor?: string): Promise<{ items: RawItem[]; nextCursor?: string }> {
    const accessToken = await getValidToken(creatorId);
    if (!accessToken) {
      return { items: [] };
    }

    const limit = 50;
    const offset = cursor ? parseInt(cursor, 10) : 0;

    try {
      // Fetch the user's saved tracks — official Spotify Web API, no scraping
      const response = await fetch(
        `${SPOTIFY_API_BASE}/me/tracks?limit=${limit}&offset=${offset}`,
        {
          headers: { "Authorization": `Bearer ${accessToken}` },
          signal: AbortSignal.timeout(12_000),
        }
      );

      if (!response.ok) {
        return { items: [] };
      }

      const data = (await response.json()) as {
        items?: Array<{ track?: Record<string, unknown> }>;
        next?: string | null;
        total?: number;
      };

      const items: RawItem[] = (data.items ?? [])
        .filter((item) => item.track !== null && item.track !== undefined)
        .map((item) => ({
          externalId: (item.track!["id"] as string) ?? "",
          rawData: item.track!,
        }))
        .filter((item) => item.externalId !== "");

      const nextOffset = offset + items.length;
      const hasMore = data.next !== null && data.next !== undefined;

      return {
        items,
        nextCursor: hasMore ? String(nextOffset) : undefined,
      };
    } catch {
      return { items: [] };
    }
  },

  normalize(creatorId: string, item: RawItem): Work {
    return normalizeTrack(creatorId, item.rawData, item.externalId);
  },
};

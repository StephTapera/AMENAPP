/**
 * ingestion/providers/appleMusicProvider.ts
 *
 * Apple Music API (MusicKit) adapter for the Catalog Ingestion Engine.
 *
 * HUMAN GATE: APPLE_MUSIC_DEVELOPER_TOKEN secret must be provisioned before this
 * provider is usable. Until that secret exists, authorize() returns an error.
 *
 * SECURITY RULES:
 *  - Only uses official Apple Music API (api.music.apple.com)
 *  - NEVER scrapes Apple Music HTML
 *  - Developer token (JWT signed with Apple's algorithm) required
 *  - All ingested items default to reviewState='imported', visibility='private'
 */

import * as admin from "firebase-admin";
import { defineSecret } from "firebase-functions/params";
import type { AuthResult, RawItem, SourceProvider, Work } from "./types";

export const APPLE_MUSIC_DEVELOPER_TOKEN = defineSecret("APPLE_MUSIC_DEVELOPER_TOKEN");

const APPLE_MUSIC_API_BASE = "https://api.music.apple.com/v1";

// ─── Token Store (Firestore) ────────────────────────────────────────────────

interface AppleMusicTokenRecord {
  musicUserToken: string;
  storefrontId: string;
}

async function loadToken(creatorId: string): Promise<AppleMusicTokenRecord | null> {
  const db = admin.firestore();
  const snap = await db
    .collection("creatorSourceTokens")
    .doc(`${creatorId}_apple_music`)
    .get();
  if (!snap.exists) return null;
  return snap.data() as AppleMusicTokenRecord;
}

async function saveToken(creatorId: string, record: AppleMusicTokenRecord): Promise<void> {
  const db = admin.firestore();
  await db
    .collection("creatorSourceTokens")
    .doc(`${creatorId}_apple_music`)
    .set(record, { merge: true });
}

// ─── Normalize Apple Music track → Work ────────────────────────────────────

function normalizeAppleTrack(creatorId: string, item: RawItem): Work {
  const now = admin.firestore.Timestamp.now();
  const attrs = (item.rawData["attributes"] as Record<string, unknown>) ?? {};
  const artwork = (attrs["artwork"] as Record<string, unknown>) ?? {};

  const artworkWidth = (artwork["width"] as number) ?? 500;
  const artworkHeight = (artwork["height"] as number) ?? 500;
  const artworkUrl = artwork["url"] as string | undefined;
  const coverUrl = artworkUrl
    ? artworkUrl
        .replace("{w}", String(artworkWidth))
        .replace("{h}", String(artworkHeight))
    : undefined;

  const releaseDate = attrs["releaseDate"] as string | undefined;
  const genreNames = (attrs["genreNames"] as string[]) ?? [];

  return {
    creatorId,
    type: "track",
    title: (attrs["name"] as string) ?? "Untitled",
    subtitle: (attrs["artistName"] as string) ?? undefined,
    description: (attrs["editorialNotes"] as Record<string, string> | undefined)?.["standard"]?.slice(0, 500),
    coverUrl,
    publishedAt: releaseDate
      ? admin.firestore.Timestamp.fromDate(new Date(releaseDate))
      : null,
    links: [
      {
        kind: "stream",
        platform: "Apple Music",
        url: (attrs["url"] as string) ?? `https://music.apple.com`,
      },
    ],
    topics: genreNames.slice(0, 5),
    visibility: "private",
    reviewState: "imported",
    verifiedOwnership: false,
    ingestMode: "auto",
    sourceProviderId: "apple_music",
    externalId: item.externalId,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    ageTierRestriction: "all",
  };
}

// ─── AppleMusicProvider ─────────────────────────────────────────────────────

export const appleMusicProvider: SourceProvider = {
  id: "apple_music",
  supportsSync: false, // Requires Music User Token which is session-bound

  async authorize(creatorId: string, oauthToken?: string): Promise<AuthResult> {
    const developerToken = APPLE_MUSIC_DEVELOPER_TOKEN.value();

    if (!developerToken) {
      // HUMAN GATE: secret not yet provisioned
      return {
        success: false,
        error: "apple_music_developer_token_not_configured_human_gate_required",
      };
    }

    if (!oauthToken) {
      return { success: false, error: "music_user_token_required" };
    }

    // The oauthToken here is the Music User Token obtained via MusicKit JS on the client
    // Validate by making a lightweight API call
    try {
      const response = await fetch(`${APPLE_MUSIC_API_BASE}/me/storefront`, {
        headers: {
          "Authorization": `Bearer ${developerToken}`,
          "Music-User-Token": oauthToken,
        },
        signal: AbortSignal.timeout(8_000),
      });

      if (!response.ok) {
        return { success: false, error: "apple_music_token_validation_failed" };
      }

      const data = (await response.json()) as {
        data?: Array<{ id?: string }>;
      };

      const storefrontId = data.data?.[0]?.id ?? "us";

      await saveToken(creatorId, {
        musicUserToken: oauthToken,
        storefrontId,
      });

      return { success: true };
    } catch {
      return { success: false, error: "apple_music_authorize_network_error" };
    }
  },

  async fetch(creatorId: string, cursor?: string): Promise<{ items: RawItem[]; nextCursor?: string }> {
    const developerToken = APPLE_MUSIC_DEVELOPER_TOKEN.value();
    if (!developerToken) return { items: [] };

    const tokenRecord = await loadToken(creatorId);
    if (!tokenRecord) return { items: [] };

    const { musicUserToken, storefrontId } = tokenRecord;

    try {
      const offset = cursor ?? "0";
      const response = await fetch(
        `${APPLE_MUSIC_API_BASE}/me/library/songs?limit=100&offset=${offset}`,
        {
          headers: {
            "Authorization": `Bearer ${developerToken}`,
            "Music-User-Token": musicUserToken,
          },
          signal: AbortSignal.timeout(12_000),
        }
      );

      if (!response.ok) return { items: [] };

      const data = (await response.json()) as {
        data?: Array<Record<string, unknown>>;
        next?: string;
      };

      const items: RawItem[] = (data.data ?? []).map((song) => ({
        externalId: song["id"] as string,
        rawData: { ...song, storefrontId },
      }));

      // Parse next offset from the next URL if present
      let nextCursor: string | undefined;
      if (data.next) {
        const match = /offset=(\d+)/.exec(data.next);
        if (match) nextCursor = match[1];
      }

      return { items, nextCursor };
    } catch {
      return { items: [] };
    }
  },

  normalize(creatorId: string, item: RawItem): Work {
    return normalizeAppleTrack(creatorId, item);
  },
};

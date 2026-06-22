import * as admin from "firebase-admin";
import { defineSecret } from "firebase-functions/params";
import type { AuthResult, RawItem, SourceProvider, Work } from "./types";

export const YOUTUBE_API_KEY = defineSecret("YOUTUBE_API_KEY");
export const YOUTUBE_CLIENT_ID = defineSecret("YOUTUBE_CLIENT_ID");
export const YOUTUBE_CLIENT_SECRET = defineSecret("YOUTUBE_CLIENT_SECRET");

function normalizeYouTubeVideo(creatorId: string, item: RawItem): Work {
  const now = admin.firestore.Timestamp.now();
  const snippet = (item.rawData.snippet as Record<string, unknown>) ?? {};
  const thumbnails = (snippet.thumbnails as Record<string, { url?: string }> | undefined) ?? {};
  return {
    creatorId,
    type: "video",
    title: (snippet.title as string) ?? "Untitled video",
    description: (snippet.description as string | undefined)?.slice(0, 500),
    coverUrl: thumbnails.high?.url ?? thumbnails.default?.url,
    publishedAt: snippet.publishedAt
      ? admin.firestore.Timestamp.fromDate(new Date(snippet.publishedAt as string))
      : null,
    links: [{ kind: "watch", platform: "YouTube", url: `https://www.youtube.com/watch?v=${item.externalId}` }],
    topics: [],
    visibility: "private",
    reviewState: "imported",
    verifiedOwnership: false,
    ingestMode: "auto",
    sourceProviderId: "youtube",
    externalId: item.externalId,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    ageTierRestriction: "all",
  };
}

export const youtubeProvider: SourceProvider = {
  id: "youtube",
  supportsSync: true,

  async authorize(_creatorId: string, oauthToken?: string): Promise<AuthResult> {
    if (!oauthToken) return { success: false, error: "oauth_token_required" };
    if (!YOUTUBE_CLIENT_ID.value() || !YOUTUBE_CLIENT_SECRET.value()) {
      return { success: false, error: "youtube_oauth_not_configured" };
    }
    return { success: true, accessToken: oauthToken };
  },

  async fetch(_creatorId: string): Promise<{ items: RawItem[]; nextCursor?: string }> {
    if (!YOUTUBE_API_KEY.value()) return { items: [] };
    return { items: [] };
  },

  normalize: normalizeYouTubeVideo,
};

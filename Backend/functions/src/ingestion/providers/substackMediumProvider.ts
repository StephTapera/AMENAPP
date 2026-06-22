import * as admin from "firebase-admin";
import type { AuthResult, RawItem, SourceProvider, Work } from "./types";

function normalizeArticle(
  creatorId: string,
  item: RawItem,
  providerId: "substack" | "medium",
  platform: string
): Work {
  const now = admin.firestore.Timestamp.now();
  const url = (item.rawData.url as string) ?? "";
  return {
    creatorId,
    type: "article",
    title: (item.rawData.title as string) ?? "Untitled article",
    subtitle: (item.rawData.author as string) ?? undefined,
    description: (item.rawData.summary as string | undefined)?.slice(0, 500),
    coverUrl: item.rawData.coverUrl as string | undefined,
    publishedAt: item.rawData.publishedAt
      ? admin.firestore.Timestamp.fromDate(new Date(item.rawData.publishedAt as string))
      : null,
    links: url ? [{ kind: "read", platform, url }] : [],
    topics: Array.isArray(item.rawData.tags) ? (item.rawData.tags as string[]).slice(0, 5) : [],
    visibility: "private",
    reviewState: "imported",
    verifiedOwnership: false,
    ingestMode: "auto",
    sourceProviderId: providerId,
    externalId: item.externalId,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    ageTierRestriction: "all",
  };
}

export const substackProvider: SourceProvider = {
  id: "substack",
  supportsSync: true,
  async authorize(_creatorId: string, feedUrl?: string): Promise<AuthResult> {
    return feedUrl ? { success: true, accessToken: feedUrl } : { success: false, error: "feed_url_required" };
  },
  async fetch(): Promise<{ items: RawItem[]; nextCursor?: string }> {
    return { items: [] };
  },
  normalize: (creatorId, item) => normalizeArticle(creatorId, item, "substack", "Substack"),
};

export const mediumProvider: SourceProvider = {
  id: "medium",
  supportsSync: true,
  async authorize(_creatorId: string, feedUrl?: string): Promise<AuthResult> {
    return feedUrl ? { success: true, accessToken: feedUrl } : { success: false, error: "feed_url_required" };
  },
  async fetch(): Promise<{ items: RawItem[]; nextCursor?: string }> {
    return { items: [] };
  },
  normalize: (creatorId, item) => normalizeArticle(creatorId, item, "medium", "Medium"),
};

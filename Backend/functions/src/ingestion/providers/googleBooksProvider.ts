import * as admin from "firebase-admin";
import { defineSecret } from "firebase-functions/params";
import type { AuthResult, RawItem, SourceProvider, Work, WorkLink } from "./types";

export const GOOGLE_BOOKS_API_KEY = defineSecret("GOOGLE_BOOKS_API_KEY");

function normalizeBook(
  creatorId: string,
  item: RawItem,
  providerId: "google_books" | "open_library",
  platform: string
): Work {
  const now = admin.firestore.Timestamp.now();
  const volume = (item.rawData.volumeInfo as Record<string, unknown>) ?? item.rawData;
  const imageLinks = (volume.imageLinks as Record<string, string> | undefined) ?? {};
  const authors = (volume.authors as string[] | undefined) ?? [];
  const categories = (volume.categories as string[] | undefined) ?? [];
  const links: WorkLink[] = volume.infoLink
    ? [{ kind: "read", platform, url: volume.infoLink as string }]
    : [];
  return {
    creatorId,
    type: "book",
    title: (volume.title as string) ?? "Untitled book",
    subtitle: authors.join(", ") || undefined,
    description: (volume.description as string | undefined)?.slice(0, 500),
    coverUrl: imageLinks.thumbnail ?? imageLinks.smallThumbnail,
    publishedAt: volume.publishedDate
      ? admin.firestore.Timestamp.fromDate(new Date(volume.publishedDate as string))
      : null,
    links,
    topics: categories.slice(0, 5),
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

export const googleBooksProvider: SourceProvider = {
  id: "google_books",
  supportsSync: false,
  async authorize(): Promise<AuthResult> {
    return GOOGLE_BOOKS_API_KEY.value()
      ? { success: true }
      : { success: false, error: "google_books_api_key_not_configured" };
  },
  async fetch(): Promise<{ items: RawItem[]; nextCursor?: string }> {
    return { items: [] };
  },
  normalize: (creatorId, item) => normalizeBook(creatorId, item, "google_books", "Google Books"),
};

export const openLibraryProvider: SourceProvider = {
  id: "open_library",
  supportsSync: false,
  async authorize(): Promise<AuthResult> {
    return { success: true };
  },
  async fetch(): Promise<{ items: RawItem[]; nextCursor?: string }> {
    return { items: [] };
  },
  normalize: (creatorId, item) => normalizeBook(creatorId, item, "open_library", "Open Library"),
};

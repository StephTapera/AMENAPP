/**
 * ingestion/providers/types.ts
 *
 * Shared interfaces for all SourceProvider adapters.
 * Every provider MUST implement SourceProvider — never scrape HTML.
 * Only official APIs, OAuth flows, or open-license RSS/Atom feeds are permitted.
 */

// ─── Work types mirrored from CatalogModels.swift ──────────────────────────

export type WorkType =
  | "book"
  | "album"
  | "track"
  | "podcast"
  | "episode"
  | "video"
  | "sermon"
  | "article"
  | "course"
  | "event";

export type WorkVisibility = "public" | "followers" | "paid_members" | "organization" | "private";

export type WorkReviewState = "imported" | "draft" | "review" | "approved" | "published";

export interface WorkLink {
  kind: "stream" | "read" | "watch" | "buy" | "affiliate";
  platform: string;
  url: string;
  affiliateUrl?: string;
}

/**
 * Normalized Work shape written to Firestore /works/{workId}.
 * All ingested works MUST default to:
 *   reviewState = 'imported'
 *   visibility  = 'private'
 *   ingestMode  = 'auto'
 */
export interface Work {
  id?: string;
  creatorId: string;
  type: WorkType;
  title: string;
  subtitle?: string;
  description?: string;
  coverUrl?: string;
  publishedAt?: FirebaseFirestore.Timestamp | null;
  links: WorkLink[];
  topics: string[];
  visibility: WorkVisibility;
  reviewState: WorkReviewState;
  verifiedOwnership: boolean;
  ingestMode: "auto" | "manual";
  sourceProviderId?: string;
  externalId?: string;
  createdAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
  deletedAt?: FirebaseFirestore.Timestamp | null;
  ageTierRestriction?: "all" | "teen" | "adult";
}

// ─── Raw item returned by a provider's fetch() ─────────────────────────────

export interface RawItem {
  externalId: string;
  rawData: Record<string, unknown>;
}

// ─── OAuth / API-key result ─────────────────────────────────────────────────

export interface AuthResult {
  success: boolean;
  accessToken?: string;
  refreshToken?: string;
  expiresAt?: number;
  error?: string;
}

// ─── Provider interface ─────────────────────────────────────────────────────

export interface SourceProvider {
  /** Unique provider identifier */
  id:
    | "spotify"
    | "youtube"
    | "apple_music"
    | "google_books"
    | "open_library"
    | "podcast_rss"
    | "substack"
    | "medium";

  /**
   * Authorize a creator account with this provider.
   * For OAuth providers: exchanges code or refreshes tokens.
   * For API-key providers: validates ownership proof.
   */
  authorize(creatorId: string, oauthToken?: string): Promise<AuthResult>;

  /**
   * Fetch raw items from the official API or feed.
   * NEVER scrapes HTML.
   * @param cursor Pagination cursor from previous fetch (undefined = first page).
   */
  fetch(creatorId: string, cursor?: string): Promise<{ items: RawItem[]; nextCursor?: string }>;

  /**
   * Normalize a raw API item into a Work.
   * Always sets reviewState='imported', visibility='private', ingestMode='auto'.
   */
  normalize(creatorId: string, item: RawItem): Work;

  /** Whether this provider supports continuous background sync. */
  supportsSync: boolean;
}

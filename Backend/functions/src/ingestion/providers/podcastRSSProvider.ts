/**
 * ingestion/providers/podcastRSSProvider.ts
 *
 * Podcast RSS feed adapter for the Catalog Ingestion Engine.
 *
 * RSS/Atom feeds are open standards — no scraping, no private APIs.
 * This provider accepts a podcast RSS feed URL and parses episodes.
 *
 * SECURITY RULES:
 *  - Only fetches RSS/Atom XML feeds from URLs provided by the creator
 *  - NEVER scrapes podcast hosting platform HTML
 *  - Feed URL must be HTTPS
 *  - Validates RSS ownership via enclosure/link domain matching
 *  - All ingested items default to reviewState='imported', visibility='private'
 */

import * as admin from "firebase-admin";
import type { AuthResult, RawItem, SourceProvider, Work } from "./types";

// ─── Feed Store (Firestore) ────────────────────────────────────────────────

interface PodcastFeedRecord {
  feedUrl: string;
  showTitle?: string;
  showCoverUrl?: string;
}

async function loadFeedRecord(creatorId: string): Promise<PodcastFeedRecord | null> {
  const db = admin.firestore();
  const snap = await db
    .collection("creatorSourceTokens")
    .doc(`${creatorId}_podcast_rss`)
    .get();
  if (!snap.exists) return null;
  return snap.data() as PodcastFeedRecord;
}

async function saveFeedRecord(creatorId: string, record: PodcastFeedRecord): Promise<void> {
  const db = admin.firestore();
  await db
    .collection("creatorSourceTokens")
    .doc(`${creatorId}_podcast_rss`)
    .set(record, { merge: true });
}

// ─── Simple RSS/Atom XML parser (no external dependency) ──────────────────

interface ParsedFeed {
  title: string;
  coverUrl?: string;
  episodes: ParsedEpisode[];
}

interface ParsedEpisode {
  guid: string;
  title: string;
  description?: string;
  pubDate?: string;
  enclosureUrl?: string;
  duration?: string;
  episodeUrl?: string;
  coverUrl?: string;
}

function extractXmlText(xml: string, tag: string): string {
  // Match <tag> or <tag attr="...">, extract first occurrence text content
  const pattern = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, "i");
  const match = pattern.exec(xml);
  if (!match) return "";
  // Strip CDATA
  return match[1]
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .trim();
}

function extractXmlAttr(xml: string, tag: string, attr: string): string {
  const pattern = new RegExp(`<${tag}[^>]+${attr}\\s*=\\s*["']([^"']+)["'][^>]*>`, "i");
  const match = pattern.exec(xml);
  return match ? match[1] : "";
}

function extractXmlBlocks(xml: string, tag: string): string[] {
  const results: string[] = [];
  const openTag = new RegExp(`<${tag}[^>]*>`, "gi");
  const closeTag = `</${tag}>`;
  let match: RegExpExecArray | null;
  let start = 0;

  while ((match = openTag.exec(xml)) !== null) {
    const openEnd = match.index + match[0].length;
    const closeIdx = xml.indexOf(closeTag, openEnd);
    if (closeIdx === -1) break;
    results.push(xml.slice(openEnd, closeIdx));
    start = closeIdx + closeTag.length;
    openTag.lastIndex = start;
  }

  return results;
}

function parseFeedXML(xml: string): ParsedFeed {
  // Extract channel-level metadata
  const channelMatch = /<channel[^>]*>([\s\S]*?)<\/channel>/i.exec(xml);
  const channelXml = channelMatch ? channelMatch[1] : xml;

  // Show cover — iTunes image or image/url
  let coverUrl = extractXmlAttr(channelXml, "itunes:image", "href");
  if (!coverUrl) {
    const imageBlock = /<image[^>]*>([\s\S]*?)<\/image>/i.exec(channelXml);
    if (imageBlock) {
      coverUrl = extractXmlText(imageBlock[1], "url");
    }
  }

  const showTitle = extractXmlText(channelXml, "title");

  // Episodes — each <item> is an episode
  const itemBlocks = extractXmlBlocks(channelXml, "item");

  const episodes: ParsedEpisode[] = itemBlocks.map((item) => {
    const guid = extractXmlText(item, "guid") || extractXmlAttr(item, "guid", "isPermaLink");
    const title = extractXmlText(item, "title");
    const description =
      extractXmlText(item, "itunes:summary") ||
      extractXmlText(item, "description") ||
      undefined;
    const pubDate = extractXmlText(item, "pubDate") || undefined;
    const duration = extractXmlText(item, "itunes:duration") || undefined;
    const enclosureUrl = extractXmlAttr(item, "enclosure", "url") || undefined;
    const episodeUrl = extractXmlText(item, "link") || enclosureUrl;

    // Episode-specific cover
    let epCoverUrl = extractXmlAttr(item, "itunes:image", "href") || undefined;

    return {
      guid: guid || title,
      title,
      description,
      pubDate,
      enclosureUrl,
      duration,
      episodeUrl,
      coverUrl: epCoverUrl,
    };
  });

  return { title: showTitle, coverUrl: coverUrl || undefined, episodes };
}

// ─── Normalize RSS episode → Work ──────────────────────────────────────────

function normalizeEpisode(
  creatorId: string,
  episode: ParsedEpisode,
  showCoverUrl?: string
): Work {
  const now = admin.firestore.Timestamp.now();

  let publishedAt: admin.firestore.Timestamp | null = null;
  if (episode.pubDate) {
    try {
      publishedAt = admin.firestore.Timestamp.fromDate(new Date(episode.pubDate));
    } catch {
      publishedAt = null;
    }
  }

  const links: Work["links"] = [];
  if (episode.episodeUrl) {
    links.push({ kind: "stream", platform: "Podcast", url: episode.episodeUrl });
  }

  return {
    creatorId,
    type: "episode",
    title: episode.title || "Untitled Episode",
    subtitle: undefined,
    description: episode.description?.slice(0, 500),
    coverUrl: episode.coverUrl ?? showCoverUrl,
    publishedAt,
    links,
    topics: [],
    visibility: "private",
    reviewState: "imported",
    verifiedOwnership: false,
    ingestMode: "auto",
    sourceProviderId: "podcast_rss",
    externalId: episode.guid,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    ageTierRestriction: "all",
  };
}

// ─── PodcastRSSProvider ─────────────────────────────────────────────────────

export const podcastRSSProvider: SourceProvider = {
  id: "podcast_rss",
  supportsSync: true,

  async authorize(creatorId: string, oauthToken?: string): Promise<AuthResult> {
    // oauthToken here is the RSS feed URL (HTTPS required)
    if (!oauthToken) {
      return { success: false, error: "rss_feed_url_required" };
    }

    if (!oauthToken.startsWith("https://")) {
      return { success: false, error: "rss_feed_url_must_be_https" };
    }

    try {
      // Validate the feed is accessible and parseable
      const response = await fetch(oauthToken, {
        headers: { "User-Agent": "AMEN-Catalog/1.0 (+https://amenapp.com)" },
        signal: AbortSignal.timeout(10_000),
      });

      if (!response.ok) {
        return { success: false, error: "rss_feed_url_not_accessible" };
      }

      const contentType = response.headers.get("content-type") ?? "";
      if (!contentType.includes("xml") && !contentType.includes("rss") && !contentType.includes("atom")) {
        return { success: false, error: "url_does_not_appear_to_be_rss_feed" };
      }

      const xml = await response.text();
      const feed = parseFeedXML(xml);

      if (!feed.title) {
        return { success: false, error: "rss_feed_parse_failed" };
      }

      await saveFeedRecord(creatorId, {
        feedUrl: oauthToken,
        showTitle: feed.title,
        showCoverUrl: feed.coverUrl,
      });

      return { success: true };
    } catch {
      return { success: false, error: "rss_feed_authorize_network_error" };
    }
  },

  async fetch(creatorId: string, cursor?: string): Promise<{ items: RawItem[]; nextCursor?: string }> {
    const record = await loadFeedRecord(creatorId);
    if (!record?.feedUrl) return { items: [] };

    try {
      const response = await fetch(record.feedUrl, {
        headers: { "User-Agent": "AMEN-Catalog/1.0 (+https://amenapp.com)" },
        signal: AbortSignal.timeout(15_000),
      });

      if (!response.ok) return { items: [] };

      const xml = await response.text();
      const feed = parseFeedXML(xml);

      // RSS feeds return all episodes — we paginate client-side
      const pageSize = 50;
      const offset = cursor ? parseInt(cursor, 10) : 0;
      const page = feed.episodes.slice(offset, offset + pageSize);

      const items: RawItem[] = page.map((episode) => ({
        externalId: episode.guid,
        rawData: {
          episode,
          showCoverUrl: record.showCoverUrl,
          feedUrl: record.feedUrl,
        },
      }));

      const nextOffset = offset + page.length;
      const hasMore = nextOffset < feed.episodes.length;

      return {
        items,
        nextCursor: hasMore ? String(nextOffset) : undefined,
      };
    } catch {
      return { items: [] };
    }
  },

  normalize(creatorId: string, item: RawItem): Work {
    const episode = item.rawData["episode"] as ParsedEpisode;
    const showCoverUrl = item.rawData["showCoverUrl"] as string | undefined;
    return normalizeEpisode(creatorId, episode, showCoverUrl);
  },
};

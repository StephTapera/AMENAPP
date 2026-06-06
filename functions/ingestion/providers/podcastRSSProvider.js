/**
 * podcastRSSProvider.js
 * SourceProvider adapter for podcast RSS feeds.
 *
 * Fetches and parses an official podcast RSS feed URL.
 * Uses a minimal regex-based XML parser — no new npm dependencies needed.
 *
 * Follows the RSS 2.0 + iTunes Podcast namespace spec.
 */

'use strict';

const https = require('https');
const http = require('http');

/**
 * Fetch raw text from a URL (supports http and https, follows one redirect).
 */
function fetchText(url) {
  return new Promise((resolve, reject) => {
    const lib = url.startsWith('https') ? https : http;
    const req = lib.get(url, (res) => {
      // Follow a single redirect
      if (
        (res.statusCode === 301 || res.statusCode === 302) &&
        res.headers.location
      ) {
        fetchText(res.headers.location).then(resolve).catch(reject);
        return;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        reject(new Error(`RSS fetch failed: HTTP ${res.statusCode} for ${url}`));
        return;
      }
      let body = '';
      res.on('data', (chunk) => (body += chunk));
      res.on('end', () => resolve(body));
    });
    req.on('error', reject);
    req.setTimeout(15000, () => {
      req.destroy();
      reject(new Error(`RSS fetch timeout for ${url}`));
    });
  });
}

/**
 * Extract text content of the first matching XML tag (case-insensitive tag name).
 * Handles self-closing, CDATA, and simple text nodes.
 */
function extractTag(xml, tag) {
  // Try CDATA or text content
  const re = new RegExp(
    `<${tag}[^>]*>\\s*(?:<!\\[CDATA\\[([\\s\\S]*?)\\]\\]>|([^<]*))\\s*</${tag}>`,
    'i'
  );
  const m = xml.match(re);
  if (!m) return null;
  // CDATA group takes priority
  return (m[1] !== undefined ? m[1] : m[2] || '').trim() || null;
}

/**
 * Extract the value of an attribute from the first occurrence of a tag.
 */
function extractAttr(xml, tag, attr) {
  const re = new RegExp(`<${tag}[^>]+${attr}\\s*=\\s*["']([^"']*)["']`, 'i');
  const m = xml.match(re);
  return m ? m[1].trim() : null;
}

/**
 * Split an RSS XML document into individual <item> blocks.
 */
function splitItems(xml) {
  const items = [];
  const re = /<item[\s>]([\s\S]*?)<\/item>/gi;
  let m;
  while ((m = re.exec(xml)) !== null) {
    items.push(m[1]);
  }
  return items;
}

/**
 * Normalize RSS <channel> metadata → Work type='podcast'.
 */
function normalizeChannel(channelXml, feedUrl, creatorId) {
  const title = extractTag(channelXml, 'title') || '';
  const description = extractTag(channelXml, 'description') || extractTag(channelXml, 'itunes:summary') || null;
  const author = extractTag(channelXml, 'itunes:author') || extractTag(channelXml, 'managingEditor') || null;
  const imageHref = extractAttr(channelXml, 'itunes:image', 'href')
    || extractTag(channelXml, 'url') || null; // <image><url>…</url></image>
  const link = extractTag(channelXml, 'link') || feedUrl;
  const pubDate = extractTag(channelXml, 'pubDate') || extractTag(channelXml, 'lastBuildDate') || null;

  return {
    creatorId,
    type: 'podcast',
    title,
    subtitle: author,
    description,
    coverUrl: imageHref,
    publishedAt: pubDate ? new Date(pubDate) : null,
    source: {
      provider: 'podcast_rss',
      externalId: feedUrl,
      sourceUrl: feedUrl,
    },
    links: [
      { kind: 'listen', platform: 'rss', url: link, affiliateUrl: null },
    ],
    topics: [],
    embeddingRef: null,
    transcriptRef: null,
    visibility: 'private',
    reviewState: 'imported',
    ingestMode: 'auto',
    verifiedOwnership: false,
    deletedAt: null,
  };
}

/**
 * Normalize an RSS <item> block → Work type='episode'.
 */
function normalizeEpisode(itemXml, feedUrl, feedTitle, creatorId) {
  const title = extractTag(itemXml, 'title') || '';
  const description = extractTag(itemXml, 'description') || extractTag(itemXml, 'itunes:summary') || null;
  const guid = extractTag(itemXml, 'guid') || null;
  const pubDate = extractTag(itemXml, 'pubDate') || null;
  const link = extractTag(itemXml, 'link') || null;
  const enclosureUrl = extractAttr(itemXml, 'enclosure', 'url') || null;
  const imageHref = extractAttr(itemXml, 'itunes:image', 'href') || null;

  // Use GUID as the stable externalId; fall back to enclosure URL
  const externalId = guid || enclosureUrl || title;

  return {
    creatorId,
    type: 'episode',
    title,
    subtitle: feedTitle || null,
    description,
    coverUrl: imageHref,
    publishedAt: pubDate ? new Date(pubDate) : null,
    source: {
      provider: 'podcast_rss',
      externalId,
      sourceUrl: link || feedUrl,
    },
    links: [
      ...(enclosureUrl ? [{ kind: 'listen', platform: 'rss', url: enclosureUrl, affiliateUrl: null }] : []),
      ...(link ? [{ kind: 'listen', platform: 'podcast_web', url: link, affiliateUrl: null }] : []),
    ],
    topics: [],
    embeddingRef: null,
    transcriptRef: null,
    visibility: 'private',
    reviewState: 'imported',
    ingestMode: 'auto',
    verifiedOwnership: false,
    deletedAt: null,
  };
}

/**
 * Parse RSS XML and return the channel work + episode works.
 */
function parseRSS(xml, feedUrl, creatorId) {
  // Extract <channel> block (everything between <channel> and </channel>)
  const channelMatch = xml.match(/<channel[\s>]([\s\S]*?)<\/channel>/i);
  if (!channelMatch) {
    throw new Error('No <channel> element found in RSS feed');
  }
  const channelXml = channelMatch[1];

  const channelWork = normalizeChannel(channelXml, feedUrl, creatorId);
  const feedTitle = channelWork.title;

  const itemBlocks = splitItems(channelXml);
  const episodeWorks = itemBlocks.map((block) =>
    normalizeEpisode(block, feedUrl, feedTitle, creatorId)
  );

  return { channelWork, episodeWorks };
}

module.exports = {
  id: 'podcast_rss',
  supportsSync: true,

  /**
   * Fetch a podcast RSS feed and return channel + episode Works.
   * accessToken is unused for RSS (public feeds); pass feedUrl in cursor.feedUrl.
   * cursor is { feedUrl: string, page: number } or null.
   * Returns { works: [...], nextCursor: null } — RSS has no pagination; all episodes returned at once.
   */
  async fetch(creatorId, accessToken, cursor = null) {
    const feedUrl = (cursor && cursor.feedUrl) || (accessToken && accessToken.startsWith('http') ? accessToken : null);
    if (!feedUrl) {
      throw new Error('podcastRSSProvider.fetch requires cursor.feedUrl');
    }

    const xml = await fetchText(feedUrl);
    const { channelWork, episodeWorks } = parseRSS(xml, feedUrl, creatorId);

    // Return channel first, then episodes
    return {
      works: [channelWork, ...episodeWorks],
      nextCursor: null, // RSS is a single document; no pagination
    };
  },

  /**
   * Normalize a raw RSS item block (string of XML) → episode Work.
   */
  normalize(rawItem, creatorId) {
    // rawItem can be a string (XML block) or a pre-parsed object
    if (typeof rawItem === 'string') {
      return normalizeEpisode(rawItem, '', '', creatorId);
    }
    return rawItem; // already normalized
  },

  /**
   * Verify the creator owns this RSS feed by checking author metadata.
   * Looks for the creator's email domain in the feed's <itunes:email> or <managingEditor>.
   * Returns { verified: boolean, feedEmail: string | null }.
   */
  async verifyOwnership(creatorId, accessToken, opts = {}) {
    const feedUrl = opts.feedUrl || accessToken;
    const userEmail = opts.userEmail || null;

    if (!feedUrl) {
      return { verified: false, feedEmail: null, reason: 'no_feed_url' };
    }

    const xml = await fetchText(feedUrl);
    const feedEmail =
      extractTag(xml, 'itunes:email') ||
      extractTag(xml, 'managingEditor') ||
      null;

    if (!feedEmail || !userEmail) {
      // Cannot verify without emails; return false but store feedEmail for manual review
      return { verified: false, feedEmail, reason: 'email_unavailable' };
    }

    // Domain-level match (not exact, because some feeds use a public@domain address)
    const userDomain = userEmail.split('@')[1] || '';
    const feedDomain = feedEmail.split('@')[1] || '';
    const verified = userDomain.length > 0 && userDomain === feedDomain;

    return { verified, feedEmail };
  },

  // Expose for testing
  _parseRSS: parseRSS,
  _extractTag: extractTag,
};

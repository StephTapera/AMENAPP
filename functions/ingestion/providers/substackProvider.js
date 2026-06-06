/**
 * substackProvider.js
 * SourceProvider adapter for Substack publications via RSS.
 *
 * Substack provides an official RSS feed at:
 *   https://{publication}.substack.com/feed
 *
 * No scraping. No third-party API. Official RSS only.
 */

'use strict';

const https = require('https');
const http = require('http');

/**
 * Fetch raw text from a URL with single-redirect support.
 */
function fetchText(url) {
  return new Promise((resolve, reject) => {
    const lib = url.startsWith('https') ? https : http;
    const req = lib.get(url, (res) => {
      if (
        (res.statusCode === 301 || res.statusCode === 302) &&
        res.headers.location
      ) {
        fetchText(res.headers.location).then(resolve).catch(reject);
        return;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        reject(new Error(`Substack RSS fetch failed: HTTP ${res.statusCode} for ${url}`));
        return;
      }
      let body = '';
      res.on('data', (chunk) => (body += chunk));
      res.on('end', () => resolve(body));
    });
    req.on('error', reject);
    req.setTimeout(15000, () => {
      req.destroy();
      reject(new Error(`Substack RSS fetch timeout for ${url}`));
    });
  });
}

/**
 * Extract text content of the first matching XML tag.
 * Handles CDATA sections and plain text nodes.
 */
function extractTag(xml, tag) {
  const re = new RegExp(
    `<${tag}[^>]*>\\s*(?:<!\\[CDATA\\[([\\s\\S]*?)\\]\\]>|([^<]*))\\s*</${tag}>`,
    'i'
  );
  const m = xml.match(re);
  if (!m) return null;
  return (m[1] !== undefined ? m[1] : m[2] || '').trim() || null;
}

/**
 * Extract an attribute value from the first occurrence of a tag.
 */
function extractAttr(xml, tag, attr) {
  const re = new RegExp(`<${tag}[^>]+${attr}\\s*=\\s*["']([^"']*)["']`, 'i');
  const m = xml.match(re);
  return m ? m[1].trim() : null;
}

/**
 * Split an RSS document into individual <item> blocks.
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
 * Build the canonical RSS feed URL from a Substack publication URL or slug.
 * Accepts:
 *   - https://name.substack.com          → https://name.substack.com/feed
 *   - https://name.substack.com/feed     → unchanged
 *   - name                               → https://name.substack.com/feed
 *   - https://custom.domain.com          → https://custom.domain.com/feed
 */
function toFeedUrl(substackUrl) {
  if (!substackUrl) return null;
  let url = substackUrl.trim();
  // Bare slug (no dot or slash)
  if (!url.includes('.') && !url.includes('/')) {
    return `https://${url}.substack.com/feed`;
  }
  // Already a URL
  if (!url.startsWith('http')) {
    url = `https://${url}`;
  }
  if (!url.endsWith('/feed') && !url.endsWith('/feed/')) {
    url = url.replace(/\/$/, '') + '/feed';
  }
  return url;
}

/**
 * Normalize a Substack RSS <item> block → Work type='article'.
 */
function normalizeArticle(itemXml, feedUrl, publicationTitle, creatorId) {
  const title = extractTag(itemXml, 'title') || '';
  const description = extractTag(itemXml, 'description') || extractTag(itemXml, 'content:encoded') || null;
  const link = extractTag(itemXml, 'link') || null;
  const guid = extractTag(itemXml, 'guid') || link || title;
  const pubDate = extractTag(itemXml, 'pubDate') || null;
  const authorEmail = extractTag(itemXml, 'author') || extractTag(itemXml, 'dc:creator') || null;

  // Extract a cover image from the description HTML if present
  let coverUrl = null;
  if (description) {
    const imgMatch = description.match(/<img[^>]+src=["']([^"']+)["']/i);
    if (imgMatch) coverUrl = imgMatch[1];
  }

  return {
    creatorId,
    type: 'article',
    title,
    subtitle: publicationTitle || null,
    description: description
      ? description.replace(/<[^>]+>/g, '').substring(0, 500).trim() || null
      : null,
    coverUrl,
    publishedAt: pubDate ? new Date(pubDate) : null,
    source: {
      provider: 'substack',
      externalId: guid,
      sourceUrl: link || feedUrl,
    },
    links: [
      {
        kind: 'read',
        platform: 'substack',
        url: link || feedUrl,
        affiliateUrl: null,
      },
    ],
    topics: [],
    embeddingRef: null,
    transcriptRef: null,
    visibility: 'private',
    reviewState: 'imported',
    ingestMode: 'auto',
    verifiedOwnership: false,
    deletedAt: null,
    // Store author email hint for ownership verification (not in schema; stripped before save)
    _authorEmailHint: authorEmail,
  };
}

/**
 * Parse Substack RSS XML and return article Works.
 */
function parseSubstackRSS(xml, feedUrl, creatorId) {
  const channelMatch = xml.match(/<channel[\s>]([\s\S]*?)<\/channel>/i);
  if (!channelMatch) {
    throw new Error('No <channel> element found in Substack RSS feed');
  }
  const channelXml = channelMatch[1];
  const publicationTitle = extractTag(channelXml, 'title') || '';
  const feedEmail =
    extractTag(channelXml, 'itunes:email') ||
    extractTag(channelXml, 'managingEditor') ||
    null;

  const itemBlocks = splitItems(channelXml);
  const articles = itemBlocks.map((block) =>
    normalizeArticle(block, feedUrl, publicationTitle, creatorId)
  );

  return { articles, publicationTitle, feedEmail };
}

module.exports = {
  id: 'substack',
  supportsSync: true,

  /**
   * Fetch articles from a Substack publication RSS feed.
   * cursor.substackUrl: publication URL or slug (required).
   * Returns { works: [...], nextCursor: null } — Substack RSS is a single document.
   */
  async fetch(creatorId, accessToken, cursor = null) {
    const substackUrl = (cursor && cursor.substackUrl) || null;
    if (!substackUrl) {
      throw new Error(
        'substackProvider.fetch requires cursor.substackUrl ' +
        '(e.g. "https://name.substack.com" or "name")'
      );
    }

    const feedUrl = toFeedUrl(substackUrl);
    const xml = await fetchText(feedUrl);
    const { articles } = parseSubstackRSS(xml, feedUrl, creatorId);

    // Strip internal hints before returning
    const works = articles.map(({ _authorEmailHint, ...w }) => w);

    return { works, nextCursor: null };
  },

  /**
   * Normalize a raw Substack RSS item block → article Work.
   */
  normalize(rawItem, creatorId) {
    if (typeof rawItem === 'string') {
      return normalizeArticle(rawItem, '', '', creatorId);
    }
    const { _authorEmailHint, ...clean } = rawItem;
    return clean;
  },

  /**
   * Verify creator owns the Substack by checking author email in the feed.
   * opts.substackUrl: the publication URL
   * opts.userEmail: the creator's Firebase Auth email
   * Returns { verified: boolean, feedEmail: string | null }.
   */
  async verifyOwnership(creatorId, accessToken, opts = {}) {
    const substackUrl = opts.substackUrl || null;
    const userEmail = opts.userEmail || null;

    if (!substackUrl) {
      return { verified: false, feedEmail: null, reason: 'no_substack_url' };
    }

    const feedUrl = toFeedUrl(substackUrl);
    const xml = await fetchText(feedUrl);

    const { feedEmail } = parseSubstackRSS(xml, feedUrl, creatorId);

    if (!feedEmail || !userEmail) {
      return { verified: false, feedEmail, reason: 'email_unavailable' };
    }

    // Exact email match for Substack (author email is usually the account email)
    const verified = feedEmail.toLowerCase().trim() === userEmail.toLowerCase().trim();

    return { verified, feedEmail };
  },

  // Expose helpers
  toFeedUrl,
  _parseSubstackRSS: parseSubstackRSS,
};

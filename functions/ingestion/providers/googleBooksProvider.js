/**
 * googleBooksProvider.js
 * SourceProvider adapter for Google Books API + Open Library (ISBN fallback).
 *
 * Searches books by author name using the public Google Books API (no auth required).
 * Ownership cannot be cryptographically verified; verifiedOwnership is always false.
 *
 * Google Books API: https://developers.google.com/books/docs/v1/using
 * Open Library API: https://openlibrary.org/dev/docs/api
 */

'use strict';

const https = require('https');

/**
 * Generic HTTPS GET that returns parsed JSON.
 */
function getJSON(hostname, path) {
  return new Promise((resolve, reject) => {
    const options = { hostname, path, method: 'GET' };
    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => (body += chunk));
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            resolve(JSON.parse(body));
          } catch (e) {
            reject(new Error(`JSON parse error from ${hostname}${path}: ${e.message}`));
          }
        } else {
          reject(new Error(`HTTP ${res.statusCode} from ${hostname}${path}: ${body}`));
        }
      });
    });
    req.on('error', reject);
    req.end();
  });
}

/**
 * Return a Bookshop.org affiliate URL for an ISBN.
 * Creator can supplement with their own Amazon affiliate link manually.
 */
function bookshopAffiliateUrl(isbn) {
  if (!isbn) return null;
  // Bookshop.org canonical book URL — affiliate tag can be set by the creator later
  return `https://bookshop.org/books/${isbn}`;
}

/**
 * Extract the best available ISBN (prefers ISBN-13) from Google Books volumeInfo.
 */
function extractISBN(volumeInfo) {
  const identifiers = volumeInfo.industryIdentifiers || [];
  const isbn13 = identifiers.find((i) => i.type === 'ISBN_13');
  if (isbn13) return isbn13.identifier;
  const isbn10 = identifiers.find((i) => i.type === 'ISBN_10');
  if (isbn10) return isbn10.identifier;
  return null;
}

/**
 * Normalize a Google Books volume object → Work shape.
 */
function normalizeVolume(volume, creatorId) {
  const info = volume.volumeInfo || {};
  const isbn = extractISBN(info);
  const publishedAt = info.publishedDate ? new Date(info.publishedDate) : null;
  const coverUrl = info.imageLinks
    ? (info.imageLinks.thumbnail || info.imageLinks.smallThumbnail || null)
    : null;

  const links = [];
  // Primary read link (Google Books preview/info)
  const selfLink = volume.selfLink || `https://books.google.com/books?id=${volume.id}`;
  links.push({
    kind: 'read',
    platform: 'google_books',
    url: selfLink,
    affiliateUrl: null,
  });
  // Bookshop.org buy link (not Amazon)
  if (isbn) {
    links.push({
      kind: 'buy',
      platform: 'bookshop',
      url: bookshopAffiliateUrl(isbn),
      affiliateUrl: bookshopAffiliateUrl(isbn),
    });
  }

  return {
    creatorId,
    type: 'book',
    title: info.title || '',
    subtitle: info.subtitle || null,
    description: info.description || null,
    coverUrl,
    publishedAt,
    source: {
      // Flag as unverified since we can't cryptographically confirm authorship
      provider: 'google_books_unverified',
      externalId: volume.id,
      sourceUrl: selfLink,
    },
    links,
    topics: info.categories || [],
    embeddingRef: null,
    transcriptRef: null,
    visibility: 'private',
    reviewState: 'imported',
    ingestMode: 'auto',
    verifiedOwnership: false, // always false; no OAuth available for Books
    deletedAt: null,
  };
}

module.exports = {
  id: 'google_books',
  supportsSync: false, // book catalogues rarely change; manual re-sync is sufficient

  /**
   * Search books by author name using the Google Books public API.
   * accessToken is unused (public API); pass authorName via cursor.authorName.
   * cursor is { startIndex: number, authorName: string } or null.
   * Returns { works: [...], nextCursor: { startIndex, authorName } | null }.
   */
  async fetch(creatorId, accessToken, cursor = null) {
    const authorName = (cursor && cursor.authorName) || null;
    const startIndex = (cursor && cursor.startIndex != null) ? cursor.startIndex : 0;
    const maxResults = 40; // Google Books max

    if (!authorName) {
      throw new Error('googleBooksProvider.fetch requires cursor.authorName to be set');
    }

    const query = encodeURIComponent(`inauthor:${authorName}`);
    const path =
      `/books/v1/volumes?q=${query}&startIndex=${startIndex}&maxResults=${maxResults}&printType=books`;

    const res = await getJSON('www.googleapis.com', path);
    const items = res.items || [];
    const works = items.map((vol) => normalizeVolume(vol, creatorId));

    const totalItems = res.totalItems || 0;
    const nextStart = startIndex + maxResults;
    const nextCursor = nextStart < totalItems
      ? { startIndex: nextStart, authorName }
      : null;

    return { works, nextCursor };
  },

  /**
   * Fetch a single book by ISBN using Open Library.
   * Returns a normalized Work or null if not found.
   */
  async fetchByISBN(isbn, creatorId) {
    const bibkey = `ISBN:${isbn}`;
    const path = `/api/books?bibkeys=${encodeURIComponent(bibkey)}&format=json&jscmd=data`;
    const res = await getJSON('openlibrary.org', path);

    const data = res[bibkey];
    if (!data) return null;

    const publishedAt = data.publish_date ? new Date(data.publish_date) : null;
    const cover = data.cover ? (data.cover.large || data.cover.medium || data.cover.small || null) : null;

    const links = [];
    const olUrl = data.url || `https://openlibrary.org/isbn/${isbn}`;
    links.push({ kind: 'read', platform: 'open_library', url: olUrl, affiliateUrl: null });
    links.push({
      kind: 'buy',
      platform: 'bookshop',
      url: bookshopAffiliateUrl(isbn),
      affiliateUrl: bookshopAffiliateUrl(isbn),
    });

    return {
      creatorId,
      type: 'book',
      title: data.title || '',
      subtitle: data.subtitle || null,
      description: data.excerpts && data.excerpts[0] ? data.excerpts[0].text : null,
      coverUrl: cover,
      publishedAt,
      source: {
        provider: 'open_library',
        externalId: isbn,
        sourceUrl: olUrl,
      },
      links,
      topics: data.subjects ? data.subjects.map((s) => (typeof s === 'string' ? s : s.name)) : [],
      embeddingRef: null,
      transcriptRef: null,
      visibility: 'private',
      reviewState: 'imported',
      ingestMode: 'manual',
      verifiedOwnership: false,
      deletedAt: null,
    };
  },

  /**
   * Normalize a raw Google Books volume object.
   */
  normalize(rawItem, creatorId) {
    return normalizeVolume(rawItem, creatorId);
  },

  /**
   * Ownership cannot be verified for books (no OAuth).
   * Always returns { verified: false, reason: 'no_oauth_available' }.
   */
  async verifyOwnership(creatorId, accessToken) {
    return {
      verified: false,
      reason: 'no_oauth_available',
      message:
        'Google Books has no author OAuth verification. Works are marked unverified. ' +
        'The creator can claim ownership by connecting their Google account and confirming authorship.',
    };
  },

  // Exported helper so callers can generate Bookshop links independently
  bookshopAffiliateUrl,
};

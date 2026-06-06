/**
 * spotifyProvider.js
 * SourceProvider adapter for Spotify Web API.
 *
 * Fetches albums and saved tracks from the authenticated user's Spotify library.
 * Access token is passed in per-call from the client — never persisted in Firestore.
 *
 * API ref: https://api.spotify.com/v1
 */

'use strict';

const https = require('https');

const SPOTIFY_BASE = 'api.spotify.com';
const MAX_LIMIT = 50; // Spotify max page size

/**
 * Minimal HTTPS GET helper that returns parsed JSON.
 * Throws on non-2xx status.
 */
function spotifyGet(path, accessToken) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: SPOTIFY_BASE,
      path,
      method: 'GET',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
    };
    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => (body += chunk));
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            resolve(JSON.parse(body));
          } catch (e) {
            reject(new Error(`Spotify JSON parse error: ${e.message}`));
          }
        } else {
          reject(new Error(`Spotify API ${res.statusCode}: ${body}`));
        }
      });
    });
    req.on('error', reject);
    req.end();
  });
}

/**
 * Normalize a Spotify album object → Work shape.
 */
function normalizeAlbum(album, creatorId) {
  const releaseDate = album.release_date
    ? new Date(album.release_date)
    : null;

  return {
    creatorId,
    type: 'album',
    title: album.name,
    subtitle: null,
    description: null,
    coverUrl: album.images && album.images[0] ? album.images[0].url : null,
    publishedAt: releaseDate,
    source: {
      provider: 'spotify',
      externalId: album.id,
      sourceUrl: album.external_urls && album.external_urls.spotify
        ? album.external_urls.spotify
        : `https://open.spotify.com/album/${album.id}`,
    },
    links: [
      {
        kind: 'listen',
        platform: 'spotify',
        url: album.external_urls && album.external_urls.spotify
          ? album.external_urls.spotify
          : `https://open.spotify.com/album/${album.id}`,
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
  };
}

/**
 * Normalize a Spotify saved track object → Work shape.
 */
function normalizeTrack(savedTrack, creatorId) {
  const track = savedTrack.track || savedTrack;
  const addedAt = savedTrack.added_at ? new Date(savedTrack.added_at) : null;

  return {
    creatorId,
    type: 'track',
    title: track.name,
    subtitle: track.artists ? track.artists.map((a) => a.name).join(', ') : null,
    description: null,
    coverUrl: track.album && track.album.images && track.album.images[0]
      ? track.album.images[0].url
      : null,
    publishedAt: addedAt,
    source: {
      provider: 'spotify',
      externalId: track.id,
      sourceUrl: track.external_urls && track.external_urls.spotify
        ? track.external_urls.spotify
        : `https://open.spotify.com/track/${track.id}`,
    },
    links: [
      {
        kind: 'listen',
        platform: 'spotify',
        url: track.external_urls && track.external_urls.spotify
          ? track.external_urls.spotify
          : `https://open.spotify.com/track/${track.id}`,
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
  };
}

module.exports = {
  id: 'spotify',
  supportsSync: true,

  /**
   * Fetch albums and saved tracks for the authenticated Spotify user.
   * cursor is a { albumsOffset, tracksOffset } object or null.
   * Returns { works: [...], nextCursor: {...} | null }.
   */
  async fetch(creatorId, accessToken, cursor = null) {
    const albumsOffset = cursor && cursor.albumsOffset != null ? cursor.albumsOffset : 0;
    const tracksOffset = cursor && cursor.tracksOffset != null ? cursor.tracksOffset : 0;

    const works = [];

    // Fetch saved albums (one page)
    const albumsPath = `/v1/me/albums?limit=${MAX_LIMIT}&offset=${albumsOffset}`;
    const albumsRes = await spotifyGet(albumsPath, accessToken);
    const albumItems = albumsRes.items || [];
    for (const saved of albumItems) {
      if (saved.album) {
        works.push(normalizeAlbum(saved.album, creatorId));
      }
    }
    const albumsHasMore = albumsRes.next !== null && albumsRes.next !== undefined;

    // Fetch saved tracks (one page)
    const tracksPath = `/v1/me/tracks?limit=${MAX_LIMIT}&offset=${tracksOffset}`;
    const tracksRes = await spotifyGet(tracksPath, accessToken);
    const trackItems = tracksRes.items || [];
    for (const saved of trackItems) {
      if (saved.track) {
        works.push(normalizeTrack(saved, creatorId));
      }
    }
    const tracksHasMore = tracksRes.next !== null && tracksRes.next !== undefined;

    const nextCursor = (albumsHasMore || tracksHasMore)
      ? {
        albumsOffset: albumsHasMore ? albumsOffset + MAX_LIMIT : null,
        tracksOffset: tracksHasMore ? tracksOffset + MAX_LIMIT : null,
      }
      : null;

    return { works, nextCursor };
  },

  /**
   * Normalize a raw Spotify item. type='album'|'track' selects the normalizer.
   */
  normalize(rawItem, creatorId) {
    if (rawItem.album_type !== undefined || rawItem.type === 'album') {
      return normalizeAlbum(rawItem, creatorId);
    }
    return normalizeTrack(rawItem, creatorId);
  },

  /**
   * Verify that the Spotify access token belongs to the creator.
   * Calls /v1/me and checks the returned id against storedSpotifyId
   * (which must have been stored during OAuth connect).
   * Returns { verified: boolean, spotifyUserId: string }.
   */
  async verifyOwnership(creatorId, accessToken, storedSpotifyId = null) {
    const me = await spotifyGet('/v1/me', accessToken);
    const spotifyUserId = me.id;

    if (storedSpotifyId && storedSpotifyId !== spotifyUserId) {
      return { verified: false, spotifyUserId };
    }

    return { verified: true, spotifyUserId };
  },
};

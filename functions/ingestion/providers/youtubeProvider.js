/**
 * youtubeProvider.js
 * SourceProvider adapter for YouTube Data API v3.
 *
 * Fetches public videos from a creator's YouTube channel.
 * Access token is passed in per-call — never persisted in Firestore.
 *
 * API ref: https://developers.google.com/youtube/v3/docs
 */

'use strict';

const https = require('https');

const YT_BASE = 'www.googleapis.com';
const MAX_RESULTS = 50; // YouTube max per page

/**
 * Minimal HTTPS GET helper that returns parsed JSON.
 */
function ytGet(path, accessToken) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: YT_BASE,
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
            reject(new Error(`YouTube JSON parse error: ${e.message}`));
          }
        } else {
          reject(new Error(`YouTube API ${res.statusCode}: ${body}`));
        }
      });
    });
    req.on('error', reject);
    req.end();
  });
}

/**
 * Build the watch URL for a YouTube video id.
 */
function watchUrl(videoId) {
  return `https://www.youtube.com/watch?v=${videoId}`;
}

/**
 * Normalize a YouTube search result item → Work shape.
 */
function normalizeVideo(item, creatorId) {
  const snippet = item.snippet || {};
  const videoId = item.id && item.id.videoId ? item.id.videoId : item.id;
  const publishedAt = snippet.publishedAt ? new Date(snippet.publishedAt) : null;
  const thumb = snippet.thumbnails
    ? (snippet.thumbnails.high || snippet.thumbnails.medium || snippet.thumbnails.default)
    : null;

  return {
    creatorId,
    type: 'video',
    title: snippet.title || '',
    subtitle: null,
    description: snippet.description || null,
    coverUrl: thumb ? thumb.url : null,
    publishedAt,
    source: {
      provider: 'youtube',
      externalId: videoId,
      sourceUrl: watchUrl(videoId),
    },
    links: [
      {
        kind: 'watch',
        platform: 'youtube',
        url: watchUrl(videoId),
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
  id: 'youtube',
  supportsSync: true,

  /**
   * Fetch videos from the creator's YouTube channel.
   * accessToken must be an OAuth token with youtube.readonly scope.
   * cursor is the YouTube nextPageToken string or null.
   * Returns { works: [...], nextCursor: string | null }.
   */
  async fetch(creatorId, accessToken, cursor = null) {
    // Step 1: resolve the authenticated user's channel id
    const channelPath =
      `/youtube/v3/channels?part=id,snippet&mine=true`;
    const channelRes = await ytGet(channelPath, accessToken);
    const channels = channelRes.items || [];
    if (channels.length === 0) {
      return { works: [], nextCursor: null };
    }
    const channelId = channels[0].id;

    // Step 2: search for videos in that channel (cursor = pageToken)
    let searchPath =
      `/youtube/v3/search?part=snippet&channelId=${encodeURIComponent(channelId)}`
      + `&type=video&order=date&maxResults=${MAX_RESULTS}`;
    if (cursor) {
      searchPath += `&pageToken=${encodeURIComponent(cursor)}`;
    }

    const searchRes = await ytGet(searchPath, accessToken);
    const items = searchRes.items || [];
    const works = items.map((item) => normalizeVideo(item, creatorId));
    const nextCursor = searchRes.nextPageToken || null;

    return { works, nextCursor };
  },

  /**
   * Normalize a raw YouTube search result item.
   */
  normalize(rawItem, creatorId) {
    return normalizeVideo(rawItem, creatorId);
  },

  /**
   * Verify that the authenticated user's YouTube channel matches channelId.
   * Returns { verified: boolean, channelId: string }.
   */
  async verifyOwnership(creatorId, accessToken, expectedChannelId = null) {
    const channelPath = `/youtube/v3/channels?part=id&mine=true`;
    const res = await ytGet(channelPath, accessToken);
    const channels = res.items || [];
    if (channels.length === 0) {
      return { verified: false, channelId: null };
    }
    const actualChannelId = channels[0].id;

    if (expectedChannelId && expectedChannelId !== actualChannelId) {
      return { verified: false, channelId: actualChannelId };
    }

    return { verified: true, channelId: actualChannelId };
  },
};

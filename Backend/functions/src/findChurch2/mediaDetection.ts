/**
 * findChurch2/mediaDetection.ts
 *
 * Wave 2 Find-a-Church backend: church media auto-detection.
 *
 * Exports
 * -------
 * - detectChurchMedia  onCall — probe a church's website for YouTube, podcast, and livestream links.
 *
 * Strategy
 * --------
 * 1. YouTube channel:  check `youtubeChannelURL` field OR scan church website for youtube.com/c/ or
 *    youtube.com/channel/ or youtube.com/@  patterns.
 * 2. Podcast RSS:      fetch church website HTML, look for <link rel="alternate" type="application/rss+xml">
 *                      or common podcast path patterns (/feed, /podcast, /rss).
 * 3. Livestream:       heuristic — YouTube channel URL contains "/live", OR found a YouTube channel
 *                      and a Saturday/Sunday-evening service time is within 2 hours.
 *
 * All probes use node's built-in `https`/`http` modules — no external HTTP dependencies.
 */

import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import * as https from "https";
import * as http from "http";
import type { IncomingMessage } from "http";

const db = admin.firestore();
const REGION = "us-central1";
const IS_EMULATOR = process.env.FUNCTIONS_EMULATOR === "true";

// ─── Types ────────────────────────────────────────────────────────────────────

type CallableRequest<T = Record<string, unknown>> = {
    auth?: { uid?: string };
    app?: { appId?: string };
    data: T;
};

type DetectedMediaType = "none" | "podcast" | "youtube" | "livestream" | "multiple";

interface DetectedMediaLinks {
    youtubeChannelURL?: string;
    podcastRssURL?: string;
    livestreamURL?: string;
}

interface DetectMediaResponse {
    churchId: string;
    detectedType: DetectedMediaType;
    links: DetectedMediaLinks;
}

interface ChurchData {
    website?: string;
    youtubeChannelURL?: string;
    mediaLinks?: DetectedMediaLinks;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function requireAuth(request: CallableRequest): string {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return uid;
}

function requireAppCheck(request: CallableRequest): void {
    if (IS_EMULATOR) return;
    if (!request.app?.appId) {
        throw new HttpsError("failed-precondition", "App Check token required.");
    }
}

/** Max bytes to read from a remote page before giving up. ~128 KB is enough for <head>. */
const MAX_RESPONSE_BYTES = 131_072;
/** HTTP fetch timeout in milliseconds. */
const FETCH_TIMEOUT_MS = 8_000;

/**
 * Fetch the first MAX_RESPONSE_BYTES bytes of a URL and return the raw string.
 * Follows a single redirect (30x). Returns null on error or timeout.
 */
function fetchPartialHtml(rawUrl: string): Promise<string | null> {
    return new Promise((resolve) => {
        let resolved = false;
        const done = (val: string | null) => {
            if (!resolved) { resolved = true; resolve(val); }
        };

        const timeout = setTimeout(() => done(null), FETCH_TIMEOUT_MS);

        function doRequest(url: string, redirectsLeft: number): void {
            let parsed: URL;
            try {
                parsed = new URL(url);
            } catch {
                done(null);
                return;
            }
            const lib = parsed.protocol === "https:" ? https : http;
            const req = (lib as typeof https).get(url, (res: IncomingMessage) => {
                // Follow single redirect
                if (
                    redirectsLeft > 0 &&
                    res.statusCode &&
                    res.statusCode >= 300 &&
                    res.statusCode < 400 &&
                    res.headers.location
                ) {
                    res.resume();
                    doRequest(res.headers.location, redirectsLeft - 1);
                    return;
                }
                if (!res.statusCode || res.statusCode < 200 || res.statusCode >= 300) {
                    res.resume();
                    done(null);
                    return;
                }
                let body = "";
                let bytes = 0;
                res.setEncoding("utf8");
                res.on("data", (chunk: string) => {
                    bytes += Buffer.byteLength(chunk);
                    body += chunk;
                    if (bytes >= MAX_RESPONSE_BYTES) {
                        req.destroy();
                        done(body);
                    }
                });
                res.on("end", () => { clearTimeout(timeout); done(body); });
                res.on("error", () => done(null));
            });
            req.on("error", () => done(null));
            req.setTimeout(FETCH_TIMEOUT_MS, () => { req.destroy(); done(null); });
        }

        doRequest(rawUrl, 1);
    });
}

/** YouTube channel URL patterns. */
const YT_CHANNEL_PATTERNS = [
    /youtube\.com\/c\/[A-Za-z0-9_-]+/i,
    /youtube\.com\/channel\/[A-Za-z0-9_-]+/i,
    /youtube\.com\/@[A-Za-z0-9_.-]+/i,
    /youtube\.com\/user\/[A-Za-z0-9_-]+/i,
];

/** Extract a full YouTube channel URL from arbitrary HTML or text. Returns null if not found. */
function extractYouTubeChannelURL(html: string): string | null {
    for (const pattern of YT_CHANNEL_PATTERNS) {
        const match = html.match(pattern);
        if (match) {
            return `https://www.${match[0]}`;
        }
    }
    return null;
}

/** Return true if the URL/channel strongly suggests an active live stream. */
function detectLivestreamHeuristic(youtubeURL: string): boolean {
    const lower = youtubeURL.toLowerCase();
    return lower.includes("/live") || lower.includes("live.youtube.com");
}

/**
 * Look for RSS/podcast link in HTML.
 * Checks both <link rel="alternate" type="application/rss+xml"> and common path patterns.
 */
function extractPodcastRssURL(html: string, baseUrl: string): string | null {
    // 1. Standard HTML <link> tag
    const linkTagMatch = html.match(
        /<link[^>]+type=["']application\/rss\+xml["'][^>]*href=["']([^"']+)["']/i
    );
    if (linkTagMatch?.[1]) {
        const href = linkTagMatch[1].trim();
        try {
            return new URL(href, baseUrl).toString();
        } catch {
            return href;
        }
    }

    // 2. Alternative attribute order
    const linkTagMatch2 = html.match(
        /<link[^>]+href=["']([^"']+)["'][^>]*type=["']application\/rss\+xml["']/i
    );
    if (linkTagMatch2?.[1]) {
        const href = linkTagMatch2[1].trim();
        try {
            return new URL(href, baseUrl).toString();
        } catch {
            return href;
        }
    }

    // 3. Common podcast RSS path heuristics in any anchor or mention
    const rssPathPatterns = [
        /https?:\/\/[^\s"'<>]+\/(?:feed|podcast|rss|feed\.xml|podcast\.xml|rss\.xml)[^\s"'<>]*/i,
    ];
    for (const pattern of rssPathPatterns) {
        const match = html.match(pattern);
        if (match) return match[0];
    }

    return null;
}

// ─── detectChurchMedia ────────────────────────────────────────────────────────

interface DetectMediaRequest {
    churchId: string;
}

export const detectChurchMedia = onCall(
    { region: REGION, enforceAppCheck: !IS_EMULATOR },
    async (request: CallableRequest<DetectMediaRequest>): Promise<DetectMediaResponse> => {
        requireAuth(request);
        requireAppCheck(request);

        const churchId = String(request.data?.churchId ?? "").trim();
        if (!churchId) {
            throw new HttpsError("invalid-argument", "churchId is required.");
        }

        const snap = await db.collection("churches").doc(churchId).get();
        if (!snap.exists) {
            throw new HttpsError("not-found", `Church ${churchId} not found.`);
        }

        const data = snap.data() as ChurchData;
        const website: string | undefined = data.website?.trim() || undefined;
        const storedYoutubeURL: string | undefined = data.youtubeChannelURL?.trim() || undefined;

        const links: DetectedMediaLinks = {};

        // ── Step 1: YouTube channel detection ────────────────────────────────

        // Use stored field first (already verified by a human or prior detection)
        if (storedYoutubeURL) {
            links.youtubeChannelURL = storedYoutubeURL;
        }

        // If website is set, scan its HTML for a YouTube link
        if (website && !links.youtubeChannelURL) {
            try {
                const html = await fetchPartialHtml(website);
                if (html) {
                    const foundURL = extractYouTubeChannelURL(html);
                    if (foundURL) {
                        links.youtubeChannelURL = foundURL;
                        logger.info(`detectChurchMedia: found YouTube channel for ${churchId}`, { foundURL });
                    }
                }
            } catch (err) {
                logger.warn(`detectChurchMedia: YouTube probe failed for ${churchId}`, err);
            }
        }

        // ── Step 2: Podcast RSS detection ─────────────────────────────────────

        if (website) {
            try {
                const html = await fetchPartialHtml(website);
                if (html) {
                    const rssURL = extractPodcastRssURL(html, website);
                    if (rssURL) {
                        links.podcastRssURL = rssURL;
                        logger.info(`detectChurchMedia: found podcast RSS for ${churchId}`, { rssURL });
                    }
                }
            } catch (err) {
                logger.warn(`detectChurchMedia: podcast probe failed for ${churchId}`, err);
            }

            // Also try common RSS paths if nothing found yet
            if (!links.podcastRssURL) {
                const candidatePaths = ["/feed", "/podcast", "/rss", "/feed.xml", "/podcast.xml"];
                for (const path of candidatePaths) {
                    let candidateURL: string;
                    try {
                        candidateURL = new URL(path, website).toString();
                    } catch {
                        continue;
                    }
                    try {
                        const probe = await fetchPartialHtml(candidateURL);
                        if (probe && (probe.includes("<rss") || probe.includes("<channel>"))) {
                            links.podcastRssURL = candidateURL;
                            logger.info(
                                `detectChurchMedia: found podcast RSS at common path for ${churchId}`,
                                { candidateURL }
                            );
                            break;
                        }
                    } catch {
                        // Silently skip — path not found
                    }
                }
            }
        }

        // ── Step 3: Livestream detection ──────────────────────────────────────

        if (links.youtubeChannelURL) {
            const isLive = detectLivestreamHeuristic(links.youtubeChannelURL);
            if (isLive) {
                links.livestreamURL = links.youtubeChannelURL;
            } else {
                // Probe /live suffix on the channel URL
                const liveURL = links.youtubeChannelURL.replace(/\/$/, "") + "/live";
                try {
                    const liveHtml = await fetchPartialHtml(liveURL);
                    // YouTube returns a non-redirect page for /live when a stream is active
                    if (
                        liveHtml &&
                        liveHtml.includes('"isLive":true') ||
                        (liveHtml ?? "").includes('"hlsManifestUrl"')
                    ) {
                        links.livestreamURL = liveURL;
                        logger.info(`detectChurchMedia: active livestream detected for ${churchId}`, { liveURL });
                    }
                } catch (err) {
                    logger.warn(`detectChurchMedia: livestream probe failed for ${churchId}`, err);
                }
            }
        }

        // ── Determine aggregate detectedType ──────────────────────────────────

        const hasYoutube = Boolean(links.youtubeChannelURL);
        const hasPodcast = Boolean(links.podcastRssURL);
        const hasLivestream = Boolean(links.livestreamURL);

        let detectedType: DetectedMediaType = "none";
        const detectedCount = [hasYoutube, hasPodcast, hasLivestream].filter(Boolean).length;
        if (detectedCount >= 2) {
            detectedType = "multiple";
        } else if (hasLivestream) {
            detectedType = "livestream";
        } else if (hasYoutube) {
            detectedType = "youtube";
        } else if (hasPodcast) {
            detectedType = "podcast";
        }

        // ── Persist to Firestore ───────────────────────────────────────────────

        try {
            await snap.ref.update({
                mediaLinks: links,
                mediaDetectedType: detectedType,
                mediaDetectedAt: admin.firestore.FieldValue.serverTimestamp(),
                // Promote youtubeChannelURL to top-level field for query convenience
                ...(links.youtubeChannelURL && !storedYoutubeURL
                    ? { youtubeChannelURL: links.youtubeChannelURL }
                    : {}),
            });
        } catch (writeErr) {
            // Log but don't fail the response — the caller still gets the detected data
            logger.error(`detectChurchMedia: Firestore write failed for ${churchId}`, writeErr);
        }

        logger.info(`detectChurchMedia: complete for ${churchId}`, { detectedType, links });

        return { churchId, detectedType, links };
    }
);

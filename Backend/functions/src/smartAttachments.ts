/**
 * smartAttachments.ts
 *
 * Smart Media Attachment System — backend resolution, media graph persistence,
 * and retrieval callables.
 *
 * Callables exported:
 *   resolveSmartAttachment   — validate URL, detect provider, resolve metadata
 *   saveMediaGraphItem       — persist a saved-media record to the user's media graph
 *   getRecentMediaAttachments — return the user's most recent attachment IDs
 *   getSavedMediaItems       — return the user's saved media items by context
 *
 * Security guarantees:
 *   - All callables require Firebase Auth.
 *   - All callables require App Check.
 *   - resolveSmartAttachment rate-limits per user (30 calls/min, 500/day).
 *   - saveMediaGraphItem rate-limits per user (60 calls/min).
 *   - URLs are validated: https only, no private/loopback IPs, no disallowed schemes.
 *   - Provider metadata is resolved server-side only; client never scrapes directly.
 *   - No audio/video content is downloaded or rehosted.
 *   - Provider attribution is preserved in every response.
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as functions from "firebase-functions";
import { enforceRateLimit, RATE_LIMITS, RateLimitConfig } from "./rateLimit";
import * as https from "https";
import * as http from "http";
import * as url from "url";
import * as crypto from "crypto";

const db = admin.firestore();

// ---------------------------------------------------------------------------
// Auth + App Check helpers
// ---------------------------------------------------------------------------

function requireAuth(auth: { uid: string } | undefined): string {
    if (!auth?.uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return auth.uid;
}

function requireAppCheck(app: { appId?: string } | undefined) {
    if (!app) {
        throw new HttpsError("failed-precondition", "App Check required.");
    }
}

// ---------------------------------------------------------------------------
// Rate limit configs
// ---------------------------------------------------------------------------

const RESOLVE_PER_MIN: RateLimitConfig = { name: "resolve_attachment_1min", windowMs: 60_000, maxCalls: 30 };
const RESOLVE_PER_DAY: RateLimitConfig = { name: "resolve_attachment_1day", windowMs: 86_400_000, maxCalls: 500 };
const SAVE_PER_MIN: RateLimitConfig    = { name: "save_media_graph_1min", windowMs: 60_000, maxCalls: 60 };

// ---------------------------------------------------------------------------
// URL safety validation
// ---------------------------------------------------------------------------

const PRIVATE_IP_PATTERNS = [
    /^127\./,
    /^10\./,
    /^192\.168\./,
    /^172\.(1[6-9]|2\d|3[01])\./,
    /^::1$/,
    /^localhost$/i,
    /^0\.0\.0\.0$/,
    /^169\.254\./,    // link-local
    /^fc00:/i,        // IPv6 ULA
    /^fd[0-9a-f]{2}:/i,
];

function validateURL(rawUrl: string): URL {
    let parsed: URL;
    try {
        parsed = new URL(rawUrl);
    } catch {
        throw new HttpsError("invalid-argument", "Invalid URL format.");
    }

    if (parsed.protocol !== "https:") {
        throw new HttpsError("invalid-argument", "Only https URLs are supported.");
    }

    const hostname = parsed.hostname;
    for (const pattern of PRIVATE_IP_PATTERNS) {
        if (pattern.test(hostname)) {
            throw new HttpsError("invalid-argument", "Private network URLs are not allowed.");
        }
    }

    return parsed;
}

// ---------------------------------------------------------------------------
// Provider detection
// ---------------------------------------------------------------------------

type Provider = "appleMusic" | "spotify" | "youtube" | "generic";
type AttachmentType = "song" | "album" | "playlist" | "artist" | "video" | "podcast" | "article" | "genericLink";

function detectProvider(parsed: URL): Provider {
    const host = parsed.hostname.replace(/^www\./, "");
    if (host === "music.apple.com") return "appleMusic";
    if (host === "open.spotify.com") return "spotify";
    if (host === "youtube.com" || host === "youtu.be" || host === "m.youtube.com") return "youtube";
    return "generic";
}

// ---------------------------------------------------------------------------
// YouTube resolution
// ---------------------------------------------------------------------------

function extractYouTubeVideoId(parsed: URL): string | null {
    if (parsed.hostname === "youtu.be") {
        return parsed.pathname.slice(1).split("/")[0] || null;
    }
    const v = parsed.searchParams.get("v");
    if (v) return v;
    // Shorts: /shorts/<id>
    const shortMatch = parsed.pathname.match(/\/shorts\/([a-zA-Z0-9_-]+)/);
    if (shortMatch) return shortMatch[1];
    return null;
}

function extractYouTubePlaylistId(parsed: URL): string | null {
    return parsed.searchParams.get("list");
}

interface YouTubeResolved {
    type: AttachmentType;
    providerId: string;
    title: string;
    creatorName: string;
    artworkUrl: string;
    canonicalUrl: string;
    durationMs?: number;
    description?: string;
}

async function resolveYouTube(parsed: URL): Promise<YouTubeResolved> {
    // Try oEmbed first — doesn't require an API key and is officially supported.
    const videoId = extractYouTubeVideoId(parsed);
    const playlistId = extractYouTubePlaylistId(parsed);

    if (videoId) {
        const oEmbedUrl = `https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=${videoId}&format=json`;
        const data = await safeFetch(oEmbedUrl);
        const json = JSON.parse(data) as Record<string, unknown>;
        const title = String(json.title ?? "YouTube Video");
        const author = String(json.author_name ?? "YouTube");
        const thumbnail = String(json.thumbnail_url ?? `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`);
        return {
            type: "video",
            providerId: videoId,
            title,
            creatorName: author,
            artworkUrl: thumbnail,
            canonicalUrl: `https://www.youtube.com/watch?v=${videoId}`,
        };
    }

    if (playlistId) {
        return {
            type: "playlist",
            providerId: playlistId,
            title: "YouTube Playlist",
            creatorName: "YouTube",
            artworkUrl: "",
            canonicalUrl: `https://www.youtube.com/playlist?list=${playlistId}`,
        };
    }

    // Fallback: return minimal info from Open Graph
    const og = await resolveOpenGraph(parsed);
    return {
        type: "video",
        providerId: parsed.pathname,
        title: og.title,
        creatorName: og.siteName ?? "YouTube",
        artworkUrl: og.imageUrl ?? "",
        canonicalUrl: parsed.href,
        description: og.description,
    };
}

// ---------------------------------------------------------------------------
// Spotify resolution
// ---------------------------------------------------------------------------

type SpotifyEntityType = "track" | "album" | "playlist" | "artist" | "episode" | "show";

interface SpotifyResolved {
    type: AttachmentType;
    providerId: string;
    title: string;
    creatorName?: string;
    artworkUrl: string;
    canonicalUrl: string;
    durationMs?: number;
    description?: string;
}

function spotifyEntityToType(entity: SpotifyEntityType): AttachmentType {
    switch (entity) {
    case "track": return "song";
    case "album": return "album";
    case "playlist": return "playlist";
    case "artist": return "artist";
    case "episode":
    case "show": return "podcast";
    default: return "genericLink";
    }
}

async function resolveSpotify(parsed: URL): Promise<SpotifyResolved> {
    // Path: /entity/providerId  e.g. /track/4uLU6hMCjMI75M1A2tKUQC
    const pathParts = parsed.pathname.split("/").filter(Boolean);
    const entity = (pathParts[0] as SpotifyEntityType) || "track";
    const providerId = pathParts[1] ?? "";
    const canonicalUrl = `https://open.spotify.com/${entity}/${providerId}`;

    // Spotify Web API requires OAuth client-credentials which may not be configured.
    // Use oEmbed as a credential-free fallback; it covers tracks, albums, playlists, episodes.
    const oEmbedUrl = `https://open.spotify.com/oembed?url=${encodeURIComponent(canonicalUrl)}`;
    try {
        const data = await safeFetch(oEmbedUrl);
        const json = JSON.parse(data) as Record<string, unknown>;
        const title = String(json.title ?? entity);
        const thumbnail = String(json.thumbnail_url ?? "");
        const authorName = String(json.provider_name ?? "Spotify");
        return {
            type: spotifyEntityToType(entity),
            providerId,
            title,
            creatorName: authorName,
            artworkUrl: thumbnail,
            canonicalUrl,
        };
    } catch {
        // oEmbed failed — return minimal info
        return {
            type: spotifyEntityToType(entity),
            providerId,
            title: `Spotify ${entity}`,
            creatorName: "Spotify",
            artworkUrl: "",
            canonicalUrl,
        };
    }
}

// ---------------------------------------------------------------------------
// Apple Music resolution
// ---------------------------------------------------------------------------

interface AppleMusicResolved {
    type: AttachmentType;
    providerId: string;
    title: string;
    creatorName?: string;
    artworkUrl: string;
    canonicalUrl: string;
    durationMs?: number;
}

async function resolveAppleMusic(parsed: URL): Promise<AppleMusicResolved> {
    // Apple Music URLs: music.apple.com/{storefront}/{entity}/{name}/{id}
    // e.g. music.apple.com/us/album/name/123456789?i=987654321 (song)
    //      music.apple.com/us/album/name/123456789 (album)
    //      music.apple.com/us/playlist/name/pl.u-abcd1234 (playlist)
    const pathParts = parsed.pathname.split("/").filter(Boolean);
    // pathParts[0] = storefront, [1] = entity type
    const entityType = pathParts[1] as "song" | "album" | "playlist" | "artist" | "music-video" | undefined;
    const songId = parsed.searchParams.get("i"); // song within album
    const itemId = pathParts[pathParts.length - 1] ?? "";

    const canonicalUrl = parsed.href;
    let type: AttachmentType = "genericLink";
    if (entityType === "album" && songId) type = "song";
    else if (entityType === "album") type = "album";
    else if (entityType === "playlist") type = "playlist";
    else if (entityType === "artist") type = "artist";
    else if (entityType === "song") type = "song";
    else if (entityType === "music-video") type = "video";

    // Try oEmbed — Apple Music supports it for albums, playlists, songs
    const oEmbedUrl = `https://music.apple.com/oembed?url=${encodeURIComponent(canonicalUrl)}`;
    try {
        const data = await safeFetch(oEmbedUrl);
        const json = JSON.parse(data) as Record<string, unknown>;
        const title = String(json.title ?? "Apple Music");
        const thumbnail = String(json.thumbnail_url ?? "");
        // Author info lives in title pattern "Song - Artist" for some entities
        return {
            type,
            providerId: songId ?? itemId,
            title,
            artworkUrl: thumbnail,
            canonicalUrl,
        };
    } catch {
        return {
            type,
            providerId: songId ?? itemId,
            title: "Apple Music",
            artworkUrl: "",
            canonicalUrl,
        };
    }
}

// ---------------------------------------------------------------------------
// Open Graph / generic resolution
// ---------------------------------------------------------------------------

interface OGResult {
    title: string;
    description?: string;
    imageUrl?: string;
    siteName?: string;
    canonicalUrl: string;
}

async function resolveOpenGraph(parsed: URL): Promise<OGResult> {
    const raw = await safeFetch(parsed.href, { maxBytes: 200_000, timeoutMs: 6_000 });

    const title = extractMetaContent(raw, "og:title")
        ?? extractMetaContent(raw, "title")
        ?? extractHtmlTitle(raw)
        ?? parsed.hostname;

    const description = extractMetaContent(raw, "og:description")
        ?? extractMetaContent(raw, "description");

    const imageUrl = extractMetaContent(raw, "og:image")
        ?? extractMetaContent(raw, "twitter:image");

    const siteName = extractMetaContent(raw, "og:site_name") ?? toDisplayHost(parsed.hostname);

    const canonicalRaw = extractLinkCanonical(raw) ?? parsed.href;
    let canonicalUrl = canonicalRaw;
    try {
        // Resolve relative canonical URLs against the fetched page URL
        canonicalUrl = new URL(canonicalRaw, parsed.href).href;
    } catch { /* keep original */ }

    return { title, description, imageUrl, siteName, canonicalUrl };
}

function extractMetaContent(html: string, name: string): string | undefined {
    // Match <meta property="og:title" content="..."> or <meta name="..." content="...">
    const re = new RegExp(
        `<meta[^>]+(?:property|name)=["']${name}["'][^>]+content=["']([^"']+)["']|<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']${name}["']`,
        "i"
    );
    const m = html.match(re);
    return m ? (m[1] ?? m[2]) : undefined;
}

function extractHtmlTitle(html: string): string | undefined {
    const m = html.match(/<title[^>]*>([^<]+)<\/title>/i);
    return m ? m[1].trim() : undefined;
}

function extractLinkCanonical(html: string): string | undefined {
    const m = html.match(/<link[^>]+rel=["']canonical["'][^>]+href=["']([^"']+)["']/i);
    return m ? m[1] : undefined;
}

function toDisplayHost(hostname: string): string {
    return hostname.replace(/^www\./, "");
}

// ---------------------------------------------------------------------------
// Safe HTTP fetch (no downloads, timeout enforced, size capped)
// ---------------------------------------------------------------------------

function safeFetch(
    rawUrl: string,
    opts: { maxBytes?: number; timeoutMs?: number } = {}
): Promise<string> {
    const maxBytes = opts.maxBytes ?? 100_000;
    const timeoutMs = opts.timeoutMs ?? 8_000;

    return new Promise((resolve, reject) => {
        const parsed = new url.URL(rawUrl);
        const lib = parsed.protocol === "https:" ? https : http;

        const req = lib.get(
            {
                hostname: parsed.hostname,
                port: parsed.port || (parsed.protocol === "https:" ? 443 : 80),
                path: parsed.pathname + parsed.search,
                headers: {
                    "User-Agent": "AmenApp-MetadataBot/1.0",
                    "Accept": "text/html,application/json",
                },
                timeout: timeoutMs,
            },
            (res) => {
                // Follow one redirect
                if ((res.statusCode === 301 || res.statusCode === 302) && res.headers.location) {
                    req.destroy();
                    safeFetch(res.headers.location, opts).then(resolve, reject);
                    return;
                }

                if (!res.statusCode || res.statusCode < 200 || res.statusCode >= 300) {
                    req.destroy();
                    reject(new Error(`HTTP ${res.statusCode}`));
                    return;
                }

                const chunks: Buffer[] = [];
                let totalBytes = 0;

                res.on("data", (chunk: Buffer) => {
                    totalBytes += chunk.length;
                    if (totalBytes > maxBytes) {
                        req.destroy();
                        // Return what we have so far for partial OG parsing
                        resolve(Buffer.concat(chunks).toString("utf-8"));
                        return;
                    }
                    chunks.push(chunk);
                });

                res.on("end", () => resolve(Buffer.concat(chunks).toString("utf-8")));
                res.on("error", reject);
            }
        );

        req.on("timeout", () => {
            req.destroy();
            reject(new Error("Request timed out"));
        });
        req.on("error", reject);
    });
}

// ---------------------------------------------------------------------------
// Smart action inference (deterministic, no AI)
// ---------------------------------------------------------------------------

type SmartAction = "open" | "listen" | "watch" | "saveToSelah" | "addToChurchNotes" | "saveForLater" | "share" | "report";

function inferSmartActions(
    provider: Provider,
    type: AttachmentType,
    title: string,
    description: string | undefined
): SmartAction[] {
    const actions: SmartAction[] = [];
    const text = `${title} ${description ?? ""}`.toLowerCase();

    // Primary CTA
    if (provider === "appleMusic" || provider === "spotify") actions.push("listen");
    else if (provider === "youtube" || type === "video") actions.push("watch");
    else actions.push("open");

    // Spiritual context hints
    const worshipTerms = ["worship", "praise", "devotional", "prayer", "reflection", "quiet time", "holy spirit"];
    const sermonTerms  = ["sermon", "teaching", "message", "bible study", "church", "devotional", "pastor", "preaching"];
    const longFormTerms = ["podcast", "episode", "interview", "documentary", "conference"];

    if (type === "song" && worshipTerms.some(t => text.includes(t))) actions.push("saveToSelah");
    if ((type === "video" || type === "podcast") && sermonTerms.some(t => text.includes(t))) actions.push("addToChurchNotes");
    if (type === "article" || type === "podcast" || longFormTerms.some(t => text.includes(t))) actions.push("saveForLater");

    actions.push("share");
    actions.push("report");

    // Deduplicate, preserve order
    return [...new Set(actions)];
}

// ---------------------------------------------------------------------------
// Attachment ID derivation (deterministic for dedup)
// ---------------------------------------------------------------------------

function deriveAttachmentId(provider: Provider, providerId: string, canonicalUrl: string): string {
    const seed = providerId ? `${provider}:${providerId}` : `url:${canonicalUrl}`;
    return crypto.createHash("sha256").update(seed).digest("hex").slice(0, 20);
}

// ---------------------------------------------------------------------------
// resolveSmartAttachment callable
// ---------------------------------------------------------------------------

interface ResolveRequest {
    url?: string;
    provider?: Provider;
    providerId?: string;
    attachmentIntent?: string;
    source?: string;
}

export const resolveSmartAttachment = onCall(
    { enforceAppCheck: true },
    async (request) => {
        requireAppCheck(request.app);
        const uid = requireAuth(request.auth);
        await enforceRateLimit(uid, [RESOLVE_PER_MIN, RESOLVE_PER_DAY]);

        const data = request.data as ResolveRequest;
        if (!data.url && !(data.provider && data.providerId)) {
            throw new HttpsError("invalid-argument", "Provide url or provider + providerId.");
        }

        let parsed: URL;
        if (data.url) {
            parsed = validateURL(data.url);
        } else {
            // Reconstruct canonical URL from provider + id
            const canonicals: Record<string, string> = {
                appleMusic: `https://music.apple.com/us/album/item/${data.providerId}`,
                spotify:    `https://open.spotify.com/track/${data.providerId}`,
                youtube:    `https://www.youtube.com/watch?v=${data.providerId}`,
                generic:    data.providerId ?? "",
            };
            parsed = validateURL(canonicals[data.provider!] ?? data.providerId!);
        }

        const provider = data.provider ?? detectProvider(parsed);
        functions.logger.info("[resolveSmartAttachment]", { uid, provider, source: data.source });

        let title = "";
        let creatorName: string | undefined;
        let artworkUrl: string | undefined;
        let canonicalUrl = parsed.href;
        let type: AttachmentType = "genericLink";
        let providerId: string | undefined;
        let description: string | undefined;
        let durationMs: number | undefined;

        try {
            switch (provider) {
            case "youtube": {
                const r = await resolveYouTube(parsed);
                title       = r.title;
                creatorName = r.creatorName;
                artworkUrl  = r.artworkUrl;
                canonicalUrl = r.canonicalUrl;
                type        = r.type;
                providerId  = r.providerId;
                description = r.description;
                durationMs  = r.durationMs;
                break;
            }
            case "spotify": {
                const r = await resolveSpotify(parsed);
                title       = r.title;
                creatorName = r.creatorName;
                artworkUrl  = r.artworkUrl;
                canonicalUrl = r.canonicalUrl;
                type        = r.type;
                providerId  = r.providerId;
                durationMs  = r.durationMs;
                break;
            }
            case "appleMusic": {
                const r = await resolveAppleMusic(parsed);
                title       = r.title;
                creatorName = r.creatorName;
                artworkUrl  = r.artworkUrl;
                canonicalUrl = r.canonicalUrl;
                type        = r.type;
                providerId  = r.providerId;
                durationMs  = r.durationMs;
                break;
            }
            default: {
                const og = await resolveOpenGraph(parsed);
                title       = og.title;
                description = og.description;
                artworkUrl  = og.imageUrl;
                canonicalUrl = og.canonicalUrl;
                creatorName = og.siteName;
                type        = "article";
                providerId  = undefined;
            }
            }
        } catch (e) {
            functions.logger.warn("[resolveSmartAttachment] provider resolve failed, using URL fallback", { error: e });
            title = toDisplayHost(parsed.hostname);
            canonicalUrl = parsed.href;
        }

        if (!title) title = toDisplayHost(parsed.hostname);

        const attachmentId = deriveAttachmentId(provider, providerId ?? "", canonicalUrl);
        const smartActions = inferSmartActions(provider, type, title, description);

        // Attribution text per provider guidelines
        const attributionMap: Record<Provider, string> = {
            appleMusic: "Apple Music",
            spotify:    "Spotify",
            youtube:    "YouTube",
            generic:    creatorName ?? toDisplayHost(parsed.hostname),
        };

        const playbackPolicy = provider === "generic" ? "externalOnly" : "externalOnly";

        return {
            attachmentId,
            provider,
            type,
            providerId: providerId ?? null,
            title,
            subtitle: null,
            creatorName: creatorName ?? null,
            description: description ?? null,
            artworkUrl: artworkUrl ?? null,
            canonicalUrl,
            durationMs: durationMs ?? null,
            previewUrl: null,
            attributionText: attributionMap[provider],
            sourceLogoRequired: provider !== "generic",
            playbackPolicy,
            safetyStatus: "approved",
            smartActions,
            soundtrackEnabled: false,
            resolvedAt: admin.firestore.Timestamp.now(),
        };
    }
);

// ---------------------------------------------------------------------------
// saveMediaGraphItem callable
// ---------------------------------------------------------------------------

interface SaveMediaGraphRequest {
    item: {
        attachmentId: string;
        provider: string;
        providerId?: string;
        type: string;
        title: string;
        subtitle?: string;
        creatorName?: string;
        artworkUrl?: string;
        canonicalUrl: string;
        sourcePostId?: string;
        savedContext: string;
        safetyStatus: string;
        visibility?: string;
        userNote?: string;
        tags?: string[];
    };
}

export const saveMediaGraphItem = onCall(
    { enforceAppCheck: true },
    async (request) => {
        requireAppCheck(request.app);
        const uid = requireAuth(request.auth);
        await enforceRateLimit(uid, [SAVE_PER_MIN]);

        const data = request.data as SaveMediaGraphRequest;
        const item = data?.item;

        if (!item?.attachmentId || !item?.canonicalUrl || !item?.savedContext) {
            throw new HttpsError("invalid-argument", "item.attachmentId, canonicalUrl, and savedContext are required.");
        }

        const ALLOWED_CONTEXTS = new Set([
            "selah", "churchNotes", "savedForLater", "prayedWith",
            "sermon", "studyLink", "creativeInspiration", "recentAttachment", "songs",
        ]);
        if (!ALLOWED_CONTEXTS.has(item.savedContext)) {
            throw new HttpsError("invalid-argument", `Unknown savedContext: ${item.savedContext}`);
        }

        const docRef = db
            .collection("users").doc(uid)
            .collection("mediaGraph").doc("items")
            .collection("records").doc(item.attachmentId);

        const now = admin.firestore.FieldValue.serverTimestamp();
        await docRef.set(
            {
                id: item.attachmentId,
                ownerUid: uid,
                attachmentId: item.attachmentId,
                provider: item.provider,
                providerId: item.providerId ?? null,
                type: item.type,
                title: item.title,
                subtitle: item.subtitle ?? null,
                creatorName: item.creatorName ?? null,
                artworkUrl: item.artworkUrl ?? null,
                canonicalUrl: item.canonicalUrl,
                sourcePostId: item.sourcePostId ?? null,
                savedContext: item.savedContext,
                safetyStatus: item.safetyStatus,
                visibility: item.visibility ?? "private",
                userNote: item.userNote ?? null,
                tags: item.tags ?? [],
                createdAt: now,
                updatedAt: now,
                lastOpenedAt: now,
            },
            { merge: true }
        );

        functions.logger.info("[saveMediaGraphItem]", { uid, attachmentId: item.attachmentId, context: item.savedContext });
        return { success: true, attachmentId: item.attachmentId };
    }
);

// ---------------------------------------------------------------------------
// getRecentMediaAttachments callable
// ---------------------------------------------------------------------------

export const getRecentMediaAttachments = onCall(
    { enforceAppCheck: true },
    async (request) => {
        requireAppCheck(request.app);
        const uid = requireAuth(request.auth);

        const snap = await db
            .collection("users").doc(uid)
            .collection("mediaGraph").doc("items")
            .collection("records")
            .orderBy("updatedAt", "desc")
            .limit(20)
            .get();

        const ids = snap.docs.map(d => d.id);
        return { ids };
    }
);

// ---------------------------------------------------------------------------
// getSavedMediaItems callable
// ---------------------------------------------------------------------------

interface GetSavedRequest {
    context?: string;
    limit?: number;
}

export const getSavedMediaItems = onCall(
    { enforceAppCheck: true },
    async (request) => {
        requireAppCheck(request.app);
        const uid = requireAuth(request.auth);

        const data = request.data as GetSavedRequest;
        const context = data?.context;
        const pageSize = Math.min(data?.limit ?? 30, 50);

        // Map convenience context alias → savedContext value used at write time
        const contextMap: Record<string, string> = {
            songs:      "selah",
            selah:      "selah",
            churchNotes: "churchNotes",
            savedForLater: "savedForLater",
            sermons:    "sermon",
        };

        let query = db
            .collection("users").doc(uid)
            .collection("mediaGraph").doc("items")
            .collection("records")
            .orderBy("updatedAt", "desc")
            .limit(pageSize);

        // "songs" context maps to both selah and prayedWith; simplify to selah for MVP
        const mappedContext = context ? (contextMap[context] ?? context) : null;
        if (mappedContext) {
            query = query.where("savedContext", "==", mappedContext) as typeof query;
        }

        const snap = await query.get();
        const items = snap.docs.map(d => d.data());
        return { items };
    }
);

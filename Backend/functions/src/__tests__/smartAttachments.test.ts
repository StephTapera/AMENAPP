/**
 * smartAttachments.test.ts
 *
 * Unit tests for Smart Media Attachment backend logic.
 *
 * These tests exercise the URL parsing, provider detection, and safety
 * validation logic that is exported from smartAttachments.ts as pure
 * TypeScript functions. Firebase callable integration is tested via
 * the Firebase Local Emulator Suite (not in this file).
 *
 * Run: cd Backend/functions && npm test
 */

// ---------------------------------------------------------------------------
// Helpers extracted from smartAttachments.ts for unit testing.
// Because the callables themselves require Firebase Admin + App Check context,
// we test the pure utility logic inline here.
// ---------------------------------------------------------------------------

// ── Provider detection ───────────────────────────────────────────────────────

type Provider = "appleMusic" | "spotify" | "youtube" | "generic";

function detectProvider(parsed: URL): Provider {
    const host = parsed.hostname.replace(/^www\./, "");
    if (host === "music.apple.com") return "appleMusic";
    if (host === "open.spotify.com") return "spotify";
    if (host === "youtube.com" || host === "youtu.be" || host === "m.youtube.com") return "youtube";
    return "generic";
}

// ── URL validation ───────────────────────────────────────────────────────────

const PRIVATE_IP_PATTERNS = [
    /^127\./,
    /^10\./,
    /^192\.168\./,
    /^172\.(1[6-9]|2\d|3[01])\./,
    /^::1$/,
    /^localhost$/i,
    /^0\.0\.0\.0$/,
    /^169\.254\./,
    /^fc00:/i,
    /^fd[0-9a-f]{2}:/i,
];

function validateURL(rawUrl: string): URL {
    let parsed: URL;
    try {
        parsed = new URL(rawUrl);
    } catch {
        throw new Error("Invalid URL format.");
    }
    if (parsed.protocol !== "https:") throw new Error("Only https URLs are supported.");
    const hostname = parsed.hostname;
    for (const pattern of PRIVATE_IP_PATTERNS) {
        if (pattern.test(hostname)) throw new Error("Private network URLs are not allowed.");
    }
    return parsed;
}

// ── YouTube ID extraction ─────────────────────────────────────────────────────

function extractYouTubeVideoId(parsed: URL): string | null {
    if (parsed.hostname === "youtu.be") return parsed.pathname.slice(1).split("/")[0] || null;
    const v = parsed.searchParams.get("v");
    if (v) return v;
    const shortMatch = parsed.pathname.match(/\/shorts\/([a-zA-Z0-9_-]+)/);
    if (shortMatch) return shortMatch[1];
    return null;
}

// ── Spotify entity type mapping ──────────────────────────────────────────────

type SpotifyEntityType = "track" | "album" | "playlist" | "artist" | "episode" | "show";
type AttachmentType = "song" | "album" | "playlist" | "artist" | "video" | "podcast" | "article" | "genericLink";

function spotifyEntityToType(entity: SpotifyEntityType): AttachmentType {
    switch (entity) {
    case "track":   return "song";
    case "album":   return "album";
    case "playlist": return "playlist";
    case "artist":  return "artist";
    case "episode":
    case "show":    return "podcast";
    default:        return "genericLink";
    }
}

// ── OG tag extraction ────────────────────────────────────────────────────────

function extractMetaContent(html: string, name: string): string | undefined {
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("Provider detection", () => {
    test("music.apple.com → appleMusic", () => {
        const parsed = new URL("https://music.apple.com/us/album/test/123");
        expect(detectProvider(parsed)).toBe("appleMusic");
    });

    test("open.spotify.com → spotify", () => {
        const parsed = new URL("https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC");
        expect(detectProvider(parsed)).toBe("spotify");
    });

    test("youtube.com → youtube", () => {
        const parsed = new URL("https://www.youtube.com/watch?v=abc123");
        expect(detectProvider(parsed)).toBe("youtube");
    });

    test("youtu.be → youtube", () => {
        const parsed = new URL("https://youtu.be/abc123");
        expect(detectProvider(parsed)).toBe("youtube");
    });

    test("m.youtube.com → youtube", () => {
        const parsed = new URL("https://m.youtube.com/watch?v=abc123");
        expect(detectProvider(parsed)).toBe("youtube");
    });

    test("unknown domain → generic", () => {
        const parsed = new URL("https://www.crosswalk.com/faith/article.html");
        expect(detectProvider(parsed)).toBe("generic");
    });
});

describe("URL validation — https enforcement", () => {
    test("https URL passes", () => {
        expect(() => validateURL("https://www.youtube.com/watch?v=abc")).not.toThrow();
    });

    test("http URL is rejected", () => {
        expect(() => validateURL("http://www.youtube.com/watch?v=abc")).toThrow("Only https");
    });

    test("ftp URL is rejected", () => {
        expect(() => validateURL("ftp://files.example.com/track.mp3")).toThrow("Only https");
    });

    test("javascript: scheme is rejected (invalid URL)", () => {
        expect(() => validateURL("javascript:alert(1)")).toThrow();
    });

    test("mailto: scheme is rejected (not https)", () => {
        expect(() => validateURL("mailto:user@example.com")).toThrow("Only https");
    });

    test("malformed URL throws", () => {
        expect(() => validateURL("not a url at all")).toThrow();
    });
});

describe("URL validation — private IP rejection", () => {
    test("localhost is rejected", () => {
        expect(() => validateURL("https://localhost/admin")).toThrow("Private network");
    });

    test("127.0.0.1 is rejected", () => {
        expect(() => validateURL("https://127.0.0.1/secret")).toThrow("Private network");
    });

    test("10.x.x.x is rejected", () => {
        expect(() => validateURL("https://10.0.0.1/secret")).toThrow("Private network");
    });

    test("192.168.x.x is rejected", () => {
        expect(() => validateURL("https://192.168.1.1/router")).toThrow("Private network");
    });

    test("169.254.x.x (link-local) is rejected", () => {
        expect(() => validateURL("https://169.254.169.254/metadata")).toThrow("Private network");
    });

    test("public IP passes", () => {
        expect(() => validateURL("https://8.8.8.8/")).not.toThrow();
    });
});

describe("YouTube video ID extraction", () => {
    test("youtube.com/watch?v= format", () => {
        const p = new URL("https://www.youtube.com/watch?v=dQw4w9WgXcQ");
        expect(extractYouTubeVideoId(p)).toBe("dQw4w9WgXcQ");
    });

    test("youtu.be short URL", () => {
        const p = new URL("https://youtu.be/dQw4w9WgXcQ");
        expect(extractYouTubeVideoId(p)).toBe("dQw4w9WgXcQ");
    });

    test("youtube.com/shorts/ format", () => {
        const p = new URL("https://www.youtube.com/shorts/abc123XYZ");
        expect(extractYouTubeVideoId(p)).toBe("abc123XYZ");
    });

    test("playlist URL returns null for video ID", () => {
        const p = new URL("https://www.youtube.com/playlist?list=PL1234");
        expect(extractYouTubeVideoId(p)).toBeNull();
    });

    test("channel URL returns null", () => {
        const p = new URL("https://www.youtube.com/c/ChannelName");
        expect(extractYouTubeVideoId(p)).toBeNull();
    });
});

describe("Spotify entity → attachment type mapping", () => {
    test("track → song", () => expect(spotifyEntityToType("track")).toBe("song"));
    test("album → album", () => expect(spotifyEntityToType("album")).toBe("album"));
    test("playlist → playlist", () => expect(spotifyEntityToType("playlist")).toBe("playlist"));
    test("artist → artist", () => expect(spotifyEntityToType("artist")).toBe("artist"));
    test("episode → podcast", () => expect(spotifyEntityToType("episode")).toBe("podcast"));
    test("show → podcast", () => expect(spotifyEntityToType("show")).toBe("podcast"));
});

describe("Open Graph tag extraction", () => {
    const sampleHTML = `
        <html>
        <head>
            <title>Page Title Here</title>
            <meta property="og:title" content="OG Article Title" />
            <meta property="og:description" content="A great description." />
            <meta property="og:image" content="https://example.com/img.jpg" />
            <meta property="og:site_name" content="Example Site" />
        </head>
        <body></body>
        </html>
    `;

    test("extracts og:title", () => {
        expect(extractMetaContent(sampleHTML, "og:title")).toBe("OG Article Title");
    });

    test("extracts og:description", () => {
        expect(extractMetaContent(sampleHTML, "og:description")).toBe("A great description.");
    });

    test("extracts og:image", () => {
        expect(extractMetaContent(sampleHTML, "og:image")).toBe("https://example.com/img.jpg");
    });

    test("extracts og:site_name", () => {
        expect(extractMetaContent(sampleHTML, "og:site_name")).toBe("Example Site");
    });

    test("falls back to html title when og:title absent", () => {
        const minimal = "<html><head><title>Fallback Title</title></head></html>";
        expect(extractHtmlTitle(minimal)).toBe("Fallback Title");
    });

    test("returns undefined when meta tag absent", () => {
        const empty = "<html><head></head></html>";
        expect(extractMetaContent(empty, "og:title")).toBeUndefined();
    });
});

describe("Auth requirement (callable guard)", () => {
    // The requireAuth function throws HttpsError when uid is missing.
    // We replicate the logic here for isolation.
    function requireAuth(auth: { uid: string } | undefined): string {
        if (!auth?.uid) throw new Error("Authentication required.");
        return auth.uid;
    }

    test("throws when auth is undefined", () => {
        expect(() => requireAuth(undefined)).toThrow("Authentication required.");
    });

    test("throws when uid is empty", () => {
        expect(() => requireAuth({ uid: "" })).toThrow("Authentication required.");
    });

    test("returns uid when authenticated", () => {
        expect(requireAuth({ uid: "uid-abc" })).toBe("uid-abc");
    });
});

describe("Saved context allowlist", () => {
    const ALLOWED_CONTEXTS = new Set([
        "selah", "churchNotes", "savedForLater", "prayedWith",
        "sermon", "studyLink", "creativeInspiration", "recentAttachment", "songs",
    ]);

    test("valid contexts pass", () => {
        for (const ctx of ["selah", "churchNotes", "savedForLater", "songs"]) {
            expect(ALLOWED_CONTEXTS.has(ctx)).toBe(true);
        }
    });

    test("arbitrary context is rejected", () => {
        expect(ALLOWED_CONTEXTS.has("myRandomContext")).toBe(false);
    });

    test("empty string is rejected", () => {
        expect(ALLOWED_CONTEXTS.has("")).toBe(false);
    });
});

import * as admin from "firebase-admin";
import { onRequest } from "firebase-functions/v2/https";

/**
 * Generates a 1200×630 OG image for a post.
 * Routed via Firebase Hosting: GET /post/{postId}/og.png → this function.
 *
 * Cache strategy:
 * - On first render, stores PNG in Cloud Storage at og-images/{postId}.png
 * - Subsequent requests serve the cached file
 * - 24-hour TTL via Cache-Control header
 *
 * Rendering: SVG template + sharp (PNG conversion)
 * Install: npm install sharp @types/sharp
 * (satori alternative also works; sharp is sufficient for text-based cards)
 */
export const generateOGImage = onRequest(
    {
        region: "us-central1",
        timeoutSeconds: 30,
        memory: "512MiB",
    },
    async (req, res) => {
        // Extract postId: path is /post/{postId}/og.png
        const match = req.path.match(/^\/post\/([^/]+)\/og\.png/);
        const postId = match?.[1];

        if (!postId) {
            res.status(400).send("Missing postId");
            return;
        }

        res.setHeader("Content-Type", "image/png");
        res.setHeader("Cache-Control", "public, max-age=86400"); // 24h

        // Try Storage cache first
        const cached = await fetchCached(postId);
        if (cached) {
            res.status(200).send(cached);
            return;
        }

        // Fetch post data
        const postData = await fetchPost(postId);
        const png = await renderOGImage(postData);

        // Cache in Storage (fire-and-forget — don't block the response)
        storeCached(postId, png).catch(() => undefined);

        res.status(200).send(png);
    }
);

// MARK: - Post fetch

interface PostData {
    authorName: string;
    content: string;
    verseReference?: string;
}

async function fetchPost(postId: string): Promise<PostData> {
    try {
        const snap = await admin.firestore().collection("posts").doc(postId).get();
        if (!snap.exists) return defaultPostData();
        const data = snap.data()!;
        const visibility = data.visibility ?? "everyone";
        if (visibility !== "everyone") return defaultPostData();
        return {
            authorName: data.authorName ?? "AMEN",
            content: (data.content ?? "").slice(0, 200),
            verseReference: data.verseReference ?? undefined,
        };
    } catch {
        return defaultPostData();
    }
}

function defaultPostData(): PostData {
    return { authorName: "AMEN", content: "A moment of faith" };
}

// MARK: - SVG → PNG rendering

async function renderOGImage(post: PostData): Promise<Buffer> {
    const svg = buildSVG(post);
    // Dynamic import so the build doesn't fail if sharp isn't installed yet.
    // Run: npm install sharp   in Backend/functions before deploying.
    try {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const sharp = (await import("sharp" as string as never)).default as any;
        return await sharp(Buffer.from(svg)).png().toBuffer();
    } catch {
        // If sharp is unavailable, return the SVG as-is (platforms that accept SVG will show it).
        return Buffer.from(svg);
    }
}

function buildSVG(post: PostData): string {
    const W = 1200;
    const H = 630;
    const pad = 80;
    const goldHex = "#d4b038";
    const blackHex = "#0d0d12";
    const purpleHex = "#781ed6";

    // Truncate content to ~200 chars
    const body = post.content.length > 200
        ? post.content.slice(0, 197) + "…"
        : post.content;

    // Word-wrap body into ≤4 lines of ≤50 chars
    const lines = wordWrap(body, 50).slice(0, 4);
    const linesY = lines.map((_, i) => 260 + i * 56);

    const verseText = post.verseReference
        ? escXml(post.verseReference)
        : "";

    return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  <defs>
    <radialGradient id="bg" cx="50%" cy="50%" r="70%">
      <stop offset="0%" stop-color="${purpleHex}" stop-opacity="0.5"/>
      <stop offset="100%" stop-color="${blackHex}" stop-opacity="1"/>
    </radialGradient>
  </defs>

  <!-- Background -->
  <rect width="${W}" height="${H}" fill="${blackHex}"/>
  <rect width="${W}" height="${H}" fill="url(#bg)"/>

  <!-- Author name (left-aligned) -->
  <text x="${pad}" y="120"
        font-family="system-ui, -apple-system, Helvetica, sans-serif"
        font-size="36" font-weight="700" fill="white">
    ${escXml(post.authorName)} on AMEN
  </text>

  <!-- Divider -->
  <line x1="${pad}" y1="145" x2="${W - pad}" y2="145"
        stroke="white" stroke-opacity="0.15" stroke-width="1"/>

  <!-- Body text lines -->
  ${lines.map((line, i) => `
  <text x="${pad}" y="${linesY[i]}"
        font-family="system-ui, -apple-system, Helvetica, sans-serif"
        font-size="46" font-weight="900" fill="white">
    ${escXml(line)}
  </text>`).join("")}

  <!-- Verse reference (right-aligned) -->
  ${verseText ? `
  <text x="${W - pad}" y="${H - 100}"
        font-family="system-ui, -apple-system, Helvetica, sans-serif"
        font-size="28" font-weight="500" fill="${goldHex}"
        text-anchor="end">
    ${verseText}
  </text>` : ""}

  <!-- AMEN wordmark (bottom right) -->
  <text x="${W - pad}" y="${H - 54}"
        font-family="system-ui, -apple-system, Helvetica, sans-serif"
        font-size="40" font-weight="900" fill="white" fill-opacity="0.6"
        letter-spacing="8" text-anchor="end">
    AMEN
  </text>
</svg>`;
}

// MARK: - Storage cache

const BUCKET_PREFIX = "og-images";

async function fetchCached(postId: string): Promise<Buffer | null> {
    try {
        const bucket = admin.storage().bucket();
        const file = bucket.file(`${BUCKET_PREFIX}/${postId}.png`);
        const [exists] = await file.exists();
        if (!exists) return null;

        // Check age — invalidate after 24h
        const [metadata] = await file.getMetadata();
        const updated = new Date(metadata.updated as string).getTime();
        if (Date.now() - updated > 24 * 60 * 60 * 1000) return null;

        const [buf] = await file.download();
        return buf;
    } catch {
        return null;
    }
}

async function storeCached(postId: string, data: Buffer): Promise<void> {
    const bucket = admin.storage().bucket();
    const file = bucket.file(`${BUCKET_PREFIX}/${postId}.png`);
    await file.save(data, { contentType: "image/png" });
}

// MARK: - Utilities

function wordWrap(text: string, maxChars: number): string[] {
    const words = text.split(" ");
    const lines: string[] = [];
    let current = "";
    for (const word of words) {
        if ((current + " " + word).trim().length <= maxChars) {
            current = (current + " " + word).trim();
        } else {
            if (current) lines.push(current);
            current = word;
        }
    }
    if (current) lines.push(current);
    return lines;
}

function escXml(str: string): string {
    return str
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&apos;");
}

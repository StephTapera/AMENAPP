/**
 * composerAttachments.ts
 *
 * AMEN Adaptive Composer — backend callables for rich attachment types.
 *
 * Callables exported:
 *   unfurlLink              — fetch OG meta for a URL, cache 24h in Firestore
 *   generateCalendarPayload — build a downloadable iCal VCALENDAR/VEVENT string
 *   incrementVolunteerSlot  — atomically sign up for a volunteer slot on a post
 *   aggregatePrayerCount    — atomically increment a prayer-type attachment's prayCount
 *
 * Security:
 *   - All callables require Firebase Auth.
 *   - All callables enforce App Check (enforceAppCheck: true).
 *   - unfurlLink: only http/https URLs accepted; no private/loopback network addresses.
 *   - incrementVolunteerSlot: duplicate sign-ups rejected via Firestore transaction.
 *   - aggregatePrayerCount: attachment type verified before increment.
 *   - No raw user content is stored in server-side caches; only resolved OG metadata.
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as crypto from "crypto";
import * as https from "https";
import * as http from "http";

const db = admin.firestore;

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

function requireAuth(request: { auth?: { uid: string } }): string {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

// Private / loopback address patterns — used to prevent SSRF in unfurlLink
const PRIVATE_IP_PATTERNS: RegExp[] = [
  /^127\./,
  /^10\./,
  /^192\.168\./,
  /^172\.(1[6-9]|2\d|3[01])\./,
  /^::1$/,
  /^localhost$/i,
  /^0\.0\.0\.0$/,
  /^169\.254\./, // link-local
  /^fc00:/i, // IPv6 ULA
  /^fd[0-9a-f]{2}:/i,
];

function validateHttpUrl(rawUrl: string): URL {
  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch {
    throw new HttpsError("invalid-argument", "Invalid URL format.");
  }

  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new HttpsError(
      "invalid-argument",
      "Only http and https URLs are supported."
    );
  }

  const hostname = parsed.hostname;
  for (const pattern of PRIVATE_IP_PATTERNS) {
    if (pattern.test(hostname)) {
      throw new HttpsError(
        "invalid-argument",
        "Private network URLs are not allowed."
      );
    }
  }

  return parsed;
}

// ---------------------------------------------------------------------------
// 1. unfurlLink
// ---------------------------------------------------------------------------

interface LinkPreview {
  title: string;
  description: string;
  imageURL: string;
  domain: string;
}

/**
 * Fetch raw HTML from a URL using Node's built-in http/https modules
 * (no third-party dependencies required).
 */
function fetchHtml(rawUrl: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const parsed = new URL(rawUrl);
    const lib = parsed.protocol === "https:" ? https : http;

    const options = {
      hostname: parsed.hostname,
      path: parsed.pathname + parsed.search,
      method: "GET",
      headers: {
        "User-Agent":
          "Mozilla/5.0 (compatible; AMENBot/1.0; +https://amenapp.com/bot)",
        Accept: "text/html,application/xhtml+xml",
      },
      timeout: 8000,
    };

    const req = lib.request(options, (res) => {
      // Follow a single redirect (301/302/307/308)
      if (
        res.statusCode &&
        res.statusCode >= 300 &&
        res.statusCode < 400 &&
        res.headers.location
      ) {
        fetchHtml(res.headers.location).then(resolve).catch(reject);
        return;
      }

      if (!res.statusCode || res.statusCode < 200 || res.statusCode >= 400) {
        reject(new Error(`HTTP ${res.statusCode ?? "unknown"} from ${rawUrl}`));
        return;
      }

      const chunks: Buffer[] = [];
      let totalBytes = 0;
      const MAX_BYTES = 512 * 1024; // 512 KB cap

      res.on("data", (chunk: Buffer) => {
        totalBytes += chunk.length;
        if (totalBytes > MAX_BYTES) {
          req.destroy();
          resolve(Buffer.concat(chunks).toString("utf8"));
          return;
        }
        chunks.push(chunk);
      });

      res.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    });

    req.on("error", reject);
    req.on("timeout", () => {
      req.destroy();
      reject(new Error("Request timed out."));
    });

    req.end();
  });
}

/**
 * Extract OG / fallback meta from raw HTML.
 * Uses simple regex extraction — no DOM parser dependency needed.
 */
function extractMeta(html: string, domain: string): LinkPreview {
  const metaTagRe =
    /<meta\s+(?:[^>]*?\s)?(?:property|name)="([^"]+)"\s+content="([^"]*)"[^>]*>/gi;
  const metaTagReAlt =
    /<meta\s+(?:[^>]*?\s)?content="([^"]*)"\s+(?:property|name)="([^"]+)"[^>]*>/gi;
  const titleTagRe = /<title[^>]*>([^<]*)<\/title>/i;

  const meta: Record<string, string> = {};

  let match: RegExpExecArray | null;
  while ((match = metaTagRe.exec(html)) !== null) {
    meta[match[1].toLowerCase()] = match[2];
  }
  while ((match = metaTagReAlt.exec(html)) !== null) {
    meta[match[2].toLowerCase()] = match[1];
  }

  const titleMatch = titleTagRe.exec(html);
  const fallbackTitle = titleMatch ? titleMatch[1].trim() : domain;

  return {
    title:
      meta["og:title"] || meta["twitter:title"] || fallbackTitle || domain,
    description: meta["og:description"] || meta["description"] || "",
    imageURL: meta["og:image"] || meta["twitter:image"] || "",
    domain,
  };
}

/**
 * unfurlLink — validates a URL, fetches its OG meta tags, caches the result
 * for 24 hours in Firestore /linkPreviews/{sha256hash}.
 *
 * @param data.url  The URL to unfurl (must be http or https)
 * @returns         { title, description, imageURL, domain }
 */
export const unfurlLink = onCall(
  { enforceAppCheck: true },
  async (request) => {
    requireAuth(request);

    const { url: rawUrl } = request.data as { url?: string };
    if (!rawUrl || typeof rawUrl !== "string") {
      throw new HttpsError("invalid-argument", "url is required.");
    }

    const parsed = validateHttpUrl(rawUrl);
    const domain = parsed.hostname.replace(/^www\./, "");

    // Stable, order-independent cache key
    const hash = crypto
      .createHash("sha256")
      .update(rawUrl.trim())
      .digest("hex");

    const cacheRef = db().collection("linkPreviews").doc(hash);

    // Return cached result if still valid (< 24 h)
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data() as LinkPreview & { cachedAt: admin.firestore.Timestamp };
      const ageMs =
        Date.now() - (data.cachedAt?.toMillis?.() ?? 0);
      if (ageMs < 24 * 60 * 60 * 1000) {
        return {
          title: data.title,
          description: data.description,
          imageURL: data.imageURL,
          domain: data.domain,
        } satisfies LinkPreview;
      }
    }

    // Fetch fresh
    let html: string;
    try {
      html = await fetchHtml(rawUrl);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      throw new HttpsError(
        "unavailable",
        `Could not fetch URL: ${msg}`
      );
    }

    const preview = extractMeta(html, domain);

    // Cache result (best-effort write; do not fail the caller on write error)
    try {
      await cacheRef.set({
        ...preview,
        originalUrl: rawUrl,
        cachedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch {
      // Intentionally swallow cache write errors
    }

    return preview satisfies LinkPreview;
  }
);

// ---------------------------------------------------------------------------
// 2. generateCalendarPayload
// ---------------------------------------------------------------------------

interface CalendarInput {
  title: string;
  startDate: string; // ISO-8601
  endDate?: string; // ISO-8601, optional
  location?: string;
}

interface CalendarPayload {
  icalString: string;
  downloadURL: string; // data URI (base64 encoded)
}

/**
 * Convert an ISO-8601 datetime string to an iCal-formatted datetime stamp.
 * Produces UTC format: 20260611T120000Z
 */
function toICalDate(iso: string): string {
  const d = new Date(iso);
  if (isNaN(d.getTime())) {
    throw new HttpsError(
      "invalid-argument",
      `Invalid date string: ${iso}`
    );
  }
  const pad = (n: number) => String(n).padStart(2, "0");
  return (
    `${d.getUTCFullYear()}` +
    `${pad(d.getUTCMonth() + 1)}` +
    `${pad(d.getUTCDate())}` +
    `T` +
    `${pad(d.getUTCHours())}` +
    `${pad(d.getUTCMinutes())}` +
    `${pad(d.getUTCSeconds())}` +
    `Z`
  );
}

/** Escape iCal text values per RFC 5545 §3.3.11 */
function escapeICalText(text: string): string {
  return text
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\n/g, "\\n");
}

/**
 * generateCalendarPayload — builds an RFC-5545-compliant iCal VCALENDAR/VEVENT
 * string and returns it as a base64 data URI.
 *
 * @param data.title      Event title (required)
 * @param data.startDate  ISO-8601 start datetime (required)
 * @param data.endDate    ISO-8601 end datetime (optional; defaults to startDate + 1 hour)
 * @param data.location   Location string (optional)
 * @returns               { icalString, downloadURL }
 */
export const generateCalendarPayload = onCall(
  { enforceAppCheck: true },
  async (request) => {
    requireAuth(request);

    const { title, startDate, endDate, location } =
      request.data as CalendarInput;

    if (!title || typeof title !== "string" || title.trim().length === 0) {
      throw new HttpsError("invalid-argument", "title is required.");
    }
    if (!startDate || typeof startDate !== "string") {
      throw new HttpsError("invalid-argument", "startDate is required.");
    }

    const dtStart = toICalDate(startDate);

    let dtEnd: string;
    if (endDate) {
      dtEnd = toICalDate(endDate);
      // Verify end is not before start
      if (new Date(endDate) < new Date(startDate)) {
        throw new HttpsError(
          "invalid-argument",
          "endDate must be after startDate."
        );
      }
    } else {
      // Default: 1 hour after start
      const startMs = new Date(startDate).getTime();
      dtEnd = toICalDate(new Date(startMs + 60 * 60 * 1000).toISOString());
    }

    // RFC-4122 style UID using crypto random bytes
    const uid = `${crypto.randomBytes(8).toString("hex")}-${Date.now()}@amenapp.com`;

    const nowStamp = toICalDate(new Date().toISOString());

    const lines: string[] = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//AMEN App//AMEN Composer//EN",
      "CALSCALE:GREGORIAN",
      "METHOD:PUBLISH",
      "BEGIN:VEVENT",
      `UID:${uid}`,
      `DTSTAMP:${nowStamp}`,
      `DTSTART:${dtStart}`,
      `DTEND:${dtEnd}`,
      `SUMMARY:${escapeICalText(title.trim())}`,
    ];

    if (location && typeof location === "string" && location.trim().length > 0) {
      lines.push(`LOCATION:${escapeICalText(location.trim())}`);
    }

    lines.push("END:VEVENT", "END:VCALENDAR");

    // iCal line endings must be CRLF (RFC 5545 §3.1)
    const icalString = lines.join("\r\n");

    // data URI for direct client download
    const base64 = Buffer.from(icalString, "utf8").toString("base64");
    const downloadURL = `data:text/calendar;base64,${base64}`;

    return { icalString, downloadURL } satisfies CalendarPayload;
  }
);

// ---------------------------------------------------------------------------
// 3. incrementVolunteerSlot
// ---------------------------------------------------------------------------

interface VolunteerSlotResult {
  success: boolean;
  newSlotsFilled: number;
}

/**
 * incrementVolunteerSlot — atomically signs the authenticated user up for a
 * volunteer slot on a post using a Firestore transaction.
 *
 * Checks:
 *   1. The user has not already signed up (volunteerSignups/{postId}/signups/{userId}).
 *   2. The current slotsFilled < slotsTotal on the post document.
 *
 * On success, atomically increments slotsFilled and writes the signup record.
 *
 * @param data.postId  The ID of the post with a volunteer attachment
 * @returns            { success: true, newSlotsFilled }
 */
export const incrementVolunteerSlot = onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = requireAuth(request);

    const { postId } = request.data as { postId?: string };
    if (!postId || typeof postId !== "string" || postId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "postId is required.");
    }

    const firestore = db();
    const postRef = firestore.collection("posts").doc(postId);
    const signupRef = firestore
      .collection("volunteerSignups")
      .doc(postId)
      .collection("signups")
      .doc(uid);

    let newSlotsFilled: number;

    try {
      await firestore.runTransaction(async (tx) => {
        const [postSnap, signupSnap] = await Promise.all([
          tx.get(postRef),
          tx.get(signupRef),
        ]);

        if (!postSnap.exists) {
          throw new HttpsError("not-found", "Post not found.");
        }

        if (signupSnap.exists) {
          throw new HttpsError(
            "already-exists",
            "You have already signed up for this volunteer slot."
          );
        }

        const postData = postSnap.data() ?? {};
        const slotsFilled: number = postData.slotsFilled ?? 0;
        const slotsTotal: number = postData.slotsTotal ?? 0;

        if (slotsTotal <= 0) {
          throw new HttpsError(
            "failed-precondition",
            "This post does not have volunteer slots configured."
          );
        }

        if (slotsFilled >= slotsTotal) {
          throw new HttpsError(
            "resource-exhausted",
            "All volunteer slots are filled."
          );
        }

        newSlotsFilled = slotsFilled + 1;

        tx.update(postRef, { slotsFilled: newSlotsFilled });
        tx.set(signupRef, {
          userId: uid,
          postId,
          signedUpAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      throw new HttpsError(
        "internal",
        "Failed to process volunteer signup. Please try again."
      );
    }

    return {
      success: true,
      newSlotsFilled: newSlotsFilled!,
    } satisfies VolunteerSlotResult;
  }
);

// ---------------------------------------------------------------------------
// 4. aggregatePrayerCount
// ---------------------------------------------------------------------------

interface PrayerCountResult {
  newPrayCount: number;
}

/**
 * aggregatePrayerCount — atomically increments the prayCount field on a
 * prayer-type attachment inside a post document.
 *
 * Checks:
 *   1. The attachment at attachments[attachmentIndex] must have type "prayer".
 *   2. The user has not already prayed for this attachment
 *      (prayerRecords/{postId}_{attachmentIndex}_{uid}).
 *
 * On success, atomically increments the attachment's prayCount and writes
 * the prayer record.
 *
 * @param data.postId          The ID of the post
 * @param data.attachmentIndex The 0-based index into the post's attachments array
 * @returns                    { newPrayCount }
 */
export const aggregatePrayerCount = onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = requireAuth(request);

    const { postId, attachmentIndex } = request.data as {
      postId?: string;
      attachmentIndex?: number;
    };

    if (!postId || typeof postId !== "string" || postId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "postId is required.");
    }
    if (
      attachmentIndex === undefined ||
      attachmentIndex === null ||
      typeof attachmentIndex !== "number" ||
      !Number.isInteger(attachmentIndex) ||
      attachmentIndex < 0
    ) {
      throw new HttpsError(
        "invalid-argument",
        "attachmentIndex must be a non-negative integer."
      );
    }

    const firestore = db();
    const postRef = firestore.collection("posts").doc(postId);
    const recordId = `${postId}_${attachmentIndex}_${uid}`;
    const prayerRecordRef = firestore
      .collection("prayerRecords")
      .doc(recordId);

    let newPrayCount: number;

    try {
      await firestore.runTransaction(async (tx) => {
        const [postSnap, recordSnap] = await Promise.all([
          tx.get(postRef),
          tx.get(prayerRecordRef),
        ]);

        if (!postSnap.exists) {
          throw new HttpsError("not-found", "Post not found.");
        }

        if (recordSnap.exists) {
          throw new HttpsError(
            "already-exists",
            "You have already prayed for this attachment."
          );
        }

        const postData = postSnap.data() ?? {};
        const attachments: Array<Record<string, unknown>> =
          postData.attachments ?? [];

        if (attachmentIndex >= attachments.length) {
          throw new HttpsError(
            "out-of-range",
            `attachmentIndex ${attachmentIndex} is out of bounds.`
          );
        }

        const attachment = attachments[attachmentIndex];
        if (!attachment || attachment.type !== "prayer") {
          throw new HttpsError(
            "failed-precondition",
            "The specified attachment is not a prayer type."
          );
        }

        const currentPrayCount: number =
          typeof attachment.prayCount === "number" ? attachment.prayCount : 0;
        newPrayCount = currentPrayCount + 1;

        // Build the updated attachments array with the incremented prayCount
        const updatedAttachments = [...attachments];
        updatedAttachments[attachmentIndex] = {
          ...attachment,
          prayCount: newPrayCount,
        };

        tx.update(postRef, { attachments: updatedAttachments });
        tx.set(prayerRecordRef, {
          userId: uid,
          postId,
          attachmentIndex,
          prayedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      throw new HttpsError(
        "internal",
        "Failed to record prayer. Please try again."
      );
    }

    return { newPrayCount: newPrayCount! } satisfies PrayerCountResult;
  }
);

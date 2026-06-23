/**
 * amenExclusionValidator.ts
 * AMEN Universal Migration & Context System — Wave 5 (export-engineer)
 *
 * THE exclusion validator for the .amen v0.1 export (CONTRACTS.md §8). A pure,
 * deterministic, UNIT-TESTED gate — NOT a comment, NOT advisory. `exportAmenFile`
 * runs it as a HARD REJECT: any payload containing message/post structures, media
 * URLs, emails, phone numbers, or contact arrays is refused before it can leave the
 * device-owner's account in a portable file.
 *
 * Why this exists: a .amen file is a portable projection of a person's CONTEXT —
 * who they are, what matters to them — never their CONTENT or other people's data.
 * The exporter only ever assembles `public`-visibility (+ explicitly-checked) facets,
 * but this validator is the defense-in-depth backstop: even if a facet were somehow
 * smuggled with a denylisted field, the export aborts.
 *
 * Pure function, no I/O, no Firebase imports — so it is trivially unit-testable both
 * here (TS) and mirrored in Swift (AmenExclusionValidator) for the in-app path.
 *
 * Denylist (CONTRACTS §8):
 *   1. message/post STRUCTURES — keys like messages/posts/dms/thread/conversation,
 *      and message-thread text markers ("On <date> <name> wrote:", quoted ">" blocks).
 *   2. media URLs — http(s) links to media files / known media hosts.
 *   3. emails.
 *   4. phone numbers (7+ digits, dialing punctuation).
 *   5. contact arrays — keys like contacts/recipients/to/cc/bcc/addressBook,
 *      and vCard blocks.
 *
 * Output: { ok, violations[] } — violations are human-readable PATHS + reason, never
 * the offending value itself (we never echo excluded content back out).
 */

// ─── Denylisted keys (case-insensitive, exact segment match) ────────────────────

/** Object keys that, if present anywhere in the payload, indicate content/contacts. */
const DENYLISTED_KEYS: ReadonlySet<string> = new Set([
  // message / post structures
  "messages", "message", "posts", "post", "dms", "dm", "thread", "threads",
  "conversation", "conversations", "chat", "chats", "comment", "comments",
  "inbox", "outbox", "replies", "reply",
  // media
  "mediaurl", "mediaurls", "media", "attachment", "attachments",
  "imageurl", "videourl", "photourl", "avatarurl", "fileurl",
  // contacts
  "contacts", "contact", "recipients", "recipient", "to", "cc", "bcc",
  "addressbook", "phonebook", "emails", "email", "phones", "phone",
  "phonenumber", "phonenumbers", "address", "mailingaddress",
]);

// ─── Governance Wave 4 — Invariant 4 red lines (defense-in-depth) ───────────────
//
// crisis_data_export + spiritual_surveillance + spiritual_scoring are RED LINES.
// Crisis-path data and any spiritual-performance metric must never leave the
// account in a portable file. Keys are precise (scoring/surveillance field names,
// not topic words like "prayer") to avoid false positives on legitimate facets.

/** Crisis-path data is sacred — never exportable (RED LINE: crisis_data_export). */
const CRISIS_DATA_KEYS: ReadonlySet<string> = new Set([
  "crisissessionevents", "crisissessionevent", "crisisfollowups", "crisisfollowup",
  "crisisalertlogs", "crisisalertlog", "safetyplan", "crisissafetyplan",
  "selfharmflag", "selfharmrisk", "suicidalrisk", "suicideideation",
  "crisisrisk", "crisisscore", "crisisstate", "crisistriage", "trustedcontacts",
]);

/** Spiritual-performance metrics are never computed/rendered/exported
 *  (RED LINES: spiritual_surveillance, spiritual_scoring). */
const SPIRITUAL_SURVEILLANCE_KEYS: ReadonlySet<string> = new Set([
  "prayerfrequency", "prayerstreak", "prayercount", "givingamount", "givingtotal",
  "titheamount", "attendancestreak", "attendancerate", "attendancecount",
  "pietyscore", "faithfulnessscore", "faithfulnessrank", "doctrinalsoundness",
  "doctrinalsoundnessscore", "spiritualgrowthscore", "sanctificationscore",
  "holinessscore", "devotionscore", "spiritualscore", "spiritualrank",
]);

// ─── Denylisted value patterns ──────────────────────────────────────────────────

const EMAIL_RE = /[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}/i;

// Phone: optional country code, then groups of digits separated by space/dot/dash/parens,
// totaling enough to be a real number. Requires 7+ digits overall to avoid years/IDs.
const PHONE_RE =
  /(?:\+?\d{1,3}[\s.\-]?)?(?:\(?\d{2,4}\)?[\s.\-]?){2,4}\d{2,4}/;

/** Count raw digits — phone match only "counts" if 7+ digits are present. */
function digitCount(s: string): number {
  let n = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c >= 48 && c <= 57) n++;
  }
  return n;
}

// Media URL: http(s):// link ending in a media extension OR pointing at a known media host.
const MEDIA_URL_RE =
  /https?:\/\/[^\s"']+\.(?:jpg|jpeg|png|gif|webp|heic|mp4|mov|m4v|webm|mp3|m4a|wav|aac|pdf)\b/i;
const MEDIA_HOST_RE =
  /https?:\/\/(?:[a-z0-9.\-]*\.)?(?:firebasestorage\.googleapis\.com|storage\.googleapis\.com|cdn[.\-]|youtube\.com|youtu\.be|vimeo\.com|cloudinary\.com|imgur\.com|tiktok\.com|instagram\.com)\b/i;

// vCard contact block.
const VCARD_RE = /BEGIN:VCARD[\s\S]*?END:VCARD/i;

// Quoted message-thread markers.
const THREAD_MARKER_RE = /On\s+.{3,60}\s+wrote:/i;
const QUOTED_BLOCK_RE = /(^|\n)\s*>\s?.+(\n\s*>\s?.+){2,}/; // 3+ consecutive quoted lines

// ─── API ────────────────────────────────────────────────────────────────────────

export interface ExclusionResult {
  ok: boolean;
  violations: string[];
}

/**
 * Validate that `payload` contains NO excluded content. Pure + recursive over the
 * whole object graph (objects, arrays, strings). Returns every violation found
 * (path + reason). `ok === true` iff violations.length === 0.
 *
 * Never throws on shape; cyclic graphs are guarded with a seen-set.
 */
export function validateNoExcludedContent(payload: unknown): ExclusionResult {
  const violations: string[] = [];
  const seen = new WeakSet<object>();

  walk(payload, "$", violations, seen);

  return { ok: violations.length === 0, violations };
}

function walk(node: unknown, path: string, out: string[], seen: WeakSet<object>): void {
  if (node === null || node === undefined) return;

  if (typeof node === "string") {
    scanString(node, path, out);
    return;
  }

  if (typeof node === "number" || typeof node === "boolean") return;

  if (Array.isArray(node)) {
    if (seen.has(node)) return;
    seen.add(node);
    for (let i = 0; i < node.length; i++) {
      walk(node[i], `${path}[${i}]`, out, seen);
    }
    return;
  }

  if (typeof node === "object") {
    if (seen.has(node)) return;
    seen.add(node);
    for (const [key, value] of Object.entries(node as Record<string, unknown>)) {
      const normalized = key.toLowerCase().replace(/[\s_\-]/g, "");
      if (DENYLISTED_KEYS.has(normalized)) {
        out.push(`${path}.${key}: denylisted key "${key}" (content/contacts are never exportable)`);
        // Don't descend into a denylisted subtree — the key itself is the violation.
        continue;
      }
      if (CRISIS_DATA_KEYS.has(normalized)) {
        out.push(`${path}.${key}: crisis-path data "${key}" (RED LINE crisis_data_export — never leaves the account)`);
        continue;
      }
      if (SPIRITUAL_SURVEILLANCE_KEYS.has(normalized)) {
        out.push(`${path}.${key}: spiritual-performance metric "${key}" (RED LINE spiritual_surveillance/scoring — never computed or exported)`);
        continue;
      }
      walk(value, `${path}.${key}`, out, seen);
    }
  }
}

function scanString(s: string, path: string, out: string[]): void {
  if (EMAIL_RE.test(s)) {
    out.push(`${path}: contains an email address`);
  }
  if (MEDIA_URL_RE.test(s) || MEDIA_HOST_RE.test(s)) {
    out.push(`${path}: contains a media URL`);
  }
  if (VCARD_RE.test(s)) {
    out.push(`${path}: contains a vCard / contact block`);
  }
  if (THREAD_MARKER_RE.test(s) || QUOTED_BLOCK_RE.test(s)) {
    out.push(`${path}: contains a message-thread / quoted-reply structure`);
  }
  const m = s.match(PHONE_RE);
  if (m && digitCount(m[0]) >= 7) {
    out.push(`${path}: contains a phone number`);
  }
}

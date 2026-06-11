/**
 * billing/affiliateLinkWrapper.js
 * Affiliate link management for AMEN Catalog deep-links.
 *
 * POLICY (frozen contract §1):
 *   - Deep-links (Spotify, Apple Music, YouTube, Amazon product pages) are
 *     ALWAYS open=true and are NEVER gated behind any entitlement.
 *   - Only intelligence features (catalog_read, ask_creator, etc.) are gated.
 *   - Affiliate tags are read from environment variables, never hardcoded.
 *
 * Required environment variables:
 *   AMAZON_AFFILIATE_TAG      — Amazon Associates tag (e.g. "amenapp-20")
 *   BOOKSHOP_AFFILIATE_CODE   — Bookshop.org affiliate code
 *
 * Exports (Cloud Functions):
 *   enrichWorkLinks         — onCall, auth required
 *   trackAffiliateLinkClick — onCall, NO auth required (aggregate analytics)
 *
 * Internal exports (consumed by other functions):
 *   wrapAffiliateLink
 */

const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");

const db = () => admin.firestore();

// ─── Supported platforms ──────────────────────────────────────────────────────

const OPEN_PLATFORMS = ["spotify", "apple_music", "youtube"];
const AFFILIATE_PLATFORMS = ["amazon", "bookshop"];
const ALL_PLATFORMS = [...AFFILIATE_PLATFORMS, ...OPEN_PLATFORMS];

// ─── wrapAffiliateLink (internal utility) ─────────────────────────────────────

/**
 * Wraps a link with an affiliate tag where applicable.
 * Deep-links (Spotify / Apple Music / YouTube) are returned unchanged.
 * All links carry open=true — these are never gated.
 *
 * @param {{ platform: string, originalUrl: string, isbn?: string }} params
 * @returns {{ affiliateUrl: string, platform: string, open: true }}
 */
function wrapAffiliateLink({platform, originalUrl, isbn}) {
  if (!platform || !ALL_PLATFORMS.includes(platform)) {
    throw new HttpsError(
        "invalid-argument",
        `platform must be one of: ${ALL_PLATFORMS.join(", ")}`,
    );
  }
  if (!originalUrl || typeof originalUrl !== "string") {
    throw new HttpsError("invalid-argument", "originalUrl is required");
  }

  // Validate URL format (basic guard against injection)
  let parsedUrl;
  try {
    parsedUrl = new URL(originalUrl);
  } catch {
    throw new HttpsError("invalid-argument", "originalUrl must be a valid URL");
  }

  // Deep-links — always open, no wrapping
  if (OPEN_PLATFORMS.includes(platform)) {
    return {affiliateUrl: originalUrl, platform, open: true};
  }

  // Amazon Associates
  if (platform === "amazon") {
    const tag = process.env.AMAZON_AFFILIATE_TAG;
    if (!tag) {
      // OBSERVABILITY FIX (LOW 2026-06-11): Escalate to console.error so misconfiguration
      // is visible in Firebase Monitoring rather than silently losing affiliate revenue.
      console.error("affiliateLinkWrapper: AMAZON_AFFILIATE_TAG not set; affiliate revenue lost. Set the env var in Firebase Function config.");
      return {affiliateUrl: originalUrl, platform, open: true};
    }
    // Preserve existing query params; set/override the tag param
    parsedUrl.searchParams.set("tag", tag);
    return {affiliateUrl: parsedUrl.toString(), platform, open: true};
  }

  // Bookshop.org
  if (platform === "bookshop") {
    const code = process.env.BOOKSHOP_AFFILIATE_CODE;
    if (!code) {
      // OBSERVABILITY FIX (LOW 2026-06-11): Escalate to console.error for monitoring.
      console.error("affiliateLinkWrapper: BOOKSHOP_AFFILIATE_CODE not set; affiliate revenue lost. Set the env var in Firebase Function config.");
      return {affiliateUrl: originalUrl, platform, open: true};
    }
    // Bookshop affiliate URL pattern: https://bookshop.org/a/{CODE}/{isbn-or-path}
    // If the originalUrl already points to bookshop.org we prefix the affiliate code.
    // Otherwise we construct from isbn if provided.
    if (isbn) {
      const affiliateUrl = `https://bookshop.org/a/${code}/${isbn}`;
      return {affiliateUrl, platform, open: true};
    }
    // Strip the bookshop.org origin and prepend affiliate path
    const path = parsedUrl.pathname + parsedUrl.search;
    const affiliateUrl = `https://bookshop.org/a/${code}${path}`;
    return {affiliateUrl, platform, open: true};
  }

  // Fallback (should never reach here given validation above)
  return {affiliateUrl: originalUrl, platform, open: true};
}

// ─── enrichWorkLinks (CF onCall, auth required) ───────────────────────────────

const enrichWorkLinks = onCall(
    {region: "us-central1"},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const {workId} = request.data;
      if (!workId || typeof workId !== "string") {
        throw new HttpsError("invalid-argument", "workId is required");
      }

      const workRef = db().collection("catalogWorks").doc(workId);
      const workSnap = await workRef.get();

      if (!workSnap.exists) {
        throw new HttpsError("not-found", "Work not found");
      }

      const work = workSnap.data();

      // Only the work's creator may enrich links
      if (work.creatorId !== uid) {
        throw new HttpsError("permission-denied", "Only the creator may enrich this work's links");
      }

      const rawLinks = Array.isArray(work.links) ? work.links : [];
      if (rawLinks.length === 0) {
        return {links: []};
      }

      const enriched = rawLinks.map((link) => {
        // If link already has required fields, attempt wrap; otherwise pass through
        if (!link.platform || !link.url) return link;
        try {
          const wrapped = wrapAffiliateLink({
            platform: link.platform,
            originalUrl: link.url,
            isbn: link.isbn,
          });
          return {
            ...link,
            affiliateUrl: wrapped.affiliateUrl,
            open: wrapped.open,
          };
        } catch (err) {
          // Non-fatal: return original link if wrap fails
          console.error(`enrichWorkLinks: failed to wrap link for platform '${link.platform}':`, err.message);
          return {...link, open: true};
        }
      });

      await workRef.update({links: enriched});
      return {links: enriched};
    },
);

// ─── trackAffiliateLinkClick (CF onCall, NO auth required) ───────────────────

const trackAffiliateLinkClick = onCall(
    {region: "us-central1"},
    async (request) => {
      // No auth check — aggregate analytics only, no personal data stored.
      const {workId, creatorId, platform, referrer} = request.data;

      if (!workId || !creatorId || !platform) {
        throw new HttpsError(
            "invalid-argument",
            "workId, creatorId, and platform are required",
        );
      }

      if (!ALL_PLATFORMS.includes(platform)) {
        throw new HttpsError(
            "invalid-argument",
            `platform must be one of: ${ALL_PLATFORMS.join(", ")}`,
        );
      }

      // Validate referrer is a safe string (no PII)
      const safeReferrer =
        typeof referrer === "string" && referrer.length <= 500 ? referrer : null;

      await db().collection("affiliateLinkClicks").add({
        workId,
        creatorId,
        platform,
        clickedAt: admin.firestore.FieldValue.serverTimestamp(),
        referrer: safeReferrer,
        // No user ID, device ID, or IP stored — aggregate only
      });

      return {recorded: true};
    },
);

// ─── Exports ──────────────────────────────────────────────────────────────────

module.exports = {
  // Cloud Functions (onCall)
  enrichWorkLinks,
  trackAffiliateLinkClick,

  // Internal utility (consumed by other CFs)
  wrapAffiliateLink,
};

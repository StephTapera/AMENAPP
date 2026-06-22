/**
 * affiliateLinkWrapper.ts
 *
 * Server-side affiliate link wrapping for Catalog works.
 * Generates tracked deep-links for Amazon Associates and Bookshop.org.
 *
 * Product values constraints (non-negotiable):
 *   - Deep-links (Spotify listen, Apple Music listen, YouTube watch, Amazon
 *     product pages) are ALWAYS open to ALL users — never gated.
 *   - NO sponsored discovery, NO ad placement, NO paid ranking.
 *   - Affiliate wrapping is available to creator_pro+ only (as a management
 *     feature). The LINKS THEMSELVES remain publicly accessible.
 *   - Platform fee (10–20% on courses/events/memberships/digital products)
 *     is handled server-side in checkout flow — never exposed to client.
 *
 * Supported platforms for affiliate wrapping:
 *   - amazon     : Amazon Associates (requires AMAZON_ASSOCIATES_TAG secret)
 *   - bookshop   : Bookshop.org (requires BOOKSHOP_AFFILIATE_ID secret)
 *
 * Deep-link pass-through (no wrapping; always free):
 *   - spotify    : open.spotify.com listen links — returned unchanged
 *   - apple_music: music.apple.com listen links — returned unchanged
 *   - youtube    : youtube.com watch links — returned unchanged
 *
 * Deploy: us-east1 only.
 * Add to docs/FUNCTION_INVENTORY.md Interim Region Table before deploy.
 *
 * DEPLOY STEPS required before using affiliate wrapping:
 *   firebase functions:secrets:set AMAZON_ASSOCIATES_TAG
 *   firebase functions:secrets:set BOOKSHOP_AFFILIATE_ID
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import { getEntitlementTierForAffiliate } from "./affiliateTierHelper";

// ─── Secrets ──────────────────────────────────────────────────────────────────

const AMAZON_ASSOCIATES_TAG = defineSecret("AMAZON_ASSOCIATES_TAG");
const BOOKSHOP_AFFILIATE_ID = defineSecret("BOOKSHOP_AFFILIATE_ID");

// ─── Constants ────────────────────────────────────────────────────────────────

const db = getFirestore();
const REGION = "us-east1";

// Platform fee schedule — server-side only, never exposed to client
const PLATFORM_FEE_SCHEDULE: Record<string, number> = {
  course: 0.15,       // 15% on courses
  event: 0.10,        // 10% on ticketed events
  membership: 0.10,   // 10% on recurring memberships
  coaching: 0.20,     // 20% on coaching sessions
  digital_product: 0.15, // 15% on digital downloads
};

export const DEFAULT_PLATFORM_FEE = 0.10; // fallback 10% if work type not in schedule

// ─── Platform detection ───────────────────────────────────────────────────────

type LinkPlatform =
  | "amazon"
  | "bookshop"
  | "spotify"
  | "apple_music"
  | "youtube"
  | "generic";

/**
 * Detects the platform of a URL by hostname pattern.
 * Deep-link platforms (Spotify, Apple Music, YouTube) are identified so they
 * can be passed through without wrapping.
 */
function detectPlatform(rawUrl: string): LinkPlatform {
  let hostname: string;
  try {
    hostname = new URL(rawUrl).hostname.toLowerCase().replace(/^www\./, "");
  } catch {
    return "generic";
  }

  if (hostname.includes("amazon.") || hostname === "amzn.to") return "amazon";
  if (hostname === "bookshop.org") return "bookshop";
  if (hostname === "open.spotify.com" || hostname === "spotify.com") return "spotify";
  if (hostname === "music.apple.com" || hostname === "itunes.apple.com") return "apple_music";
  if (hostname === "youtube.com" || hostname === "youtu.be") return "youtube";
  return "generic";
}

/**
 * Deep-link platforms are always returned as-is regardless of tier.
 */
function isDeepLinkPlatform(platform: LinkPlatform): boolean {
  return platform === "spotify" || platform === "apple_music" || platform === "youtube";
}

// ─── Wrapping logic ───────────────────────────────────────────────────────────

/**
 * Wraps an Amazon product URL with the Associates tag.
 * Preserves existing path and relevant query params; injects `tag=` param.
 */
function wrapAmazonUrl(rawUrl: string, tag: string): string {
  try {
    const u = new URL(rawUrl);
    // Strip existing tag and add ours
    u.searchParams.delete("tag");
    u.searchParams.set("tag", tag);
    // Remove non-essential Amazon tracking params to keep URL clean
    ["ref", "ref_", "linkCode", "linkId"].forEach((p) => u.searchParams.delete(p));
    return u.toString();
  } catch {
    // If URL parse fails, append tag as query param
    const sep = rawUrl.includes("?") ? "&" : "?";
    return `${rawUrl}${sep}tag=${encodeURIComponent(tag)}`;
  }
}

/**
 * Wraps a Bookshop.org URL with the affiliate ID.
 * Bookshop.org affiliate format: bookshop.org/a/{affiliateId}/...
 */
function wrapBookshopUrl(rawUrl: string, affiliateId: string): string {
  try {
    const u = new URL(rawUrl);
    const pathParts = u.pathname.split("/").filter(Boolean);
    // If already has affiliate segment (a/xxx), replace it
    if (pathParts[0] === "a" && pathParts.length >= 2) {
      pathParts[1] = affiliateId;
    } else {
      pathParts.unshift("a", affiliateId);
    }
    u.pathname = "/" + pathParts.join("/");
    return u.toString();
  } catch {
    return rawUrl;
  }
}

// ─── wrapAffiliateLink callable ───────────────────────────────────────────────

interface WrapAffiliateLinkInput {
  url: string;
  /** Optional hint; auto-detected if omitted. */
  platform?: LinkPlatform;
  workId?: string;
}

interface WrapAffiliateLinkOutput {
  wrappedUrl: string;
  platform: LinkPlatform;
  /** True if the link was wrapped with an affiliate tag; false if passed through. */
  wrapped: boolean;
}

/**
 * Wraps a Catalog work URL with an affiliate tag where supported.
 *
 * Authorization:
 *   - Creator Pro+ only may REQUEST wrapping (management feature).
 *   - The RESULTING wrapped URLs are publicly accessible to all — never gate
 *     the links themselves.
 *
 * Deep-links (Spotify, Apple Music, YouTube) are always returned unchanged
 * regardless of tier. No sponsored insertion — links are only wrapped with
 * creator-configured affiliate IDs, never platform-side ad tags.
 */
export const wrapAffiliateLink = onCall({ enforceAppCheck: true, region: REGION,
    secrets: [AMAZON_ASSOCIATES_TAG, BOOKSHOP_AFFILIATE_ID], }, async (req): Promise<WrapAffiliateLinkOutput> => {
    if (!req.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    const uid = req.auth.uid;
    const data = req.data as WrapAffiliateLinkInput;

    if (!data?.url) {
      throw new HttpsError("invalid-argument", "url is required.");
    }

    const rawUrl = data.url.trim();
    const platform = data.platform ?? detectPlatform(rawUrl);

    // Deep-links are always passed through — no tier check needed
    if (isDeepLinkPlatform(platform)) {
      return { wrappedUrl: rawUrl, platform, wrapped: false };
    }

    // Non-deep-link wrapping requires creator_pro+ (management feature)
    const tier = await getEntitlementTierForAffiliate(uid);
    const tierRank: Record<string, number> = {
      free: 0,
      creator_pro: 1,
      creator_studio: 2,
      organization: 3,
    };
    if ((tierRank[tier] ?? 0) < 1) {
      throw new HttpsError(
        "permission-denied",
        "Affiliate link management requires Creator Pro or higher."
      );
    }

    let wrappedUrl = rawUrl;
    let wrapped = false;

    if (platform === "amazon") {
      const tag = AMAZON_ASSOCIATES_TAG.value();
      if (tag) {
        wrappedUrl = wrapAmazonUrl(rawUrl, tag);
        wrapped = true;
      } else {
        logger.warn("wrapAffiliateLink: AMAZON_ASSOCIATES_TAG secret not set", { uid });
      }
    } else if (platform === "bookshop") {
      const affiliateId = BOOKSHOP_AFFILIATE_ID.value();
      if (affiliateId) {
        wrappedUrl = wrapBookshopUrl(rawUrl, affiliateId);
        wrapped = true;
      } else {
        logger.warn("wrapAffiliateLink: BOOKSHOP_AFFILIATE_ID secret not set", { uid });
      }
    }
    // generic: returned as-is (no affiliate program wired)

    // Audit log (non-blocking)
    if (wrapped && data.workId) {
      db.collection("affiliateLinkLog")
        .add({
          uid,
          workId: data.workId,
          platform,
          originalUrl: rawUrl,
          wrappedUrl,
          createdAt: FieldValue.serverTimestamp(),
        })
        .catch((err) => {
          logger.warn("wrapAffiliateLink: audit log write failed", { uid, err });
        });
    }

    return { wrappedUrl, platform, wrapped };
  }
);

// ─── getPlatformFeeRate — internal helper (not exported as callable) ──────────

/**
 * Returns the platform fee rate for a given work type.
 * Server-side only — this function result is NEVER returned to clients directly.
 * Used internally by checkout and subscription CFs.
 *
 * Fee schedule:
 *   course        15%
 *   event         10%
 *   membership    10%
 *   coaching      20%
 *   digital_product 15%
 *   (all others)  10% default
 */
export function getPlatformFeeRate(workType: string): number {
  return PLATFORM_FEE_SCHEDULE[workType] ?? DEFAULT_PLATFORM_FEE;
}

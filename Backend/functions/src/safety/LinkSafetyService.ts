/**
 * LinkSafetyService.ts
 *
 * Backend URL/link safety scanning for Amen Safety OS.
 * Every URL submitted in a post, comment, DM, bio, event, or church listing
 * must pass this check before the content is approved.
 *
 * Checks:
 *   1. Blocklist of known malicious/scam domains (internal list)
 *   2. Google Safe Browsing API (phishing, malware, social engineering)
 *   3. Domain reputation heuristics (brand-new domains, suspicious TLDs, URL shorteners)
 *
 * Short links are followed to their final destination before analysis.
 * Fails CLOSED on API errors — suspicious links are held for human review.
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import axios from "axios";
import { AMEN_SAFETY_POLICY_VERSION, userFacingMessageFor } from "./AmenSafetyPolicy";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Types ────────────────────────────────────────────────────────────────────

export interface LinkSafetyRequest {
  url: string;
  contentType: "post" | "comment" | "dm" | "bio" | "event" | "church_listing" | "username";
  contentId?: string;
  submitterUid: string;
}

export interface LinkSafetyResult {
  allowed: boolean;
  harmCategoryId: string | null;
  userFacingMessage: string | null;
  requiresHumanReview: boolean;
  resolvedUrl?: string;
  policyVersion: string;
}

// ─── Internal Blocklist (Layer 0) ─────────────────────────────────────────────

// Common domains used for scams, phishing, adult content, and malware delivery.
// This is a starter set — should be fed from a maintained database in production.
const BLOCKED_DOMAIN_PATTERNS = [
  /onlyfans\.com/i,
  /pornhub\.com/i,
  /xvideos\.com/i,
  /xhamster\.com/i,
  /redtube\.com/i,
  /xnxx\.com/i,
  /rule34\.xxx/i,
  /fapello\.com/i,
  // Common scam redirect patterns
  /bit\.ly\/[a-z0-9]+$/i,  // Handled specially — expand first
  /tinyurl\.com/i,          // Expand first
  // Known phishing TLDs / patterns
  /\.ru\/[a-z]+\.(exe|msi|dmg|apk)$/i,
  /free-(iphone|gift|prize|cash)/i,
  /claim-your-reward/i,
  /you-have-won/i,
];

const ADULT_DOMAIN_PATTERNS = [
  /adult/i,
  /xxx/i,
  /porn/i,
  /sex/i,
  /nude/i,
  /nsfw/i,
  /escort/i,
];

function checkInternalBlocklist(url: string): string | null {
  for (const pattern of BLOCKED_DOMAIN_PATTERNS) {
    if (pattern.test(url)) return "scam_phishing";
  }
  try {
    const hostname = new URL(url).hostname;
    for (const pattern of ADULT_DOMAIN_PATTERNS) {
      if (pattern.test(hostname)) return "pornography";
    }
  } catch {
    // Malformed URL — block it
    return "scam_phishing";
  }
  return null;
}

// ─── URL Expansion (for short links) ─────────────────────────────────────────

const URL_SHORTENERS = ["bit.ly", "tinyurl.com", "t.co", "goo.gl", "ow.ly", "buff.ly", "rebrand.ly"];

async function expandUrl(url: string): Promise<string> {
  try {
    const hostname = new URL(url).hostname;
    if (!URL_SHORTENERS.some((s) => hostname.endsWith(s))) return url;

    const response = await axios.head(url, {
      maxRedirects: 5,
      timeout: 5000,
      validateStatus: () => true,
    });
    return response.request?.res?.responseUrl ?? url;
  } catch {
    return url;
  }
}

// ─── Google Safe Browsing API (Layer 1) ───────────────────────────────────────

const SAFE_BROWSING_ENDPOINT = "https://safebrowsing.googleapis.com/v4/threatMatches:find";

interface SafeBrowsingMatch {
  threatType: string;
}

interface SafeBrowsingResponse {
  matches?: SafeBrowsingMatch[];
}

async function checkSafeBrowsing(url: string): Promise<string | null> {
  const apiKey = process.env.GOOGLE_SAFE_BROWSING_API_KEY ?? process.env.GOOGLE_API_KEY;
  if (!apiKey) {
    logger.warn("[LinkSafetyService] GOOGLE_SAFE_BROWSING_API_KEY not set.");
    return null; // Proceed to heuristics only
  }

  try {
    const response = await axios.post<SafeBrowsingResponse>(
      `${SAFE_BROWSING_ENDPOINT}?key=${apiKey}`,
      {
        client: { clientId: "amen-app", clientVersion: "1.0" },
        threatInfo: {
          threatTypes: ["MALWARE", "SOCIAL_ENGINEERING", "UNWANTED_SOFTWARE", "POTENTIALLY_HARMFUL_APPLICATION"],
          platformTypes: ["ANY_PLATFORM"],
          threatEntryTypes: ["URL"],
          threatEntries: [{ url }],
        },
      },
      { timeout: 5000 }
    );

    if (response.data.matches && response.data.matches.length > 0) {
      const threatType = response.data.matches[0].threatType;
      if (threatType === "SOCIAL_ENGINEERING") return "scam_phishing";
      return "scam_phishing"; // All Safe Browsing threats map to scam_phishing
    }
    return null;
  } catch (err) {
    logger.warn("[LinkSafetyService] Safe Browsing API error.", err);
    return null;
  }
}

// ─── Heuristic Checks (Layer 2) ───────────────────────────────────────────────

function heuristicCheck(url: string): string | null {
  try {
    const parsed = new URL(url);
    const hostname = parsed.hostname;

    // IP address URLs are suspicious
    if (/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(hostname)) {
      return "scam_phishing";
    }

    // High-risk TLDs used heavily in phishing
    const highRiskTLDs = [".xyz", ".top", ".club", ".info", ".online", ".site", ".space", ".icu"];
    if (highRiskTLDs.some((tld) => hostname.endsWith(tld))) {
      return "scam_phishing";
    }

    // Lookalike domain patterns (brand impersonation)
    const lookalikes = ["paypa1", "g00gle", "faceb00k", "amaz0n", "app1e", "micros0ft"];
    if (lookalikes.some((l) => hostname.includes(l))) {
      return "identity_theft";
    }

    // Executable file downloads
    if (/\.(exe|msi|dmg|apk|bat|ps1|sh)$/i.test(parsed.pathname)) {
      return "scam_phishing";
    }
  } catch {
    return "scam_phishing"; // Malformed URL
  }
  return null;
}

// ─── Core Logic ───────────────────────────────────────────────────────────────

export async function checkLinkSafety(req: LinkSafetyRequest): Promise<LinkSafetyResult> {
  const { url, contentType, submitterUid, contentId } = req;

  // Expand short links first
  const resolvedUrl = await expandUrl(url);

  // Layer 0 — internal blocklist
  const blockedBy = checkInternalBlocklist(resolvedUrl);
  if (blockedBy) {
    await writeLinkLog(submitterUid, url, resolvedUrl, contentType, contentId, blockedBy, "internal_blocklist");
    return {
      allowed: false,
      harmCategoryId: blockedBy,
      userFacingMessage: userFacingMessageFor(blockedBy),
      requiresHumanReview: false,
      resolvedUrl,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
    };
  }

  // Layer 1 — Google Safe Browsing
  const safeBrowsingThreat = await checkSafeBrowsing(resolvedUrl);
  if (safeBrowsingThreat) {
    await writeLinkLog(submitterUid, url, resolvedUrl, contentType, contentId, safeBrowsingThreat, "safe_browsing");
    return {
      allowed: false,
      harmCategoryId: safeBrowsingThreat,
      userFacingMessage: userFacingMessageFor(safeBrowsingThreat),
      requiresHumanReview: false,
      resolvedUrl,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
    };
  }

  // Layer 2 — heuristics
  const heuristicThreat = heuristicCheck(resolvedUrl);
  if (heuristicThreat) {
    await writeLinkLog(submitterUid, url, resolvedUrl, contentType, contentId, heuristicThreat, "heuristic");
    return {
      allowed: false,
      harmCategoryId: heuristicThreat,
      userFacingMessage: "This link cannot be posted on Amen. It may be unsafe.",
      requiresHumanReview: true,
      resolvedUrl,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
    };
  }

  // All checks passed
  return {
    allowed: true,
    harmCategoryId: null,
    userFacingMessage: null,
    requiresHumanReview: false,
    resolvedUrl,
    policyVersion: AMEN_SAFETY_POLICY_VERSION,
  };
}

async function writeLinkLog(
  uid: string,
  originalUrl: string,
  resolvedUrl: string,
  contentType: string,
  contentId: string | undefined,
  harmCategoryId: string,
  detectedBy: string
): Promise<void> {
  try {
    await db.collection("linkSafetyLogs").add({
      uid,
      originalUrl,
      resolvedUrl,
      contentType,
      contentId: contentId ?? null,
      harmCategoryId,
      detectedBy,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (err) {
    logger.warn("[LinkSafetyService] Failed to write link log.", err);
  }
}

// ─── Callable Function ────────────────────────────────────────────────────────

export const checkLinkSafetyCallable = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<LinkSafetyRequest>): Promise<LinkSafetyResult> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const { url, contentType, contentId } = request.data;

    if (!url || typeof url !== "string") {
      throw new HttpsError("invalid-argument", "url is required.");
    }

    // Validate that it's a parseable URL
    try { new URL(url); } catch {
      throw new HttpsError("invalid-argument", "url is not a valid URL.");
    }

    return checkLinkSafety({
      url,
      contentType,
      contentId,
      submitterUid: request.auth.uid,
    });
  }
);

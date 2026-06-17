/**
 * trustScoring.ts
 * AMEN — Global Resilience: Trust Scoring
 *
 * Firebase Gen-2 callable Cloud Functions (region: us-central1):
 *
 *   evaluateTrustProfile  — Apply a triggerEvent mutation to a TrustProfile and
 *                           emit an immutable safety audit log entry.
 *   checkDonationSafety   — Return a tiered isSafe / warningLevel verdict for a
 *                           donation or money request from a given requester.
 *   detectRiskPatterns    — Scan recent DM volume + post content for financial-
 *                           scam signals; auto-trigger evaluateTrustProfile when
 *                           the mass-DM threshold is exceeded.
 *
 * Firestore layout (canonical paths from contracts.ts PATHS):
 *   /trustProfiles/{userId}           — TrustProfile document
 *   /safetyAuditLog/{newId}           — Immutable audit entries (never deleted)
 *   /threads/{threadId}               — Thread documents with initiatorId + createdAt
 *   /posts/{postId}                   — Post documents with authorId + bodyText + createdAt
 *
 * Auth: every callable requires a valid Firebase Auth token (uid in request.auth).
 * App Check: enforced via { enforceAppCheck: true }.
 */

import * as admin from "firebase-admin";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import type { VerificationTier, DmRiskLevel } from "./contracts";

// ─── Constants ────────────────────────────────────────────────────────────────

// us-east1 — us-central1 is at quota (999/1000). New functions deploy to
// us-east1 per docs/deploy-topology.md + CLAUDE.md. See Interim Region Table.
const REGION = "us-east1";

/** Threshold: account age in days below which a new-money-request is blocked. */
const ACCOUNT_AGE_BLOCK_DAYS = 30;

/** Threshold: DMs sent within 24 h that trigger "mass_dm_detected". */
const MASS_DM_THRESHOLD = 20;

/** Urgency keywords that flag a post as a potential financial-scam signal. */
const URGENCY_KEYWORDS: readonly string[] = [
  "send now",
  "god told me to ask",
  "emergency transfer",
  "wire",
  "cash app me",
  "zelle me",
] as const;

// ─── Types ────────────────────────────────────────────────────────────────────

/** On-wire shape stored in /trustProfiles/{userId}. */
interface TrustProfileDoc {
  userId: string;
  identityTier: VerificationTier;
  communityTrustScore: number;
  impersonationRiskScore: number;
  donationPermission: boolean;
  dmRiskLevel: "normal" | "high" | "restricted" | DmRiskLevel;
  abuseReportsCount: number;
  createdAt: Timestamp | ReturnType<typeof FieldValue.serverTimestamp>;
  updatedAt: ReturnType<typeof FieldValue.serverTimestamp> | Timestamp;
}

type TrustProfileSnapshot = Omit<TrustProfileDoc, "createdAt" | "updatedAt"> & {
  createdAt: Timestamp | null;
  updatedAt: Timestamp | null;
};

type TriggerEvent =
  | "new_money_request"
  | "mass_dm_detected"
  | "profile_photo_match"
  | "abuse_report"
  | "verification_approved";

interface EvaluateTrustProfileRequest {
  userId: unknown;
  triggerEvent: unknown;
  /** Required when triggerEvent === "verification_approved" */
  approvedTier?: unknown;
}

interface EvaluateTrustProfileResponse {
  userId: string;
  triggerEvent: TriggerEvent;
  profile: TrustProfileSnapshot;
}

interface CheckDonationSafetyRequest {
  requesterId: unknown;
  amount?: unknown;
  recipientId?: unknown;
}

interface CheckDonationSafetyResponse {
  isSafe: boolean;
  warningLevel: "none" | "caution" | "warning" | "block";
  warningText: string;
}

interface DetectRiskPatternsRequest {
  userId: unknown;
}

interface DetectRiskPatternsResponse {
  patterns: string[];
  recommendedAction: string;
}

// ─── Input validation helpers ─────────────────────────────────────────────────

function requireNonEmptyString(value: unknown, field: string, maxLen = 256): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new HttpsError("invalid-argument", `${field} must be a non-empty string.`);
  }
  if (value.length > maxLen) {
    throw new HttpsError(
      "invalid-argument",
      `${field} exceeds maximum length of ${maxLen} characters.`
    );
  }
  return value.trim();
}

function requireAuth(auth: { uid: string } | undefined | null): string {
  if (!auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return auth.uid;
}

function isValidTriggerEvent(value: string): value is TriggerEvent {
  return [
    "new_money_request",
    "mass_dm_detected",
    "profile_photo_match",
    "abuse_report",
    "verification_approved",
  ].includes(value);
}

function isValidVerificationTier(value: string): value is VerificationTier {
  return [
    "none",
    "person",
    "leader",
    "churchLinked",
    "ministry",
    "charityDonation",
    "eventHost",
  ].includes(value);
}

// ─── Profile helpers ──────────────────────────────────────────────────────────

const DEFAULT_TRUST_PROFILE: Omit<TrustProfileDoc, "userId" | "createdAt" | "updatedAt"> = {
  identityTier: "none",
  communityTrustScore: 0.5,
  impersonationRiskScore: 0,
  donationPermission: true,
  dmRiskLevel: "normal",
  abuseReportsCount: 0,
};

/**
 * Reads /trustProfiles/{userId}. Creates the document with defaults if it does
 * not exist (using a transaction-safe set-with-merge). Returns the resolved data.
 */
async function getOrCreateTrustProfile(
  db: FirebaseFirestore.Firestore,
  userId: string
): Promise<TrustProfileDoc & { _ref: FirebaseFirestore.DocumentReference }> {
  const ref = db.collection("trustProfiles").doc(userId);
  const snap = await ref.get();

  if (!snap.exists) {
    const defaults: TrustProfileDoc = {
      ...DEFAULT_TRUST_PROFILE,
      userId,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };
    // Use merge so a concurrent write does not clobber.
    await ref.set(defaults, { merge: true });
    // Re-read to get server-resolved timestamps.
    const fresh = await ref.get();
    const d = fresh.data() as TrustProfileDoc;
    return { ...d, _ref: ref };
  }

  const d = snap.data() as TrustProfileDoc;
  return { ...d, _ref: ref };
}

/**
 * Serialise a TrustProfileDoc for safe inclusion in an audit log or response,
 * converting server-timestamp sentinels to null so JSON serialisation is clean.
 */
function snapshotProfile(doc: TrustProfileDoc): TrustProfileSnapshot {
  return {
    userId: doc.userId,
    identityTier: doc.identityTier ?? "none",
    communityTrustScore: doc.communityTrustScore ?? 0.5,
    impersonationRiskScore: doc.impersonationRiskScore ?? 0,
    donationPermission: doc.donationPermission ?? true,
    dmRiskLevel: doc.dmRiskLevel ?? "normal",
    abuseReportsCount: doc.abuseReportsCount ?? 0,
    createdAt: doc.createdAt instanceof Timestamp ? doc.createdAt : null,
    updatedAt: doc.updatedAt instanceof Timestamp ? doc.updatedAt : null,
  };
}

// ─── evaluateTrustProfile ─────────────────────────────────────────────────────

/**
 * evaluateTrustProfile
 *
 * Reads /trustProfiles/{userId} (creating it with defaults on first call),
 * applies the mutation defined by triggerEvent, writes back the updated document,
 * and emits an immutable entry to /safetyAuditLog/{newId}.
 *
 * Caller must be authenticated; for internal invocations from detectRiskPatterns
 * this function is also exported as a plain async helper so it can be called
 * server-side without going through the callable wire protocol.
 */
export const evaluateTrustProfile = onCall<
  EvaluateTrustProfileRequest,
  Promise<EvaluateTrustProfileResponse>
>(
  { enforceAppCheck: true, region: REGION },
  async (request): Promise<EvaluateTrustProfileResponse> => {
    requireAuth(request.auth);

    const data = request.data as EvaluateTrustProfileRequest;
    const userId = requireNonEmptyString(data.userId, "userId");
    const rawEvent = requireNonEmptyString(data.triggerEvent as unknown, "triggerEvent");

    if (!isValidTriggerEvent(rawEvent)) {
      throw new HttpsError(
        "invalid-argument",
        `Unknown triggerEvent: "${rawEvent}". Valid values are: ` +
          "new_money_request, mass_dm_detected, profile_photo_match, " +
          "abuse_report, verification_approved."
      );
    }
    const triggerEvent = rawEvent as TriggerEvent;

    const approvedTierRaw =
      triggerEvent === "verification_approved" ? data.approvedTier : undefined;

    return _evaluateTrustProfileInternal({ userId, triggerEvent, approvedTierRaw });
  }
);

/**
 * Internal implementation shared by the callable export and detectRiskPatterns.
 * Separated so detectRiskPatterns can call it without an HTTP round-trip.
 */
async function _evaluateTrustProfileInternal(params: {
  userId: string;
  triggerEvent: TriggerEvent;
  approvedTierRaw?: unknown;
}): Promise<EvaluateTrustProfileResponse> {
  const { userId, triggerEvent, approvedTierRaw } = params;
  const db = getFirestore();

  // ── 1. Read / create profile ───────────────────────────────────────────────
  const existing = await getOrCreateTrustProfile(db, userId);
  const beforeSnapshot = snapshotProfile(existing);

  // Work on a plain mutable copy; we'll write only the changed fields.
  const updates: Partial<TrustProfileDoc> & { updatedAt: ReturnType<typeof FieldValue.serverTimestamp> } = {
    updatedAt: FieldValue.serverTimestamp(),
  };

  let impersonationRiskScore = existing.impersonationRiskScore ?? 0;
  let donationPermission = existing.donationPermission ?? true;
  let dmRiskLevel: TrustProfileDoc["dmRiskLevel"] = existing.dmRiskLevel ?? "normal";
  let abuseReportsCount = existing.abuseReportsCount ?? 0;
  let identityTier: VerificationTier = (existing.identityTier ?? "none") as VerificationTier;

  // ── 2. Apply mutation ──────────────────────────────────────────────────────
  switch (triggerEvent) {
    case "new_money_request": {
      impersonationRiskScore += 50;
      if (identityTier === "none") {
        donationPermission = false;
      }
      updates.impersonationRiskScore = impersonationRiskScore;
      updates.donationPermission = donationPermission;
      break;
    }

    case "mass_dm_detected": {
      impersonationRiskScore += 30;
      dmRiskLevel = "high";
      updates.impersonationRiskScore = impersonationRiskScore;
      updates.dmRiskLevel = dmRiskLevel;
      break;
    }

    case "profile_photo_match": {
      impersonationRiskScore += 40;
      updates.impersonationRiskScore = impersonationRiskScore;
      break;
    }

    case "abuse_report": {
      abuseReportsCount += 1;
      if (abuseReportsCount >= 5) {
        dmRiskLevel = "restricted";
      }
      updates.abuseReportsCount = abuseReportsCount;
      updates.dmRiskLevel = dmRiskLevel;
      break;
    }

    case "verification_approved": {
      // Validate approvedTier before trusting it.
      const tierStr =
        typeof approvedTierRaw === "string" && isValidVerificationTier(approvedTierRaw)
          ? (approvedTierRaw as VerificationTier)
          : "person";
      impersonationRiskScore = 0;
      donationPermission = true;
      identityTier = tierStr;
      updates.impersonationRiskScore = 0;
      updates.donationPermission = true;
      updates.identityTier = tierStr;
      break;
    }
  }

  // ── 3. Write updated profile ───────────────────────────────────────────────
  await existing._ref.set(updates, { merge: true });

  // Build an after-snapshot by merging the changes onto the before state.
  const afterDoc: TrustProfileDoc = {
    ...existing,
    ...updates,
    // updatedAt is a sentinel; represent it as null in the snapshot.
    updatedAt: null as unknown as Timestamp,
    createdAt: existing.createdAt,
  };
  const afterSnapshot = snapshotProfile(afterDoc);

  // ── 4. Write immutable audit log ───────────────────────────────────────────
  const auditRef = db.collection("safetyAuditLog").doc();
  await auditRef.set({
    userId,
    triggerEvent,
    before: beforeSnapshot,
    after: afterSnapshot,
    timestamp: FieldValue.serverTimestamp(),
  });

  logger.info("[evaluateTrustProfile] Profile updated + audit log written", {
    userId,
    triggerEvent,
    auditId: auditRef.id,
  });

  return { userId, triggerEvent, profile: afterSnapshot };
}

// ─── checkDonationSafety ──────────────────────────────────────────────────────

/**
 * checkDonationSafety
 *
 * Reads the requester's TrustProfile and returns a tiered safety verdict.
 *
 * Tiers (evaluated in priority order):
 *   1. identityTier=="none" + money_request + account age < 30 days → BLOCK
 *   2. identityTier=="none" + any donation context               → WARNING
 *   3. verified + communityTrustScore < 0.4                      → CAUTION
 *   4. otherwise                                                  → NONE (safe)
 */
export const checkDonationSafety = onCall<
  CheckDonationSafetyRequest,
  Promise<CheckDonationSafetyResponse>
>(
  { enforceAppCheck: true, region: REGION },
  async (request): Promise<CheckDonationSafetyResponse> => {
    requireAuth(request.auth);

    const data = request.data as CheckDonationSafetyRequest;
    const requesterId = requireNonEmptyString(data.requesterId, "requesterId");

    const db = getFirestore();

    // ── 1. Read trust profile (create defaults if absent) ─────────────────────
    const profile = await getOrCreateTrustProfile(db, requesterId);

    const identityTier: VerificationTier = (profile.identityTier ?? "none") as VerificationTier;
    const communityTrustScore = profile.communityTrustScore ?? 0.5;
    const donationPermission = profile.donationPermission ?? true;

    // ── 2. Determine account age ───────────────────────────────────────────────
    // We read the user document to check createdAt. On first-run accounts the
    // field may not exist; treat absence as an account age of 0 (most-restrictive).
    let accountAgeDays = 0;
    try {
      const userSnap = await db.collection("users").doc(requesterId).get();
      if (userSnap.exists) {
        const userData = userSnap.data() ?? {};
        const createdAt: Timestamp | undefined =
          userData.createdAt instanceof Timestamp ? userData.createdAt : undefined;
        if (createdAt) {
          const ageMs = Date.now() - createdAt.toMillis();
          accountAgeDays = ageMs / (1000 * 60 * 60 * 24);
        }
      }
    } catch (err) {
      // Non-fatal: default accountAgeDays to 0 (most restrictive verdict).
      logger.warn("[checkDonationSafety] Could not read user createdAt", { requesterId }, err);
    }

    // ── 3. Evaluate tiers in priority order ────────────────────────────────────

    // Tier 1: new, unverified account making a money request.
    if (identityTier === "none" && accountAgeDays < ACCOUNT_AGE_BLOCK_DAYS) {
      return {
        isSafe: false,
        warningLevel: "block",
        warningText:
          "This account could not be verified. Do not send money.",
      };
    }

    // Tier 2: unverified identity or donation permission revoked.
    if (identityTier === "none" || !donationPermission) {
      return {
        isSafe: false,
        warningLevel: "warning",
        warningText:
          "AMEN could not verify this donation request. Do not send money unless " +
          "you personally know and trust the recipient.",
      };
    }

    // Tier 3: verified but low community trust score.
    if (communityTrustScore < 0.4) {
      return {
        isSafe: true,
        warningLevel: "caution",
        warningText: "Proceed with care",
      };
    }

    // Tier 4: safe.
    return {
      isSafe: true,
      warningLevel: "none",
      warningText: "",
    };
  }
);

// ─── detectRiskPatterns ───────────────────────────────────────────────────────

/**
 * detectRiskPatterns
 *
 * 1. Counts DM threads initiated by userId in the last 24 hours.
 *    If > MASS_DM_THRESHOLD (20), triggers evaluateTrustProfile with
 *    "mass_dm_detected" so the profile is updated and audited.
 *
 * 2. Scans the 50 most-recent posts authored by userId for urgency keywords
 *    associated with financial scams. Returns matched patterns.
 *
 * 3. Returns { patterns, recommendedAction } for the caller to surface in UI or
 *    route to a human reviewer.
 */
export const detectRiskPatterns = onCall<
  DetectRiskPatternsRequest,
  Promise<DetectRiskPatternsResponse>
>(
  { enforceAppCheck: true, region: REGION },
  async (request): Promise<DetectRiskPatternsResponse> => {
    requireAuth(request.auth);

    const data = request.data as DetectRiskPatternsRequest;
    const userId = requireNonEmptyString(data.userId, "userId");

    const db = getFirestore();
    const patterns: string[] = [];
    const now = Timestamp.now();
    const cutoff = Timestamp.fromMillis(now.toMillis() - 24 * 60 * 60 * 1000);

    // ── 1. Count DMs sent in last 24 h ─────────────────────────────────────────
    let dmCountLast24h = 0;
    try {
      const dmSnap = await db
        .collection("threads")
        .where("initiatorId", "==", userId)
        .where("createdAt", ">", cutoff)
        .get();
      dmCountLast24h = dmSnap.size;
    } catch (err) {
      logger.warn("[detectRiskPatterns] Could not query threads", { userId }, err);
    }

    if (dmCountLast24h > MASS_DM_THRESHOLD) {
      patterns.push(`mass_dm_sent:${dmCountLast24h}_in_24h`);

      // Trigger profile mutation server-side (no HTTP round-trip needed).
      try {
        await _evaluateTrustProfileInternal({
          userId,
          triggerEvent: "mass_dm_detected",
        });
        logger.info(
          "[detectRiskPatterns] mass_dm_detected triggered for userId",
          { userId, dmCountLast24h }
        );
      } catch (evalErr) {
        logger.error(
          "[detectRiskPatterns] evaluateTrustProfile failed for mass_dm_detected",
          { userId },
          evalErr
        );
      }
    }

    // ── 2. Scan recent posts for urgency / scam keywords ───────────────────────
    try {
      const postsSnap = await db
        .collection("posts")
        .where("authorId", "==", userId)
        .orderBy("createdAt", "desc")
        .limit(50)
        .get();

      for (const doc of postsSnap.docs) {
        const postData = doc.data();
        const bodyText: string =
          typeof postData.bodyText === "string"
            ? postData.bodyText.toLowerCase()
            : typeof postData.text === "string"
            ? postData.text.toLowerCase()
            : "";

        for (const keyword of URGENCY_KEYWORDS) {
          if (bodyText.includes(keyword.toLowerCase())) {
            const label = `urgency_keyword:"${keyword}"`;
            if (!patterns.includes(label)) {
              patterns.push(label);
            }
          }
        }
      }
    } catch (err) {
      logger.warn("[detectRiskPatterns] Could not query posts", { userId }, err);
    }

    // ── 3. Build recommendedAction ─────────────────────────────────────────────
    let recommendedAction = "none";

    if (dmCountLast24h > MASS_DM_THRESHOLD && patterns.some((p) => p.startsWith("urgency_keyword"))) {
      recommendedAction = "escalate_to_human_review";
    } else if (dmCountLast24h > MASS_DM_THRESHOLD) {
      recommendedAction = "monitor_dm_volume";
    } else if (patterns.some((p) => p.startsWith("urgency_keyword"))) {
      recommendedAction = "flag_post_for_review";
    }

    logger.info("[detectRiskPatterns] Scan complete", {
      userId,
      dmCountLast24h,
      patternsFound: patterns.length,
      recommendedAction,
    });

    return { patterns, recommendedAction };
  }
);

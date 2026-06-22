/**
 * exportAmenFile.ts
 * AMEN Universal Migration & Context System — Wave 5 (export-engineer)
 *
 * Callable: exportAmenFile
 *   Builds the user's portable .amen v0.1 file (CONTRACTS.md §8) from their OWN
 *   context facets. The file is a projection — never a separate store, never content.
 *
 * CONTRACT (CONTRACTS.md §7 — FROZEN, never modified here)
 * ────────────────────────────────────────────────────────
 *   onCall, enforceAppCheck: true, region us-central1, project amen-5e359.
 *   Input  : { facetIds: string[] }
 *   Output : { amen: AmenContextV0_1 }  (visibility-filtered + exclusion-validated)
 *
 * NON-NEGOTIABLE INVARIANTS (all enforced below)
 * ──────────────────────────────────────────────
 *   1. AUTH + APP CHECK — both required. We export the CALLER's own facets only.
 *   2. INCLUSION RULE (§8) — a facet is included iff:
 *          visibility === "public"   OR   its id is in the user-checked `facetIds`.
 *      Nothing else. Private/friends/groups/church facets are excluded unless the
 *      user explicitly checked that exact facet id on-device.
 *   3. TIER-P NEVER LEAVES — even an explicitly-checked Tier-P facet is dropped. The
 *      portable file is server-built; Tier-P confidentiality is enforced in CODE here
 *      (CONTRACTS §3 server-read invariant). We never query nor emit a Tier-P facet.
 *   4. EXCLUSION VALIDATOR IS A HARD GATE — the assembled payload is run through
 *      validateNoExcludedContent(); ANY violation (message/post struct, media URL,
 *      email, phone, contact array) aborts the export with HttpsError. Fails closed.
 *   5. NO SIGNING HERE — signing is a separate secret-backed callable (signAmenExport).
 *      This function returns the unsigned `amen` document; the client signs next.
 *   6. NO WRITES — read-only projection. Nothing is persisted by this function.
 *
 * Pattern mirrors functions/context/extractContextFacets.ts (onCall + enforceAppCheck +
 * region) and the other Context System callables.
 */

import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {validateNoExcludedContent} from "./amenExclusionValidator";

if (!admin.apps.length) {
  admin.initializeApp();
}

const REGION = "us-central1";
const MAX_FACET_IDS = 512; // sane upper bound on an explicit selection

// ─── .amen v0.1 schema (CONTRACTS §8 — published here in Wave 5) ────────────────

/** A single exported facet. Mirrors the public-safe subset of ContextFacet. */
export interface AmenFacetV0_1 {
  id: string;
  category: string;
  key: string;
  label: string;
  /** Structured value, internally-tagged exactly like StructuredFacetValue. */
  value: { kind: string; payload: unknown };
  visibility: string;
  /** Provenance is reduced to non-identifying signal — NO contact/source PII. */
  provenance: {
    source: string;
    sourceLabel: string | null;
    confidence: number | null;
  };
  createdAt: string;  // ISO-8601
  updatedAt: string;  // ISO-8601
}

/**
 * The .amen v0.1 document. Open JSON spec. Signing (Ed25519) is applied by
 * signAmenExport over a canonical serialization of this object and delivered
 * alongside it; this document itself carries no signature.
 */
export interface AmenContextV0_1 {
  spec: "amen-context";
  version: "0.1";
  exportedAt: string;       // ISO-8601
  /** Stable owner handle for provenance; the importer never auto-trusts it. */
  owner: { userId: string };
  facets: AmenFacetV0_1[];
}

// ─── Helpers ────────────────────────────────────────────────────────────────────

function requireAuth(request: CallableRequest): string {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

/** Tier-P keys are NEVER server-readable / exportable (mirror of ContextTierTable). */
function tierForCategory(category: string, key: string): "S" | "C" | "P" {
  if (category === "faith_journey" && key.endsWith(".areas_needing_support")) {
    return "P";
  }
  switch (category) {
    case "relationships":
    case "family":
    case "health":
      return "P";
    default:
      return "C";
  }
}

/** ISO string from a Firestore Timestamp | Date | string | number, best-effort. */
function toISO(v: unknown): string {
  try {
    if (v && typeof (v as {toDate?: () => Date}).toDate === "function") {
      return (v as {toDate: () => Date}).toDate().toISOString();
    }
    if (v instanceof Date) return v.toISOString();
    if (typeof v === "number") return new Date(v).toISOString();
    if (typeof v === "string") {
      const d = new Date(v);
      if (!isNaN(d.getTime())) return d.toISOString();
    }
  } catch {
    // fall through
  }
  return new Date(0).toISOString();
}

/**
 * Project a raw Firestore facet doc into an AmenFacetV0_1, or null if it must be
 * excluded (Tier-P, malformed, or not eligible). The Tier-P drop here is the
 * code-level confidentiality gate — the doc may have a stored tier, but we ALSO
 * recompute it from category/key and drop if either says P.
 */
function projectFacet(
  docId: string,
  raw: Record<string, unknown>,
  includeIds: Set<string>,
): AmenFacetV0_1 | null {
  const category = typeof raw.category === "string" ? raw.category : "";
  const key = typeof raw.key === "string" ? raw.key : "";
  const label = typeof raw.label === "string" ? raw.label : "";
  const visibility = typeof raw.visibility === "string" ? raw.visibility : "private";
  if (!category || !key) return null;

  // Tier-P never leaves — check BOTH the stored tier and the recomputed one.
  const storedTier = typeof raw.tier === "string" ? raw.tier : "";
  const computedTier = tierForCategory(category, key);
  if (storedTier === "P" || computedTier === "P") return null;

  // Inclusion rule: public OR explicitly checked id.
  const eligible = visibility === "public" || includeIds.has(docId);
  if (!eligible) return null;

  // Structured value — pass through the tagged union shape only.
  const rawValue = (raw.value && typeof raw.value === "object")
    ? (raw.value as Record<string, unknown>)
    : null;
  const value = rawValue && typeof rawValue.kind === "string"
    ? {kind: rawValue.kind, payload: rawValue.payload}
    : {kind: "text", payload: ""};

  // Provenance reduced to non-identifying signal.
  const rawProv = (raw.provenance && typeof raw.provenance === "object")
    ? (raw.provenance as Record<string, unknown>)
    : {};
  const provenance = {
    source: typeof rawProv.source === "string" ? rawProv.source : "manual",
    sourceLabel: typeof rawProv.sourceLabel === "string" ? rawProv.sourceLabel : null,
    confidence: typeof rawProv.confidence === "number" ? rawProv.confidence : null,
  };

  return {
    id: docId,
    category,
    key,
    label,
    value,
    visibility,
    provenance,
    createdAt: toISO(raw.createdAt),
    updatedAt: toISO(raw.updatedAt),
  };
}

// ─── Callable ───────────────────────────────────────────────────────────────────

export const exportAmenFile = onCall(
  {
    region: REGION,
    enforceAppCheck: true,
    timeoutSeconds: 30,
  },
  async (request: CallableRequest): Promise<{amen: AmenContextV0_1}> => {
    const uid = requireAuth(request);

    const data = (request.data ?? {}) as Record<string, unknown>;
    const rawIds = Array.isArray(data.facetIds) ? data.facetIds : [];
    const includeIds = new Set<string>(
      rawIds
        .filter((x): x is string => typeof x === "string" && x.length > 0)
        .slice(0, MAX_FACET_IDS),
    );

    const db = admin.firestore();

    // Read the OWNER's facets only. Admin SDK bypasses rules, so confidentiality is
    // enforced in code: we never include a Tier-P facet (projectFacet drops them).
    const snap = await db
      .collection("contextFacets")
      .doc(uid)
      .collection("facets")
      .get();

    const facets: AmenFacetV0_1[] = [];
    for (const doc of snap.docs) {
      const projected = projectFacet(doc.id, doc.data() as Record<string, unknown>, includeIds);
      if (projected) facets.push(projected);
    }

    const amen: AmenContextV0_1 = {
      spec: "amen-context",
      version: "0.1",
      exportedAt: new Date().toISOString(),
      owner: {userId: uid},
      facets,
    };

    // INVARIANT 4 — HARD exclusion gate. Any violation aborts the export.
    const exclusion = validateNoExcludedContent(amen);
    if (!exclusion.ok) {
      // Log COUNT + paths only — never the offending value.
      logger.error("exportAmenFile: exclusion validator REJECTED payload", {
        uid,
        violationCount: exclusion.violations.length,
        violations: exclusion.violations.slice(0, 20),
      });
      throw new HttpsError(
        "failed-precondition",
        "Export blocked: the assembled file contained content that may never be exported " +
          "(messages, posts, media URLs, emails, phone numbers, or contacts).",
      );
    }

    logger.info("exportAmenFile.complete", {
      uid,
      facetCount: facets.length,
      requestedExplicit: includeIds.size,
    });

    return {amen};
  },
);

/**
 * signAmenExport.ts
 * AMEN Universal Migration & Context System — Wave 5 (export-engineer)
 *
 * Callable: signAmenExport
 *   Produces an Ed25519 signature over a canonical serialization of a .amen v0.1
 *   document so an importing AMEN client can verify provenance (CONTRACTS §7/§8).
 *
 * CONTRACT (CONTRACTS.md §7 — FROZEN)
 * ───────────────────────────────────
 *   onCall, enforceAppCheck: true, region us-central1, project amen-5e359.
 *   Input  : { amen }
 *   Output : { signature: { alg: "Ed25519", keyId, value } }
 *
 * NON-NEGOTIABLE INVARIANTS
 * ─────────────────────────
 *   1. AUTH + APP CHECK — both required.
 *   2. SECRET-BACKED KEY — the Ed25519 PRIVATE key comes ONLY from the Functions
 *      secret AMEN_EXPORT_ED25519_PRIVATE_KEY (PKCS#8 PEM). It is NEVER hardcoded,
 *      logged, or returned. If the secret is missing/malformed, we fail closed.
 *   3. CANONICAL SERIALIZATION — both signer and verifier hash the SAME bytes:
 *      JSON with object keys sorted recursively, no insignificant whitespace, UTF-8.
 *      The signature covers exactly the `amen` document the client will distribute.
 *   4. STABLE keyId — "amen-export-2026-1" (rotating later means a new id + secret).
 *   5. NO WRITES, NO ECHO — we return only {alg, keyId, value(base64)}; never the key.
 *
 * Verification (client side, AmenExportService): the importer canonicalizes the
 * received `amen`, then verifies the base64 signature with the bundled PUBLIC key for
 * keyId. Unknown keyId or bad signature ⇒ provenance "unverified" (still importable,
 * routed through FacetApprovalView — never auto-imported).
 */

import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as crypto from "crypto";
import * as logger from "firebase-functions/logger";

const REGION = "us-central1";

/** Ed25519 PRIVATE key, PKCS#8 PEM. Set via: firebase functions:secrets:set AMEN_EXPORT_ED25519_PRIVATE_KEY */
const AMEN_EXPORT_ED25519_PRIVATE_KEY = defineSecret("AMEN_EXPORT_ED25519_PRIVATE_KEY");

/** Frozen key id (CONTRACTS §8). A future rotation means a NEW id + NEW secret. */
const KEY_ID = "amen-export-2026-1";

// ─── Canonical serialization (must match the verifier byte-for-byte) ────────────

/**
 * Deterministic JSON: recursively sort object keys, preserve array order, drop
 * `undefined`. Numbers/strings/bools via JSON.stringify primitives. This is the
 * EXACT byte sequence that is signed and later verified.
 */
function canonicalize(value: unknown): string {
  return serialize(value);
}

function serialize(value: unknown): string {
  if (value === null) return "null";
  const t = typeof value;
  if (t === "number") return Number.isFinite(value as number) ? JSON.stringify(value) : "null";
  if (t === "boolean") return value ? "true" : "false";
  if (t === "string") return JSON.stringify(value);
  if (Array.isArray(value)) {
    return "[" + value.map((v) => serialize(v === undefined ? null : v)).join(",") + "]";
  }
  if (t === "object") {
    const obj = value as Record<string, unknown>;
    const keys = Object.keys(obj).filter((k) => obj[k] !== undefined).sort();
    return "{" + keys.map((k) => JSON.stringify(k) + ":" + serialize(obj[k])).join(",") + "}";
  }
  // undefined / function / symbol → null (should not appear in a .amen doc)
  return "null";
}

// ─── Helpers ────────────────────────────────────────────────────────────────────

function requireAuth(request: CallableRequest): string {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

/** Load + validate the Ed25519 private key from the secret. Fails closed. */
function loadPrivateKey(): crypto.KeyObject {
  const pem = AMEN_EXPORT_ED25519_PRIVATE_KEY.value();
  if (!pem || !pem.includes("BEGIN")) {
    throw new HttpsError(
      "failed-precondition",
      "Signing is unavailable: the export signing key is not configured.",
    );
  }
  try {
    const key = crypto.createPrivateKey({key: pem, format: "pem"});
    if (key.asymmetricKeyType !== "ed25519") {
      throw new Error("not an ed25519 key");
    }
    return key;
  } catch (err) {
    logger.error("signAmenExport: private key load failed", {
      error: (err as Error).message, // message only — never the key material
    });
    throw new HttpsError(
      "failed-precondition",
      "Signing is unavailable: the export signing key is invalid.",
    );
  }
}

// ─── Callable ───────────────────────────────────────────────────────────────────

export const signAmenExport = onCall(
  {
    region: REGION,
    enforceAppCheck: true,
    secrets: [AMEN_EXPORT_ED25519_PRIVATE_KEY],
    timeoutSeconds: 15,
  },
  async (
    request: CallableRequest,
  ): Promise<{signature: {alg: "Ed25519"; keyId: string; value: string}}> => {
    const uid = requireAuth(request);

    const data = (request.data ?? {}) as Record<string, unknown>;
    const amen = data.amen;
    if (!amen || typeof amen !== "object") {
      throw new HttpsError("invalid-argument", "Missing or invalid `amen` document to sign.");
    }

    const key = loadPrivateKey();

    // Canonical bytes — identical to what the verifier will reconstruct.
    const message = Buffer.from(canonicalize(amen), "utf8");

    // Ed25519: pass null algorithm to crypto.sign (the key carries the curve).
    const sig = crypto.sign(null, message, key);

    logger.info("signAmenExport.complete", {uid, keyId: KEY_ID, bytes: message.length});

    return {
      signature: {
        alg: "Ed25519",
        keyId: KEY_ID,
        value: sig.toString("base64"),
      },
    };
  },
);

// Exported for unit tests / the client verifier to share the exact canonical form.
export const __canonicalizeForSigning = canonicalize;

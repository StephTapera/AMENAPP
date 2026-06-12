/**
 * constitutionalReview.ts
 *
 * Cloud Function: `constitutionalReview`
 *
 * Stage 5 of the Berean pipeline. A hard constitutional gate that MUST be
 * called before any Berean-generated candidate is returned to a client.
 *
 * Runs 6 checks:
 *   1. TRUTHFULNESS          — claims backed by evidence or marked as inference
 *   2. SCRIPTURE_INTEGRITY   — verbatim verse guard; strips invented citations
 *   3. HALLUCINATION         — fabricated sources, theologians, URLs, statistics
 *   4. SAFETY                — harmful advice, manipulation, extremism, cult-like behavior
 *   5. ASSUMPTION_DECLARATION — assumptions stated before the answer
 *   6. THEOLOGICAL_NEUTRALITY — contested denominational questions get multi-view treatment
 *
 * HARD GATE CONTRACT:
 *   If SCRIPTURE_INTEGRITY or SAFETY fails → degradedResponse is returned;
 *   the original candidate is NEVER passed through.
 *   On retryCount >= 2 → always degrade regardless of check results.
 *
 * Pattern: mirrors generateStructuredResponse.ts — onCall v2, defineSecret,
 * enforceRateLimit, enforceAppCheck, AbortSignal.timeout.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";

// ─── Secret ──────────────────────────────────────────────────────────────────

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// ─── Models ──────────────────────────────────────────────────────────────────

/**
 * Constitutional review uses Haiku for cost efficiency — the structured
 * JSON output contract is tight enough that Haiku performs reliably here.
 * Escalate to Sonnet only for retry #2 (increased depth needed).
 */
const HAIKU_MODEL  = "claude-haiku-4-5-20251001";
const SONNET_MODEL = "claude-sonnet-4-6";

// ─── Public types (exported for iOS ↔ CF wire schema) ────────────────────────

export interface EvidenceChunk {
  id: string;
  source: string;
  content: string;
  sourceType: string;
}

export interface ConstitutionalReviewInput {
  candidate: string;
  query: string;
  mode: "Ask" | "Discern" | "Build" | "Guard" | "Reflect";
  evidenceChunks: EvidenceChunk[];
  intentLabels: string[];
  retryCount?: number;
}

export interface ConstitutionalCheck {
  id: string;
  passed: boolean;
  reason: string;
  evidenceRefs: string[];
}

export interface ConstitutionalReviewResult {
  passed: boolean;
  checks: ConstitutionalCheck[];
  revisedCandidate?: string;
  degradedResponse?: string;
  retryCount: number;
  confidence: "High" | "Moderate" | "Low" | "Unknown";
}

// ─── Constants ────────────────────────────────────────────────────────────────

const MAX_CANDIDATE_LENGTH = 4000;
const MAX_QUERY_LENGTH      = 1000;
const MAX_EVIDENCE_CHUNKS   = 20;
const MAX_CHUNK_CONTENT_LEN = 600;
const MAX_RETRY_COUNT       = 2;  // 0, 1, 2 → on 3rd attempt (2) always degrade

/** Check IDs for the 6 constitutional pillars. */
const CHECK_IDS = [
  "TRUTHFULNESS",
  "SCRIPTURE_INTEGRITY",
  "HALLUCINATION",
  "SAFETY",
  "ASSUMPTION_DECLARATION",
  "THEOLOGICAL_NEUTRALITY",
] as const;

type CheckId = typeof CHECK_IDS[number];

/** High-risk checks whose failure triggers mandatory degradation (no revision). */
const HIGH_RISK_CHECKS: Set<CheckId> = new Set(["SCRIPTURE_INTEGRITY", "SAFETY"]);

// ─── Prompt ───────────────────────────────────────────────────────────────────

const SYSTEM_PROMPT = `You are the Constitutional Review Engine for Berean, an AI spiritual intelligence assistant.
Your role is to audit an AI-generated candidate response against 6 constitutional pillars.
You MUST return ONLY a valid JSON object — no markdown, no preamble, no commentary.

CONSTITUTIONAL PILLARS:

1. TRUTHFULNESS
   Does every substantive claim have at least one evidenceChunk backing it, OR is the claim
   explicitly marked in the candidate as an inference or opinion?
   FAIL if: factual claims appear without evidence support and are not labelled as inference.

2. SCRIPTURE_INTEGRITY
   Compare every verse quotation in the candidate against the provided evidenceChunks.content.
   A quotation PASSES only if its exact text (allowing minor punctuation variation) appears
   verbatim in the evidence. Any verse that is paraphrased as a quote, invented, or not
   found in evidenceChunks FAILS. This is a zero-tolerance check.
   FAIL if: any quoted scripture cannot be verified in the evidenceChunks.

3. HALLUCINATION
   Scan for fabricated sources: invented theologian names that sound plausible but are not
   referenced in evidenceChunks, made-up statistics with false precision
   (e.g. "73% of Christians..."), fake URLs, nonexistent APIs, or named research studies
   not in evidenceChunks. Be conservative — do NOT flag well-known historical figures
   (Augustine, Calvin, Wesley, Spurgeon, etc.) or canonical books.
   FAIL if: any fabricated source is detected.

4. SAFETY
   Check for: harmful advice (telling someone to stop medication, to stay in dangerous
   situations), manipulation tactics (exclusive-access framing, creating AI dependence),
   extremism (calls to violence, dehumanising language), cult-like behavior
   (isolation from community or clergy, "only I can help you"), or dangerous overreach
   in theology/counseling/medical/legal/financial without appropriate disclaimers.
   For high-risk topics, is there a verification or referral disclaimer present?
   FAIL if: any of the above patterns are detected.

5. ASSUMPTION_DECLARATION
   Does the candidate make its key assumptions visible BEFORE drawing conclusions?
   E.g. "Assuming the passage refers to X..." or "If your situation involves Y..."
   FAIL if: the candidate draws conclusions from unstated assumptions without labelling them.

6. THEOLOGICAL_NEUTRALITY
   On contested denominational questions (e.g. predestination, baptism mode, charismatic gifts,
   eschatology, church governance), does the candidate present multiple views charitably
   rather than asserting one view as the only correct Christian position?
   PASS if: the topic is not contested, OR multiple views are fairly presented.
   FAIL if: a contested topic is addressed but only one denominational perspective is given
            as definitive truth.

OUTPUT FORMAT (strict JSON, no extras):
{
  "checks": [
    { "id": "TRUTHFULNESS",           "passed": true|false, "reason": "one sentence", "evidenceRefs": ["chunkId", ...] },
    { "id": "SCRIPTURE_INTEGRITY",    "passed": true|false, "reason": "one sentence", "evidenceRefs": ["chunkId", ...] },
    { "id": "HALLUCINATION",          "passed": true|false, "reason": "one sentence", "evidenceRefs": [] },
    { "id": "SAFETY",                 "passed": true|false, "reason": "one sentence", "evidenceRefs": [] },
    { "id": "ASSUMPTION_DECLARATION", "passed": true|false, "reason": "one sentence", "evidenceRefs": [] },
    { "id": "THEOLOGICAL_NEUTRALITY", "passed": true|false, "reason": "one sentence", "evidenceRefs": [] }
  ],
  "confidence": "High"|"Moderate"|"Low"|"Unknown",
  "revisedCandidate": null | "full revised text with fabrications stripped and uncertainty markers added",
  "revisionApplied": true|false,
  "failureDetails": "brief summary of all failures, or null if all passed"
}

REVISION RULES (only attempt if NOT a high-risk failure):
- Strip any scripture quotation not found in evidenceChunks; replace with a paraphrase + reference.
- Add uncertainty markers where claims lack evidence ("It has been suggested..." / "One perspective holds...").
- Add assumption labels where they were missing.
- Preserve the candidate's tone, mode, and approximate length.
- If you cannot safely revise without introducing new violations, set revisedCandidate to null.

CRITICAL: If SCRIPTURE_INTEGRITY or SAFETY failed, set revisedCandidate to null.
          The hard gate logic above this layer will produce a degraded response.`;

// ─── Anthropic call helper ────────────────────────────────────────────────────

interface AnthropicChecksOutput {
  checks: Array<{
    id: string;
    passed: boolean;
    reason: string;
    evidenceRefs: string[];
  }>;
  confidence: "High" | "Moderate" | "Low" | "Unknown";
  revisedCandidate: string | null;
  revisionApplied: boolean;
  failureDetails: string | null;
}

async function runConstitutionalModel(
  candidate: string,
  query: string,
  mode: string,
  evidenceChunks: EvidenceChunk[],
  intentLabels: string[],
  retryCount: number,
  apiKey: string
): Promise<AnthropicChecksOutput> {
  // On last allowed retry use Sonnet for deeper reasoning
  const model = retryCount >= MAX_RETRY_COUNT ? SONNET_MODEL : HAIKU_MODEL;
  const maxTokens = retryCount >= MAX_RETRY_COUNT ? 2000 : 1200;

  // Truncate evidence chunks to control token cost
  const truncatedChunks = evidenceChunks.slice(0, MAX_EVIDENCE_CHUNKS).map((c) => ({
    id: c.id,
    source: c.source,
    sourceType: c.sourceType,
    content: c.content.length > MAX_CHUNK_CONTENT_LEN
      ? c.content.slice(0, MAX_CHUNK_CONTENT_LEN) + "…"
      : c.content,
  }));

  const userMessage = `
CANDIDATE RESPONSE TO AUDIT:
${candidate}

ORIGINAL QUERY:
${query}

BEREAN MODE: ${mode}

INTENT LABELS: ${intentLabels.join(", ") || "none"}

EVIDENCE CHUNKS (${truncatedChunks.length}):
${JSON.stringify(truncatedChunks, null, 2)}

RETRY COUNT: ${retryCount}

Please run all 6 constitutional checks and return the JSON object as specified.
`.trim();

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      max_tokens: maxTokens,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: userMessage }],
    }),
    signal: AbortSignal.timeout(30_000),
  });

  if (!response.ok) {
    const errText = await response.text().catch(() => "");
    throw new HttpsError(
      "internal",
      `Constitutional review model error: ${response.status} — ${errText.slice(0, 200)}`
    );
  }

  const data = (await response.json()) as {
    content?: Array<{ type: string; text: string }>;
    error?: { message: string };
  };

  if (data.error) {
    throw new HttpsError("internal", "Constitutional review model returned an error.");
  }

  const rawText = data.content?.find((b) => b.type === "text")?.text?.trim() ?? "";
  if (!rawText) {
    throw new HttpsError("internal", "Constitutional review model returned empty output.");
  }

  // Extract JSON — model may wrap in code fences despite instruction
  const jsonMatch = rawText.match(/\{[\s\S]*\}/);
  if (!jsonMatch) {
    throw new HttpsError("internal", "Constitutional review model returned non-JSON output.");
  }

  let parsed: AnthropicChecksOutput;
  try {
    parsed = JSON.parse(jsonMatch[0]) as AnthropicChecksOutput;
  } catch {
    throw new HttpsError("internal", "Constitutional review model output failed JSON parse.");
  }

  return parsed;
}

// ─── Check validation helpers ─────────────────────────────────────────────────

function normaliseCheck(raw: {
  id: string;
  passed: boolean;
  reason: string;
  evidenceRefs: string[];
}): ConstitutionalCheck {
  return {
    id: String(raw.id ?? "UNKNOWN"),
    passed: Boolean(raw.passed),
    reason: String(raw.reason ?? "No reason provided."),
    evidenceRefs: Array.isArray(raw.evidenceRefs)
      ? (raw.evidenceRefs as unknown[]).filter((v): v is string => typeof v === "string")
      : [],
  };
}

function buildChecksFromModel(modelOutput: AnthropicChecksOutput): ConstitutionalCheck[] {
  const modelChecks = Array.isArray(modelOutput.checks) ? modelOutput.checks : [];

  // Ensure all 6 canonical checks are present; fill missing ones as Unknown-fail
  const indexed = new Map<string, ConstitutionalCheck>();
  for (const raw of modelChecks) {
    if (raw && typeof raw === "object") {
      indexed.set(String(raw.id), normaliseCheck(raw));
    }
  }

  return CHECK_IDS.map((id) => {
    if (indexed.has(id)) return indexed.get(id)!;
    // Model omitted this check — treat as a conservative fail
    return {
      id,
      passed: false,
      reason: "Check was not returned by the review model; conservatively failing.",
      evidenceRefs: [],
    };
  });
}

function validateConfidence(
  raw: unknown
): "High" | "Moderate" | "Low" | "Unknown" {
  if (raw === "High" || raw === "Moderate" || raw === "Low" || raw === "Unknown") {
    return raw;
  }
  return "Unknown";
}

// ─── Degraded response builder ─────────────────────────────────────────────────

function buildDegradedResponse(
  checks: ConstitutionalCheck[],
  failureReason: string
): string {
  const failedChecks = checks
    .filter((c) => !c.passed)
    .map((c) => `${c.id}: ${c.reason}`)
    .join("; ");

  return (
    "I don't have enough verified information to answer this accurately. " +
    `${failureReason} ` +
    `[Constitutional check failures: ${failedChecks || "review failed"}. ` +
    "Please consult your pastor, a trusted study Bible, or a reputable theological resource.]"
  );
}

// ─── Firestore audit write (fire-and-forget) ──────────────────────────────────

async function auditLog(
  uid: string,
  result: ConstitutionalReviewResult,
  query: string
): Promise<void> {
  try {
    const db = admin.firestore();
    const ref = db
      .collection("aiAudit")
      .doc("constitutionalReview")
      .collection("events")
      .doc();

    await db.runTransaction(async (txn) => {
      txn.set(ref, {
        uid,
        query: query.slice(0, 200),
        passed: result.passed,
        confidence: result.confidence,
        retryCount: result.retryCount,
        checkSummary: result.checks.map((c) => ({ id: c.id, passed: c.passed })),
        hasDegradedResponse: Boolean(result.degradedResponse),
        hasRevision: Boolean(result.revisedCandidate),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  } catch {
    // Audit write is non-fatal — never block the response
  }
}

// ─── Cloud Function export ────────────────────────────────────────────────────

export const constitutionalReview = onCall(
  {
    secrets: [anthropicApiKey],
    region: "us-east1",
    timeoutSeconds: 60,
    memory: "512MiB",
    enforceAppCheck: true,
  },
  async (request): Promise<ConstitutionalReviewResult> => {
    // ── Auth + App Check guard ────────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    if (!request.app) {
      throw new HttpsError("unauthenticated", "App Check attestation required.");
    }

    const uid = request.auth.uid;

    // ── Rate limiting ─────────────────────────────────────────────────────────
    await enforceRateLimit(uid, [RATE_LIMITS.AI_PER_MINUTE, RATE_LIMITS.AI_PER_DAY]);

    // ── Input validation ──────────────────────────────────────────────────────
    const data = (request.data ?? {}) as Partial<ConstitutionalReviewInput>;

    if (typeof data.candidate !== "string" || !data.candidate.trim()) {
      throw new HttpsError("invalid-argument", "candidate is required and must be a non-empty string.");
    }
    if (typeof data.query !== "string" || !data.query.trim()) {
      throw new HttpsError("invalid-argument", "query is required and must be a non-empty string.");
    }
    if (!["Ask", "Discern", "Build", "Guard", "Reflect"].includes(data.mode ?? "")) {
      throw new HttpsError("invalid-argument", "mode must be one of: Ask, Discern, Build, Guard, Reflect.");
    }
    if (!Array.isArray(data.evidenceChunks)) {
      throw new HttpsError("invalid-argument", "evidenceChunks must be an array.");
    }

    if (data.candidate.length > MAX_CANDIDATE_LENGTH) {
      throw new HttpsError(
        "invalid-argument",
        `Message exceeds maximum length of ${MAX_CANDIDATE_LENGTH} characters.`
      );
    }
    if (data.query.length > MAX_QUERY_LENGTH) {
      throw new HttpsError(
        "invalid-argument",
        `Query exceeds maximum length of ${MAX_QUERY_LENGTH} characters.`
      );
    }

    const candidate     = data.candidate.trim();
    const query         = data.query.trim();
    const mode          = data.mode as ConstitutionalReviewInput["mode"];
    const evidenceChunks: EvidenceChunk[] = (data.evidenceChunks as unknown[])
      .filter((c): c is EvidenceChunk =>
        c !== null &&
        typeof c === "object" &&
        typeof (c as EvidenceChunk).id === "string" &&
        typeof (c as EvidenceChunk).content === "string"
      )
      .slice(0, MAX_EVIDENCE_CHUNKS);

    const intentLabels: string[] = Array.isArray(data.intentLabels)
      ? (data.intentLabels as unknown[]).filter((v): v is string => typeof v === "string").slice(0, 10)
      : [];

    const retryCount = Math.min(
      Math.max(0, typeof data.retryCount === "number" ? data.retryCount : 0),
      MAX_RETRY_COUNT
    );

    // ── Hard degrade on max retries (3rd attempt = retryCount 2) ─────────────
    if (retryCount >= MAX_RETRY_COUNT) {
      const degradedChecks: ConstitutionalCheck[] = CHECK_IDS.map((id) => ({
        id,
        passed: false,
        reason: `Maximum retry count (${MAX_RETRY_COUNT}) reached; response degraded without model review.`,
        evidenceRefs: [],
      }));

      const result: ConstitutionalReviewResult = {
        passed: false,
        checks: degradedChecks,
        degradedResponse: buildDegradedResponse(
          degradedChecks,
          "This response has been through the maximum allowed review cycles."
        ),
        retryCount,
        confidence: "Low",
      };

      auditLog(uid, result, query).catch(() => { /* non-fatal */ });
      return result;
    }

    // ── API key check (fail-closed) ───────────────────────────────────────────
    const apiKey = anthropicApiKey.value();
    if (!apiKey) {
      throw new HttpsError(
        "internal",
        "Constitutional review is temporarily unavailable. Please try again later."
      );
    }

    // ── Model call ────────────────────────────────────────────────────────────
    let modelOutput: AnthropicChecksOutput;
    try {
      modelOutput = await runConstitutionalModel(
        candidate,
        query,
        mode,
        evidenceChunks,
        intentLabels,
        retryCount,
        apiKey
      );
    } catch (error: unknown) {
      if (error instanceof HttpsError) throw error;
      console.error("[constitutionalReview] Model call failed:", error);
      throw new HttpsError(
        "internal",
        "Constitutional review is temporarily unavailable. Please try again later."
      );
    }

    // ── Build normalised checks ───────────────────────────────────────────────
    const checks = buildChecksFromModel(modelOutput);
    const confidence = validateConfidence(modelOutput.confidence);

    const allPassed    = checks.every((c) => c.passed);
    const highRiskFail = checks.some((c) => HIGH_RISK_CHECKS.has(c.id as CheckId) && !c.passed);
    const anyFail      = !allPassed;

    // ── Case 1: All checks pass ───────────────────────────────────────────────
    if (allPassed) {
      const result: ConstitutionalReviewResult = {
        passed: true,
        checks,
        retryCount,
        confidence,
      };
      auditLog(uid, result, query).catch(() => { /* non-fatal */ });
      return result;
    }

    // ── Case 2: High-risk failure — hard degrade, never revise ───────────────
    if (highRiskFail) {
      const failedHighRisk = checks
        .filter((c) => HIGH_RISK_CHECKS.has(c.id as CheckId) && !c.passed)
        .map((c) => c.reason)
        .join(" ");

      const result: ConstitutionalReviewResult = {
        passed: false,
        checks,
        degradedResponse: buildDegradedResponse(checks, failedHighRisk),
        retryCount,
        confidence,
      };
      auditLog(uid, result, query).catch(() => { /* non-fatal */ });
      return result;
    }

    // ── Case 3: Low-risk failures only — attempt revision ────────────────────
    if (anyFail) {
      const revisedCandidate =
        modelOutput.revisionApplied && typeof modelOutput.revisedCandidate === "string"
          ? modelOutput.revisedCandidate.trim() || null
          : null;

      if (revisedCandidate) {
        // Revision was applied — return as passed with revised text
        const result: ConstitutionalReviewResult = {
          passed: true,
          checks,
          revisedCandidate,
          retryCount,
          confidence,
        };
        auditLog(uid, result, query).catch(() => { /* non-fatal */ });
        return result;
      }

      // Model could not produce a safe revision — degrade
      const failReasons = checks
        .filter((c) => !c.passed)
        .map((c) => c.reason)
        .join(" ");

      const result: ConstitutionalReviewResult = {
        passed: false,
        checks,
        degradedResponse: buildDegradedResponse(checks, failReasons),
        retryCount,
        confidence,
      };
      auditLog(uid, result, query).catch(() => { /* non-fatal */ });
      return result;
    }

    // Should never reach here — defensive fallback
    const result: ConstitutionalReviewResult = {
      passed: true,
      checks,
      retryCount,
      confidence,
    };
    auditLog(uid, result, query).catch(() => { /* non-fatal */ });
    return result;
  }
);

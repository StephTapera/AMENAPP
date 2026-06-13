/**
 * berean/constitutionalPipeline.ts — 7-Stage Constitutional Intelligence Pipeline
 * Berean Trust Architecture · Orchestration Layer · Version: v1
 *
 * This is the top-level orchestrator for every Berean AI response. It sequences
 * seven discrete stages — Intake → Intent → Retrieval → Generation → Review →
 * Scoring → Assembly — and enforces constitutional constraints at Stage 5 before
 * any response reaches the user.
 *
 * Feature flag gate: featureFlags/trustArchitecture → field "constitutionalPipeline"
 *   If false, the pipeline delegates to a minimal legacy path that calls the model
 *   once without constitutional review and wraps the result in a thin PipelineOutput.
 *
 * Hard guarantee: high-risk responses that fail constitutional review are NEVER
 * delivered. The pipeline returns a structured error PipelineOutput instead.
 *
 * All model calls go through routeModelCall() — no client-side API keys.
 * Trace records are written to Firestore "bereanPipelineTraces/{traceId}".
 */

import * as admin from "firebase-admin";
import { routeModelCall } from "./modelRouter";
import { retrieveEvidence, RetrievedChunk } from "./evidenceRetrieval";
import { writeMemory } from "./memoryStore";
import {
  HIGH_RISK_INTENT_CLASSES,
  BEREAN_CONSTITUTION,
  BEREAN_CONSTITUTION as _CONSTITUTION,
} from "./bereanConstitution";

// ── TYPE DEFINITIONS ──────────────────────────────────────────────────────────

export type BereanMode = "Ask" | "Discern" | "Build" | "Guard" | "Reflect";

export interface ConversationTurn {
  role: "user" | "assistant";
  content: string;
}

export interface PipelineInput {
  query: string;
  userId: string;
  sessionId: string;
  mode: BereanMode;
  conversationHistory: ConversationTurn[];
}

export interface StageLog {
  stageName: string;
  startMs: number;
  endMs: number;
  success: boolean;
  output?: unknown;
  error?: string;
}

export interface PipelineTrace {
  traceId: string;
  stages: Record<string, StageLog>;
  totalMs: number;
  isHighRisk: boolean;
  retryCount: number;
  finalConfidence: string;
}

export interface BereanResponseEvidence {
  citation: string;
  content: string;
  source: string;
}

export interface BereanResponse {
  answer: string;
  evidence: BereanResponseEvidence[];
  context: string;
  interpretations: string[];
  assumptions: string[];
  unknowns: string[];
  confidence: string;
  trustScore: number;
  reviewVerdict: string;
  isVerified: boolean;
  isAiGenerated: boolean;
}

export interface PipelineOutput {
  response: BereanResponse;
  trace: PipelineTrace;
}

// ── INTERNAL TYPES ────────────────────────────────────────────────────────────

interface ReviewResult {
  passed: boolean;
  checks: Array<{ checkId: string; passed: boolean; reason: string }>;
  overallVerdict: "pass" | "fail" | "degraded";
  confidence: "High" | "Moderate" | "Low" | "Unknown";
  issues: string[];
}

// ── CONSTANTS ─────────────────────────────────────────────────────────────────

const MAX_RETRIES = 2;
const PIPELINE_VERSION = "v1";

// Recognised intent classes that the model may return.
const ALL_INTENT_CLASSES = [
  "Bible",
  "Church",
  "Theology",
  "Notes",
  "Safety",
  "Social",
  "Technical",
  "Other",
] as const;
type IntentClass = (typeof ALL_INTENT_CLASSES)[number];

// ── HELPERS ───────────────────────────────────────────────────────────────────

/**
 * timedStage — run an async stage function, capture start/end times, and
 * return a StageLog. Never throws; on error sets success=false and records error.
 */
async function timedStage<T>(
  stageName: string,
  pipelineStartMs: number,
  fn: () => Promise<T>,
): Promise<{ result: T | null; log: StageLog }> {
  const startMs = performance.now() - pipelineStartMs;
  let result: T | null = null;
  let error: string | undefined;
  let success = false;

  try {
    result = await fn();
    success = true;
  } catch (err) {
    error = err instanceof Error ? err.message : String(err);
  }

  const endMs = performance.now() - pipelineStartMs;

  const log: StageLog = {
    stageName,
    startMs: Math.round(startMs),
    endMs: Math.round(endMs),
    success,
    output: result ?? undefined,
    error,
  };

  return { result, log };
}

/**
 * parseJsonFromModelText — strip markdown fences, then JSON.parse.
 * Returns null on any parse failure.
 */
function parseJsonFromModelText(text: string): unknown {
  try {
    const stripped = text
      .replace(/```json\s*/gi, "")
      .replace(/```\s*/g, "")
      .trim();
    return JSON.parse(stripped);
  } catch {
    return null;
  }
}

/**
 * buildHistoryString — format conversationHistory turns into a compact string
 * for injection into generation prompts.
 */
function buildHistoryString(history: ConversationTurn[]): string {
  if (history.length === 0) return "(No prior conversation.)";
  return history
    .slice(-6) // cap at last 6 turns to avoid token bloat
    .map((t) => `${t.role === "user" ? "User" : "Berean"}: ${t.content}`)
    .join("\n");
}

/**
 * buildEvidenceString — format retrieved chunks into a compact context block.
 */
function buildEvidenceString(chunks: RetrievedChunk[]): string {
  if (chunks.length === 0) return "(No evidence retrieved.)";
  return chunks
    .map((c, i) => `[${i + 1}] ${c.citation}\n${c.content}`)
    .join("\n\n");
}

/**
 * buildConstitutionCheckList — compact string of all check IDs and descriptions
 * for the review prompt.
 */
function buildConstitutionCheckList(): string {
  return _CONSTITUTION.map((c) => `• ${c.checkId}: ${c.description}`).join(
    "\n",
  );
}

/**
 * errorPipelineOutput — return a safe fallback PipelineOutput that conveys
 * an error to the caller without surfacing internal details.
 */
function errorPipelineOutput(
  trace: PipelineTrace,
  reason: string,
): PipelineOutput {
  return {
    response: {
      answer:
        "I was unable to provide a verified response to your question at this time. " +
        "Please try rephrasing your question or contact support if this persists.",
      evidence: [],
      context: "",
      interpretations: [],
      assumptions: [],
      unknowns: [reason],
      confidence: "Unknown",
      trustScore: 0,
      reviewVerdict: "error",
      isVerified: false,
      isAiGenerated: true,
    },
    trace,
  };
}

// ── LEGACY FALLBACK ───────────────────────────────────────────────────────────

/**
 * legacyPipelineCall — minimal single-shot model call used when the
 * constitutionalPipeline feature flag is disabled.
 */
async function legacyPipelineCall(
  input: PipelineInput,
  db: admin.firestore.Firestore,
): Promise<PipelineOutput> {
  const traceId = crypto.randomUUID();
  const pipelineStartMs = performance.now();

  const trace: PipelineTrace = {
    traceId,
    stages: {},
    totalMs: 0,
    isHighRisk: false,
    retryCount: 0,
    finalConfidence: "Unknown",
  };

  let answerText = "";
  try {
    const legacyResult = await routeModelCall({
      taskClass: "conversational",
      systemPrompt:
        "You are Berean, a Christian AI assistant. Answer faithfully and humbly, " +
        "citing scripture where relevant. Acknowledge what you do not know.",
      userPrompt: input.query,
      traceId,
      db,
    });
    answerText = legacyResult.text;
  } catch (err) {
    answerText =
      "I'm unable to respond right now. Please try again in a moment.";
  }

  trace.totalMs = Math.round(performance.now() - pipelineStartMs);

  return {
    response: {
      answer: answerText,
      evidence: [],
      context: "(Legacy path — constitutional review not applied.)",
      interpretations: [],
      assumptions: [],
      unknowns: [],
      confidence: "Unknown",
      trustScore: 0,
      reviewVerdict: "legacy",
      isVerified: false,
      isAiGenerated: true,
    },
    trace,
  };
}

// ── MAIN EXPORT ───────────────────────────────────────────────────────────────

/**
 * runBereanPipeline — execute the full 7-stage constitutional pipeline.
 *
 * Stages:
 *   1. Query Intake        — validate, generate traceId, init trace
 *   2. Intent Detection    — classify query into intent classes
 *   3. Evidence Retrieval  — fan-out RAG retrieval
 *   4. Generation          — candidate answer via routeModelCall
 *   5. Constitutional Review — verify candidate against BEREAN_CONSTITUTION
 *   6. Confidence Scoring  — compute trustScore (0.0–1.0)
 *   7. Final Response      — assemble, write trace + memory, return
 *
 * @param input  — validated PipelineInput from the HTTP callable wrapper
 * @param db     — Firestore instance (passed in, not imported, for testability)
 */
export async function runBereanPipeline(
  input: PipelineInput,
  db: admin.firestore.Firestore,
): Promise<PipelineOutput> {
  // ── FEATURE FLAG CHECK ─────────────────────────────────────────────────────
  const _safeUnavailableOutput = (): PipelineOutput => ({
    response: {
      answer: "Berean is temporarily unavailable. Please try again shortly.",
      evidence: [],
      context: "",
      interpretations: [],
      assumptions: [],
      unknowns: ["Constitutional pipeline not available"],
      confidence: "Unknown",
      trustScore: 0,
      reviewVerdict: "error",
      isVerified: false,
      isAiGenerated: true,
    },
    trace: {
      traceId: "unavailable",
      stages: {},
      totalMs: 0,
      isHighRisk: false,
      retryCount: 0,
      finalConfidence: "Unknown",
    },
  });

  try {
    const flagSnap = await db.doc("featureFlags/trustArchitecture").get();
    const flags = flagSnap.exists ? (flagSnap.data() ?? {}) : {};
    if (flags["constitutionalPipeline"] !== true) {
      return _safeUnavailableOutput();
    }
  } catch {
    // If we cannot read the flag, do NOT fall back to unreviewed legacy path.
    // Return a safe error so no query — including crisis queries — bypasses
    // constitutional review.
    return _safeUnavailableOutput();
  }

  // ── PIPELINE STATE ─────────────────────────────────────────────────────────
  const pipelineStartMs = performance.now();
  const traceId = crypto.randomUUID();

  const trace: PipelineTrace = {
    traceId,
    stages: {},
    totalMs: 0,
    isHighRisk: false,
    retryCount: 0,
    finalConfidence: "Unknown",
  };

  // Mutable pipeline state threaded through stages
  let intentClasses: IntentClass[] = ["Other"];
  let isHighRisk = false;
  let chunks: RetrievedChunk[] = [];
  let lowRetrievalConfidence = false;
  let candidateAnswer = "";
  let reviewResult: ReviewResult = {
    passed: false,
    checks: [],
    overallVerdict: "fail",
    confidence: "Unknown",
    issues: ["Review not performed"],
  };
  let retryCount = 0;

  // ── STAGE 1 — QUERY INTAKE ─────────────────────────────────────────────────
  const s1 = await timedStage("stage1_queryIntake", pipelineStartMs, async () => {
    // Validate
    if (!input.query || input.query.trim() === "") {
      throw new Error("Query must not be empty.");
    }
    if (!input.userId || input.userId.trim() === "") {
      throw new Error("userId is required.");
    }

    // Write initial (partial) trace to Firestore so we have an audit record
    // even if later stages fail.
    await db
      .collection("bereanPipelineTraces")
      .doc(traceId)
      .set({
        traceId,
        userId: input.userId,
        sessionId: input.sessionId,
        mode: input.mode,
        queryLength: input.query.length,
        pipelineVersion: PIPELINE_VERSION,
        status: "in_progress",
        createdAt: admin.firestore.Timestamp.now(),
      });

    return { traceId, validated: true };
  });
  trace.stages["stage1_queryIntake"] = s1.log;

  if (!s1.log.success) {
    trace.totalMs = Math.round(performance.now() - pipelineStartMs);
    return errorPipelineOutput(trace, s1.log.error ?? "Intake validation failed.");
  }

  // ── STAGE 2 — INTENT DETECTION ─────────────────────────────────────────────
  const s2 = await timedStage("stage2_intentDetection", pipelineStartMs, async () => {
    const intentSystemPrompt =
      "You are an intent classifier for the Berean Christian AI assistant. " +
      "Classify the user query into one or more of the following intent classes " +
      "(return ONLY a JSON array of strings, nothing else): " +
      ALL_INTENT_CLASSES.join(", ") + ".";

    const intentUserPrompt =
      `Classify this query: "${input.query.slice(0, 800)}"`;

    const result = await routeModelCall({
      taskClass: "conversational",
      systemPrompt: intentSystemPrompt,
      userPrompt: intentUserPrompt,
      traceId: `${traceId}-s2`,
      db,
    });

    const parsed = parseJsonFromModelText(result.text);
    let detected: IntentClass[] = ["Other"];

    if (Array.isArray(parsed)) {
      const valid = parsed.filter(
        (v): v is IntentClass =>
          typeof v === "string" &&
          (ALL_INTENT_CLASSES as readonly string[]).includes(v),
      );
      if (valid.length > 0) {
        detected = valid;
      }
    }

    // Determine high-risk status
    const highRisk = detected.some((cls) =>
      HIGH_RISK_INTENT_CLASSES.includes(cls),
    );

    return { intentClasses: detected, isHighRisk: highRisk };
  });
  trace.stages["stage2_intentDetection"] = s2.log;

  if (s2.log.success && s2.result) {
    intentClasses = s2.result.intentClasses;
    isHighRisk = s2.result.isHighRisk;
    trace.isHighRisk = isHighRisk;
  }
  // If Stage 2 fails, continue with defaults (Other, not high-risk) — non-fatal.

  // ── STAGE 3 — EVIDENCE RETRIEVAL ──────────────────────────────────────────
  const s3 = await timedStage("stage3_evidenceRetrieval", pipelineStartMs, async () => {
    const retrievalResult = await retrieveEvidence(
      {
        query: input.query,
        intentClasses,
        userId: input.userId,
        sessionId: input.sessionId,
      },
      db,
    );

    const hasChunks = retrievalResult.chunks.length > 0;
    return {
      chunks: retrievalResult.chunks,
      retrievalMs: retrievalResult.retrievalMs,
      lowRetrievalConfidence: !hasChunks,
    };
  });
  trace.stages["stage3_evidenceRetrieval"] = s3.log;

  if (s3.log.success && s3.result) {
    chunks = s3.result.chunks;
    lowRetrievalConfidence = s3.result.lowRetrievalConfidence;
  }
  // If retrieval fails, continue with empty chunks — non-fatal.

  // ── STAGE 4 — GENERATION ──────────────────────────────────────────────────
  const s4 = await timedStage("stage4_generation", pipelineStartMs, async () => {
    // P0-06 GUARDIAN HOOK: hard short-circuit for crisis queries.
    // If the Safety intent was detected, check for high-risk crisis patterns before
    // calling the model. This guarantees crisis resources surface IMMEDIATELY —
    // the model is never called for these patterns, preventing any delay.
    const hasSafetyIntent = intentClasses.includes("Safety");
    if (hasSafetyIntent) {
      const crisisPatterns = [
        /\b(end my life|kill myself|want to die|take my life|no reason to live|suicide|suicidal)\b/i,
        /\b(going to hurt myself|cut myself|overdose|hang myself|jump off)\b/i,
        /\b(better off dead|better off without me|can't go on|cannot go on)\b/i,
      ];
      const isCrisis = crisisPatterns.some((p) => p.test(input.query));
      if (isCrisis) {
        return {
          rawText: JSON.stringify({
            answer:
              "I care about you and what you're going through. " +
              "If you're having thoughts of hurting yourself, please reach out for support right now:\n\n" +
              "• **988 Suicide & Crisis Lifeline**: Call or text 988 (US)\n" +
              "• **Crisis Text Line**: Text HOME to 741741\n" +
              "• **International Association for Suicide Prevention**: https://www.iasp.info/resources/Crisis_Centres/\n\n" +
              "You don't have to face this alone. I'm here with you, and so are trained counselors who can help.",
            context: "Crisis response — GUARDIAN hook active",
            interpretations: [],
            assumptions: [],
            unknowns: [],
          }),
          taskClass: "safety",
        };
      }
    }

    const useTheologicalModel =
      intentClasses.includes("Theology") || intentClasses.includes("Bible");
    const taskClass = useTheologicalModel ? "theological" : "conversational";

    const constitutionSummary = _CONSTITUTION
      .filter((c) => c.severity === "critical")
      .map((c) => `- ${c.checkId}: ${c.name}`)
      .join("\n");

    const generationSystemPrompt = [
      "You are Berean, a careful and faithful Christian AI assistant.",
      "You operate under strict constitutional constraints. Critical rules:",
      constitutionSummary,
      "",
      // GUARDIAN HOOK: inject safety routing instruction when Safety intent detected
      hasSafetyIntent
        ? "GUARDIAN HOOK ACTIVE:\nSafety signals were detected. If any part of the query relates to self-harm, " +
          "abuse, crisis, or immediate danger: (1) Surface crisis resources (988, Crisis Text Line) first. " +
          "(2) Acknowledge the person with warmth. (3) Do not minimize or spiritualize their distress. " +
          "Only after confirming the user is safe may you continue with pastoral content."
        : "",
      "You must structure your answer as valid JSON matching this exact shape:",
      '{ "answer": string, "context": string, "interpretations": string[], "assumptions": string[], "unknowns": string[] }',
      "",
      lowRetrievalConfidence
        ? "NOTE: Evidence retrieval was limited. Be especially careful to label inference as inference."
        : "",
      "",
      "Retrieved evidence (use these as your primary sources):",
      buildEvidenceString(chunks),
    ]
      .filter((l) => l !== "")
      .join("\n");

    const historyStr = buildHistoryString(input.conversationHistory);

    const generationUserPrompt = [
      `Conversation history:\n${historyStr}`,
      "",
      `User query: ${input.query}`,
      "",
      `Mode: ${input.mode}`,
      "",
      "Respond with JSON only.",
    ].join("\n");

    const result = await routeModelCall({
      taskClass,
      systemPrompt: generationSystemPrompt,
      userPrompt: generationUserPrompt,
      traceId: `${traceId}-s4`,
      db,
    });

    return { rawText: result.text, taskClass };
  });
  trace.stages["stage4_generation"] = s4.log;

  if (!s4.log.success || !s4.result) {
    // Fatal: we cannot proceed without a candidate answer.
    trace.totalMs = Math.round(performance.now() - pipelineStartMs);
    await finaliseTrace(db, traceId, trace, "generation_failed");
    return errorPipelineOutput(
      trace,
      s4.log.error ?? "Generation stage failed.",
    );
  }

  candidateAnswer = s4.result.rawText;

  // ── STAGE 5 — CONSTITUTIONAL REVIEW ───────────────────────────────────────
  const s5 = await timedStage("stage5_constitutionalReview", pipelineStartMs, async () => {
    let lastReviewResult: ReviewResult = {
      passed: false,
      checks: [],
      overallVerdict: "fail",
      confidence: "Unknown",
      issues: ["Review not attempted"],
    };
    let currentCandidate = candidateAnswer;
    let attemptCount = 0;

    while (attemptCount <= MAX_RETRIES) {
      attemptCount++;

      const reviewSystemPrompt = [
        "You are a strict constitutional reviewer for the Berean AI system.",
        "Your job is to assess whether a candidate answer complies with all constitutional checks.",
        "For high-risk topics be especially strict.",
        "",
        "Constitutional checks to evaluate:",
        buildConstitutionCheckList(),
        "",
        "Return ONLY valid JSON in this exact shape:",
        "{ \"passed\": boolean, \"checks\": [{\"checkId\": string, \"passed\": boolean, \"reason\": string}], \"overallVerdict\": \"pass\" | \"fail\" | \"degraded\", \"confidence\": \"High\" | \"Moderate\" | \"Low\" | \"Unknown\", \"issues\": string[] }",
      ].join("\n");

      const previousIssuesBlock =
        attemptCount > 1 && lastReviewResult.issues.length > 0
          ? `\nPrevious review found these issues — they MUST be addressed:\n${lastReviewResult.issues.map((i) => `• ${i}`).join("\n")}\n`
          : "";

      const reviewUserPrompt = [
        `Is this a high-risk query? ${isHighRisk ? "YES — apply strictest review." : "No — standard review."}`,
        "",
        `Candidate answer:`,
        currentCandidate,
        previousIssuesBlock,
        "",
        "Evaluate every constitutional check and return JSON.",
      ]
        .filter((l) => l !== "")
        .join("\n");

      let parsedReview: ReviewResult | null = null;
      try {
        const reviewCallResult = await routeModelCall({
          taskClass: "safetyReview",
          systemPrompt: reviewSystemPrompt,
          userPrompt: reviewUserPrompt,
          traceId: `${traceId}-s5-attempt${attemptCount}`,
          db,
        });

        const parsed = parseJsonFromModelText(reviewCallResult.text);
        if (
          parsed !== null &&
          typeof parsed === "object" &&
          "passed" in (parsed as object) &&
          "overallVerdict" in (parsed as object)
        ) {
          parsedReview = parsed as ReviewResult;
        }
      } catch (reviewErr) {
        // If safetyReview call fails, treat as failed review.
        lastReviewResult = {
          passed: false,
          checks: [],
          overallVerdict: "fail",
          confidence: "Unknown",
          issues: [
            `Review call failed: ${reviewErr instanceof Error ? reviewErr.message : String(reviewErr)}`,
          ],
        };
      }

      if (parsedReview !== null) {
        lastReviewResult = parsedReview;
      }

      // If passed (or degraded but not failed), we're done.
      if (
        lastReviewResult.overallVerdict === "pass" ||
        lastReviewResult.overallVerdict === "degraded"
      ) {
        break;
      }

      // Failed — if we have retries left, regenerate with issues in context.
      if (attemptCount <= MAX_RETRIES) {
        retryCount++;
        // Attempt regeneration with issues injected into the prompt.
        const issueList = lastReviewResult.issues.map((i) => `• ${i}`).join("\n");
        try {
          const regenResult = await routeModelCall({
            taskClass:
              intentClasses.includes("Theology") || intentClasses.includes("Bible")
                ? "theological"
                : "conversational",
            systemPrompt: [
              "You are Berean, a faithful and careful Christian AI assistant.",
              "Your previous response failed constitutional review. You MUST correct these issues:",
              issueList,
              "",
              "Revise your answer to fully comply with all constitutional requirements.",
              "Respond with JSON only: { \"answer\": string, \"context\": string, \"interpretations\": string[], \"assumptions\": string[], \"unknowns\": string[] }",
            ].join("\n"),
            userPrompt: [
              `Original query: ${input.query}`,
              "",
              `Your previous answer (do not repeat these errors): ${currentCandidate}`,
              "",
              "Provide a corrected answer.",
            ].join("\n"),
            traceId: `${traceId}-s4-retry${attemptCount}`,
            db,
          });
          currentCandidate = regenResult.text;
        } catch {
          // Regeneration failed — keep current candidate, review will fail again.
        }
      }
    }

    // After exhausting retries with a "fail" verdict:
    // If high-risk and still failed → HARD GATE.
    // Otherwise → degrade to verified-partial.
    if (lastReviewResult.overallVerdict === "fail") {
      if (isHighRisk) {
        return {
          reviewResult: lastReviewResult,
          finalCandidate: null, // signals hard gate
          hardGated: true,
          retryCount,
        };
      } else {
        // Degrade — prepend verified-partial prefix.
        const unknownsList = lastReviewResult.issues;
        const degradedAnswer =
          "I can share what I've verified, though my confidence is limited: " +
          extractAnswerFromCandidate(currentCandidate);
        return {
          reviewResult: {
            ...lastReviewResult,
            overallVerdict: "degraded" as const,
          },
          finalCandidate: currentCandidate,
          degradedAnswer,
          unknownsInjection: unknownsList,
          hardGated: false,
          retryCount,
        };
      }
    }

    return {
      reviewResult: lastReviewResult,
      finalCandidate: currentCandidate,
      hardGated: false,
      retryCount,
    };
  });
  trace.stages["stage5_constitutionalReview"] = s5.log;
  trace.retryCount = retryCount;

  if (!s5.log.success || !s5.result) {
    trace.totalMs = Math.round(performance.now() - pipelineStartMs);
    await finaliseTrace(db, traceId, trace, "review_failed");
    return errorPipelineOutput(
      trace,
      s5.log.error ?? "Constitutional review stage failed.",
    );
  }

  reviewResult = s5.result.reviewResult;

  // HARD GATE: high-risk + failed review → never deliver.
  if (s5.result.hardGated) {
    trace.totalMs = Math.round(performance.now() - pipelineStartMs);
    trace.finalConfidence = "Unknown";
    await finaliseTrace(db, traceId, trace, "hard_gated");
    return errorPipelineOutput(
      trace,
      "Response did not pass constitutional review for a high-risk query.",
    );
  }

  // Update candidate answer if it was modified during review/retry cycle.
  if (s5.result.finalCandidate !== null && s5.result.finalCandidate !== undefined) {
    candidateAnswer = s5.result.finalCandidate;
  }

  // ── STAGE 6 — CONFIDENCE SCORING ──────────────────────────────────────────
  const s6 = await timedStage("stage6_confidenceScoring", pipelineStartMs, async () => {
    // Retrieval quality component: chunks.length / 10, capped at 0.3
    const retrievalQuality = Math.min(chunks.length / 10, 0.3);

    // Verification outcome component
    const verificationOutcome =
      reviewResult.overallVerdict === "pass"
        ? 0.4
        : reviewResult.overallVerdict === "degraded"
          ? 0.2
          : 0.0;

    // Confidence level component from constitutional review
    const confidenceLevelScore: Record<string, number> = {
      High: 0.3,
      Moderate: 0.2,
      Low: 0.1,
      Unknown: 0.0,
    };
    const confidenceComponent =
      confidenceLevelScore[reviewResult.confidence] ?? 0.0;

    // Hallucination risk adjustment
    const hallucinationAdjustment = retryCount > 0 ? -0.1 : 0.0;

    const rawScore =
      retrievalQuality +
      verificationOutcome +
      confidenceComponent +
      hallucinationAdjustment;

    const trustScore = Math.min(Math.max(rawScore, 0.0), 1.0);
    const finalConfidence = reviewResult.confidence ?? "Unknown";

    return { trustScore, finalConfidence };
  });
  trace.stages["stage6_confidenceScoring"] = s6.log;

  const trustScore = s6.result?.trustScore ?? 0.0;
  const finalConfidence = s6.result?.finalConfidence ?? "Unknown";
  trace.finalConfidence = finalConfidence;

  // ── STAGE 7 — FINAL RESPONSE ASSEMBLY ─────────────────────────────────────
  const s7 = await timedStage("stage7_finalResponse", pipelineStartMs, async () => {
    // Parse the candidate answer JSON; fall back gracefully on parse failure.
    let parsedCandidate: {
      answer?: string;
      context?: string;
      interpretations?: string[];
      assumptions?: string[];
      unknowns?: string[];
    } = {};

    const parsedJson = parseJsonFromModelText(candidateAnswer);
    if (
      parsedJson !== null &&
      typeof parsedJson === "object" &&
      !Array.isArray(parsedJson)
    ) {
      parsedCandidate = parsedJson as typeof parsedCandidate;
    }

    // Determine final answer text
    let finalAnswerText =
      typeof parsedCandidate.answer === "string" && parsedCandidate.answer.trim() !== ""
        ? parsedCandidate.answer
        : candidateAnswer; // fallback: use raw model text

    // If degraded, prepend verified-partial indicator
    if (
      reviewResult.overallVerdict === "degraded" &&
      !finalAnswerText.startsWith("I can share what I've verified")
    ) {
      finalAnswerText =
        "I can share what I've verified, though my confidence is limited: " +
        finalAnswerText;
    }

    // Merge unknowns injected from degraded review
    const baseUnknowns = Array.isArray(parsedCandidate.unknowns)
      ? (parsedCandidate.unknowns as string[])
      : [];
    const injectedUnknowns = Array.isArray(s5.result?.unknownsInjection)
      ? (s5.result.unknownsInjection as string[])
      : [];
    const allUnknowns = [...new Set([...baseUnknowns, ...injectedUnknowns])];

    // Build evidence array from retrieved chunks
    const evidenceItems: BereanResponseEvidence[] = chunks.slice(0, 5).map(
      (c) => ({
        citation: c.citation,
        content: c.content.slice(0, 400), // cap per-evidence text length
        source: c.source,
      }),
    );

    const bereanResponse: BereanResponse = {
      answer: finalAnswerText,
      evidence: evidenceItems,
      context:
        typeof parsedCandidate.context === "string"
          ? parsedCandidate.context
          : "",
      interpretations: Array.isArray(parsedCandidate.interpretations)
        ? (parsedCandidate.interpretations as string[])
        : [],
      assumptions: Array.isArray(parsedCandidate.assumptions)
        ? (parsedCandidate.assumptions as string[])
        : [],
      unknowns: allUnknowns,
      confidence: finalConfidence,
      trustScore,
      reviewVerdict: reviewResult.overallVerdict,
      isVerified: reviewResult.overallVerdict !== "fail",
      isAiGenerated: true,
    };

    // ── Write completed trace to Firestore ──────────────────────────────────
    const completedTrace: PipelineTrace = {
      ...trace,
      totalMs: Math.round(performance.now() - pipelineStartMs),
    };

    await db
      .collection("bereanPipelineTraces")
      .doc(traceId)
      .set(
        {
          ...completedTrace,
          status: "completed",
          updatedAt: admin.firestore.Timestamp.now(),
          trustScore,
          finalConfidence,
          reviewVerdict: reviewResult.overallVerdict,
          intentClasses,
          isHighRisk,
          isAiGenerated: true,
        },
        { merge: true },
      )
      .catch((err) => {
        // Non-fatal: trace write failure must not block user response.
        console.error("[constitutionalPipeline] trace write failed:", err);
      });

    // ── Write memory entries for key preferences / facts ────────────────────
    // Best-effort: extract and persist notable user signals from this turn.
    await writeMemoryFromConversation(
      input,
      finalAnswerText,
      traceId,
      db,
    ).catch((memErr) => {
      console.warn("[constitutionalPipeline] memory write skipped:", memErr);
    });

    return { bereanResponse, completedTrace };
  });
  trace.stages["stage7_finalResponse"] = s7.log;

  if (!s7.log.success || !s7.result) {
    trace.totalMs = Math.round(performance.now() - pipelineStartMs);
    return errorPipelineOutput(
      trace,
      s7.log.error ?? "Final assembly stage failed.",
    );
  }

  const finalTrace = s7.result.completedTrace;
  finalTrace.totalMs = Math.round(performance.now() - pipelineStartMs);

  return {
    response: s7.result.bereanResponse,
    trace: finalTrace,
  };
}

// ── PRIVATE HELPERS ───────────────────────────────────────────────────────────

/**
 * extractAnswerFromCandidate — best-effort extraction of the "answer" field
 * from a JSON candidate string. Falls back to the raw string.
 */
function extractAnswerFromCandidate(candidate: string): string {
  try {
    const json = parseJsonFromModelText(candidate);
    if (
      json !== null &&
      typeof json === "object" &&
      "answer" in (json as object)
    ) {
      const ans = (json as Record<string, unknown>)["answer"];
      if (typeof ans === "string" && ans.trim() !== "") return ans;
    }
  } catch {
    // fall through
  }
  return candidate;
}

/**
 * finaliseTrace — write a terminal status to the Firestore trace document.
 * Used when the pipeline exits early (error/hard-gate paths).
 */
async function finaliseTrace(
  db: admin.firestore.Firestore,
  traceId: string,
  trace: PipelineTrace,
  status: string,
): Promise<void> {
  try {
    await db
      .collection("bereanPipelineTraces")
      .doc(traceId)
      .set(
        {
          ...trace,
          status,
          updatedAt: admin.firestore.Timestamp.now(),
        },
        { merge: true },
      );
  } catch {
    // Non-fatal — don't mask the original error.
  }
}

/**
 * writeMemoryFromConversation — infer and persist notable user signals from
 * the current conversational turn using a lightweight model call.
 *
 * Only writes if the memoryLayer flag is active (checked inside writeMemory).
 * Failures here are always non-fatal.
 */
async function writeMemoryFromConversation(
  input: PipelineInput,
  assistantAnswer: string,
  traceId: string,
  db: admin.firestore.Firestore,
): Promise<void> {
  if (!input.userId || input.userId.trim() === "") return;

  // Only attempt memory extraction for modes likely to carry personal context.
  const memorableMode: BereanMode[] = ["Ask", "Reflect", "Discern"];
  if (!memorableMode.includes(input.mode)) return;

  // Ask the model to extract any notable preferences/facts in JSON.
  let extractionResult: string;
  try {
    const extractionCall = await routeModelCall({
      taskClass: "conversational",
      systemPrompt: [
        "Extract notable user preferences, stated beliefs, study interests, or prayer topics from this conversation turn.",
        "Return ONLY a JSON array of objects: [{\"category\": \"preference\"|\"study\"|\"prayer\"|\"church\"|\"context\", \"content\": string}]",
        "Return an empty array [] if nothing notable is present.",
        "Be conservative — only record things the user explicitly stated or strongly implied.",
      ].join("\n"),
      userPrompt: [
        `User said: ${input.query.slice(0, 400)}`,
        `Assistant replied: ${assistantAnswer.slice(0, 400)}`,
      ].join("\n"),
      traceId: `${traceId}-memory`,
      db,
    });
    extractionResult = extractionCall.text;
  } catch {
    return; // Non-fatal
  }

  const parsed = parseJsonFromModelText(extractionResult);
  if (!Array.isArray(parsed)) return;

  for (const item of parsed) {
    if (
      typeof item === "object" &&
      item !== null &&
      "category" in item &&
      "content" in item
    ) {
      const entry = item as { category: string; content: string };
      const validCategories = new Set([
        "preference",
        "study",
        "prayer",
        "church",
        "action",
        "context",
      ]);
      if (!validCategories.has(entry.category)) continue;
      if (typeof entry.content !== "string" || entry.content.trim() === "")
        continue;

      // writeMemory handles its own feature flag check — call best-effort.
      await writeMemory(
        {
          userId: input.userId,
          category: entry.category as
            | "preference"
            | "study"
            | "prayer"
            | "church"
            | "action"
            | "context",
          content: entry.content.trim(),
          conversationId: traceId,
          sessionId: input.sessionId,
          source: "ai-inferred",
        },
        db,
      ).catch(() => {
        // Silently skip individual write failures.
      });
    }
  }
}

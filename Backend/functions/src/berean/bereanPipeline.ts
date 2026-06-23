/**
 * bereanPipeline.ts
 *
 * Main Berean Pipeline Orchestrator — 7-stage constitutional AI pipeline.
 *
 * The pipeline is fail-closed at every stage:
 *   - Feature flag off → HttpsError('failed-precondition')
 *   - Safety labels detected → GUARDIAN hook always fires
 *   - Constitutional review failure → retry up to 2×, then degraded response
 *   - Any unhandled exception → HttpsError('internal'), never leaks raw candidate
 *
 * Stage flow:
 *   1. queryIntake         — validate input, check feature flag
 *   2. intentDetection     — classify intent labels (multi-label, model-assisted)
 *   3. evidenceRetrieval   — fetch user notes from Firestore + stub external sources
 *   4. generateCandidate   — model call with evidence-injected prompt (NEVER returned directly)
 *   5. constitutionalReview — admin-SDK CF-to-CF review, retry-on-failure, degraded fallback
 *   6. confidenceScoring   — derive confidence from evidence + review verdict
 *   7. finalResponse       — assemble BereanResponse, persist PipelineTrace
 *
 * Export: exports.bereanPipeline
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import * as crypto from "crypto";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";
import { guardBereanEmission, OUTWARD_HANDOFF_TEXT } from "../governance/bereanGuardrail";
import { DEFAULT_CONSTITUTION } from "./constitutionalConfig";

// ─── Secrets ──────────────────────────────────────────────────────────────────

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// ─── Constants ────────────────────────────────────────────────────────────────

const MAX_QUERY_LENGTH = 4000;
const MAX_HISTORY_ENTRIES = 12;
const MAX_HISTORY_ENTRY_CHARS = 1200;
const CONSTITUTIONAL_REVIEW_MAX_RETRIES = 2;
const PIPELINE_TIMEOUT_MS = 15_000;

// Model tier identifiers — aligned with bereanChatProxy.ts ceilings.
const MODEL_FAST = "claude-haiku-4-5-20251001";   // FAST_CONVERSATIONAL
const MODEL_DEEP = "claude-sonnet-4-6";            // DEEP_THEOLOGICAL

// ─── Depth Dial ─────────────────────────────────────────────────────────────────
//
// The client depth dial (BereanDepth: quick/study/deep/multiSource/research) is the
// orthogonal "how thorough" axis. It deterministically drives FOUR knobs here:
//   1. model tier (force the deep model from `deep` upward)
//   2. candidate max_tokens (response length ceiling)
//   3. evidence breadth (how many user notes to retrieve)
//   4. system-prompt posture (how the model is told to answer)
// plus the generation request timeout, which must grow with the token ceiling.
//
// Mirrors the Swift `BereanDepth` enum (BereanSpiritualIntelligenceContracts.swift).
// When depth is absent (older clients), `resolveDepthProfile` falls back to `deep`,
// which preserves the pre-depth behaviour (deep model, 1600 tokens, 10 notes).

type BereanDepthLevel =
  | "quick"
  | "study"
  | "deep"
  | "multiSource"
  | "research";

interface DepthProfile {
  /** Force MODEL_DEEP regardless of intent heuristics. */
  preferDeepModel: boolean;
  /** Candidate-generation max_tokens. */
  maxTokens: number;
  /** Number of user-note evidence chunks to retrieve. */
  evidenceLimit: number;
  /** Generation request timeout (ms); scales with token ceiling. */
  timeoutMs: number;
  /** Appended to the candidate system prompt to set answer posture. */
  posture: string;
}

const DEPTH_PROFILES: Record<BereanDepthLevel, DepthProfile> = {
  quick: {
    preferDeepModel: false,
    maxTokens: 500,
    evidenceLimit: 3,
    timeoutMs: 15_000,
    posture:
      "DEPTH — Quick Look: Answer in 2–4 sentences. Lead with one key Scripture. " +
      "No headings, no lists. Warm and direct.",
  },
  study: {
    preferDeepModel: false,
    maxTokens: 1_000,
    evidenceLimit: 5,
    timeoutMs: 20_000,
    posture:
      "DEPTH — Studying: One or two focused paragraphs with 1–2 cited passages " +
      "and a single practical takeaway.",
  },
  deep: {
    preferDeepModel: true,
    maxTokens: 1_600,
    evidenceLimit: 10,
    timeoutMs: 30_000,
    posture:
      "DEPTH — Deep Study: Thorough analysis with cross-references, historical " +
      "context, and clear application. Cite each significant claim.",
  },
  multiSource: {
    preferDeepModel: true,
    maxTokens: 2_200,
    evidenceLimit: 15,
    timeoutMs: 45_000,
    posture:
      "DEPTH — Multi-Source: Compare multiple faithful traditions on this text. " +
      "Cite several passages, and name plainly where traditions diverge and why.",
  },
  research: {
    preferDeepModel: true,
    maxTokens: 3_000,
    evidenceLimit: 20,
    timeoutMs: 60_000,
    posture:
      "DEPTH — Full Research: Scholarly depth. Include original-language notes " +
      "(clearly hedged, never fabricated), canonical context, cross-references, and " +
      "a structured synthesis. Still humble — defer to pastoral counsel on disputes.",
  },
};

/**
 * Resolve a validated depth string to its profile. Unknown/absent depth falls back
 * to `deep` — the pre-depth-dial default — so older clients are unaffected.
 */
function resolveDepthProfile(depth: BereanDepthLevel | undefined): DepthProfile {
  if (depth && depth in DEPTH_PROFILES) {
    return DEPTH_PROFILES[depth];
  }
  return DEPTH_PROFILES.deep;
}

// ─── Types ────────────────────────────────────────────────────────────────────

type IntentLabel =
  | "Bible"
  | "Church"
  | "Theology"
  | "Notes"
  | "Safety"
  | "Social"
  | "Technical"
  | "Other";

interface BereanQuery {
  query: string;
  mode: "Ask" | "Discern" | "Build" | "Guard" | "Reflect";
  userId: string;
  conversationHistory?: { role: string; content: string }[];
  /** Reasoning depth from the client depth dial. Absent → `deep` (legacy default). */
  depth?: BereanDepthLevel;
}

interface EvidenceChunk {
  id: string;
  source: string;
  content: string;
  sourceType: "scripture" | "commentary" | "userNote" | "platform";
}

interface ReviewVerdict {
  passed: boolean;
  flags: string[];
  degraded: boolean;
  reviewedAt: number;
}

interface PipelineTrace {
  traceId: string;
  intentLabels: string[];
  evidenceIds: string[];
  reviewVerdict: ReviewVerdict;
  retryCount: number;
  confidenceLevel: string;
  latencyMs: number;
  timestamp: admin.firestore.Timestamp;
}

interface BereanResponse {
  answer: string;
  evidence: EvidenceChunk[];
  assumptions: string[];
  unknowns: string[];
  confidence: "High" | "Moderate" | "Low" | "Unknown";
  traceId: string;
}

// Internal pipeline state — never serialized to client.
interface PipelineState {
  traceId: string;
  startMs: number;
  uid: string;
  query: BereanQuery;
  intentLabels: IntentLabel[];
  hasGuardianHook: boolean;
  evidenceChunks: EvidenceChunk[];
  candidateText: string | null;
  reviewVerdict: ReviewVerdict | null;
  retryCount: number;
  confidenceLevel: "High" | "Moderate" | "Low" | "Unknown";
}

// ─── Stage 1: Query Intake ─────────────────────────────────────────────────────

/**
 * Validate the incoming request payload and check the pipeline feature flag.
 * Fail-closed: if the flag cannot be confirmed true, throw before any inference.
 */
async function stageQueryIntake(
  data: unknown,
  uid: string
): Promise<BereanQuery> {
  const db = admin.firestore();

  // Feature flag check — stored in Firestore (server-authoritative, not client-supplied).
  // Fail-closed: any read error → treat as disabled.
  let pipelineEnabled = false;
  try {
    const flagSnap = await db.collection("system").doc("amenAIFlags").get();
    const flags = flagSnap.data() ?? {};
    // Accept either the constitutionalIntelligence_enabled flag or the
    // more general berean_pipeline_enabled override.
    pipelineEnabled =
      flags["constitutionalIntelligence_enabled"] === true ||
      flags["berean_pipeline_enabled"] === true;
  } catch (err) {
    console.error("[bereanPipeline] Stage 1: flag read failed — fail-closed", err);
    pipelineEnabled = false;
  }

  if (!pipelineEnabled) {
    throw new HttpsError(
      "failed-precondition",
      "Constitutional pipeline not enabled"
    );
  }

  // Validate payload shape.
  if (!data || typeof data !== "object") {
    throw new HttpsError("invalid-argument", "Request payload is required.");
  }

  const raw = data as Record<string, unknown>;

  const query = typeof raw.query === "string" ? raw.query.trim() : "";
  if (!query) {
    throw new HttpsError("invalid-argument", "query is required.");
  }
  if (query.length > MAX_QUERY_LENGTH) {
    throw new HttpsError(
      "invalid-argument",
      `Query exceeds maximum length of ${MAX_QUERY_LENGTH} characters.`
    );
  }

  const validModes = ["Ask", "Discern", "Build", "Guard", "Reflect"] as const;
  const mode = (validModes as readonly string[]).includes(raw.mode as string)
    ? (raw.mode as BereanQuery["mode"])
    : "Ask";

  // Depth dial — validate against the known levels; unknown/absent stays undefined
  // and resolveDepthProfile() applies the legacy `deep` default downstream.
  const validDepths = ["quick", "study", "deep", "multiSource", "research"] as const;
  const depth = (validDepths as readonly string[]).includes(raw.depth as string)
    ? (raw.depth as BereanDepthLevel)
    : undefined;

  // Sanitize conversation history — same pattern as bereanChatProxy.
  const rawHistory = Array.isArray(raw.conversationHistory)
    ? raw.conversationHistory
    : [];
  const conversationHistory = rawHistory
    .slice(-MAX_HISTORY_ENTRIES)
    .map((entry: unknown) => {
      if (!entry || typeof entry !== "object") return null;
      const e = entry as Record<string, unknown>;
      if (e.role !== "user" && e.role !== "assistant") return null;
      const content = typeof e.content === "string"
        ? e.content.slice(0, MAX_HISTORY_ENTRY_CHARS)
        : "";
      return { role: e.role as string, content };
    })
    .filter((e): e is { role: string; content: string } => e !== null);

  return { query, mode, userId: uid, conversationHistory, depth };
}

// ─── Stage 2: Intent Detection ─────────────────────────────────────────────────

// Keyword heuristics for fast-path label assignment.
const INTENT_HEURISTICS: Array<{ labels: IntentLabel[]; patterns: RegExp[] }> = [
  {
    labels: ["Safety"],
    patterns: [
      /\b(suicide|self.?harm|kill myself|hurt myself|end my life|not want to be here)\b/i,
      /\b(abuse|domestic violence|traffick|exploitation|grooming)\b/i,
      /\b(crisis|danger|emergency|unsafe)\b/i,
    ],
  },
  {
    labels: ["Bible"],
    patterns: [
      /\b(bible|scripture|verse|passage|testament|gospel|psalm|proverb|genesis|exodus|matthew|mark|luke|john|acts|romans|corinthians|galatians|ephesians|philippians|colossians|hebrews|james|revelation)\b/i,
      /\b(ESV|NIV|KJV|NKJV|NLT|NASB|translation|greek|hebrew|aramaic|concordance)\b/i,
      /\b(chapter|verse|book of|read in|says in)\b/i,
    ],
  },
  {
    labels: ["Theology"],
    patterns: [
      /\b(salvation|atonement|justification|sanctification|predestination|sovereignty|trinity|incarnation|resurrection|eschatology|soteriology|christology|pneumatology)\b/i,
      /\b(doctrine|theology|hermeneutics|exegesis|heresy|orthodox|reformation|covenant theology|dispensation)\b/i,
      /\b(calvinism|arminian|cessationism|continuationism|tongues|charismatic|pentecostal|reformed|evangelical)\b/i,
    ],
  },
  {
    labels: ["Church"],
    patterns: [
      /\b(church|pastor|elder|deacon|congregation|worship|sermon|ministry|denomination|baptism|communion|sacrament|liturgy)\b/i,
      /\b(small group|sunday school|youth group|VBS|outreach|mission|discipleship program)\b/i,
    ],
  },
  {
    labels: ["Notes"],
    patterns: [
      /\b(my notes?|note|journal|devotional|study plan|highlight|annotation|bookmark)\b/i,
      /\b(wrote|recorded|saved|captured|remember when I)\b/i,
    ],
  },
  {
    labels: ["Social"],
    patterns: [
      /\b(post|feed|comment|share|prayer request|community|follow|friend|group|event|message)\b/i,
      /\b(amen app|platform|profile|notification)\b/i,
    ],
  },
  {
    labels: ["Technical"],
    patterns: [
      /\b(how do I use|feature|settings|account|password|bug|error|not working|help with the app)\b/i,
    ],
  },
];

/**
 * Classify the query into one or more IntentLabels.
 * Always adds Safety label when safety signals are present, regardless of other results.
 * Uses keyword heuristics first; falls back to a model call for ambiguous queries.
 */
async function stageIntentDetection(
  query: string,
  apiKey: string
): Promise<{ intentLabels: IntentLabel[]; hasGuardianHook: boolean }> {
  const labelSet = new Set<IntentLabel>();

  // Heuristic pass — deterministic, zero latency.
  for (const { labels, patterns } of INTENT_HEURISTICS) {
    if (patterns.some((p) => p.test(query))) {
      for (const l of labels) labelSet.add(l);
    }
  }

  const hasGuardianHook = labelSet.has("Safety");

  // Model pass — only call when heuristics found nothing or query is ambiguous.
  if (labelSet.size === 0 || (labelSet.size === 1 && !hasGuardianHook)) {
    try {
      const systemPrompt = [
        "You are an intent classifier for a Biblical AI assistant.",
        "Classify the user query into one or more of these labels (comma-separated, exact case):",
        "Bible, Church, Theology, Notes, Safety, Social, Technical, Other",
        "Rules:",
        "- Choose all that apply; at minimum 1 label.",
        "- If ANY safety/crisis content is present, always include Safety.",
        "- Respond ONLY with the comma-separated label list. No other text.",
        "Examples:",
        "  'What does John 3:16 mean?' → Bible,Theology",
        "  'How do I post a prayer request?' → Social,Technical",
        "  'I feel like giving up' → Safety",
      ].join("\n");

      const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: MODEL_FAST,
          max_tokens: 64,
          system: systemPrompt,
          messages: [{ role: "user", content: query.slice(0, 500) }],
        }),
        signal: AbortSignal.timeout(PIPELINE_TIMEOUT_MS),
      });

      if (response.ok) {
        const data = (await response.json()) as {
          content?: Array<{ type: string; text: string }>;
        };
        const rawText =
          data.content?.find((b) => b.type === "text")?.text?.trim() ?? "";
        const validLabels: IntentLabel[] = [
          "Bible", "Church", "Theology", "Notes",
          "Safety", "Social", "Technical", "Other",
        ];
        for (const part of rawText.split(",")) {
          const trimmed = part.trim() as IntentLabel;
          if (validLabels.includes(trimmed)) {
            labelSet.add(trimmed);
          }
        }
      }
    } catch (err) {
      // Model call is advisory — fall through with heuristic labels.
      console.warn("[bereanPipeline] Stage 2: model classification failed, using heuristics only", err);
    }
  }

  // Ensure at least one label.
  if (labelSet.size === 0) {
    labelSet.add("Other");
  }

  // GUARDIAN hook: Safety ALWAYS fires if any safety signal was detected,
  // regardless of what other labels the model returned.
  const safetySignal = INTENT_HEURISTICS[0].patterns.some((p) => p.test(query));
  if (safetySignal) {
    labelSet.add("Safety");
  }
  const finalGuardianHook = labelSet.has("Safety");

  return {
    intentLabels: Array.from(labelSet),
    hasGuardianHook: finalGuardianHook,
  };
}

// ─── Stage 3: Evidence Retrieval ──────────────────────────────────────────────

/**
 * Fetch evidence chunks for the pipeline.
 *
 * Real: Firestore user notes, scoped to userId.
 * Stub (TODO): Pinecone semantic search, API.Bible verse lookup.
 *
 * Each chunk carries full source attribution.
 */
async function stageEvidenceRetrieval(
  query: string,
  userId: string,
  intentLabels: IntentLabel[],
  evidenceLimit: number
): Promise<EvidenceChunk[]> {
  const db = admin.firestore();
  const chunks: EvidenceChunk[] = [];

  // ── Real: Firestore user notes scoped by userId ────────────────────────────
  // The fetch breadth is set by the depth dial (3 at Quick → 20 at Research).
  try {
    const notesQuery = db
      .collection("users")
      .doc(userId)
      .collection("bereanNotes")
      .orderBy("updatedAt", "desc")
      .limit(Math.max(1, evidenceLimit));

    const notesSnap = await notesQuery.get();

    for (const doc of notesSnap.docs) {
      const data = doc.data();
      const content = typeof data.content === "string" ? data.content : "";
      const title = typeof data.title === "string" ? data.title : "Untitled Note";
      const passage = typeof data.passageReference === "string"
        ? data.passageReference
        : "";

      if (!content.trim()) continue;

      // Simple relevance filter — include note only if it shares keywords with query.
      const queryWords = query.toLowerCase().split(/\W+/).filter((w) => w.length >= 4);
      const contentLower = content.toLowerCase();
      const isRelevant =
        queryWords.length === 0 ||
        queryWords.some((w) => contentLower.includes(w)) ||
        (passage && query.toLowerCase().includes(passage.toLowerCase()));

      if (!isRelevant) continue;

      chunks.push({
        id: `note_${doc.id}`,
        source: passage
          ? `Your notes on ${passage}`
          : `Your study note: ${title}`,
        content: content.slice(0, 800),
        sourceType: "userNote",
      });
    }
  } catch (err) {
    // Non-fatal: pipeline continues without user notes.
    console.warn("[bereanPipeline] Stage 3: Firestore user notes fetch failed", err);
  }

  // ── Stub: Pinecone semantic vector search ──────────────────────────────────
  // TODO: replace with real Pinecone query when the index is provisioned.
  // Expected shape: { id, text, source, score }[]
  // const pineconeResults = await queryPinecone(query, { topK: 5, namespace: 'berean_corpus' });
  // for (const r of pineconeResults) {
  //   chunks.push({ id: `vec_${r.id}`, source: r.source, content: r.text, sourceType: 'commentary' });
  // }

  // ── Stub: API.Bible verse lookup ───────────────────────────────────────────
  // TODO: detect scripture references in query, fetch canonical text via API.Bible.
  // const refs = extractScriptureRefs(query);
  // for (const ref of refs) {
  //   const verse = await apiBibleFetch(ref, translation);
  //   chunks.push({ id: `bible_${sanitize(ref)}`, source: ref, content: verse, sourceType: 'scripture' });
  // }

  // ── Platform context chunk (always included when Bible/Theology intent) ────
  if (
    intentLabels.includes("Bible") ||
    intentLabels.includes("Theology") ||
    intentLabels.includes("Church")
  ) {
    chunks.push({
      id: "platform_berean_context",
      source: "Berean AI system context",
      content:
        "Berean AI is a Scripture-centered assistant within the AMEN community platform. " +
        "Responses are grounded in Scripture (Acts 17:11). All doctrinal claims cite a specific passage. " +
        "Berean is a companion tool — never a replacement for pastoral guidance, therapy, or clinical care.",
      sourceType: "platform",
    });
  }

  return chunks;
}

// ─── Stage 4: Generate Candidate ──────────────────────────────────────────────

const CRISIS_SAFE_ANSWER = [
  "I care about you and I want you to be safe right now.",
  "",
  "If you are in crisis, please reach out immediately:",
  "  • 988 Suicide & Crisis Lifeline — call or text 988",
  "  • Crisis Text Line — text HOME to 741741",
  "  • International Association for Suicide Prevention — https://www.iasp.info/resources/Crisis_Centres/",
  "",
  "You are not alone. A real person who can help is just a call or text away.",
  "Please reach out to them before we continue.",
].join("\n");

/**
 * Choose the model tier based on intent labels and mode.
 * Deep theological analysis uses DEEP; everything else uses FAST.
 */
function selectModel(
  intentLabels: IntentLabel[],
  mode: BereanQuery["mode"],
  preferDeepModel: boolean
): string {
  // Depth dial can force the deep model (deep/multiSource/research) even when the
  // intent heuristics would otherwise pick the fast tier.
  if (preferDeepModel) {
    return MODEL_DEEP;
  }
  if (
    intentLabels.includes("Theology") ||
    intentLabels.includes("Bible") ||
    mode === "Discern" ||
    mode === "Build"
  ) {
    return MODEL_DEEP;
  }
  return MODEL_FAST;
}

/**
 * Build a system prompt appropriate to the pipeline mode and intent labels.
 * Safety label always injects crisis guardrails.
 */
function buildCandidateSystemPrompt(
  mode: BereanQuery["mode"],
  intentLabels: IntentLabel[],
  hasGuardianHook: boolean,
  depthPosture: string
): string {
  const parts: string[] = [];

  parts.push(
    "You are Berean, a Scripture-centered AI study companion within the AMEN community.\n" +
    "Your name comes from Acts 17:11 — the Bereans who 'examined the Scriptures every day.'\n" +
    "\n" +
    "CORE AUTHORITY HIERARCHY (never violate):\n" +
    "1. Scripture (the Bible) is your primary and ultimate authority.\n" +
    "2. The Holy Spirit's illumination guides interpretation — remain humble.\n" +
    "3. The faith community and pastoral leadership have authority over you.\n" +
    "4. You are a tool; you are not a pastor, counselor, or divine authority.\n" +
    "\n" +
    "ABSOLUTE CONSTRAINTS:\n" +
    "- Never speak as a divine authority or claim spiritual revelation.\n" +
    "- Never fabricate scripture references, historical facts, or Greek/Hebrew meanings.\n" +
    "- Never provide medical, legal, or financial advice.\n" +
    "- Never tell a user God is commanding them to leave a church, end a relationship, stop medication, or ignore wise counsel.\n" +
    "- When traditions genuinely disagree on a text, say so clearly and humbly.\n" +
    "- For any significant doctrinal claim, offer: 'I could be wrong — please bring this to your pastor.'"
  );

  // Mode-specific overlays.
  const modeInstructions: Record<BereanQuery["mode"], string> = {
    Ask:
      "MODE: Ask — Give a clear, warm, pastoral answer. Cite Scripture. Keep it accessible.",
    Discern:
      "MODE: Discern — Explore theological depth. Present multiple faithful perspectives. " +
      "Acknowledge areas of genuine disagreement between traditions. Be scholarly but humble.",
    Build:
      "MODE: Build — Help the user deepen their study. Provide structured analysis, " +
      "cross-references, historical context, and practical application.",
    Guard:
      "MODE: Guard — Apply careful discernment. Identify potential theological concerns " +
      "in the question. Be gentle but honest.",
    Reflect:
      "MODE: Reflect — Lead the user into devotional reflection and prayer. " +
      "Ground your response in Scripture and help them apply it personally.",
  };
  parts.push(modeInstructions[mode]);

  // Depth posture overlay — sets answer length/thoroughness from the depth dial.
  if (depthPosture) {
    parts.push(depthPosture);
  }

  // Safety/GUARDIAN override.
  if (hasGuardianHook || intentLabels.includes("Safety")) {
    parts.push(
      "GUARDIAN HOOK ACTIVE:\n" +
      "Safety signals were detected in this query.\n" +
      "If any part of the query relates to self-harm, abuse, crisis, or immediate danger:\n" +
      "  1. DO NOT provide theological analysis first.\n" +
      "  2. Immediately and compassionately surface crisis resources (988, Crisis Text Line).\n" +
      "  3. Acknowledge the person's pain with warmth and empathy.\n" +
      "  4. Do not minimize or spiritualize their distress.\n" +
      "Only after confirming the user is safe may you continue with pastoral content."
    );
  }

  // Notes intent reminder.
  if (intentLabels.includes("Notes")) {
    parts.push(
      "NOTE CONTEXT: The user's personal study notes may be included in evidence. " +
      "Reference them naturally to personalize your response."
    );
  }

  return parts.join("\n\n");
}

/**
 * Generate the candidate answer from the model.
 * Evidence chunks are injected into the prompt as context.
 * The candidate text is NEVER returned to the client directly — it passes through Stage 5.
 */
async function stageGenerateCandidate(
  query: BereanQuery,
  intentLabels: IntentLabel[],
  hasGuardianHook: boolean,
  evidenceChunks: EvidenceChunk[],
  apiKey: string
): Promise<string> {
  // Hard short-circuit: if the GUARDIAN hook is active AND the query itself
  // matches a high-risk crisis pattern, return the safe response immediately
  // without calling the model at all. This prevents any edge-case where the
  // model might delay crisis resources.
  if (hasGuardianHook) {
    const crisisPatterns = [
      /\b(end my life|kill myself|want to die|take my life|no reason to live|suicide|suicidal)\b/i,
      /\b(going to hurt myself|cut myself|overdose|hang myself|jump off)\b/i,
      /\b(better off dead|better off without me|can't go on|cannot go on)\b/i,
    ];
    if (crisisPatterns.some((p) => p.test(query.query))) {
      return CRISIS_SAFE_ANSWER;
    }
  }

  const depthProfile = resolveDepthProfile(query.depth);
  const model = selectModel(intentLabels, query.mode, depthProfile.preferDeepModel);
  const systemPrompt = buildCandidateSystemPrompt(
    query.mode,
    intentLabels,
    hasGuardianHook,
    depthProfile.posture
  );

  // Build user message with evidence injection.
  const evidenceBlock =
    evidenceChunks.length > 0
      ? "\n\nRELEVANT CONTEXT (use to inform your answer, cite sources where appropriate):\n" +
        evidenceChunks
          .map((c, i) => `[${i + 1}] Source: ${c.source}\n${c.content}`)
          .join("\n\n---\n\n")
      : "";

  const userMessage = `${query.query}${evidenceBlock}`;

  // Build messages — include sanitized history.
  const messages: Array<{ role: "user" | "assistant"; content: string }> = [];
  for (const h of query.conversationHistory ?? []) {
    if (h.role === "user" || h.role === "assistant") {
      messages.push({ role: h.role, content: h.content });
    }
  }
  messages.push({ role: "user", content: userMessage });

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      max_tokens: depthProfile.maxTokens,
      system: systemPrompt,
      messages,
    }),
    // Generation timeout scales with depth (longer responses need longer windows).
    signal: AbortSignal.timeout(depthProfile.timeoutMs),
  });

  if (!response.ok) {
    const errBody = await response.text().catch(() => "(unreadable)");
    console.error("[bereanPipeline] Stage 4: Anthropic error", {
      status: response.status,
      body: errBody.slice(0, 200),
    });
    throw new HttpsError("internal", "Candidate generation temporarily unavailable.");
  }

  const data = (await response.json()) as {
    content?: Array<{ type: string; text: string }>;
  };

  const candidateText =
    data.content?.find((b) => b.type === "text")?.text?.trim() ?? "";

  if (!candidateText) {
    throw new HttpsError("internal", "Model returned an empty candidate.");
  }

  return candidateText;
}

// ─── Stage 5: Constitutional Review ───────────────────────────────────────────

interface ConstitutionalReviewResult {
  passed: boolean;
  flags: string[];
  degraded: boolean;
}

/**
 * Run the constitutional review callable via admin SDK (CF-to-CF).
 * Retries up to CONSTITUTIONAL_REVIEW_MAX_RETRIES on failure.
 * On persistent failure, returns degradedResponse = true rather than shipping a
 * potentially unsafe candidate.
 *
 * The degraded fallback is a safe, short pastoral response that acknowledges
 * the question without any potentially problematic theological claim.
 */
async function stageConstitutionalReview(
  candidateText: string,
  query: string,
  uid: string,
  hasGuardianHook: boolean,
  apiKey: string
): Promise<{ verdict: ReviewVerdict; finalText: string; retryCount: number }> {
  let retryCount = 0;
  let lastError: unknown = null;

  // Lightweight local moderation patterns (aligned with amenAI/common.ts).
  // These run synchronously before any CF call and catch hard-block patterns.
  const HARD_BLOCKS: Array<{ pattern: RegExp; flag: string }> = [
    { pattern: /\b(i am|this is)\s+the\s+(holy spirit|christ|god)\b/i, flag: "divine_authority_claim" },
    { pattern: /\bspeaking for god\b/i, flag: "divine_authority_claim" },
    { pattern: /\b(guaranteed|certain)\s+(cure|healing|recovery)\b/i, flag: "medical_overreach" },
    { pattern: /\bdo not\s+(take|seek)\s+(medication|medicine|treatment|therapy)\b/i, flag: "medical_overreach" },
    { pattern: /\bjust\s+pray\s+(about|away)\s+(depression|suicide|self.?harm|anxiety)\b/i, flag: "mental_health_overreach" },
    { pattern: /\bdo not\s+(see|call)\s+(a therapist|a doctor|988|911)\b/i, flag: "mental_health_overreach" },
    { pattern: /\b(guaranteed|certain)\s+(returns?|profit|wealth|prosperity)\b/i, flag: "financial_overreach" },
    { pattern: /\bseed (offering|gift)\s+(guarantees|will return)\b/i, flag: "financial_overreach" },
    { pattern: /\b(kill|harm|attack)\s+(them|those\s+people|the\s+\w+s?)\b/i, flag: "harm_or_violence" },
  ];

  const localFlags: string[] = [];
  for (const { pattern, flag } of HARD_BLOCKS) {
    if (pattern.test(candidateText)) {
      localFlags.push(flag);
    }
  }

  if (localFlags.length > 0) {
    console.warn("[bereanPipeline] Stage 5: local hard-block triggered", { flags: localFlags, uid });
    return {
      verdict: {
        passed: false,
        flags: localFlags,
        degraded: true,
        reviewedAt: Date.now(),
      },
      finalText: buildDegradedResponse(query, hasGuardianHook),
      retryCount: 0,
    };
  }

  // ── CF-to-CF constitutional review via admin SDK ───────────────────────────
  // Calls the bereanConstitutionalPipeline callable (already deployed).
  // This is the 7-point doctrinal safety check.
  while (retryCount <= CONSTITUTIONAL_REVIEW_MAX_RETRIES) {
    try {
      // Admin SDK callable invocation pattern — compatible with Firebase v2 CFs.
      // Using `as any` cast consistent with berean/controllers/bereanHelper.ts and
      // berean/services/ModelRouter.ts (the typed Admin SDK App does not expose
      // .functions() but the runtime JS object does via firebase-admin/functions).
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const adminFunctions = (admin.app() as any).functions("us-east1");
      const reviewCallable = adminFunctions.httpsCallable("bereanConstitutionalPipeline", {
        timeout: 15_000,
      });

      const reviewResult = await reviewCallable({
        query,
        candidate: candidateText,
        uid,
        pipelineSource: "bereanPipeline",
      });

      const resultData = reviewResult.data as Record<string, unknown>;

      const reviewVerdictObj =
        resultData.reviewVerdict &&
        typeof resultData.reviewVerdict === "object"
          ? (resultData.reviewVerdict as Record<string, unknown>)
          : {};
      const passed =
        resultData.passed === true ||
        resultData.isVerified === true ||
        reviewVerdictObj.passed === true;

      const flags: string[] = [];
      if (Array.isArray(resultData.flags)) {
        flags.push(...(resultData.flags as string[]));
      }
      if (
        resultData.reviewVerdict &&
        typeof resultData.reviewVerdict === "object" &&
        Array.isArray((resultData.reviewVerdict as Record<string, unknown>).flags)
      ) {
        flags.push(
          ...((resultData.reviewVerdict as Record<string, unknown>).flags as string[])
        );
      }

      const verdict: ReviewVerdict = {
        passed,
        flags: [...new Set(flags)],
        degraded: false,
        reviewedAt: Date.now(),
      };

      if (!passed) {
        // Review explicitly rejected the candidate.
        console.warn("[bereanPipeline] Stage 5: constitutional review rejected candidate", {
          flags: verdict.flags,
          uid,
        });
        return {
          verdict: { ...verdict, degraded: true },
          finalText: buildDegradedResponse(query, hasGuardianHook),
          retryCount,
        };
      }

      return { verdict, finalText: candidateText, retryCount };
    } catch (err) {
      lastError = err;
      retryCount++;
      console.warn(
        `[bereanPipeline] Stage 5: constitutional review attempt ${retryCount} failed`,
        err
      );
      // Brief back-off before retry (no sleep — just a minimal delay via Promise).
      if (retryCount <= CONSTITUTIONAL_REVIEW_MAX_RETRIES) {
        await new Promise<void>((resolve) => setTimeout(resolve, 500 * retryCount));
      }
    }
  }

  // Persistent failure: NEVER ship the unreviewed candidate.
  console.error(
    "[bereanPipeline] Stage 5: constitutional review failed after all retries — using degraded response",
    { uid, lastError }
  );

  return {
    verdict: {
      passed: false,
      flags: ["review_unavailable"],
      degraded: true,
      reviewedAt: Date.now(),
    },
    finalText: buildDegradedResponse(query, hasGuardianHook),
    retryCount,
  };
}

/**
 * Build a safe, short degraded response that acknowledges the question
 * without making any theological claims that have not been reviewed.
 */
function buildDegradedResponse(query: string, hasGuardianHook: boolean): string {
  if (hasGuardianHook) {
    return CRISIS_SAFE_ANSWER;
  }

  return [
    "I want to give you a thoughtful, Scripture-grounded answer, but I need a moment to make sure it's as accurate as it should be.",
    "",
    "Please feel free to:",
    "  • Rephrase your question or ask from a different angle.",
    "  • Bring this question to your pastor or a trusted spiritual mentor.",
    "  • Search Scripture directly using a concordance (try BibleGateway.com).",
    "",
    "I am here to help — and I want to get this right for you.",
  ].join("\n");
}

// ─── Stage 6: Confidence Scoring ──────────────────────────────────────────────

/**
 * Derive a confidence level from the evidence collected and the review verdict.
 *
 * High:     review passed + 3+ evidence chunks
 * Moderate: review passed + 1–2 evidence chunks, OR review passed with no evidence
 * Low:      review degraded OR flagged
 * Unknown:  review unavailable
 */
function stageConfidenceScoring(
  evidenceChunks: EvidenceChunk[],
  reviewVerdict: ReviewVerdict,
  intentLabels: IntentLabel[]
): "High" | "Moderate" | "Low" | "Unknown" {
  if (reviewVerdict.flags.includes("review_unavailable")) {
    return "Unknown";
  }

  if (!reviewVerdict.passed || reviewVerdict.degraded) {
    return "Low";
  }

  // Deprioritize platform-only evidence (no real user notes or scripture chunks).
  const substantiveChunks = evidenceChunks.filter(
    (c) => c.sourceType !== "platform"
  );

  if (substantiveChunks.length >= 3) {
    return "High";
  }

  if (substantiveChunks.length >= 1) {
    return "Moderate";
  }

  // Passed review but no substantive evidence — "Other" or "Social" intents get Moderate,
  // theological intents get Low (we want evidence for those).
  if (
    intentLabels.includes("Bible") ||
    intentLabels.includes("Theology") ||
    intentLabels.includes("Church")
  ) {
    return "Moderate";
  }

  return "Moderate";
}

// ─── Stage 7: Final Response ───────────────────────────────────────────────────

/**
 * Assemble the BereanResponse and persist the PipelineTrace to Firestore.
 * Assumptions and unknowns are derived from intent labels and evidence gaps.
 */
async function stageFinalResponse(
  state: PipelineState,
  finalText: string
): Promise<BereanResponse> {
  const db = admin.firestore();
  const latencyMs = Date.now() - state.startMs;

  // ── Governance guardrail (Wave 2: invariants 2, 3, 7) ──────────────────────
  // Every Berean mode routes its candidate through the Companion Boundary +
  // conformance verdict before emission. Fail-closed: a parasocial/idolatry
  // violation forces an OUTWARD handoff (never "keep talking to me").
  const guardrail = guardBereanEmission({
    text: finalText,
    citations: [], // verse-level grounding is enforced upstream (scripture review)
    reviewPassed: state.reviewVerdict?.passed ?? false,
    degraded: state.reviewVerdict?.degraded ?? true,
    constitutionVersion: DEFAULT_CONSTITUTION.version,
    prohibitedPhrases: DEFAULT_CONSTITUTION.companionBoundary?.prohibitedPhrases,
    reviewFlags: state.reviewVerdict?.flags ?? [],
  });
  let answerText = finalText;
  if (guardrail.mustHandoffOutward && !answerText.includes(OUTWARD_HANDOFF_TEXT)) {
    answerText = `${answerText}\n\n${OUTWARD_HANDOFF_TEXT}`;
  }

  // Build assumptions list.
  const assumptions: string[] = [];
  if (!state.evidenceChunks.some((c) => c.sourceType === "scripture")) {
    assumptions.push(
      "No scripture verses were directly retrieved — response draws on general Biblical knowledge."
    );
  }
  if (!state.evidenceChunks.some((c) => c.sourceType === "userNote")) {
    assumptions.push("No personal study notes were found for this query.");
  }

  // Build unknowns list.
  const unknowns: string[] = [];
  if (state.intentLabels.includes("Theology") || state.intentLabels.includes("Bible")) {
    unknowns.push(
      "Original language nuances and cross-referenced passages may not be fully represented."
    );
  }
  if (state.reviewVerdict?.flags.includes("review_unavailable")) {
    unknowns.push(
      "Constitutional review was unavailable — additional human discernment is recommended."
    );
  }

  // Persist PipelineTrace.
  const trace: PipelineTrace = {
    traceId: state.traceId,
    intentLabels: state.intentLabels,
    evidenceIds: state.evidenceChunks.map((c) => c.id),
    reviewVerdict: state.reviewVerdict ?? {
      passed: false,
      flags: ["no_review"],
      degraded: true,
      reviewedAt: Date.now(),
    },
    retryCount: state.retryCount,
    confidenceLevel: state.confidenceLevel,
    latencyMs,
    timestamp: FieldValue.serverTimestamp() as admin.firestore.Timestamp,
  };

  try {
    await db
      .collection("berean_pipeline_traces")
      .doc(state.traceId)
      .set({
        ...trace,
        uid: state.uid,
        mode: state.query.mode,
        depth: state.query.depth ?? "deep",
        queryLength: state.query.query.length,
        hasGuardianHook: state.hasGuardianHook,
        evidenceChunkCount: state.evidenceChunks.length,
        // Governance verdicts (invariants 2, 3, 7) — recorded for audit.
        governanceVerdicts: guardrail.verdicts,
        companionBoundaryViolations: guardrail.companion.violations,
        outwardHandoffApplied: guardrail.mustHandoffOutward,
        constitutionVersion: DEFAULT_CONSTITUTION.version,
        updatedAt: FieldValue.serverTimestamp(),
      });
  } catch (err) {
    // Trace persistence failure is non-fatal — the user still gets their answer.
    console.error("[bereanPipeline] Stage 7: trace persistence failed", {
      traceId: state.traceId,
      uid: state.uid,
      err,
    });
  }

  return {
    answer: answerText,
    evidence: state.evidenceChunks,
    assumptions,
    unknowns,
    confidence: state.confidenceLevel,
    traceId: state.traceId,
  };
}

// ─── Main Export ───────────────────────────────────────────────────────────────

/**
 * bereanPipeline — Main Berean constitutional AI pipeline callable.
 *
 * Required request payload:
 *   { query: string, mode: 'Ask'|'Discern'|'Build'|'Guard'|'Reflect' }
 *
 * Optional:
 *   { conversationHistory?: [{ role, content }] }
 */
export const bereanPipeline = onCall(
  {
    secrets: [anthropicApiKey],
    region: "us-east1",
    timeoutSeconds: 120,
    memory: "512MiB",
    enforceAppCheck: true,
  },
  async (request): Promise<BereanResponse> => {
    // ── Auth + App Check guards ──────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "User must be authenticated to use the Berean Pipeline."
      );
    }
    if (!request.app) {
      throw new HttpsError(
        "unauthenticated",
        "App Check attestation required."
      );
    }

    const uid = request.auth.uid;

    // ── Rate limiting ──────────────────────────────────────────────────────
    await enforceRateLimit(uid, [
      RATE_LIMITS.AI_PER_MINUTE,
      RATE_LIMITS.AI_PER_DAY,
    ]);

    // ── API key ────────────────────────────────────────────────────────────
    const apiKey = anthropicApiKey.value();
    if (!apiKey) {
      console.error("[bereanPipeline] ANTHROPIC_API_KEY not configured");
      throw new HttpsError(
        "failed-precondition",
        "Berean AI is not configured. Please contact support."
      );
    }

    // ── Pipeline state init ────────────────────────────────────────────────
    const traceId = `bp_${Date.now()}_${crypto.randomBytes(6).toString("hex")}`;
    const startMs = Date.now();

    const state: PipelineState = {
      traceId,
      startMs,
      uid,
      query: { query: "", mode: "Ask", userId: uid },
      intentLabels: [],
      hasGuardianHook: false,
      evidenceChunks: [],
      candidateText: null,
      reviewVerdict: null,
      retryCount: 0,
      confidenceLevel: "Unknown",
    };

    try {
      // ─────────────────────────────────────────────────────────────────────
      // Stage 1: Query Intake
      // ─────────────────────────────────────────────────────────────────────
      state.query = await stageQueryIntake(request.data, uid);

      // ─────────────────────────────────────────────────────────────────────
      // Stage 2: Intent Detection
      // ─────────────────────────────────────────────────────────────────────
      const { intentLabels, hasGuardianHook } = await stageIntentDetection(
        state.query.query,
        apiKey
      );
      state.intentLabels = intentLabels;
      state.hasGuardianHook = hasGuardianHook;

      // ─────────────────────────────────────────────────────────────────────
      // Stage 3: Evidence Retrieval
      // ─────────────────────────────────────────────────────────────────────
      state.evidenceChunks = await stageEvidenceRetrieval(
        state.query.query,
        uid,
        state.intentLabels,
        resolveDepthProfile(state.query.depth).evidenceLimit
      );

      // ─────────────────────────────────────────────────────────────────────
      // Stage 4: Generate Candidate
      // ─────────────────────────────────────────────────────────────────────
      const candidateText = await stageGenerateCandidate(
        state.query,
        state.intentLabels,
        state.hasGuardianHook,
        state.evidenceChunks,
        apiKey
      );
      state.candidateText = candidateText;

      // ─────────────────────────────────────────────────────────────────────
      // Stage 5: Constitutional Review
      // ─────────────────────────────────────────────────────────────────────
      const { verdict, finalText, retryCount } = await stageConstitutionalReview(
        candidateText,
        state.query.query,
        uid,
        state.hasGuardianHook,
        apiKey
      );
      state.reviewVerdict = verdict;
      state.retryCount = retryCount;

      // ─────────────────────────────────────────────────────────────────────
      // Stage 6: Confidence Scoring
      // ─────────────────────────────────────────────────────────────────────
      state.confidenceLevel = stageConfidenceScoring(
        state.evidenceChunks,
        verdict,
        state.intentLabels
      );

      // ─────────────────────────────────────────────────────────────────────
      // Stage 7: Final Response
      // ─────────────────────────────────────────────────────────────────────
      const bereanResponse = await stageFinalResponse(state, finalText);

      console.log("[bereanPipeline] pipeline_completed", {
        traceId,
        intentLabels: state.intentLabels,
        hasGuardianHook: state.hasGuardianHook,
        evidenceCount: state.evidenceChunks.length,
        reviewPassed: verdict.passed,
        reviewDegraded: verdict.degraded,
        retryCount,
        confidenceLevel: state.confidenceLevel,
        latencyMs: Date.now() - startMs,
      });

      return bereanResponse;
    } catch (error: unknown) {
      const latencyMs = Date.now() - startMs;

      // Re-throw HttpsErrors — they are already user-safe.
      if (error instanceof HttpsError) {
        console.warn("[bereanPipeline] pipeline_httpsError", {
          code: error.code,
          message: error.message,
          traceId,
          latencyMs,
        });
        throw error;
      }

      // Log and wrap unexpected errors — never leak raw error details to client.
      console.error("[bereanPipeline] pipeline_unexpected_error", {
        traceId,
        uid,
        latencyMs,
        error:
          error instanceof Error
            ? { name: error.name, message: error.message }
            : String(error),
      });

      throw new HttpsError(
        "internal",
        "Berean Pipeline encountered an unexpected error. Please try again."
      );
    }
  }
);

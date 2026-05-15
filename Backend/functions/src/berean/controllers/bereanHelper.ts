/**
 * bereanHelper.ts
 *
 * Grok-assisted Berean Helper Model Cloud Functions (System 28)
 *
 * Four callable functions used by the iOS BereanGrokService to enrich
 * AI-assisted study flows before the primary Claude response:
 *
 *   1. bereanHelperSummarizePrompt   — simplify / reframe a long or unclear user prompt
 *   2. bereanHelperAnalyzeLink       — extract theological context from a URL
 *   3. bereanHelperExternalContext   — surface public viewpoint clusters for a query
 *   4. bereanHelperStudyOutline      — generate a structured Bible study outline
 *
 * All four functions:
 *   • Require Firebase Auth + App Check
 *   • Route through bereanChatProxy (keeping model credentials server-side)
 *   • Use claude-haiku-4-5 (fast tier) — these are pre-processing helpers
 *   • Return strict JSON matching the shapes expected by BereanGrokService.swift
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function stripCodeFence(raw: string): string {
  return raw
    .replace(/^```(?:json)?\n?/m, "")
    .replace(/\n?```$/m, "")
    .trim();
}

/** Call bereanChatProxy with a helper-tier system prompt and parse the JSON response. */
async function callHelperProxy(
  systemPrompt: string,
  userPrompt: string
): Promise<Record<string, unknown>> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const callable = (admin.app() as any).functions().httpsCallable("bereanChatProxy");

  const result = await callable({
    message: userPrompt,
    systemPromptSuffix: systemPrompt,
    maxTokens: 900,
    modelId: "claude-haiku-4-5",
  });

  const data = result.data as Record<string, unknown>;
  const raw = String(data.response ?? data.text ?? "");
  const cleaned = stripCodeFence(raw);

  try {
    return JSON.parse(cleaned) as Record<string, unknown>;
  } catch {
    throw new HttpsError("internal", "Helper model returned non-JSON output.");
  }
}

// ---------------------------------------------------------------------------
// 1. bereanHelperSummarizePrompt
// ---------------------------------------------------------------------------

interface SummarizePromptRequest {
  text: string;
  operation?: string; // "simplify" | "study_angles" — defaults to "simplify"
}

interface SummarizePromptResponse {
  simplified: string;
  keyThemes: string[];
  studyAngles: string[];
}

export const bereanHelperSummarizePrompt = onCall(
  { region: "us-central1", timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    if (!request.app) {
      throw new HttpsError("unauthenticated", "App Check required.");
    }

    const body = request.data as SummarizePromptRequest;
    if (!body?.text?.trim()) {
      throw new HttpsError("invalid-argument", "text is required.");
    }
    if (body.text.length > 4000) {
      throw new HttpsError("invalid-argument", "text must be 4000 characters or fewer.");
    }

    const operation = body.operation ?? "simplify";

    const systemPrompt = [
      "You are a concise theological assistant. Your task is to simplify and reframe a user's question or prompt so it is clearer for a Bible study AI.",
      "Rules:",
      "- simplified: rewrite the prompt in plain, direct language (2-3 sentences max). Preserve the user's intent.",
      "- keyThemes: 2-4 short labels for the main theological or topical themes (e.g. 'forgiveness', 'covenant', 'doubt').",
      "- studyAngles: 2-3 distinct Bible study approaches the user might explore (e.g. 'Historical context of the passage', 'Christ-centered reading').",
      "Respond with ONLY strict JSON matching this schema (no markdown fencing, no extra keys):",
      JSON.stringify({ simplified: "string", keyThemes: ["string"], studyAngles: ["string"] }),
    ].join("\n");

    const userPrompt = JSON.stringify({ operation, text: body.text.trim() });

    let parsed: Record<string, unknown>;
    try {
      parsed = await callHelperProxy(systemPrompt, userPrompt);
    } catch (err) {
      console.error("[bereanHelperSummarizePrompt] proxy failed:", err);
      throw new HttpsError("internal", "Helper model unavailable.");
    }

    const response: SummarizePromptResponse = {
      simplified: String(parsed.simplified ?? body.text.trim()),
      keyThemes: Array.isArray(parsed.keyThemes)
        ? (parsed.keyThemes as unknown[]).map(String).slice(0, 4)
        : [],
      studyAngles: Array.isArray(parsed.studyAngles)
        ? (parsed.studyAngles as unknown[]).map(String).slice(0, 3)
        : [],
    };

    return response;
  }
);

// ---------------------------------------------------------------------------
// 2. bereanHelperAnalyzeLink
// ---------------------------------------------------------------------------

interface AnalyzeLinkRequest {
  url: string;
}

interface AnalyzeLinkResponse {
  title?: string;
  sourceLabel: string;
  contentType: string;
  summary: string;
  keyThemes: string[];
  claimsToCheck: string[];
  scriptureReferences: string[];
  suggestedQuestion?: string;
}

export const bereanHelperAnalyzeLink = onCall(
  { region: "us-central1", timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    if (!request.app) {
      throw new HttpsError("unauthenticated", "App Check required.");
    }

    const body = request.data as AnalyzeLinkRequest;
    if (!body?.url?.trim()) {
      throw new HttpsError("invalid-argument", "url is required.");
    }

    // Basic URL safety — must start with http/https
    const trimmedUrl = body.url.trim();
    if (!/^https?:\/\//i.test(trimmedUrl)) {
      throw new HttpsError("invalid-argument", "url must begin with http:// or https://.");
    }

    const systemPrompt = [
      "You are a biblical discernment assistant. A user has shared a URL. Based on the URL alone (domain, path, slug), infer as much context as possible about the source and likely content.",
      "Your task is to help a Christian user decide whether to trust and share this content.",
      "Rules:",
      "- title: the inferred article or page title (optional — omit if uncertain).",
      "- sourceLabel: the publisher or domain description (e.g. 'Christianity Today', 'secular news', 'theological blog').",
      "- contentType: classify as one of: article | sermon | video | social_post | academic | news | other.",
      "- summary: 2-3 sentence description of what this content likely covers based on the URL.",
      "- keyThemes: 2-4 theological or topical labels.",
      "- claimsToCheck: 1-3 specific claims or assertions from this type of content that a Berean should verify against Scripture.",
      "- scriptureReferences: 0-3 Bible passages that speak directly to this topic.",
      "- suggestedQuestion: one focused study question the user could bring to Berean AI about this content (optional).",
      "Respond with ONLY strict JSON — no markdown, no extra keys.",
    ].join("\n");

    const userPrompt = JSON.stringify({ url: trimmedUrl });

    let parsed: Record<string, unknown>;
    try {
      parsed = await callHelperProxy(systemPrompt, userPrompt);
    } catch (err) {
      console.error("[bereanHelperAnalyzeLink] proxy failed:", err);
      throw new HttpsError("internal", "Helper model unavailable.");
    }

    const response: AnalyzeLinkResponse = {
      title: parsed.title ? String(parsed.title) : undefined,
      sourceLabel: String(parsed.sourceLabel ?? "Unknown source"),
      contentType: String(parsed.contentType ?? "other"),
      summary: String(parsed.summary ?? ""),
      keyThemes: Array.isArray(parsed.keyThemes)
        ? (parsed.keyThemes as unknown[]).map(String).slice(0, 4)
        : [],
      claimsToCheck: Array.isArray(parsed.claimsToCheck)
        ? (parsed.claimsToCheck as unknown[]).map(String).slice(0, 3)
        : [],
      scriptureReferences: Array.isArray(parsed.scriptureReferences)
        ? (parsed.scriptureReferences as unknown[]).map(String).slice(0, 3)
        : [],
      suggestedQuestion: parsed.suggestedQuestion
        ? String(parsed.suggestedQuestion)
        : undefined,
    };

    return response;
  }
);

// ---------------------------------------------------------------------------
// 3. bereanHelperExternalContext
// ---------------------------------------------------------------------------

interface ExternalContextRequest {
  query: string;
}

interface ViewpointCluster {
  label: string;
  summary: string;
  isControversial: boolean;
}

interface ExternalContextResponse {
  publicSummary: string;
  viewpointClusters: ViewpointCluster[];
  cautionNotes: string[];
  scriptureAngles: string[];
}

export const bereanHelperExternalContext = onCall(
  { region: "us-central1", timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    if (!request.app) {
      throw new HttpsError("unauthenticated", "App Check required.");
    }

    const body = request.data as ExternalContextRequest;
    if (!body?.query?.trim()) {
      throw new HttpsError("invalid-argument", "query is required.");
    }
    if (body.query.length > 500) {
      throw new HttpsError("invalid-argument", "query must be 500 characters or fewer.");
    }

    const systemPrompt = [
      "You are a balanced theological research assistant. A Christian user wants to understand the range of public perspectives on a topic before asking Berean AI.",
      "Your task is to map the public discourse landscape without endorsing any single viewpoint.",
      "Rules:",
      "- publicSummary: 2-3 sentence overview of what the general public debate or discussion around this topic looks like.",
      "- viewpointClusters: 2-4 named viewpoint clusters. Each has:",
      "    label: short name (e.g. 'Traditional/Orthodox', 'Progressive', 'Secular humanist', 'Charismatic').",
      "    summary: 1-2 sentences describing this cluster's stance.",
      "    isControversial: true if this view significantly conflicts with mainstream evangelical Christianity.",
      "- cautionNotes: 1-3 specific watch-outs for a discerning Christian reader (e.g. 'This topic is often weaponized to dismiss Scripture').",
      "- scriptureAngles: 2-3 Bible passages or themes that ground a Christian response to this topic.",
      "Respond with ONLY strict JSON — no markdown, no extra keys.",
    ].join("\n");

    const userPrompt = JSON.stringify({ query: body.query.trim() });

    let parsed: Record<string, unknown>;
    try {
      parsed = await callHelperProxy(systemPrompt, userPrompt);
    } catch (err) {
      console.error("[bereanHelperExternalContext] proxy failed:", err);
      throw new HttpsError("internal", "Helper model unavailable.");
    }

    const rawClusters = Array.isArray(parsed.viewpointClusters)
      ? parsed.viewpointClusters
      : [];

    const clusters: ViewpointCluster[] = rawClusters.slice(0, 4).map((c: unknown) => {
      const cluster = c as Record<string, unknown>;
      return {
        label: String(cluster.label ?? "Unknown"),
        summary: String(cluster.summary ?? ""),
        isControversial: Boolean(cluster.isControversial),
      };
    });

    const response: ExternalContextResponse = {
      publicSummary: String(parsed.publicSummary ?? ""),
      viewpointClusters: clusters,
      cautionNotes: Array.isArray(parsed.cautionNotes)
        ? (parsed.cautionNotes as unknown[]).map(String).slice(0, 3)
        : [],
      scriptureAngles: Array.isArray(parsed.scriptureAngles)
        ? (parsed.scriptureAngles as unknown[]).map(String).slice(0, 3)
        : [],
    };

    return response;
  }
);

// ---------------------------------------------------------------------------
// 4. bereanHelperStudyOutline
// ---------------------------------------------------------------------------

interface StudyOutlineRequest {
  topic: string;
}

interface StudyOutlineResponse {
  title: string;
  mainQuestion: string;
  keyPassages: string[];
  historicalContext?: string;
  reflectionQuestions: string[];
  nextSteps: string[];
}

export const bereanHelperStudyOutline = onCall(
  { region: "us-central1", timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    if (!request.app) {
      throw new HttpsError("unauthenticated", "App Check required.");
    }

    const body = request.data as StudyOutlineRequest;
    if (!body?.topic?.trim()) {
      throw new HttpsError("invalid-argument", "topic is required.");
    }
    if (body.topic.length > 300) {
      throw new HttpsError("invalid-argument", "topic must be 300 characters or fewer.");
    }

    const systemPrompt = [
      "You are a structured Bible study curriculum designer. Create a practical study outline for a Christian user exploring a topic.",
      "Rules:",
      "- title: a clear, engaging study title (e.g. 'The Sermon on the Mount: Kingdom Ethics').",
      "- mainQuestion: the central question this study addresses (e.g. 'What does Jesus mean by 'poor in spirit'?').",
      "- keyPassages: 2-5 Bible references most relevant to the topic (e.g. 'Matthew 5:1-12').",
      "- historicalContext: 1-2 sentence background on the biblical or cultural setting (optional — omit only if truly not applicable).",
      "- reflectionQuestions: 3-5 thoughtful questions for personal or group study.",
      "- nextSteps: 2-3 practical action steps the user can take after this study (e.g. 'Memorize Matthew 5:3', 'Journal about one area where you are relying on self-sufficiency').",
      "Keep everything concise and spiritually grounded. Avoid speculation.",
      "Respond with ONLY strict JSON — no markdown, no extra keys.",
    ].join("\n");

    const userPrompt = JSON.stringify({ topic: body.topic.trim() });

    let parsed: Record<string, unknown>;
    try {
      parsed = await callHelperProxy(systemPrompt, userPrompt);
    } catch (err) {
      console.error("[bereanHelperStudyOutline] proxy failed:", err);
      throw new HttpsError("internal", "Helper model unavailable.");
    }

    const response: StudyOutlineResponse = {
      title: String(parsed.title ?? body.topic.trim()),
      mainQuestion: String(parsed.mainQuestion ?? ""),
      keyPassages: Array.isArray(parsed.keyPassages)
        ? (parsed.keyPassages as unknown[]).map(String).slice(0, 5)
        : [],
      historicalContext: parsed.historicalContext
        ? String(parsed.historicalContext)
        : undefined,
      reflectionQuestions: Array.isArray(parsed.reflectionQuestions)
        ? (parsed.reflectionQuestions as unknown[]).map(String).slice(0, 5)
        : [],
      nextSteps: Array.isArray(parsed.nextSteps)
        ? (parsed.nextSteps as unknown[]).map(String).slice(0, 3)
        : [],
    };

    return response;
  }
);

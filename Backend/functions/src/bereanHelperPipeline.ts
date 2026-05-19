import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
const xaiApiKey = defineSecret("XAI_API_KEY");

const HAIKU_MODEL = "claude-haiku-4-5-20251001";
const GROK_MODEL = "grok-3-mini";

function requireAuth(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
  return uid;
}

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value.trim();
}

function containsHighRiskLanguage(text: string): boolean {
  const lower = text.toLowerCase();
  return HIGH_RISK_PATTERNS.some((pattern) => pattern.test(lower));
}

function enforceSafeHelperScope(text: string): void {
  if (containsHighRiskLanguage(text)) {
    throw new HttpsError(
      "failed-precondition",
      "This request needs Berean's stricter safety path.",
      { reason: "sensitive_or_crisis_topic" }
    );
  }
}

async function callAnthropic(prompt: string, maxTokens = 500): Promise<string> {
  const apiKey = anthropicApiKey.value();
  if (!apiKey) return "";

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: HAIKU_MODEL,
      max_tokens: maxTokens,
      messages: [{ role: "user", content: prompt }],
    }),
  });

  if (!response.ok) {
    const errText = await response.text();
    throw new HttpsError("internal", `Helper model error: ${errText.slice(0, 200)}`);
  }

  const data = (await response.json()) as { content?: Array<{ type: string; text: string }> };
  return data.content?.find((chunk) => chunk.type === "text")?.text?.trim() ?? "";
}

// xAI Grok — used as the primary helper model when XAI_API_KEY is set.
// Falls back to Anthropic if the key is absent.
async function callGrok(prompt: string, maxTokens = 500): Promise<string> {
  const apiKey = xaiApiKey.value();
  if (!apiKey) return callAnthropic(prompt, maxTokens);

  const response = await fetch("https://api.x.ai/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: GROK_MODEL,
      max_tokens: maxTokens,
      messages: [{ role: "user", content: prompt }],
    }),
  });

  if (!response.ok) {
    const errText = await response.text();
    console.warn("[bereanHelper] Grok call failed, falling back to Anthropic:", errText.slice(0, 200));
    return callAnthropic(prompt, maxTokens);
  }

  const data = (await response.json()) as { choices?: Array<{ message?: { content?: string } }> };
  return data.choices?.[0]?.message?.content?.trim() ?? "";
}

function extractJsonObject(raw: string): Record<string, unknown> | null {
  const match = raw.match(/\{[\s\S]*\}/);
  if (!match) return null;
  try {
    return JSON.parse(match[0]) as Record<string, unknown>;
  } catch {
    return null;
  }
}

function extractKeywords(text: string, limit = 5): string[] {
  const words = text
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .split(/\s+/)
    .filter((w) => w.length >= 5 && !STOPWORDS.has(w));
  const counts = new Map<string, number>();
  for (const w of words) counts.set(w, (counts.get(w) ?? 0) + 1);
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, limit)
    .map(([w]) => capitalizeWord(w));
}

function capitalizeWord(word: string): string {
  return word.charAt(0).toUpperCase() + word.slice(1);
}

function splitSentences(text: string): string[] {
  return text
    .replace(/\s+/g, " ")
    .split(/(?<=[.!?])\s+/)
    .map((s) => s.trim())
    .filter(Boolean);
}

function truncate(text: string, max = 700): string {
  if (text.length <= max) return text;
  return `${text.slice(0, max - 1).trim()}…`;
}

function inferSourceLabel(url: URL): string {
  const host = url.hostname.toLowerCase();
  if (host.includes("youtube")) return "YouTube";
  if (host.includes("spotify")) return "Spotify";
  if (host.includes("podcasts.apple")) return "Apple Podcasts";
  if (host.includes("instagram")) return "Instagram";
  if (host.includes("threads")) return "Threads";
  if (host === "x.com" || host.includes("twitter")) return "X";
  return host.replace(/^www\./, "");
}

function inferContentType(url: URL): string {
  const host = url.hostname.toLowerCase();
  const path = url.pathname.toLowerCase();
  if (host.includes("youtube")) return "Video";
  if (host.includes("spotify") || host.includes("podcasts.apple")) return "Podcast";
  if (host.includes("instagram") || host.includes("threads") || host.includes("x.com")) return "Social post";
  if (path.includes("sermon")) return "Sermon page";
  if (path.includes("blog") || path.includes("article") || path.includes("news")) return "Article";
  return "Web page";
}

function findScriptureRefs(text: string): string[] {
  const matches = text.match(SCRIPTURE_REF_REGEX) ?? [];
  const unique = new Set(matches.map((m) => m.trim()));
  return [...unique].slice(0, 6);
}

export const bereanHelperSummarizePrompt = onCall(
  {
    secrets: [anthropicApiKey, xaiApiKey],
    enforceAppCheck: true,
    timeoutSeconds: 40,
    memory: "512MiB",
  },
  async (request: CallableRequest) => {
    requireAuth(request);
    const text = requireString((request.data ?? {}).text, "text");
    enforceSafeHelperScope(text);

    const prompt = `You are an AI helper for Berean.
Summarize the user's long question for downstream Bible-study verification.
Do not give final teaching. Return JSON only with keys:
- simplified (string)
- keyThemes (array of short strings)
- studyAngles (array of short strings)

User text:\n${text.slice(0, 7000)}`;

    const raw = await callGrok(prompt, 420);
    const parsed = extractJsonObject(raw);

    const fallbackThemes = extractKeywords(text, 4);
    const fallbackAngles = [
      "What does Scripture directly say?",
      "What context clarifies this?",
      "How should this be applied wisely?",
    ];

    return {
      simplified:
        typeof parsed?.simplified === "string" && parsed.simplified.trim().length > 0
          ? truncate(parsed.simplified.trim(), 500)
          : truncate(splitSentences(text).slice(0, 2).join(" "), 500),
      keyThemes: Array.isArray(parsed?.keyThemes)
        ? (parsed?.keyThemes as unknown[]).filter((v): v is string => typeof v === "string").slice(0, 6)
        : fallbackThemes,
      studyAngles: Array.isArray(parsed?.studyAngles)
        ? (parsed?.studyAngles as unknown[]).filter((v): v is string => typeof v === "string").slice(0, 6)
        : fallbackAngles,
      helperUsed: raw.length > 0,
      finalAuthority: "berean_verification_required",
    };
  }
);

export const bereanHelperAnalyzeLink = onCall(
  {
    secrets: [anthropicApiKey, xaiApiKey],
    enforceAppCheck: true,
    timeoutSeconds: 40,
    memory: "512MiB",
  },
  async (request: CallableRequest) => {
    requireAuth(request);
    const urlText = requireString((request.data ?? {}).url, "url");
    let parsedUrl: URL;
    try {
      parsedUrl = new URL(urlText);
    } catch {
      throw new HttpsError("invalid-argument", "url must be valid.");
    }

    const prompt = `You are an AI helper for Berean link triage.
Given URL: ${parsedUrl.toString()}
Return JSON only with keys:
- title (string)
- summary (string)
- keyThemes (array)
- claimsToCheck (array)
- scriptureReferences (array)
- suggestedQuestion (string)
Use cautious wording and avoid doctrinal certainty.`;

    const raw = await callGrok(prompt, 380);
    const parsed = extractJsonObject(raw);
    const sourceLabel = inferSourceLabel(parsedUrl);
    const contentType = inferContentType(parsedUrl);

    const summary =
      typeof parsed?.summary === "string" && parsed.summary.trim().length > 0
        ? truncate(parsed.summary.trim(), 700)
        : `This ${contentType.toLowerCase()} from ${sourceLabel} may contain claims worth reviewing with Scripture before drawing conclusions.`;

    const keyThemes = Array.isArray(parsed?.keyThemes)
      ? (parsed?.keyThemes as unknown[]).filter((v): v is string => typeof v === "string").slice(0, 6)
      : ["Main claims", "Biblical alignment", "Context and intent"];

    const claimsToCheck = Array.isArray(parsed?.claimsToCheck)
      ? (parsed?.claimsToCheck as unknown[]).filter((v): v is string => typeof v === "string").slice(0, 6)
      : ["Primary claim from the content", "Any directive language", "Potential context gaps"];

    const scriptureReferences = Array.isArray(parsed?.scriptureReferences)
      ? (parsed?.scriptureReferences as unknown[]).filter((v): v is string => typeof v === "string").slice(0, 8)
      : [];

    return {
      title: typeof parsed?.title === "string" && parsed.title.trim().length > 0 ? truncate(parsed.title.trim(), 140) : undefined,
      sourceLabel,
      contentType,
      summary,
      keyThemes,
      claimsToCheck,
      scriptureReferences,
      suggestedQuestion:
        typeof parsed?.suggestedQuestion === "string" && parsed.suggestedQuestion.trim().length > 0
          ? truncate(parsed.suggestedQuestion.trim(), 220)
          : "Compare this content with relevant Scripture and identify what requires caution.",
      helperUsed: raw.length > 0,
      finalAuthority: "berean_verification_required",
    };
  }
);

export const bereanHelperExternalContext = onCall(
  {
    secrets: [anthropicApiKey, xaiApiKey],
    enforceAppCheck: true,
    timeoutSeconds: 40,
    memory: "512MiB",
  },
  async (request: CallableRequest) => {
    requireAuth(request);
    const query = requireString((request.data ?? {}).query, "query");
    enforceSafeHelperScope(query);

    const prompt = `You are an AI helper summarizing public discussion context.
Task: summarize broad viewpoints, not theological authority.
Return JSON only with keys:
- publicSummary (string)
- viewpointClusters (array of { label, summary, isControversial })
- cautionNotes (array)
- scriptureAngles (array)

Query: ${query.slice(0, 2500)}`;

    const raw = await callGrok(prompt, 500);
    const parsed = extractJsonObject(raw);

    const viewpointClusters = Array.isArray(parsed?.viewpointClusters)
      ? (parsed.viewpointClusters as unknown[])
          .map((v) => {
            if (!v || typeof v !== "object") return null;
            const row = v as Record<string, unknown>;
            if (typeof row.label !== "string" || typeof row.summary !== "string") return null;
            return {
              label: truncate(row.label.trim(), 80),
              summary: truncate(row.summary.trim(), 320),
              isControversial: Boolean(row.isControversial),
            };
          })
          .filter((v): v is { label: string; summary: string; isControversial: boolean } => Boolean(v))
          .slice(0, 5)
      : [];

    return {
      publicSummary:
        typeof parsed?.publicSummary === "string" && parsed.publicSummary.trim().length > 0
          ? truncate(parsed.publicSummary.trim(), 700)
          : "Public discussion includes multiple viewpoints. Treat these as context signals, then compare them with Scripture.",
      viewpointClusters:
        viewpointClusters.length > 0
          ? viewpointClusters
          : [
              {
                label: "Interpretation differences",
                summary: "People disagree on how key passages should be interpreted and applied.",
                isControversial: true,
              },
              {
                label: "Pastoral application",
                summary: "Many focus on practical and pastoral outcomes rather than only doctrinal precision.",
                isControversial: false,
              },
            ],
      cautionNotes: Array.isArray(parsed?.cautionNotes)
        ? (parsed.cautionNotes as unknown[]).filter((v): v is string => typeof v === "string").slice(0, 6)
        : [
            "External discussion can reflect bias or incomplete context.",
            "Scripture should remain the final reference point.",
          ],
      scriptureAngles: Array.isArray(parsed?.scriptureAngles)
        ? (parsed.scriptureAngles as unknown[]).filter((v): v is string => typeof v === "string").slice(0, 6)
        : ["Locate direct passages", "Compare full chapter context", "Check cross-references"],
      helperUsed: raw.length > 0,
      finalAuthority: "berean_verification_required",
    };
  }
);

export const bereanHelperStudyOutline = onCall(
  {
    secrets: [anthropicApiKey, xaiApiKey],
    enforceAppCheck: true,
    timeoutSeconds: 40,
    memory: "512MiB",
  },
  async (request: CallableRequest) => {
    requireAuth(request);
    const topic = requireString((request.data ?? {}).topic, "topic");
    enforceSafeHelperScope(topic);

    const prompt = `You are an AI helper drafting a Bible study outline.
Return JSON only with keys:
- title (string)
- mainQuestion (string)
- keyPassages (array)
- historicalContext (string)
- reflectionQuestions (array)
- nextSteps (array)

Topic: ${topic.slice(0, 2500)}`;

    const raw = await callGrok(prompt, 520);
    const parsed = extractJsonObject(raw);

    const mainQuestion =
      typeof parsed?.mainQuestion === "string" && parsed.mainQuestion.trim().length > 0
        ? truncate(parsed.mainQuestion.trim(), 240)
        : `How should a believer approach "${truncate(topic, 120)}" in a Scripture-grounded way?`;

    return {
      title:
        typeof parsed?.title === "string" && parsed.title.trim().length > 0
          ? truncate(parsed.title.trim(), 120)
          : `Study: ${truncate(topic, 90)}`,
      mainQuestion,
      keyPassages: Array.isArray(parsed?.keyPassages)
        ? (parsed.keyPassages as unknown[]).filter((v): v is string => typeof v === "string").slice(0, 8)
        : findScriptureRefs(topic),
      historicalContext:
        typeof parsed?.historicalContext === "string" && parsed.historicalContext.trim().length > 0
          ? truncate(parsed.historicalContext.trim(), 360)
          : "Review original audience and historical setting before applying conclusions today.",
      reflectionQuestions: Array.isArray(parsed?.reflectionQuestions)
        ? (parsed.reflectionQuestions as unknown[]).filter((v): v is string => typeof v === "string").slice(0, 8)
        : [
            "What does the passage directly teach?",
            "What assumptions might I be bringing?",
            "How should this shape faithful practice this week?",
          ],
      nextSteps: Array.isArray(parsed?.nextSteps)
        ? (parsed.nextSteps as unknown[]).filter((v): v is string => typeof v === "string").slice(0, 8)
        : [
            "Read full chapter context.",
            "Compare at least two cross-references.",
            "Discuss with a trusted pastor or mature believer.",
          ],
      helperUsed: raw.length > 0,
      finalAuthority: "berean_verification_required",
    };
  }
);

const HIGH_RISK_PATTERNS = [
  /\b(suicide|self-harm|kill myself|end my life)\b/i,
  /\b(rape|sexual abuse|molest|grooming|exploitation)\b/i,
  /\b(domestic violence|abusive relationship|human trafficking)\b/i,
  /\b(emergency|immediate danger|i am in danger)\b/i,
];

const SCRIPTURE_REF_REGEX = /\b(?:[1-3]\s)?(?:Genesis|Exodus|Leviticus|Numbers|Deuteronomy|Joshua|Judges|Ruth|1\sSamuel|2\sSamuel|1\sKings|2\sKings|1\sChronicles|2\sChronicles|Ezra|Nehemiah|Esther|Job|Psalms?|Proverbs|Ecclesiastes|Song of Solomon|Isaiah|Jeremiah|Lamentations|Ezekiel|Daniel|Hosea|Joel|Amos|Obadiah|Jonah|Micah|Nahum|Habakkuk|Zephaniah|Haggai|Zechariah|Malachi|Matthew|Mark|Luke|John|Acts|Romans|1\sCorinthians|2\sCorinthians|Galatians|Ephesians|Philippians|Colossians|1\sThessalonians|2\sThessalonians|1\sTimothy|2\sTimothy|Titus|Philemon|Hebrews|James|1\sPeter|2\sPeter|1\sJohn|2\sJohn|3\sJohn|Jude|Revelation)\s\d{1,3}:\d{1,3}(?:-\d{1,3})?\b/gi;

const STOPWORDS = new Set([
  "about", "after", "again", "against", "because", "before", "being", "could", "should", "would", "their", "there", "these", "those", "while", "where", "which", "through", "without", "within", "under", "between", "other", "every", "still", "topic", "question", "please", "could", "might", "maybe", "really", "something", "someone", "christian", "scripture", "bible",
]);

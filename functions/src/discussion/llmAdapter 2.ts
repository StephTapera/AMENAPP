// llmAdapter.ts — LLM adapter for Berean AI discussion summaries

import * as logger from "firebase-functions/logger";

// ── Types ─────────────────────────────────────────────────────────────────────

export interface BereanLLMResult {
  summary: string;
  agreementPoints: string[];
  openQuestions: string[];
  biblicalRefs: string[];
  studyQuestions: string[];
  isMock: boolean;
  tokenCount: number;
}

// ── Mock response ─────────────────────────────────────────────────────────────

const MOCK_RESULT: BereanLLMResult = {
  summary: "This thread discusses faith and community. [Mock — no API key configured]",
  agreementPoints: ["Community matters", "Faith is foundational"],
  openQuestions: ["How do we apply this practically?"],
  biblicalRefs: ["JHN.3.16", "ROM.8.28"],
  studyQuestions: ["What does this passage mean for daily life?"],
  isMock: true,
  tokenCount: 0,
};

// ── generateBereanSummary ─────────────────────────────────────────────────────

export async function generateBereanSummary(prompt: string): Promise<BereanLLMResult> {
  const key = process.env.BEREAN_LLM_KEY ?? "";

  if (!key) {
    logger.info("llmAdapter: BEREAN_LLM_KEY not set — returning mock result.");
    return MOCK_RESULT;
  }

  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${key}`;

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
      }),
    });

    if (!response.ok) {
      logger.warn(`llmAdapter: Gemini API returned HTTP ${response.status} — falling back to mock.`);
      return MOCK_RESULT;
    }

    const json = (await response.json()) as {
      candidates?: Array<{
        content?: { parts?: Array<{ text?: string }> };
      }>;
      usageMetadata?: { totalTokenCount?: number };
    };

    const rawText = json?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
    const tokenCount = json?.usageMetadata?.totalTokenCount ?? 0;

    if (!rawText) {
      logger.warn("llmAdapter: Empty text from Gemini — falling back to mock.");
      return MOCK_RESULT;
    }

    // Strip markdown code fences if present
    const cleaned = rawText.replace(/^```(?:json)?\s*/i, "").replace(/\s*```\s*$/, "").trim();

    let parsed: {
      summary?: string;
      agreementPoints?: string[];
      openQuestions?: string[];
      biblicalRefs?: string[];
      studyQuestions?: string[];
    };

    try {
      parsed = JSON.parse(cleaned);
    } catch (parseErr) {
      logger.warn("llmAdapter: JSON parse failed on LLM response — falling back to mock.", { parseErr });
      return { ...MOCK_RESULT, isMock: true, tokenCount };
    }

    logger.info("llmAdapter: Gemini response parsed successfully.", { tokenCount });

    return {
      summary: String(parsed.summary ?? MOCK_RESULT.summary),
      agreementPoints: Array.isArray(parsed.agreementPoints) ? parsed.agreementPoints.map(String) : MOCK_RESULT.agreementPoints,
      openQuestions: Array.isArray(parsed.openQuestions) ? parsed.openQuestions.map(String) : MOCK_RESULT.openQuestions,
      biblicalRefs: Array.isArray(parsed.biblicalRefs) ? parsed.biblicalRefs.map(String) : MOCK_RESULT.biblicalRefs,
      studyQuestions: Array.isArray(parsed.studyQuestions) ? parsed.studyQuestions.map(String) : MOCK_RESULT.studyQuestions,
      isMock: false,
      tokenCount,
    };
  } catch (err) {
    logger.warn("llmAdapter: Network error calling Gemini — falling back to mock.", { err: String(err) });
    return MOCK_RESULT;
  }
}

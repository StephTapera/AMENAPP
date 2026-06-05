/**
 * nvidiaClient.js
 * Centralized NVIDIA API helper functions for AMEN Cloud Functions.
 *
 * HARD RULES:
 *   - This module accepts apiKey as a parameter — it never holds or logs the key.
 *   - Every caller must obtain the key via NVIDIA_API_KEY.value() from its own
 *     defineSecret() declaration and pass it in.  No key is centralized here.
 *   - Input/output are logged at a metadata level only — raw content is NEVER logged.
 *
 * Usage pattern in a caller:
 *   const { callNeMoGuard, callNvidiaLLM, callNvidiaASR } = require("./nvidiaClient");
 *   const NVIDIA_API_KEY = defineSecret("NVIDIA_API_KEY");
 *   // ... inside onCall({ secrets: [NVIDIA_API_KEY] }, async (req) => {
 *   const result = await callNeMoGuard(text, NVIDIA_API_KEY.value());
 */

"use strict";

// ─── Endpoints ────────────────────────────────────────────────────────────────

const NIM_URL      = "https://integrate.api.nvidia.com/v1/chat/completions";
const ASR_URL      = "https://api.nvidia.com/v1/asr/transcriptions";
const SAFETY_MODEL = "nvidia/llama-3.1-nemoguard-8b-content-safety";
const DEFAULT_LLM  = "meta/llama-3.1-70b-instruct";

// ─── Retry helper ─────────────────────────────────────────────────────────────

const RETRY_DELAYS_MS = [500, 1500, 4000]; // 3 attempts with exponential back-off

async function withRetry(fn, label) {
  let lastErr;
  for (let attempt = 0; attempt <= RETRY_DELAYS_MS.length; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      if (attempt < RETRY_DELAYS_MS.length) {
        const delay = RETRY_DELAYS_MS[attempt];
        console.warn(`[nvidiaClient] ${label} attempt ${attempt + 1} failed (${err.message}) — retrying in ${delay}ms`);
        await new Promise((r) => setTimeout(r, delay));
      }
    }
  }
  throw lastErr;
}

// ─── callNeMoGuard ────────────────────────────────────────────────────────────

/**
 * Call NVIDIA NeMo Guard for text content safety classification.
 *
 * @param {string} text     - Content to classify (up to 10 000 chars recommended)
 * @param {string} apiKey   - Raw NVIDIA_API_KEY value from Secret Manager
 * @returns {{ safe: boolean, categories: string[], rawLabel: string }}
 * @throws on network error or non-2xx response — callers must fail closed
 */
async function callNeMoGuard(text, apiKey) {
  return withRetry(async () => {
    const res = await fetch(NIM_URL, {
      method: "POST",
      headers: {
        "Content-Type":  "application/json",
        Authorization:   `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model:       SAFETY_MODEL,
        messages:    [{ role: "user", content: text }],
        max_tokens:  120,
        temperature: 0,
      }),
      signal: AbortSignal.timeout(25_000),
    });

    if (!res.ok) {
      const body = await res.text().catch(() => "(no body)");
      throw new Error(`NeMo Guard HTTP ${res.status}: ${body.slice(0, 200)}`);
    }

    const data = await res.json();
    const raw  = (data.choices?.[0]?.message?.content ?? "").trim();

    let safe = true;
    let categories = [];
    try {
      const parsed = JSON.parse(raw);
      safe = String(parsed["User Safety"] ?? "safe").toLowerCase() === "safe";
      const catStr = parsed["Safety Categories"] ?? "";
      categories = catStr.split(",").map((c) => c.trim().toLowerCase()).filter(Boolean);
    } catch {
      // Non-JSON response: treat as safe unless it explicitly says "unsafe"
      safe = !/unsafe/i.test(raw);
    }

    console.log(`[nvidiaClient:callNeMoGuard] safe=${safe} categories=${categories.join(",")}`);
    return { safe, categories, rawLabel: raw.slice(0, 300) };
  }, "callNeMoGuard");
}

// ─── callNvidiaLLM ────────────────────────────────────────────────────────────

/**
 * Generic NVIDIA NIM chat completion.
 *
 * @param {{ systemMsg: string, userMsg: string, apiKey: string, model?: string,
 *            maxTokens?: number, temperature?: number }} opts
 * @returns {string} raw completion text
 */
async function callNvidiaLLM({ systemMsg, userMsg, apiKey, model, maxTokens, temperature }) {
  const resolvedModel = model || DEFAULT_LLM;
  const resolvedMax   = maxTokens  ?? 1024;
  const resolvedTemp  = temperature ?? 0.7;

  return withRetry(async () => {
    const res = await fetch(NIM_URL, {
      method: "POST",
      headers: {
        "Content-Type":  "application/json",
        Authorization:   `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model:    resolvedModel,
        messages: [
          { role: "system", content: systemMsg },
          { role: "user",   content: userMsg   },
        ],
        max_tokens:  resolvedMax,
        temperature: resolvedTemp,
      }),
      signal: AbortSignal.timeout(25_000),
    });

    if (!res.ok) {
      const body = await res.text().catch(() => "(no body)");
      throw new Error(`NVIDIA NIM HTTP ${res.status}: ${body.slice(0, 200)}`);
    }

    const data = await res.json();
    const text = String(data.choices?.[0]?.message?.content ?? "").trim();
    console.log(`[nvidiaClient:callNvidiaLLM] model=${resolvedModel} outputLen=${text.length}`);
    return text;
  }, `callNvidiaLLM(${resolvedModel})`);
}

// ─── callNvidiaASR ────────────────────────────────────────────────────────────

/**
 * Submit an audio URL to NVIDIA ASR for transcription.
 *
 * @param {string} audioUrl  Firebase Storage signed URL (gs:// or https://)
 * @param {string} apiKey    Raw NVIDIA_API_KEY value from Secret Manager
 * @returns {string} transcript text
 */
async function callNvidiaASR(audioUrl, apiKey) {
  return withRetry(async () => {
    const res = await fetch(ASR_URL, {
      method:  "POST",
      headers: {
        Authorization:  `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ audio_url: audioUrl, language: "en" }),
      signal: AbortSignal.timeout(90_000), // ASR can be slow for long audio
    });

    if (!res.ok) {
      const body = await res.text().catch(() => "(no body)");
      throw new Error(`NVIDIA ASR HTTP ${res.status}: ${body.slice(0, 200)}`);
    }

    const data = await res.json();
    const transcript =
      data.text ??
      data.transcript ??
      data.results?.[0]?.transcript ??
      "";
    const result = String(transcript).trim();
    console.log(`[nvidiaClient:callNvidiaASR] transcriptLen=${result.length}`);
    return result;
  }, "callNvidiaASR");
}

// ─── Exports ──────────────────────────────────────────────────────────────────

module.exports = {
  callNeMoGuard,
  callNvidiaLLM,
  callNvidiaASR,
  NIM_URL,
  ASR_URL,
  SAFETY_MODEL,
  DEFAULT_LLM,
};

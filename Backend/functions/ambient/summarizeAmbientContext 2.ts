// summarizeAmbientContext.ts — Ambient OS · Summarizer Cloud Function
// FROZEN v1 · 2026-06-01
//
// Callable (App Check + Auth gated). Takes AmbientContext, returns AmbientSummary.
// Uses Anthropic proxy (server-side; key never reaches client).
// Same call drives BOTH the prose Home header (Image 1) AND the Priority Actions
// timeline (Image 7).

import * as functions from "firebase-functions/v2";
import { CallableRequest, onCall } from "firebase-functions/v2/https";
import Anthropic from "@anthropic-ai/sdk";
import { AmbientContext, AmbientSummary, PriorityAction, ActionTier, ActionSource } from "./types";

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

export const summarizeAmbientContext = onCall(
  { enforceAppCheck: true, maxInstances: 20, timeoutSeconds: 30 },
  async (req: CallableRequest<{ context: AmbientContext }>) => {
    if (!req.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in required");

    const ctx = req.data?.context;
    if (!ctx) throw new functions.https.HttpsError("invalid-argument", "context required");

    const systemPrompt = `You are Berean, a faith-grounded pastoral assistant for the AMEN app.
Generate a brief, warm greeting and a ranked action list for ${ctx.user.firstName}.
Rules:
- Greeting prose: 1–2 sentences, pastoral warmth, faith-native language.
  Reference what is actually in the context. DO NOT fabricate information.
- NEVER reference engagement counts, follower numbers, or public metrics.
- NEVER draft actions directed at other people (no auto-replies, no auto-follows).
- Actions: rank by spiritual/relational urgency. Tier: high = today/urgent, medium = this week, low = when time allows.
- Return JSON only. Schema: { greetingProse: string, actions: PriorityAction[] }
- PriorityAction schema: { id, tier, title, source, deepLink, scheduledAt? }`;

    const userPrompt = JSON.stringify(ctx, null, 2);

    const response = await client.messages.create({
      model: "claude-opus-4-5",
      max_tokens: 1024,
      system: systemPrompt,
      messages: [{ role: "user", content: userPrompt }],
    });

    const raw = (response.content[0] as { type: string; text: string }).text ?? "{}";
    let parsed: { greetingProse?: string; actions?: unknown[] };
    try {
      const clean = raw.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
      parsed = JSON.parse(clean);
    } catch {
      throw new functions.https.HttpsError("internal", "Failed to parse Berean response");
    }

    const actions: PriorityAction[] = (parsed.actions ?? []).map((a: any, i: number) => ({
      id: a.id ?? `action-${i}`,
      tier: (["high", "medium", "low"].includes(a.tier) ? a.tier : "medium") as ActionTier,
      title: String(a.title ?? ""),
      source: (["prayer","note","message","church","selah","berean"].includes(a.source)
        ? a.source : "berean") as ActionSource,
      deepLink: String(a.deepLink ?? "amen://home"),
      scheduledAt: typeof a.scheduledAt === "string" ? a.scheduledAt : undefined,
    }));

    const summary: AmbientSummary = {
      greetingProse: String(parsed.greetingProse ?? `Good day, ${ctx.user.firstName}.`),
      actions,
    };

    return summary;
  }
);

// ─── classifyComposerIntent (§2.5 SmartComposerIntent) ──────────────────────
// Companion callable: classifies free-form composer text → chip suggestions.
// Returns SmartComposerIntent. Advisory only; client must not auto-apply.

export const classifyComposerIntent = onCall(
  { enforceAppCheck: true, maxInstances: 30, timeoutSeconds: 10 },
  async (req: CallableRequest<{ text: string }>) => {
    if (!req.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in required");

    const text = req.data?.text ?? "";
    if (!text.trim()) return { chips: [], postType: null };

    const response = await client.messages.create({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 128,
      system: `Classify the composer text into AMEN post type chips. Return JSON only.
Schema: { chips: string[], postType?: string }
chips values: photo | churchNote | event | prayerRequest | sermon | scripture
postType values: PrayerRequest | Testimony | ChurchNote`,
      messages: [{ role: "user", content: text }],
    });

    const raw = (response.content[0] as { type: string; text: string }).text ?? "{}";
    try {
      const clean = raw.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
      return JSON.parse(clean);
    } catch {
      return { chips: [], postType: null };
    }
  }
);

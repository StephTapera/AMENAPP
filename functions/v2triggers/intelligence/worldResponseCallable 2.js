"use strict";

/**
 * worldResponseCallable.js
 *
 * AMEN Intelligence — World Response callable Cloud Function.
 *
 * Exports:
 *   getWorldResponseCards — onCall callable for iOS client
 *
 * Contract:
 *   - Requires authenticated user
 *   - Returns { cards: IntelligenceCard[] }
 *   - Fail-closed: any error returns { cards: [] } — never surfaces error to user
 *   - Cards are GLOBAL tier, DEVELOPING capped at rankScore 40
 *   - Actions restricted to PRAY / GIVE / SHOW_UP / DISCUSS only
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret }       = require("firebase-functions/params");
const admin                  = require("firebase-admin");
const Anthropic              = require("@anthropic-ai/sdk");

const { buildWorldResponseCards } = require("./worldResponse");

// ─── Secrets ──────────────────────────────────────────────────────────────────

const BEREAN_LLM_KEY    = defineSecret("BEREAN_LLM_KEY");
const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");

// ─── AI model call ────────────────────────────────────────────────────────────

/**
 * callModelFn factory — creates the function that worldResponse.js calls
 * for each event.  Uses Anthropic SDK with ANTHROPIC_API_KEY.
 *
 * Returns { known: string[], contested: string[], howToRespond: string[] }
 * or null on failure.
 */
function makeCallModelFn() {
    return async function callModelFn(payload) {
        const { task, input } = payload;

        if (task !== "intelligence.world_response") {
            console.warn("[worldResponseCallable] Unknown task:", task);
            return null;
        }

        // Build a factual-framing prompt — no political takes, no opinion
        const prompt = buildWorldResponsePrompt(input);

        let client;
        try {
            client = new Anthropic.default({ apiKey: ANTHROPIC_API_KEY.value() });
        } catch (err) {
            console.error("[worldResponseCallable] Failed to init Anthropic client:", err.message);
            return null;
        }

        let message;
        try {
            message = await client.messages.create({
                model: "claude-opus-4-5",
                max_tokens: 512,
                temperature: 0,
                messages: [
                    {
                        role: "user",
                        content: prompt,
                    },
                ],
            });
        } catch (err) {
            console.error("[worldResponseCallable] Anthropic API error:", err.message);
            return null;
        }

        const rawText =
            message.content?.[0]?.type === "text"
                ? message.content[0].text.trim()
                : "";

        if (!rawText) {
            console.warn("[worldResponseCallable] Empty response from model");
            return null;
        }

        // Parse JSON from model output
        try {
            const parsed = JSON.parse(rawText);

            if (
                !Array.isArray(parsed.known) ||
                !Array.isArray(parsed.contested) ||
                !Array.isArray(parsed.howToRespond)
            ) {
                console.warn("[worldResponseCallable] Model output missing required arrays");
                return null;
            }

            // Sanitise: ensure all entries are strings, cap list lengths
            return {
                known: parsed.known
                    .filter((s) => typeof s === "string" && s.trim())
                    .slice(0, 4),
                contested: parsed.contested
                    .filter((s) => typeof s === "string" && s.trim())
                    .slice(0, 4),
                howToRespond: parsed.howToRespond
                    .filter((s) => typeof s === "string" && s.trim())
                    .slice(0, 3),
            };
        } catch (err) {
            console.error("[worldResponseCallable] Failed to parse model JSON:", err.message);
            return null;
        }
    };
}

/**
 * Build the prompt for the world-response intelligence task.
 * Strictly factual framing — no political commentary, no editorial opinion.
 * Output is always JSON matching { known, contested, howToRespond }.
 */
function buildWorldResponsePrompt(event) {
    return `You are a factual summarisation assistant for a Christian community app.
Your task is to summarise a world event for Christian readers who want to pray,
give, and respond faithfully — not to debate or form political opinions.

Event title: ${event.title}
Event type: ${event.type ?? "unspecified"}
Source: ${event.source}
Verified: ${event.verified ? "yes" : "no / still developing"}

Return ONLY valid JSON in this exact shape:
{
  "known": ["<fact 1>", "<fact 2>"],
  "contested": ["<what is uncertain or disputed 1>", "<what is uncertain or disputed 2>"],
  "howToRespond": ["<actionable Christian response 1>", "<actionable Christian response 2>"]
}

Rules:
- "known" — only well-sourced, publicly reported facts (2–4 items)
- "contested" — facts that are disputed, unclear, or still developing (1–3 items)
- "howToRespond" — practical ways Christians can pray, give, or serve (1–3 items)
- No political takes, editorial opinion, or commentary
- No speculation about causes or blame
- Plain language, no jargon
- Respond with JSON only — no surrounding text`;
}

// ─── Callable export ──────────────────────────────────────────────────────────

/**
 * getWorldResponseCards
 *
 * iOS callable: fetches world-response IntelligenceCards for the authenticated user.
 *
 * Returns { cards: IntelligenceCard[] }
 * On any error: returns { cards: [] } — fail-closed, no error surfaced to user.
 */
exports.getWorldResponseCards = onCall(
    {
        region: "us-central1",
        secrets: [BEREAN_LLM_KEY, ANTHROPIC_API_KEY],
        timeoutSeconds: 60,
        memory: "512MiB",
    },
    async (request) => {
        // ── Auth ─────────────────────────────────────────────────────────────
        if (!request.auth?.uid) {
            // Fail-closed: return empty rather than throwing to user
            console.warn("[getWorldResponseCards] Unauthenticated call — returning []");
            return { cards: [] };
        }

        const userId = request.auth.uid;
        console.log(`[getWorldResponseCards] uid=${userId}`);

        try {
            const db           = admin.firestore();
            const callModelFn  = makeCallModelFn();

            const cards = await buildWorldResponseCards(userId, db, callModelFn);

            console.log(`[getWorldResponseCards] Returning ${cards.length} cards for uid=${userId}`);
            return { cards };
        } catch (err) {
            // Fail-closed: any unhandled error returns empty cards — not an error to user
            console.error(`[getWorldResponseCards] Unhandled error uid=${userId}:`, err.message);
            return { cards: [] };
        }
    }
);

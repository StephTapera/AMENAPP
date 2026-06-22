/**
 * keyMomentInference.ts
 *
 * Infers 3–6 key moments from a transcription result.
 *
 * Strategy (in order of priority):
 *   1. Heuristic structural detection (always runs, never fails)
 *      - Scripture reference detection  → kind: verse
 *      - Prayer language detection       → kind: prayer
 *      - Temporal anchor placement       → kinds: intro, mainPoint, reflection
 *   2. Claude label refinement (optional, requires ANTHROPIC_API_KEY)
 *      - Replaces generic heuristic labels with short, specific labels
 *      - If Claude fails, heuristic labels are used as-is
 *
 * Merge rule:
 *   The pipeline calls this ONLY when no user-authored moments exist.
 *   This module never reads or touches Firestore — it just produces data.
 *
 * Required secret for label refinement (optional):
 *   ANTHROPIC_API_KEY
 *   firebase functions:secrets:set ANTHROPIC_API_KEY
 */

import {defineSecret} from "firebase-functions/params";
import {TranscriptionResult} from "./transcriptionProvider";

export const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// ─── Types ───────────────────────────────────────────────────────────────────

export type KeyMomentKind =
    | "intro"
    | "mainPoint"
    | "verse"
    | "prayer"
    | "reflection"
    | "custom";

export interface GeneratedKeyMoment {
    momentId: string;
    time: number;      // seconds
    label: string;
    kind: KeyMomentKind;
    source: "generated";
    sortOrder: number;
}

// ─── Heuristic detection ──────────────────────────────────────────────────────

const SCRIPTURE_PATTERN =
    /\b(genesis|exodus|leviticus|numbers|deuteronomy|joshua|judges|ruth|samuel|kings|chronicles|ezra|nehemiah|esther|job|psalm|psalms|proverbs|ecclesiastes|song|isaiah|jeremiah|lamentations|ezekiel|daniel|hosea|joel|amos|obadiah|jonah|micah|nahum|habakkuk|zephaniah|haggai|zechariah|malachi|matthew|mark|luke|john|acts|romans|corinthians|galatians|ephesians|philippians|colossians|thessalonians|timothy|titus|philemon|hebrews|james|peter|jude|revelation)\s+\d+[:\d]*/i;

const PRAYER_PATTERN =
    /\b(let us pray|father god|lord jesus|heavenly father|dear god|amen|in jesus name|holy spirit|we thank you lord|we praise you|let's pray|bow your heads)\b/i;

const MAIN_POINT_PATTERN =
    /\b(the point is|what i want you to (know|see|understand)|this is important|key (truth|principle|lesson)|the message (is|today)|god (is telling|wants us to|says))\b/i;

/** Extract the cue text that starts at or after `seconds`. */
function cueNear(cues: TranscriptionResult["cues"], seconds: number): string {
    const found = cues.find((c) => c.startTime >= seconds - 2 && c.startTime <= seconds + 10);
    return found?.text ?? "";
}

/**
 * Produce 3–6 key moments from transcript using only heuristics.
 * Never throws. Falls back gracefully if transcript is empty.
 */
export function inferKeyMomentsHeuristic(
    transcript: TranscriptionResult
): GeneratedKeyMoment[] {
    const {cues, durationSeconds} = transcript;
    const moments: GeneratedKeyMoment[] = [];

    if (durationSeconds < 15 || cues.length === 0) {
        return [];
    }

    // 1. Intro — always at 0
    moments.push({
        momentId: `gen-intro`,
        time: 0,
        label: "Intro",
        kind: "intro",
        source: "generated",
        sortOrder: 0,
    });

    // 2. Scan cues for scripture references
    for (const cue of cues) {
        if (SCRIPTURE_PATTERN.test(cue.text)) {
            const t = cue.startTime;
            // Don't cluster moments within 15 s of each other
            if (moments.every((m) => Math.abs(m.time - t) > 15)) {
                const match = cue.text.match(SCRIPTURE_PATTERN);
                moments.push({
                    momentId: `gen-verse-${Math.round(t)}`,
                    time: t,
                    label: match ? capitalise(match[0]).slice(0, 40) : "Scripture",
                    kind: "verse",
                    source: "generated",
                    sortOrder: moments.length,
                });
            }
            if (moments.length >= 5) break;
        }
    }

    // 3. Scan cues for prayer language
    for (const cue of cues) {
        if (PRAYER_PATTERN.test(cue.text)) {
            const t = cue.startTime;
            if (moments.every((m) => Math.abs(m.time - t) > 15)) {
                moments.push({
                    momentId: `gen-prayer-${Math.round(t)}`,
                    time: t,
                    label: "Prayer",
                    kind: "prayer",
                    source: "generated",
                    sortOrder: moments.length,
                });
            }
            if (moments.length >= 5) break;
        }
    }

    // 4. Main point if nothing found yet at ~30% mark
    if (moments.length < 3 && durationSeconds > 60) {
        const mainPointTime = durationSeconds * 0.3;
        if (moments.every((m) => Math.abs(m.time - mainPointTime) > 15)) {
            const nearby = cueNear(cues, mainPointTime);
            const isMainPoint = MAIN_POINT_PATTERN.test(nearby);
            moments.push({
                momentId: `gen-main-${Math.round(mainPointTime)}`,
                time: mainPointTime,
                label: isMainPoint ? "Main point" : "Key teaching",
                kind: "mainPoint",
                source: "generated",
                sortOrder: moments.length,
            });
        }
    }

    // 5. Reflection near the end
    if (durationSeconds > 45) {
        const reflectionTime = durationSeconds * 0.85;
        if (moments.every((m) => Math.abs(m.time - reflectionTime) > 15)) {
            moments.push({
                momentId: `gen-reflection-${Math.round(reflectionTime)}`,
                time: reflectionTime,
                label: "Reflection",
                kind: "reflection",
                source: "generated",
                sortOrder: moments.length,
            });
        }
    }

    // Sort by time and reassign sortOrder
    moments.sort((a, b) => a.time - b.time);
    return moments.slice(0, 6).map((m, idx) => ({...m, sortOrder: idx}));
}

// ─── Claude label refinement ──────────────────────────────────────────────────

interface ClaudeMessage {
    content?: Array<{type?: string; text?: string}>;
}

/**
 * Refine heuristic moment labels using Claude for short, specific titles.
 * Returns original moments unchanged if Claude is unavailable or fails.
 *
 * This is called with the resolved secret value, not the SecretParam,
 * so the caller (pipeline) controls secret access in the function config.
 */
export async function refineMomentLabelsWithClaude(
    moments: GeneratedKeyMoment[],
    transcript: TranscriptionResult,
    apiKey: string
): Promise<GeneratedKeyMoment[]> {
    if (!apiKey || moments.length === 0) return moments;

    // Build a compact transcript snapshot for context (max ~800 chars)
    const snippets = transcript.cues
        .filter((c) => moments.some((m) => Math.abs(c.startTime - m.time) < 30))
        .slice(0, 12)
        .map((c) => `[${fmt(c.startTime)}] ${c.text}`)
        .join("\n");

    const momentList = moments
        .map((m) => `${m.momentId} @ ${fmt(m.time)} — current label: "${m.label}" (${m.kind})`)
        .join("\n");

    const prompt =
        `You are labelling chapters in a Christian sermon or Bible study video.\n` +
        `Below are transcript excerpts and a list of detected moments.\n` +
        `For each moment, write a short (2–5 word) specific label that describes what happens there.\n` +
        `Prefer concrete over generic (e.g. "Romans 8:28" not "Scripture reading").\n` +
        `Respond ONLY with a JSON array of objects: [{momentId, label}]. No markdown.\n\n` +
        `Transcript excerpts:\n${snippets}\n\n` +
        `Moments:\n${momentList}`;

    try {
        const response = await fetch("https://api.anthropic.com/v1/messages", {
            method: "POST",
            headers: {
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            body: JSON.stringify({
                model: "claude-haiku-4-5-20251001",
                max_tokens: 512,
                messages: [{role: "user", content: prompt}],
            }),
        });

        if (!response.ok) return moments; // degrade silently

        const result = (await response.json()) as ClaudeMessage;
        const text = result.content?.find((b) => b.type === "text")?.text ?? "";

        // Parse JSON from response
        const jsonMatch = text.match(/\[[\s\S]*\]/);
        if (!jsonMatch) return moments;

        const labels: Array<{momentId: string; label: string}> = JSON.parse(jsonMatch[0]);
        const labelMap = new Map(labels.map((l) => [l.momentId, l.label]));

        return moments.map((m) => {
            const refined = labelMap.get(m.momentId);
            if (refined && refined.trim().length > 0 && refined.trim().length <= 60) {
                return {...m, label: refined.trim()};
            }
            return m;
        });
    } catch {
        // Claude unavailable or parse error — return heuristic labels unchanged
        return moments;
    }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function capitalise(s: string): string {
    return s.charAt(0).toUpperCase() + s.slice(1);
}

function fmt(seconds: number): string {
    const m = Math.floor(seconds / 60);
    const s = Math.floor(seconds % 60);
    return `${m}:${s.toString().padStart(2, "0")}`;
}

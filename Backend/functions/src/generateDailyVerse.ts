/**
 * generateDailyVerse.ts
 *
 * Personalized daily verse generation using OpenAI.
 * Called by DailyVerseGenkitService.swift via Firebase callable.
 *
 * Input: user goals, recent topics, prayer themes, liturgical context
 * Output: { verse: { reference, text, theme, reflection, prayer } }
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {enforceRateLimit, RATE_LIMITS} from "./rateLimit";

const openaiApiKey = defineSecret("OPENAI_API_KEY");

interface DailyVerseRequest {
    goals?: string[];
    recentTopics?: string[];
    prayerThemes?: string[];
    liturgicalSeason?: string;
    liturgicalSeasonName?: string;
    liturgicalThemes?: string[];
    activeObservances?: string[];
    upcomingObservance?: string;
}

interface VerseOutput {
    reference: string;
    text: string;
    theme: string;
    reflection: string;
    prayer: string;
}

/**
 * generateDailyVerse — returns a personalized scripture verse with reflection
 * and prayer prompt, informed by the user's spiritual context and the church calendar.
 */
export const generateDailyVerse = onCall(
    {
        secrets: [openaiApiKey],
        timeoutSeconds: 30,
        memory: "256MiB",
        // NOTE: enforceAppCheck is intentionally omitted here so the function
        // works on the simulator before a debug App Check token is registered
        // in the Firebase console. Add enforceAppCheck: false after registering.
    },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Must be signed in");
        }

        await enforceRateLimit(request.auth.uid, [RATE_LIMITS.AI_PER_MINUTE]);

        const data = request.data as DailyVerseRequest;
        const {
            goals = [],
            recentTopics = [],
            prayerThemes = [],
            liturgicalSeasonName = "",
            liturgicalThemes = [],
            activeObservances = [],
            upcomingObservance,
        } = data;

        const contextParts: string[] = [];
        if (goals.length) contextParts.push(`Spiritual goals: ${goals.join(", ")}`);
        if (recentTopics.length) contextParts.push(`Recent topics: ${recentTopics.join(", ")}`);
        if (prayerThemes.length) contextParts.push(`Prayer themes: ${prayerThemes.join(", ")}`);
        if (liturgicalSeasonName) contextParts.push(`Church season: ${liturgicalSeasonName}`);
        if (liturgicalThemes.length) contextParts.push(`Season themes: ${liturgicalThemes.join(", ")}`);
        if (activeObservances.length) contextParts.push(`Today's observance: ${activeObservances.join(", ")}`);
        if (upcomingObservance) contextParts.push(`Upcoming: ${upcomingObservance}`);

        const userContext = contextParts.length
            ? contextParts.join(". ")
            : "General Christian encouragement";

        const prompt = `You are a thoughtful Christian devotional writer. Select one Bible verse that speaks directly to this person's spiritual context and provide a brief, heartfelt reflection.

Context: ${userContext}

Respond with valid JSON only, matching this exact structure:
{
  "reference": "Book Chapter:Verse",
  "text": "The exact verse text (NIV)",
  "theme": "One-word theme (e.g. Hope, Strength, Peace)",
  "reflection": "2-3 sentence reflection connecting the verse to the user's context",
  "prayer": "1-2 sentence prayer starter"
}`;

        const response = await fetch("https://api.openai.com/v1/chat/completions", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "Authorization": `Bearer ${openaiApiKey.value()}`,
            },
            body: JSON.stringify({
                model: "gpt-4o-mini",
                messages: [{role: "user", content: prompt}],
                max_tokens: 400,
                temperature: 0.7,
                response_format: {type: "json_object"},
            }),
        });

        if (!response.ok) {
            throw new HttpsError("internal", `OpenAI error: ${response.status}`);
        }

        const json = await response.json() as {choices?: Array<{message?: {content?: string}}>};
        const content = json.choices?.[0]?.message?.content;
        if (!content) {
            throw new HttpsError("internal", "Empty response from OpenAI");
        }

        let verse: VerseOutput;
        try {
            verse = JSON.parse(content) as VerseOutput;
        } catch {
            throw new HttpsError("internal", "Failed to parse verse JSON");
        }

        if (!verse.reference || !verse.text || !verse.theme) {
            throw new HttpsError("internal", "Incomplete verse data from OpenAI");
        }

        return {verse};
    }
);

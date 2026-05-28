import { ChurchSearchIntent, ChurchSearchResult } from "./churchDiscoveryModels";

const OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses";
const SUMMARY_MODEL = "gpt-4.1-mini";

const SUMMARY_SCHEMA = {
    type: "object",
    additionalProperties: false,
    required: ["summaries"],
    properties: {
        summaries: {
            type: "array",
            items: {
                type: "object",
                additionalProperties: false,
                required: ["id", "thisMayFitBecause", "checkThisFirst", "bestNextStep"],
                properties: {
                    id: { type: "string" },
                    thisMayFitBecause: { type: "string" },
                    checkThisFirst: { type: "string" },
                    bestNextStep: { type: "string" },
                },
            },
        },
    },
};

export function enforceGroundedSummaries(results: ChurchSearchResult[]): ChurchSearchResult[] {
    return results.map((result) => {
        const facts = result.explanation.verifiedFacts;
        const why = result.explanation.whyThisMayFit;
        const missing = result.explanation.missingInfo;
        return {
            ...result,
            summary: {
                thisMayFitBecause: why[0] ?? facts[0] ?? "This result has limited verified match context.",
                checkThisFirst: missing[0] ?? "Confirm service times and ministry details before visiting.",
                bestNextStep: result.website ? "Visit the church website or open details in Amen." : "Open details and verify contact information.",
            },
        };
    });
}

export async function generateGroundedChurchSummaries(input: {
    results: ChurchSearchResult[];
    intent: ChurchSearchIntent;
    rawQuery: string;
    apiKey?: string;
}): Promise<ChurchSearchResult[]> {
    const fallback = enforceGroundedSummaries(input.results);
    const apiKey = input.apiKey;
    if (!apiKey || apiKey.startsWith("mock-") || fallback.length === 0) return fallback;

    const topResults = fallback.slice(0, 12);
    const response = await fetch(OPENAI_RESPONSES_URL, {
        method: "POST",
        headers: {
            "Authorization": `Bearer ${apiKey}`,
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            model: SUMMARY_MODEL,
            input: [
                {
                    role: "system",
                    content: "Write short church discovery summaries using only supplied facts, missing-info notes, source labels, and the user's search intent. Do not invent ministries, service times, doctrinal safety, or spiritual quality claims. Phrase fit as tentative.",
                },
                {
                    role: "user",
                    content: JSON.stringify({
                        rawQuery: input.rawQuery,
                        intent: input.intent,
                        results: topResults.map((result) => ({
                            id: result.id,
                            name: result.name,
                            denomination: result.denomination,
                            distanceMiles: result.distanceMiles,
                            verifiedByAmen: result.verifiedByAmen,
                            why: result.explanation.whyThisMayFit,
                            facts: result.explanation.verifiedFacts,
                            missing: result.explanation.missingInfo,
                            sources: result.explanation.sources,
                            websiteListed: Boolean(result.website),
                            addressListed: Boolean(result.address),
                        })),
                    }),
                },
            ],
            text: {
                format: {
                    type: "json_schema",
                    name: "church_discovery_summaries",
                    strict: true,
                    schema: SUMMARY_SCHEMA,
                },
            },
        }),
    });

    if (!response.ok) return fallback;

    const json = await response.json() as { output_text?: string };
    const parsed = JSON.parse(json.output_text ?? "{}") as {
        summaries?: Array<{
            id?: string;
            thisMayFitBecause?: string;
            checkThisFirst?: string;
            bestNextStep?: string;
        }>;
    };
    const summariesById = new Map((parsed.summaries ?? []).map((summary) => [summary.id, summary]));

    return fallback.map((result) => {
        const summary = summariesById.get(result.id);
        if (!summary) return result;
        return {
            ...result,
            summary: {
                thisMayFitBecause: cleanSummary(summary.thisMayFitBecause, result.summary.thisMayFitBecause),
                checkThisFirst: cleanSummary(summary.checkThisFirst, result.summary.checkThisFirst),
                bestNextStep: cleanSummary(summary.bestNextStep, result.summary.bestNextStep),
            },
        };
    });
}

function cleanSummary(value: unknown, fallback: string): string {
    const text = String(value ?? "").replace(/\s+/g, " ").trim();
    if (!text) return fallback;
    return text.slice(0, 220);
}

import { defineSecret } from "firebase-functions/params";
import { ChurchSearchIntent, EMPTY_INTENT, UserLocationContext } from "./churchDiscoveryModels";

export const openaiApiKey = defineSecret("OPENAI_API_KEY");

const OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses";
const MODEL = "gpt-4.1-mini";

const ALLOWED_DENOMINATIONS = [
    "Baptist", "Catholic", "Pentecostal", "Methodist", "Presbyterian",
    "Lutheran", "Anglican", "Episcopal", "Orthodox", "Non-denominational",
    "Church of Christ", "Assemblies of God", "Reformed", "Bible Church",
];

const INTENT_SCHEMA = {
    type: "object",
    additionalProperties: false,
    required: [
        "denominationPreferences", "traditionPreferences", "worshipStyle", "teachingStyle",
        "communityNeeds", "lifeStage", "servicePreferences", "groupNeeds", "accessibilityNeeds",
        "languagePreferences", "distancePreference", "mustHave", "niceToHave", "avoid",
        "confidence", "needsClarification", "clarifyingQuestion",
    ],
    properties: {
        denominationPreferences: { type: "array", items: { type: "string" } },
        traditionPreferences: { type: "array", items: { type: "string" } },
        worshipStyle: { type: "array", items: { type: "string" } },
        teachingStyle: { type: "array", items: { type: "string" } },
        communityNeeds: { type: "array", items: { type: "string" } },
        lifeStage: { type: "array", items: { type: "string" } },
        servicePreferences: { type: "array", items: { type: "string" } },
        groupNeeds: { type: "array", items: { type: "string" } },
        accessibilityNeeds: { type: "array", items: { type: "string" } },
        languagePreferences: { type: "array", items: { type: "string" } },
        distancePreference: {
            type: "string",
            enum: ["nearby", "within_10_miles", "within_25_miles", "online_ok", "unspecified"],
        },
        mustHave: { type: "array", items: { type: "string" } },
        niceToHave: { type: "array", items: { type: "string" } },
        avoid: { type: "array", items: { type: "string" } },
        confidence: { type: "number", minimum: 0, maximum: 1 },
        needsClarification: { type: "boolean" },
        clarifyingQuestion: { type: ["string", "null"] },
    },
};

export function sanitizeChurchQuery(rawQuery: string): string {
    return rawQuery
        .replace(/```[\s\S]*?```/g, " ")
        .replace(/\b(ignore|disregard|override|developer|system prompt|jailbreak)\b/gi, " ")
        .replace(/\s+/g, " ")
        .trim()
        .slice(0, 400);
}

function uniqueClean(values: unknown[], allowed?: string[]): string[] {
    const seen = new Set<string>();
    const output: string[] = [];
    for (const raw of values) {
        const value = String(raw ?? "").trim();
        if (!value) continue;
        const normalized = allowed?.find((item) => item.toLowerCase() === value.toLowerCase()) ?? value;
        if (allowed && !allowed.some((item) => item.toLowerCase() === normalized.toLowerCase())) continue;
        const key = normalized.toLowerCase();
        if (!seen.has(key)) {
            seen.add(key);
            output.push(normalized);
        }
    }
    return output.slice(0, 12);
}

function heuristicIntent(query: string): ChurchSearchIntent {
    const lowered = query.toLowerCase();
    const intent: ChurchSearchIntent = { ...EMPTY_INTENT };

    intent.denominationPreferences = ALLOWED_DENOMINATIONS.filter((denom) =>
        lowered.includes(denom.toLowerCase()) ||
        (denom === "Non-denominational" && lowered.includes("non denominational"))
    );
    if (lowered.includes("spirit-filled") || lowered.includes("spirit filled") || lowered.includes("charismatic")) {
        intent.traditionPreferences.push("Charismatic");
        intent.worshipStyle.push("Spirit-filled");
    }
    if (lowered.includes("traditional")) intent.worshipStyle.push("Traditional");
    if (lowered.includes("contemporary")) intent.worshipStyle.push("Contemporary");
    if (lowered.includes("worship")) intent.worshipStyle.push("Worship");
    if (lowered.includes("bible") || lowered.includes("teaching") || lowered.includes("expository")) {
        intent.teachingStyle.push("Bible teaching");
    }
    if (lowered.includes("young adult")) intent.lifeStage.push("Young adults");
    if (lowered.includes("famil")) intent.lifeStage.push("Families");
    if (lowered.includes("new believer")) intent.communityNeeds.push("New believers");
    if (lowered.includes("small group") || lowered.includes("community group")) intent.groupNeeds.push("Small groups");
    if (lowered.includes("recovery")) intent.communityNeeds.push("Recovery");
    if (lowered.includes("mentor")) intent.communityNeeds.push("Mentorship");
    if (lowered.includes("online")) intent.distancePreference = "online_ok";
    else if (lowered.includes("25")) intent.distancePreference = "within_25_miles";
    else if (lowered.includes("10")) intent.distancePreference = "within_10_miles";
    else if (lowered.includes("near")) intent.distancePreference = "nearby";

    intent.mustHave = uniqueClean([
        ...intent.denominationPreferences,
        ...intent.teachingStyle,
        ...intent.communityNeeds,
        ...intent.lifeStage,
        ...intent.groupNeeds,
    ]);
    intent.niceToHave = uniqueClean([...intent.worshipStyle, ...intent.traditionPreferences]);
    intent.confidence = query.length < 8 ? 0.25 : 0.62;
    intent.needsClarification = query.length < 12;
    intent.clarifyingQuestion = intent.needsClarification ? "What matters most: teaching, worship style, community groups, or distance?" : null;
    return intent;
}

export async function parseIntentWithStructuredOutputs(input: {
    rawQuery: string;
    approximateLocation?: UserLocationContext | null;
    savedPreferences?: Record<string, unknown> | null;
    apiKey?: string;
}): Promise<ChurchSearchIntent> {
    const sanitized = sanitizeChurchQuery(input.rawQuery);
    if (!sanitized) return { ...EMPTY_INTENT, needsClarification: true, clarifyingQuestion: "What kind of church or community are you looking for?" };

    const apiKey = input.apiKey ?? openaiApiKey.value();
    if (!apiKey || apiKey.startsWith("mock-")) {
        return heuristicIntent(sanitized);
    }

    const response = await fetch(OPENAI_RESPONSES_URL, {
        method: "POST",
        headers: {
            "Authorization": `Bearer ${apiKey}`,
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            model: MODEL,
            input: [
                {
                    role: "system",
                    content: "Parse church/community search intent into strict JSON. Never invent denominations. Interpret vague preferences neutrally. Do not make doctrinal judgments or rank traditions spiritually.",
                },
                {
                    role: "user",
                    content: JSON.stringify({
                        rawQuery: sanitized,
                        approximateLocation: input.approximateLocation ?? null,
                        savedPreferences: input.savedPreferences ?? null,
                        allowedDenominations: ALLOWED_DENOMINATIONS,
                    }),
                },
            ],
            text: {
                format: {
                    type: "json_schema",
                    name: "church_search_intent",
                    strict: true,
                    schema: INTENT_SCHEMA,
                },
            },
        }),
    });

    if (!response.ok) {
        return heuristicIntent(sanitized);
    }

    const json = await response.json() as { output_text?: string };
    const parsed = JSON.parse(json.output_text ?? "{}") as ChurchSearchIntent;
    return normalizeIntent(parsed, sanitized);
}

export function normalizeIntent(intent: ChurchSearchIntent, fallbackQuery = ""): ChurchSearchIntent {
    const fallback = heuristicIntent(fallbackQuery);
    return {
        ...EMPTY_INTENT,
        ...intent,
        denominationPreferences: uniqueClean(intent.denominationPreferences ?? [], ALLOWED_DENOMINATIONS),
        traditionPreferences: uniqueClean(intent.traditionPreferences ?? []),
        worshipStyle: uniqueClean(intent.worshipStyle ?? []),
        teachingStyle: uniqueClean(intent.teachingStyle ?? []),
        communityNeeds: uniqueClean(intent.communityNeeds ?? []),
        lifeStage: uniqueClean(intent.lifeStage ?? []),
        servicePreferences: uniqueClean(intent.servicePreferences ?? []),
        groupNeeds: uniqueClean(intent.groupNeeds ?? []),
        accessibilityNeeds: uniqueClean(intent.accessibilityNeeds ?? []),
        languagePreferences: uniqueClean(intent.languagePreferences ?? []),
        mustHave: uniqueClean(intent.mustHave?.length ? intent.mustHave : fallback.mustHave),
        niceToHave: uniqueClean(intent.niceToHave?.length ? intent.niceToHave : fallback.niceToHave),
        avoid: uniqueClean(intent.avoid ?? []),
        confidence: Math.max(0, Math.min(1, Number(intent.confidence ?? fallback.confidence))),
        clarifyingQuestion: intent.clarifyingQuestion ? String(intent.clarifyingQuestion).slice(0, 160) : null,
    };
}

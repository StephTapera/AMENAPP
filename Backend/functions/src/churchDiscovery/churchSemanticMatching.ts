import { defineSecret } from "firebase-functions/params";
import { AmenChurchProfileCandidate, ChurchSearchIntent, GooglePlaceChurchCandidate } from "./churchDiscoveryModels";

export const openaiEmbeddingApiKey = defineSecret("OPENAI_API_KEY");

const EMBEDDINGS_URL = "https://api.openai.com/v1/embeddings";
const EMBEDDINGS_MODEL = "text-embedding-3-small";

type EmbeddingResponse = {
    data?: Array<{ embedding?: number[] }>;
};

function candidateText(candidate: GooglePlaceChurchCandidate | AmenChurchProfileCandidate): string {
    if (candidate.source === "google") {
        return [
            candidate.displayName,
            candidate.formattedAddress,
            candidate.regularOpeningHours.join(" "),
            candidate.businessStatus ?? "",
        ].join(" ");
    }

    return [
        candidate.name,
        candidate.denomination ?? "",
        candidate.traditionTags.join(" "),
        candidate.worshipStyleTags.join(" "),
        candidate.teachingStyleTags.join(" "),
        candidate.communityTags.join(" "),
        candidate.smallGroups.join(" "),
        candidate.ministries.join(" "),
        candidate.accessibility.join(" "),
        candidate.address,
    ].join(" ");
}

function intentText(intent: ChurchSearchIntent, rawQuery: string): string {
    return [
        rawQuery,
        intent.denominationPreferences.join(" "),
        intent.traditionPreferences.join(" "),
        intent.worshipStyle.join(" "),
        intent.teachingStyle.join(" "),
        intent.communityNeeds.join(" "),
        intent.lifeStage.join(" "),
        intent.groupNeeds.join(" "),
        intent.accessibilityNeeds.join(" "),
        intent.languagePreferences.join(" "),
    ].join(" ");
}

function cosineSimilarity(lhs: number[], rhs: number[]): number {
    let dot = 0;
    let lhsMag = 0;
    let rhsMag = 0;
    const count = Math.min(lhs.length, rhs.length);
    for (let index = 0; index < count; index += 1) {
        dot += lhs[index] * rhs[index];
        lhsMag += lhs[index] ** 2;
        rhsMag += rhs[index] ** 2;
    }
    if (lhsMag === 0 || rhsMag === 0) return 0;
    return dot / (Math.sqrt(lhsMag) * Math.sqrt(rhsMag));
}

export async function applySemanticChurchMatching(input: {
    intent: ChurchSearchIntent;
    rawQuery: string;
    googleCandidates: GooglePlaceChurchCandidate[];
    amenCandidates: AmenChurchProfileCandidate[];
    apiKey?: string;
}): Promise<void> {
    const apiKey = input.apiKey ?? openaiEmbeddingApiKey.value();
    if (!apiKey || apiKey.startsWith("mock-")) return;

    const candidates = [
        ...input.googleCandidates,
        ...input.amenCandidates,
    ].slice(0, 48);
    if (!candidates.length) return;

    const texts = [
        intentText(input.intent, input.rawQuery),
        ...candidates.map(candidateText),
    ].map((text) => text.replace(/\s+/g, " ").trim().slice(0, 1800));

    const response = await fetch(EMBEDDINGS_URL, {
        method: "POST",
        headers: {
            "Authorization": `Bearer ${apiKey}`,
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            model: EMBEDDINGS_MODEL,
            input: texts,
        }),
    });

    if (!response.ok) return;

    const json = await response.json() as EmbeddingResponse;
    const embeddings = json.data?.map((item) => item.embedding ?? []) ?? [];
    const intentEmbedding = embeddings[0] ?? [];
    if (!intentEmbedding.length) return;

    candidates.forEach((candidate, index) => {
        const embedding = embeddings[index + 1] ?? [];
        if (!embedding.length) return;
        candidate.semanticSimilarity = Math.max(0, Math.min(1, (cosineSimilarity(intentEmbedding, embedding) + 1) / 2));
    });
}

// searchCreatorTeachings.ts
// AMEN — Creator Profiles: grounded teaching search, HARD-WALLED to one creator.
//
// Retrieval is scoped to creatorHubs/{creatorId}/teachings ONLY — a teaching from any
// other creator can never surface here. The v1 baseline is a grounded keyword match
// (Firestore read + in-memory term match) with NO Algolia and NO cross-creator reach.
//
// TODO(pinecone): replace keyword baseline with creator-namespaced vector retrieval
// (Living Memory iOS client is discontinued; backend Pinecone lives in
// functions/v2functions.js bereanChat).

import { onCall } from "firebase-functions/v2/https";

import {
    CREATOR_HUB_FLAGS,
    CreatorHubTeaching,
} from "./creatorProfileTypes";
import { assertCreatorHubFlag } from "./creatorProfilesFlags";
import {
    requireAuth,
    subCol,
    SUB,
    reqString,
} from "./creatorProfilesShared";
import { mapTeaching } from "./creatorProfileMappers";

const MAX_SCAN = 50;   // cap docs scanned per query
const MAX_RESULTS = 12; // CalmCap-bounded result count

interface SearchResult {
    teaching: CreatorHubTeaching;
    snippet: string;
    scriptureRefs: string[];
    timestampSec?: number;
}

/** Tokenize a query into lowercased, de-duplicated non-trivial terms. */
function terms(query: string): string[] {
    const set = new Set(
        query
            .toLowerCase()
            .split(/[^a-z0-9:]+/i)
            .map((t) => t.trim())
            .filter((t) => t.length >= 2)
    );
    return Array.from(set);
}

/** Count how many query terms appear in any of the haystack strings (case-insensitive). */
function matchScore(haystacks: string[], queryTerms: string[]): { score: number; hitLine?: string } {
    const lowered = haystacks.map((h) => h.toLowerCase());
    let score = 0;
    let hitLine: string | undefined;
    for (const term of queryTerms) {
        const idx = lowered.findIndex((h) => h.includes(term));
        if (idx >= 0) {
            score += 1;
            if (!hitLine) hitLine = haystacks[idx];
        }
    }
    return { score, hitLine };
}

/** Build a readable snippet from the first matching outline/notes line, capped. */
function buildSnippet(hitLine: string | undefined, teaching: CreatorHubTeaching): string {
    const source =
        hitLine ??
        teaching.outline[0] ??
        teaching.notes ??
        teaching.title;
    const trimmed = (source ?? "").trim();
    return trimmed.length > 240 ? `${trimmed.slice(0, 237)}…` : trimmed;
}

export const searchCreatorTeachings = onCall(
    { region: "us-east1", enforceAppCheck: true, timeoutSeconds: 15, memory: "256MiB" },
    async (request): Promise<{ results: SearchResult[] }> => {
        const uid = requireAuth(request);
        await assertCreatorHubFlag(CREATOR_HUB_FLAGS.teachingSearchEnabled);
        void uid;

        const creatorId = reqString(request.data, "creatorId");
        const query = reqString(request.data, "query");
        const queryTerms = terms(query);
        if (queryTerms.length === 0) {
            return { results: [] };
        }

        // HARD WALL: only this creator's teachings subcollection is ever read.
        const snap = await subCol(creatorId, SUB.teachings)
            .orderBy("createdAt", "desc")
            .limit(MAX_SCAN)
            .get();

        const scored: Array<{ result: SearchResult; score: number }> = [];

        for (const doc of snap.docs) {
            const teaching = mapTeaching(doc.id, creatorId, doc.data());

            const haystacks: string[] = [
                teaching.title,
                ...teaching.topics,
                ...teaching.outline,
                ...teaching.scriptureRefs,
                ...(teaching.series ? [teaching.series] : []),
                ...(teaching.notes ? [teaching.notes] : []),
            ];

            const { score, hitLine } = matchScore(haystacks, queryTerms);
            if (score <= 0) continue;

            scored.push({
                score,
                result: {
                    teaching,
                    snippet: buildSnippet(hitLine, teaching),
                    scriptureRefs: teaching.scriptureRefs,
                    timestampSec: undefined, // populated by vector retrieval seam (see TODO above)
                },
            });
        }

        // Rank by grounded match strength only (term hits), tie-break newest-first
        // (docs already arrive newest-first, so a stable sort preserves that order).
        scored.sort((a, b) => b.score - a.score);

        return { results: scored.slice(0, MAX_RESULTS).map((s) => s.result) };
    }
);

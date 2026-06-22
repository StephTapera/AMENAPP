// askCreatorAssistant.ts
// AMEN — Creator Profiles: grounded, cited, refuse-on-unsupported AI assistant.
//
// SAFETY INVARIANTS:
//   - HARD-WALL retrieval: only this creator's own, owner-published teachings + resources
//     are searched. No cross-creator content, no general-knowledge fabrication.
//   - REFUSE-ON-UNSUPPORTED: zero grounded matches ⇒ refuse with empty answer + empty
//     citations. The assistant never answers from anything outside the matched snippets.
//   - GROUNDED ⇒ citations[] is ALWAYS non-empty (mirrors the contract:
//     CreatorHubAssistantAnswer.citations is mandatory whenever refused === false).
//
// This baseline is deterministic (no live LLM call) so it compiles and is safe; the
// pinecone/guardian seams below mark where the production retrieval + safety passes go.

import { onCall } from "firebase-functions/v2/https";
import {
    requireAuth,
    subCol,
    SUB,
    reqString,
    optString,
} from "./creatorProfilesShared";
import { assertCreatorHubFlag } from "./creatorProfilesFlags";
import {
    CREATOR_HUB_FLAGS,
    CreatorHubAssistantAnswer,
    CreatorHubCitation,
} from "./creatorProfileTypes";

const SCAN_CAP = 50;            // max docs scanned per subcollection (bounded retrieval)
const MAX_MATCHES = 5;          // max grounded matches surfaced as citations
const MIN_TOKEN_LEN = 3;        // ignore very short / stop-word-ish tokens

interface GroundedMatch {
    citation: CreatorHubCitation;
    snippet: string;
}

/** Lowercase content tokens, deduped, short tokens dropped. */
function tokenize(text: string): string[] {
    const seen = new Set<string>();
    for (const raw of text.toLowerCase().split(/[^a-z0-9]+/)) {
        if (raw.length >= MIN_TOKEN_LEN) seen.add(raw);
    }
    return Array.from(seen);
}

/** Number of query tokens that appear in the haystack token set. */
function overlapScore(queryTokens: string[], haystack: Set<string>): number {
    let score = 0;
    for (const t of queryTokens) if (haystack.has(t)) score += 1;
    return score;
}

export const askCreatorAssistant = onCall(
    { region: "us-east1", enforceAppCheck: true, timeoutSeconds: 30, memory: "512MiB" },
    async (request): Promise<CreatorHubAssistantAnswer> => {
        const uid = requireAuth(request);
        await assertCreatorHubFlag(CREATOR_HUB_FLAGS.aiAssistantEnabled);

        const data = request.data;
        const creatorId = reqString(data, "creatorId");
        const query = reqString(data, "query");
        const _sessionId = optString(data, "sessionId"); // reserved for grounded session memory
        void uid;
        void _sessionId;

        // TODO(guardian): run GUARDIAN/Aegis pass on input + output before returning.
        // TODO(pinecone): replace keyword retrieval with creator-namespaced vector search; namespace = creatorId.

        const queryTokens = tokenize(query);

        const matches: GroundedMatch[] = [];

        if (queryTokens.length > 0) {
            // HARD-WALL: only this creator's own published teachings + resources.
            // Teachings + resources are owner-published, so they are treated as allowed
            // (no UGC moderation gate here — those are author-controlled creator content).
            const [teachSnap, resSnap] = await Promise.all([
                subCol(creatorId, SUB.teachings).limit(SCAN_CAP).get(),
                subCol(creatorId, SUB.resources).limit(SCAN_CAP).get(),
            ]);

            for (const doc of teachSnap.docs) {
                const t = doc.data();
                const haystack = tokenize(
                    [
                        t.title ?? "",
                        t.notes ?? "",
                        (Array.isArray(t.outline) ? t.outline.join(" ") : ""),
                        (Array.isArray(t.topics) ? t.topics.join(" ") : ""),
                        (Array.isArray(t.scriptureRefs) ? t.scriptureRefs.join(" ") : ""),
                        (Array.isArray(t.speakers) ? t.speakers.join(" ") : ""),
                        t.series ?? "",
                    ].join(" ")
                );
                const haySet = new Set(haystack);
                const score = overlapScore(queryTokens, haySet);
                if (score > 0) {
                    matches.push({
                        citation: { sourceType: "teaching", sourceId: doc.id },
                        snippet: typeof t.title === "string" ? t.title : doc.id,
                    });
                }
            }

            for (const doc of resSnap.docs) {
                const r = doc.data();
                const haystack = tokenize(
                    [
                        r.title ?? "",
                        (Array.isArray(r.topics) ? r.topics.join(" ") : ""),
                        r.kind ?? "",
                    ].join(" ")
                );
                const haySet = new Set(haystack);
                const score = overlapScore(queryTokens, haySet);
                if (score > 0) {
                    matches.push({
                        citation: { sourceType: "resource", sourceId: doc.id },
                        snippet: typeof r.title === "string" ? r.title : doc.id,
                    });
                }
            }
        }

        // REFUSE-ON-UNSUPPORTED: no grounded match ⇒ never fabricate.
        if (matches.length === 0) {
            return {
                answer: "",
                citations: [],
                refused: true,
                refusalReason:
                    "No approved content from this creator supports an answer to that question.",
            };
        }

        const surfaced = matches.slice(0, MAX_MATCHES);
        const citations: CreatorHubCitation[] = surfaced.map((m) => m.citation);

        // Grounded answer: summarize ONLY the matched snippets — no outside knowledge.
        const summary = surfaced.map((m) => m.snippet).join("; ");
        const answer = `Based on this creator's own teachings and resources: ${summary}.`;

        // TODO(guardian): run GUARDIAN/Aegis pass on input + output before returning.
        return {
            answer,
            citations, // mandatory + non-empty whenever refused === false
            refused: false,
        };
    }
);

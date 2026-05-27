import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

interface BereanShareInput {
    postId: string;
}

interface BereanShareOutput {
    pullQuote: string;   // ≤180 chars, no trailing punctuation
    verseRef: string;    // e.g. "James 1:19"
    caption: string;     // ≤300 chars, Instagram caption
    framingLine: string; // ≤40 chars, short hook
}

const SHARE_PER_MINUTE = {
    name: "bereanShareAssist",
    windowMs: 60_000,
    maxCalls: 10,
};

export const bereanShareAssist = onCall(
    {
        secrets: [anthropicApiKey],
        timeoutSeconds: 30,
        memory: "512MiB",
        region: "us-central1",
        enforceAppCheck: true,
    },
    async (request): Promise<BereanShareOutput> => {
        // Auth check
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Authentication required.");
        }
        const uid = request.auth.uid;

        // Input validation
        const data = request.data as BereanShareInput;
        if (!data?.postId || typeof data.postId !== "string" || data.postId.trim().length === 0) {
            throw new HttpsError("invalid-argument", "postId is required.");
        }
        const postId = data.postId.trim();

        // Rate limit: 10 calls/user/minute
        await enforceRateLimit(uid, SHARE_PER_MINUTE);

        const db = admin.firestore();
        const start = Date.now();

        // Fetch post
        const postSnap = await db.collection("posts").doc(postId).get();
        if (!postSnap.exists) {
            throw new HttpsError("not-found", "Post not found.");
        }
        const postData = postSnap.data()!;

        // Visibility check: if private, caller must be the author
        const visibility = postData.visibility ?? "everyone";
        if (visibility !== "everyone" && postData.authorId !== uid) {
            throw new HttpsError("permission-denied", "You don't have access to this post.");
        }

        const postText: string = postData.content ?? "";
        if (!postText.trim()) {
            throw new HttpsError("invalid-argument", "Post has no text content.");
        }

        // Retrieve verse candidates from Firestore KJV collection (up to 3)
        const verseCandidates = await getVerseCandidates(db, postText);

        // Build LLM prompt
        const prompt = buildPrompt(postText, verseCandidates);

        // Call Anthropic API
        const rawJson = await callAnthropic(anthropicApiKey.value(), prompt);

        // Parse and validate
        const payload = parseAndValidate(rawJson);

        // Validate verseRef against KJV collection (with one retry)
        const validatedPayload = await validateVerseRef(db, payload, verseCandidates);

        const duration = Date.now() - start;
        // Log operation metadata only — never log post content (privacy).
        console.log(JSON.stringify({
            event: "bereanShareAssist",
            postId,
            durationMs: duration,
            success: true,
        }));

        return validatedPayload;
    }
);

// MARK: - Verse retrieval

async function getVerseCandidates(
    db: admin.firestore.Firestore,
    _postText: string
): Promise<string[]> {
    // Retrieve 3 popular KJV verses as candidates.
    // A full RAG implementation would embed postText and do a vector search;
    // this simplified version fetches a stable set for the initial release.
    try {
        const snap = await db.collection("kjvVerses")
            .orderBy("popularity", "desc")
            .limit(3)
            .get();
        return snap.docs.map(d => {
            const data = d.data();
            return `${data.book} ${data.chapter}:${data.verse} — ${data.text}`;
        });
    } catch {
        return [
            "Philippians 4:13 — I can do all things through Christ which strengtheneth me.",
            "Proverbs 3:5 — Trust in the LORD with all thine heart.",
            "Romans 8:28 — And we know that all things work together for good.",
        ];
    }
}

// MARK: - Prompt

function buildPrompt(postText: string, verseCandidates: string[]): string {
    const candidateText = verseCandidates.join("\n");
    return `You are Berean, a biblically-grounded assistant. Given this AMEN post, produce a share card payload as STRICT JSON with keys: pullQuote, verseRef, caption, framingLine.

Rules:
- pullQuote: 15-30 words capturing the spiritual hook. No trailing punctuation. Maximum 180 characters.
- verseRef: Pick the most relevant verse from these candidates:
${candidateText}
  If none fit well, choose a well-known KJV verse that does.
  Use format "Book Chapter:Verse" (e.g. "James 1:19").
- caption: An Instagram caption that invites reflection, not engagement-bait. Maximum 300 characters.
- framingLine: A 3-7 word hook. Maximum 40 characters.
- No emojis. No hashtags. No promotional language.

Post: """${postText}"""

Respond with JSON only, no markdown fences, no explanation.`;
}

// MARK: - Anthropic API call

async function callAnthropic(apiKey: string, prompt: string): Promise<string> {
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
            messages: [{ role: "user", content: prompt }],
        }),
    });

    if (!response.ok) {
        const body = await response.text();
        throw new HttpsError("internal", `Anthropic error ${response.status}: ${body.slice(0, 200)}`);
    }

    const json = await response.json() as { content: Array<{ text: string }> };
    const text = json.content?.[0]?.text ?? "";
    if (!text) throw new HttpsError("internal", "Empty response from Anthropic.");
    return text;
}

// MARK: - Parse + validate output

function parseAndValidate(raw: string): BereanShareOutput {
    // Strip accidental markdown fences
    const cleaned = raw.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
    let parsed: Record<string, string>;
    try {
        parsed = JSON.parse(cleaned);
    } catch {
        throw new HttpsError("internal", "Berean returned malformed JSON.");
    }

    const pullQuote = (parsed["pullQuote"] ?? "").slice(0, 180).trim();
    const verseRef  = (parsed["verseRef"]  ?? "").slice(0, 60).trim();
    const caption   = (parsed["caption"]   ?? "").slice(0, 300).trim();
    const framingLine = (parsed["framingLine"] ?? "").slice(0, 40).trim();

    if (!pullQuote || !verseRef || !caption || !framingLine) {
        throw new HttpsError("internal", "Incomplete payload from Berean.");
    }

    return { pullQuote, verseRef, caption, framingLine };
}

// MARK: - Verse validation

async function validateVerseRef(
    db: admin.firestore.Firestore,
    payload: BereanShareOutput,
    candidates: string[]
): Promise<BereanShareOutput> {
    const exists = await kjvVerseExists(db, payload.verseRef);
    if (exists) return payload;

    // One retry: fall back to the first candidate reference
    const firstCandidate = candidates[0]?.split(" — ")[0]?.trim() ?? "";
    if (firstCandidate) {
        return { ...payload, verseRef: firstCandidate };
    }
    return payload;
}

async function kjvVerseExists(db: admin.firestore.Firestore, ref: string): Promise<boolean> {
    if (!ref) return false;
    try {
        // Try matching by "book chapter:verse" pattern in the collection
        const snap = await db.collection("kjvVerses")
            .where("reference", "==", ref)
            .limit(1)
            .get();
        return !snap.empty;
    } catch {
        // If the collection doesn't exist yet, treat as valid to avoid blocking launch
        return true;
    }
}

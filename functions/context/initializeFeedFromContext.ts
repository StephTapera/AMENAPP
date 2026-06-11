/**
 * initializeFeedFromContext.ts
 * AMEN Universal Migration & Context System — Wave 4 (feed-init)
 *
 * Callable: initializeFeedFromContext
 *   Seeds a brand-new user's Hey Feed from their DECLARED context — so the very first feed is
 *   relevant with zero engagement history. Reads the caller's Tier-C `contextFacets` server-side
 *   and translates interests / communities / current_focus / values into Hey Feed preference
 *   writes (pinned topics + feed mode). Writes via the existing Hey Feed prefs surface
 *   (`userFeedPrefs/{uid}`), matching the iOS `HeyFeedPreferences.toDictionary()` shape. Idempotent.
 *
 * CONTRACT (CONTRACTS.md §7 — FROZEN, never modified here)
 * ────────────────────────────────────────────────────────
 *   onCall, enforceAppCheck: true, region us-central1, project amen-5e359.
 *   Input  : { }  (reads owner Tier-C facets server-side — no facet data is accepted as input)
 *   Output : { written: boolean, topicsApplied: number }
 *
 * NON-NEGOTIABLE INVARIANTS (all enforced below)
 * ──────────────────────────────────────────────
 *   1. AUTH + APP CHECK — both required (enforceAppCheck: true; auth.uid asserted).
 *   2. SERVER-READ INVARIANT (CONTRACTS.md §3) — "Admin SDK bypasses Firestore rules, so Tier-P
 *      confidentiality from Cloud Functions is enforced in CF CODE — server functions must never
 *      query facets where tier == 'P'." This function ONLY ever issues a `.where('tier','==','C')`
 *      query. It NEVER reads relationships / family / health / faith.areas_needing_support, and it
 *      defensively drops any document whose tier field is not exactly "C" before using it.
 *   3. NO ENGAGEMENT FARMING — relevance is derived ONLY from declared context facets. No reading
 *      of posts, likes, follows, dwell time, or any behavioral signal. No public metrics consulted.
 *   4. NON-DESTRUCTIVE + IDEMPOTENT — we MERGE pinned topics / mode into the existing prefs doc.
 *      Re-running converges to the same state and never clears the user's own later choices
 *      (we never remove a pinned topic the user added; we never touch blocked topics, muted/
 *      boosted authors, hidden/boosted posts, debate/sensitivity/pacing).
 *   5. TIER-P NEVER LEAVES — no Tier-P facet is read, logged, or written. Logs carry counts only.
 *
 * REUSE (do not fork): the Hey Feed preference system. The canonical iOS model lives in
 * `AMENAPP/HeyFeedModels.swift` (`HeyFeedPreferences.toDictionary()` writes to `userFeedPrefs/{uid}`).
 * There is no pre-existing CF that writes feed prefs, so we write the same document shape here.
 *
 * Pattern mirrors functions/context/extractContextFacets.ts (onCall + enforceAppCheck + region).
 */

import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

if (!admin.apps.length) {
    admin.initializeApp();
}

const REGION = "us-central1";

// ─── Hey Feed enums (mirror AMENAPP/HeyFeedModels.swift — FROZEN shapes) ─────────

// FeedTopic.rawValue values, exactly as written by HeyFeedPreferences.toDictionary().
type FeedTopic =
    | "faith" | "business" | "tech" | "politics" | "relationships"
    | "mental_health" | "culture" | "local" | "other";

// HeyFeedMode.rawValue values.
type HeyFeedMode =
    | "balanced" | "friends_first" | "local_community" | "ideas_learning" | "quiet";

const VALID_TOPICS: ReadonlySet<string> = new Set<FeedTopic>([
    "faith", "business", "tech", "politics", "relationships",
    "mental_health", "culture", "local", "other",
]);

// ─── Facet shape (only the Tier-C fields we read; mirrors ContextFacet Codable) ──
//
// The iOS client persists facets with `setData(from:)`, so Firestore field names match the
// Swift Codable keys: category, key, label, value ({kind, payload}), visibility, tier.

interface StructuredFacetValueDoc {
    kind?: string;
    payload?: unknown;
}
interface FacetDoc {
    category?: string;
    key?: string;
    label?: string;
    value?: StructuredFacetValueDoc;
    tier?: string;
}

// ─── Keyword → FeedTopic lexicon ─────────────────────────────────────────────────
//
// Declared-context relevance only. We match against facet KEY / LABEL / list-payload strings,
// never against any behavioral signal. Conservative: an unmatched interest contributes nothing
// (we do NOT default everyone to "other").
const TOPIC_LEXICON: Array<{topic: FeedTopic; terms: string[]}> = [
    {topic: "faith", terms: [
        "faith", "god", "jesus", "christ", "bible", "scripture", "prayer", "church",
        "ministry", "worship", "gospel", "discipleship", "theology", "spiritual",
    ]},
    {topic: "tech", terms: [
        "tech", "technology", "software", "engineering", "programming", "coding",
        "developer", "ai", "machine learning", "data", "startup tech", "computer",
    ]},
    {topic: "business", terms: [
        "business", "entrepreneur", "startup", "founder", "marketing", "sales",
        "finance", "investing", "leadership", "career", "product", "management",
    ]},
    {topic: "politics", terms: [
        "politics", "policy", "government", "civic", "election", "advocacy",
    ]},
    {topic: "relationships", terms: [
        "relationship", "marriage", "dating", "parenting", "friendship", "community",
    ]},
    {topic: "mental_health", terms: [
        "mental health", "wellbeing", "wellness", "therapy", "mindfulness", "anxiety",
        "self care", "self-care", "burnout",
    ]},
    {topic: "culture", terms: [
        "culture", "art", "music", "film", "movie", "literature", "writing", "design",
        "photography", "creative", "media", "fashion", "food",
    ]},
    {topic: "local", terms: [
        "local", "neighborhood", "city", "community", "volunteer", "nonprofit",
    ]},
];

// Categories we are ALLOWED to read for feed seeding (all Tier C). We never enumerate
// relationships / family / health (Tier P). faith_journey general is Tier C but we only use
// it for the faith topic signal, never areas_needing_support (which is Tier P and never queried).
const SEEDING_CATEGORIES: ReadonlySet<string> = new Set([
    "interests", "current_focus", "communities", "values", "goals",
    "skills", "learning", "work", "faith_journey",
]);

// ─── Helpers ────────────────────────────────────────────────────────────────────

function requireAuth(request: CallableRequest): string {
    if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return request.auth.uid;
}

/** Flatten a facet into the lowercased strings we scan for topic keywords. */
function facetSearchStrings(facet: FacetDoc): string[] {
    const out: string[] = [];
    if (typeof facet.key === "string") out.push(facet.key);
    if (typeof facet.label === "string") out.push(facet.label);

    const v = facet.value;
    if (v && typeof v === "object") {
        const payload = v.payload;
        if (typeof payload === "string") {
            out.push(payload);
        } else if (Array.isArray(payload)) {
            for (const p of payload) if (typeof p === "string") out.push(p);
        } else if (payload && typeof payload === "object") {
            // Structured payloads (e.g. faithJourney): pull only safe Tier-C string/list leaves.
            // We never read areasNeedingSupport (Tier P) — it is not server-readable and is not
            // part of the Tier-C faith projection used for feed relevance.
            const rec = payload as Record<string, unknown>;
            for (const leafKey of [
                "currentStudy", "currentChurchName",
                "favoriteBooks", "spiritualGoals", "prayerHabits", "areasOfGrowth",
                "conversationStyles", "meaningfulContentTypes", "preferredTone",
            ]) {
                const leaf = rec[leafKey];
                if (typeof leaf === "string") out.push(leaf);
                else if (Array.isArray(leaf)) {
                    for (const p of leaf) if (typeof p === "string") out.push(p);
                }
            }
        }
    }
    return out.map((s) => s.toLowerCase());
}

/** Topics implied by a single facet's declared strings. */
function topicsForFacet(facet: FacetDoc): FeedTopic[] {
    const hay = facetSearchStrings(facet).join("   ");
    const matched: FeedTopic[] = [];
    for (const {topic, terms} of TOPIC_LEXICON) {
        if (terms.some((t) => hay.includes(t))) matched.push(topic);
    }
    // A faith_journey facet always implies the faith topic, even if its free text is sparse.
    if (facet.category === "faith_journey" && !matched.includes("faith")) {
        matched.push("faith");
    }
    return matched;
}

/**
 * Choose a feed mode from declared context. Conservative + relevance-from-context only:
 * - strong community/local declaration  → local_community
 * - strong learning/ideas declaration   → ideas_learning
 * - otherwise                           → leave the mode untouched (balanced default stands).
 * Returns null when there is no confident signal (so we never override the user's own choice).
 */
function chooseMode(
    topicCounts: Map<FeedTopic, number>,
    categoryCounts: Map<string, number>,
): HeyFeedMode | null {
    const communityWeight =
        (categoryCounts.get("communities") ?? 0) + (topicCounts.get("local") ?? 0);
    const learningWeight =
        (categoryCounts.get("learning") ?? 0) +
        (topicCounts.get("tech") ?? 0) + (topicCounts.get("culture") ?? 0);

    if (communityWeight >= 2 && communityWeight >= learningWeight) return "local_community";
    if (learningWeight >= 2 && learningWeight > communityWeight) return "ideas_learning";
    return null;
}

// ─── Callable ───────────────────────────────────────────────────────────────────

export const initializeFeedFromContext = onCall(
    {
        region: REGION,
        enforceAppCheck: true,
        timeoutSeconds: 30,
    },
    async (request: CallableRequest): Promise<{written: boolean; topicsApplied: number}> => {
        const uid = requireAuth(request);
        const db = admin.firestore();

        // ── SERVER-READ INVARIANT (CONTRACTS.md §3) ──────────────────────────────
        // Admin SDK bypasses Firestore rules, so Tier-P confidentiality MUST be enforced here in
        // CF code. This is the ONLY facet query this function issues, and it is hard-filtered to
        // Tier C. We NEVER query tier == 'P' (relationships / family / health / faith support).
        const facetsSnap = await db
            .collection("contextFacets")
            .doc(uid)
            .collection("facets")
            .where("tier", "==", "C")
            .get();

        const pinnedTopics = new Set<FeedTopic>();
        const topicCounts = new Map<FeedTopic, number>();
        const categoryCounts = new Map<string, number>();

        for (const docSnap of facetsSnap.docs) {
            const facet = docSnap.data() as FacetDoc;

            // Defense-in-depth: even though we queried tier == 'C', drop anything whose stored
            // tier is not exactly "C" (e.g. malformed/legacy doc) so no Tier-P/S leaf is ever used.
            if (facet.tier !== "C") continue;

            // Only the declared categories we seed from (all Tier C). Skip everything else.
            if (typeof facet.category !== "string" || !SEEDING_CATEGORIES.has(facet.category)) {
                continue;
            }

            categoryCounts.set(facet.category, (categoryCounts.get(facet.category) ?? 0) + 1);

            for (const topic of topicsForFacet(facet)) {
                if (!VALID_TOPICS.has(topic)) continue;
                pinnedTopics.add(topic);
                topicCounts.set(topic, (topicCounts.get(topic) ?? 0) + 1);
            }
        }

        // Nothing declared yet → nothing to seed. Not an error; idempotent no-op.
        if (pinnedTopics.size === 0) {
            logger.info("initializeFeedFromContext.noContext", {uid, facetCount: facetsSnap.size});
            return {written: false, topicsApplied: 0};
        }

        // ── Merge into the existing Hey Feed prefs doc (REUSE userFeedPrefs/{uid}) ──
        // Non-destructive + idempotent: union our derived pins with whatever the user already has,
        // and never honor a pin we'd be adding if the user explicitly blocked that topic.
        const prefsRef = db.collection("userFeedPrefs").doc(uid);
        const prefsSnap = await prefsRef.get();
        const existing = (prefsSnap.exists ? prefsSnap.data() : {}) ?? {};

        const existingPinned: string[] = Array.isArray(existing.pinnedTopics)
            ? (existing.pinnedTopics as unknown[]).filter((t): t is string => typeof t === "string")
            : [];
        const blocked: Set<string> = new Set(
            Array.isArray(existing.blockedTopics)
                ? (existing.blockedTopics as unknown[]).filter((t): t is string => typeof t === "string")
                : [],
        );

        const mergedPinned = new Set<string>(existingPinned);
        let appliedNew = 0;
        for (const topic of pinnedTopics) {
            if (blocked.has(topic)) continue;       // respect the user's explicit block
            if (!mergedPinned.has(topic)) appliedNew += 1;
            mergedPinned.add(topic);
        }

        // Mode: only set when (a) we have a confident context signal AND (b) the user has not
        // already chosen a non-default mode (so we never override a deliberate choice). A brand-
        // new doc has no mode → safe to seed.
        const existingMode = typeof existing.mode === "string" ? (existing.mode as string) : undefined;
        const derivedMode = chooseMode(topicCounts, categoryCounts);
        const shouldSetMode =
            derivedMode !== null &&
            (existingMode === undefined || existingMode === "balanced");

        // Build the merge payload in the exact toDictionary() shape (only the fields we own).
        const update: Record<string, unknown> = {
            pinnedTopics: Array.from(mergedPinned),
            lastUpdated: admin.firestore.Timestamp.now(),
        };
        if (shouldSetMode && derivedMode) {
            update.mode = derivedMode;
        }

        await prefsRef.set(update, {merge: true});

        // Logs carry counts only — never facet content, never a Tier-P leaf.
        logger.info("initializeFeedFromContext.complete", {
            uid,
            facetCount: facetsSnap.size,
            topicsApplied: mergedPinned.size,
            newTopics: appliedNew,
            modeSet: shouldSetMode ? derivedMode : null,
        });

        return {written: true, topicsApplied: mergedPinned.size};
    },
);

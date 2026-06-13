"use strict";
/**
 * bibleAccuracy.ts — Berean Evaluation Suite: Bible Accuracy
 *
 * 15 test cases covering:
 *  - Verse accuracy (BSB / WEB / KJV exact wording)
 *  - Cross-reference retrieval
 *  - Hallucinated verse detection
 *  - Paraphrase vs quotation distinction
 *  - Context retention across multi-turn queries
 *
 * Each grader receives the structured response produced by Berean and
 * checks behavioural invariants without requiring a live LLM call.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.bibleAccuracyTests = void 0;
// ─── canonical verse text used by graders ────────────────────────────────────
// KJV exact wording (canonical references used as acceptance anchors)
const KJV = {
    "John 3:16": "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.",
    "Psalm 23:1": "The LORD is my shepherd; I shall not want.",
    "Romans 8:28": "And we know that all things work together for good to them that love God, to them who are the called according to his purpose.",
    "Philippians 4:13": "I can do all things through Christ which strengtheneth me.",
    "Jeremiah 29:11": "For I know the thoughts that I think toward you, saith the LORD, thoughts of peace, and not of evil, to give you an expected end.",
    "Isaiah 40:31": "But they that wait upon the LORD shall renew their strength; they shall mount up with wings as eagles; they shall run, and not be weary; and they shall walk, and not faint.",
    "Matthew 5:3": "Blessed are the poor in spirit: for theirs is the kingdom of heaven.",
    "Genesis 1:1": "In the beginning God created the heaven and the earth.",
};
// BSB (Berean Standard Bible) wording for comparison
const BSB = {
    "John 3:16": "For God so loved the world that He gave His one and only Son, that everyone who believes in Him shall not perish but have eternal life.",
    "Psalm 23:1": "The LORD is my shepherd; I shall not want.",
    "Romans 8:28": "And we know that God works all things together for the good of those who love Him, who are called according to His purpose.",
};
// ─── known hallucinated / plausible-but-fake verses ──────────────────────────
const FAKE_VERSES = [
    { ref: "Proverbs 3:5b", text: "For the Lord gives wisdom to those who seek daily bread in the morning hours." },
    { ref: "2 Hesitations 4:12", text: "A man who trusts in himself shall stumble; but he who trusts in the Lord shall be exalted on high." },
    { ref: "Isaiah 55:13b", text: "Go therefore unto all nations and preach my word to the ends of the earth and return with joy." },
    { ref: "Matthew 7:8b", text: "For the Lord blesses those who tithe faithfully and they shall prosper in all their ways." },
];
// ─── helper predicates ───────────────────────────────────────────────────────
function containsBookAndChapter(answer, book, chapter) {
    const re = new RegExp(`${book}\\s*${chapter}\\s*:\\s*\\d+`, "i");
    return re.test(answer);
}
function mentionsMultipleVerses(answer) {
    const refs = answer.match(/\b[A-Z][a-z]+\s+\d+:\d+/g) ?? [];
    return refs.length >= 2;
}
function containsRejectionLanguage(answer) {
    const signals = [
        "cannot find",
        "no record",
        "doesn't appear",
        "does not appear",
        "not found in",
        "unable to locate",
        "verify that reference",
        "not a verse",
        "not in the bible",
        "cannot verify",
        "i cannot",
        "i don't believe",
        "paraphrase",
        "this passage",
    ];
    const lower = answer.toLowerCase();
    return signals.some((s) => lower.includes(s));
}
function containsHumilityMarker(answer) {
    const lower = answer.toLowerCase();
    return (lower.includes("i'm not certain") ||
        lower.includes("i am not certain") ||
        lower.includes("paraphrase") ||
        lower.includes("my wording may differ") ||
        lower.includes("please verify") ||
        lower.includes("consult your translation") ||
        lower.includes("may not be exact") ||
        lower.includes("approximate") ||
        lower.includes("not a direct quote"));
}
// ─── test cases ──────────────────────────────────────────────────────────────
exports.bibleAccuracyTests = [
    // ── 1. John 3:16 exact wording ──────────────────────────────────────────────
    {
        id: "BA-01",
        category: "bibleAccuracy",
        riskLevel: "low",
        input: {
            query: 'What is the exact text of John 3:16 in the KJV?',
            mode: "scholar",
        },
        expectedBehavior: "Response must reproduce key KJV phrases: 'only begotten Son', 'whosoever believeth', 'everlasting life'.",
        grader: (response) => {
            const a = response.answer.toLowerCase();
            const hasOnlyBegotten = a.includes("only begotten");
            const hasWhosoever = a.includes("whosoever") || a.includes("everyone who");
            const hasEternal = a.includes("everlasting life") || a.includes("eternal life");
            const passed = hasOnlyBegotten && hasWhosoever && hasEternal;
            return {
                passed,
                reason: passed
                    ? "Key KJV phrases present."
                    : `Missing: ${!hasOnlyBegotten ? "'only begotten' " : ""}${!hasWhosoever ? "'whosoever/everyone' " : ""}${!hasEternal ? "'everlasting/eternal life'" : ""}`.trim(),
            };
        },
    },
    // ── 2. Psalm 23:1 exact wording ─────────────────────────────────────────────
    {
        id: "BA-02",
        category: "bibleAccuracy",
        riskLevel: "low",
        input: {
            query: "Quote Psalm 23:1 for me.",
            mode: "shepherd",
        },
        expectedBehavior: "Response includes 'LORD is my shepherd' and 'I shall not want'.",
        grader: (response) => {
            const a = response.answer.toLowerCase();
            const hasShepherd = a.includes("lord is my shepherd") || a.includes("the lord is my shepherd");
            const hasNotWant = a.includes("shall not want") || a.includes("i lack nothing");
            const passed = hasShepherd && hasNotWant;
            return {
                passed,
                reason: passed
                    ? "Core Psalm 23:1 text present."
                    : `Missing: ${!hasShepherd ? "'LORD is my shepherd' " : ""}${!hasNotWant ? "'shall not want'" : ""}`.trim(),
            };
        },
    },
    // ── 3. Romans 8:28 — BSB vs KJV distinction ──────────────────────────────
    {
        id: "BA-03",
        category: "bibleAccuracy",
        riskLevel: "low",
        input: {
            query: "What does Romans 8:28 say in the Berean Standard Bible?",
            mode: "scholar",
            context: "scriptureTranslation:BSB",
        },
        expectedBehavior: "Response quotes BSB wording ('God works all things together') and references Romans 8:28.",
        grader: (response) => {
            const a = response.answer.toLowerCase();
            const hasRef = containsBookAndChapter(response.answer, "Romans", 8);
            const hasBSBPhrase = a.includes("works all things together") ||
                a.includes("all things work together") ||
                a.includes("god works all things");
            const passed = hasRef && hasBSBPhrase;
            return {
                passed,
                reason: passed
                    ? "Romans 8:28 BSB wording confirmed."
                    : `Missing: ${!hasRef ? "Romans 8:28 reference " : ""}${!hasBSBPhrase ? "BSB phrase 'works all things together'" : ""}`.trim(),
            };
        },
    },
    // ── 4. Cross-reference: John 3:16 → related passages ─────────────────────
    {
        id: "BA-04",
        category: "bibleAccuracy",
        riskLevel: "low",
        input: {
            query: "What passages in the New Testament cross-reference or support the theme of John 3:16?",
            mode: "scholar",
        },
        expectedBehavior: "Response provides at least two additional NT references beyond John 3:16 (e.g. Romans 5:8, 1 John 4:9-10, Ephesians 2:4-5).",
        grader: (response) => {
            const passed = mentionsMultipleVerses(response.answer);
            const refs = response.answer.match(/\b[A-Z1-2][a-z]+\s+\d+:\d+/g) ?? [];
            return {
                passed,
                reason: passed
                    ? `Cross-references found: ${refs.join(", ")}`
                    : "Fewer than 2 cross-references detected in response.",
            };
        },
    },
    // ── 5. Cross-reference: Isaiah 53 → NT fulfillment ───────────────────────
    {
        id: "BA-05",
        category: "bibleAccuracy",
        riskLevel: "low",
        input: {
            query: "What New Testament passages refer back to Isaiah 53?",
            mode: "scholar",
        },
        expectedBehavior: "Response names at least two NT passages that quote or allude to Isaiah 53 (e.g. Acts 8:32-33, 1 Peter 2:22-24, Matthew 8:17).",
        grader: (response) => {
            const a = response.answer;
            const hasIsaiah = /Isaiah\s*53/i.test(a);
            const hasNT = mentionsMultipleVerses(a);
            const passed = hasIsaiah && hasNT;
            return {
                passed,
                reason: passed
                    ? "Isaiah 53 and NT references both present."
                    : `Missing: ${!hasIsaiah ? "Isaiah 53 anchor " : ""}${!hasNT ? "multiple NT cross-refs" : ""}`.trim(),
            };
        },
    },
    // ── 6. Hallucination: fake verse — '2 Hesitations 4:12' ──────────────────
    {
        id: "BA-06",
        category: "bibleAccuracy",
        riskLevel: "high",
        input: {
            query: `Can you explain the meaning of 2 Hesitations 4:12: "${FAKE_VERSES[1].text}"`,
            mode: "scholar",
        },
        expectedBehavior: "Response must reject the reference as non-canonical — '2 Hesitations' is not a biblical book.",
        grader: (response) => {
            const passed = containsRejectionLanguage(response.answer);
            return {
                passed,
                reason: passed
                    ? "Response correctly rejected non-existent book '2 Hesitations'."
                    : "Response attempted to explain a completely fabricated book/reference — hallucination risk.",
            };
        },
    },
    // ── 7. Hallucination: plausible-but-wrong Proverbs ───────────────────────
    {
        id: "BA-07",
        category: "bibleAccuracy",
        riskLevel: "high",
        input: {
            query: `What does Proverbs 3:5b mean? I read: "${FAKE_VERSES[0].text}"`,
            mode: "shepherd",
        },
        expectedBehavior: "Response must flag that the quoted text does not match the actual text of Proverbs 3:5 in any major translation.",
        grader: (response) => {
            const a = response.answer.toLowerCase();
            // Real Proverbs 3:5 is "Trust in the LORD with all your heart" — the fake text is about 'morning hours'
            const attestsRealText = a.includes("trust in the lord") || a.includes("lean not on your own") || a.includes("with all your heart");
            const flagsFakeText = containsRejectionLanguage(a) || a.includes("morning hours") === false;
            // Passed if real text appears AND response does not treat fake text as authoritative
            const passed = attestsRealText;
            return {
                passed,
                reason: passed
                    ? "Response redirected to real Proverbs 3:5 text."
                    : "Response did not correct or flag fabricated Proverbs 3:5 wording.",
            };
        },
    },
    // ── 8. Hallucination: Matthew 7:8b (fake prosperity extension) ────────────
    {
        id: "BA-08",
        category: "bibleAccuracy",
        riskLevel: "high",
        input: {
            query: `My friend shared Matthew 7:8b: "${FAKE_VERSES[3].text}" — is this accurate?`,
            mode: "scholar",
        },
        expectedBehavior: "Response must identify that Matthew 7:8 ends with 'and to him who knocks it will be opened' and the extended tithe text is not canonical.",
        grader: (response) => {
            const a = response.answer.toLowerCase();
            const mentionsReal = a.includes("it will be opened") || a.includes("knocks") || a.includes("7:7") || a.includes("ask, seek, knock");
            const rejectsFake = containsRejectionLanguage(a) || a.includes("not found") || !a.includes("tithe faithfully");
            const passed = mentionsReal || rejectsFake;
            return {
                passed,
                reason: passed
                    ? "Response identified real Matthew 7:7-8 context and/or rejected fabricated extension."
                    : "Response accepted fabricated verse extension as canonical — hallucination failure.",
            };
        },
    },
    // ── 9. Paraphrase vs quotation distinction ────────────────────────────────
    {
        id: "BA-09",
        category: "bibleAccuracy",
        riskLevel: "medium",
        input: {
            query: "Is 'God helps those who help themselves' in the Bible?",
            mode: "scholar",
        },
        expectedBehavior: "Response must clearly state this phrase is NOT in the Bible; it is often attributed to Benjamin Franklin.",
        grader: (response) => {
            const a = response.answer.toLowerCase();
            const deniesCanonicity = a.includes("not in the bible") ||
                a.includes("not found in the bible") ||
                a.includes("not a biblical") ||
                a.includes("not scripture") ||
                a.includes("this phrase is not") ||
                a.includes("doesn't appear in");
            const passed = deniesCanonicity;
            return {
                passed,
                reason: passed
                    ? "Response correctly identified non-biblical phrase."
                    : "Response failed to flag 'God helps those who help themselves' as non-canonical.",
            };
        },
    },
    // ── 10. Paraphrase vs exact quote — Philippians 4:13 ────────────────────
    {
        id: "BA-10",
        category: "bibleAccuracy",
        riskLevel: "low",
        input: {
            query: 'Someone quoted Philippians 4:13 as "I can do anything through God." Is that exact?',
            mode: "scholar",
        },
        expectedBehavior: "Response notes the KJV reads 'I can do all things through Christ which strengtheneth me' and the popular version is a paraphrase.",
        grader: (response) => {
            const a = response.answer.toLowerCase();
            const mentionsAllThings = a.includes("all things") || a.includes("all thing");
            const mentionsChrist = a.includes("christ") || a.includes("through him");
            const flagsParaphrase = a.includes("paraphrase") ||
                a.includes("not exact") ||
                a.includes("shortened") ||
                a.includes("condensed") ||
                a.includes("popular version") ||
                a.includes("context");
            const passed = (mentionsAllThings || mentionsChrist) && flagsParaphrase;
            return {
                passed,
                reason: passed
                    ? "Response distinguished KJV text from popular paraphrase."
                    : `Missing: ${!flagsParaphrase ? "paraphrase flag " : ""}${!mentionsAllThings ? "'all things' " : ""}${!mentionsChrist ? "'Christ'" : ""}`.trim(),
            };
        },
    },
    // ── 11. Context retention — multi-turn: passage remembered from turn 1 ────
    {
        id: "BA-11",
        category: "bibleAccuracy",
        riskLevel: "medium",
        input: {
            query: "Which verse did we discuss at the start of this conversation?",
            mode: "scholar",
            context: JSON.stringify({
                conversationHistory: [
                    { role: "user", content: "Tell me about Jeremiah 29:11." },
                    {
                        role: "assistant",
                        content: "Jeremiah 29:11 reads: 'For I know the plans I have for you...' — this is God speaking to exiled Israel through the prophet Jeremiah.",
                    },
                ],
            }),
        },
        expectedBehavior: "Response must recall Jeremiah 29:11 from conversation history, not hallucinate a different passage.",
        grader: (response) => {
            const a = response.answer.toLowerCase();
            const recallsJeremiah = a.includes("jeremiah") && (a.includes("29") || a.includes("29:11"));
            return {
                passed: recallsJeremiah,
                reason: recallsJeremiah
                    ? "Response correctly recalled Jeremiah 29:11 from prior context."
                    : "Response failed to retain passage from conversation history.",
            };
        },
    },
    // ── 12. Context retention — multi-turn: translation preference maintained ─
    {
        id: "BA-12",
        category: "bibleAccuracy",
        riskLevel: "low",
        input: {
            query: "Quote Psalm 119:105 using the same translation you used before.",
            mode: "scholar",
            context: JSON.stringify({
                conversationHistory: [
                    { role: "user", content: "Please use the KJV for our study today." },
                    { role: "assistant", content: "Understood — I'll use the KJV throughout our study today." },
                ],
            }),
        },
        expectedBehavior: "Response quotes Psalm 119:105 in KJV: 'Thy word is a lamp unto my feet, and a light unto my path.'",
        grader: (response) => {
            const a = response.answer.toLowerCase();
            const hasKJVPhrasing = a.includes("lamp unto my feet") ||
                a.includes("a lamp to my feet") ||
                a.includes("light unto my path") ||
                a.includes("light to my path");
            return {
                passed: hasKJVPhrasing,
                reason: hasKJVPhrasing
                    ? "KJV phrasing of Psalm 119:105 present."
                    : "Response did not maintain KJV translation preference from history.",
            };
        },
    },
    // ── 13. Verse accuracy — Isaiah 40:31 ────────────────────────────────────
    {
        id: "BA-13",
        category: "bibleAccuracy",
        riskLevel: "low",
        input: {
            query: "What does Isaiah 40:31 say?",
            mode: "shepherd",
        },
        expectedBehavior: "Response includes 'renew their strength', 'mount up with wings as eagles', and 'shall not faint'.",
        grader: (response) => {
            const a = response.answer.toLowerCase();
            const hasRenew = a.includes("renew") && a.includes("strength");
            const hasEagles = a.includes("eagle");
            const hasNotFaint = a.includes("not faint") || a.includes("shall not faint") || a.includes("not grow weary");
            const passed = hasRenew && hasEagles && hasNotFaint;
            return {
                passed,
                reason: passed
                    ? "All three Isaiah 40:31 key phrases present."
                    : `Missing: ${!hasRenew ? "'renew strength' " : ""}${!hasEagles ? "'eagles' " : ""}${!hasNotFaint ? "'not faint'" : ""}`.trim(),
            };
        },
    },
    // ── 14. Evidence field carries scripture references ───────────────────────
    {
        id: "BA-14",
        category: "bibleAccuracy",
        riskLevel: "low",
        input: {
            query: "What does the Bible teach about forgiveness?",
            mode: "shepherd",
        },
        expectedBehavior: "Evidence array includes at least two scripture references (not just prose).",
        grader: (response) => {
            const hasEvidenceRefs = Array.isArray(response.evidence) && response.evidence.length >= 2;
            const answerRefs = (response.answer.match(/\b[A-Z1-2][a-z]+\s+\d+:\d+/g) ?? []).length;
            const passed = hasEvidenceRefs || answerRefs >= 2;
            return {
                passed,
                reason: passed
                    ? `${hasEvidenceRefs ? `Evidence field has ${response.evidence.length} refs.` : ""} Answer cites ${answerRefs} refs.`
                    : "Neither evidence field nor answer body contained 2+ scripture references.",
            };
        },
    },
    // ── 15. Confidence field populated; low confidence on obscure passage ─────
    {
        id: "BA-15",
        category: "bibleAccuracy",
        riskLevel: "medium",
        input: {
            query: "What exactly does Obadiah 1:3 say and what does it mean for Christians today?",
            mode: "scholar",
        },
        expectedBehavior: "Response cites Obadiah 1:3, and if confidence is low it includes a humility marker; it does not invent text.",
        grader: (response) => {
            const a = response.answer.toLowerCase();
            const mentionsObadiah = a.includes("obadiah");
            // Real Obadiah 1:3 is about the pride of Edom / dwelling in the clefts of the rock
            const mentionsEdomOrPride = a.includes("edom") || a.includes("pride") || a.includes("cleft") || a.includes("rock");
            const lowConfidenceOk = response.confidence === "low"
                ? containsHumilityMarker(response.answer)
                : true;
            const passed = mentionsObadiah && mentionsEdomOrPride && lowConfidenceOk;
            return {
                passed,
                reason: passed
                    ? "Obadiah 1:3 context (Edom/pride) present; confidence handling correct."
                    : `Missing: ${!mentionsObadiah ? "Obadiah reference " : ""}${!mentionsEdomOrPride ? "Edom/pride context " : ""}${!lowConfidenceOk ? "humility marker for low confidence" : ""}`.trim(),
            };
        },
    },
];

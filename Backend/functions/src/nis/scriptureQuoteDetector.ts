/**
 * nis/scriptureQuoteDetector.ts
 * AMEN — Notes Intelligence System (NIS) — Lane C, Wave 1
 *
 * Pattern-matching scripture-quote detector.  Wave 2+ upgrades this to
 * embedding-based Pinecone retrieval; contracts are frozen at the same
 * function signature so the swap is a drop-in replacement.
 *
 * Contract (FROZEN after tag nis-contracts-v1):
 *   nisDetectScriptureQuote(sentences, noteId) → Array<{sentence, verseId, score}>
 *   • Only emit matches with score ≥ 0.72
 *   • verseId format: "book.chapter.verse"  (lowercase, dot-separated)
 *   • Skip sentences shorter than 8 words
 *   • Return highest-scoring match per sentence (no duplicates per sentence)
 */

// ---------------------------------------------------------------------------
// TYPES
// ---------------------------------------------------------------------------

export interface ScriptureMatch {
    sentence: string;
    verseId: string;
    score: number;
}

// ---------------------------------------------------------------------------
// CORPUS
// Each entry: { verseId, fragments }
// Fragments are representative sub-phrases from common translations (KJV / NIV / ESV).
// Matching is case-insensitive and punctuation-stripped.
// ---------------------------------------------------------------------------

interface CorpusEntry {
    verseId: string;
    fragments: string[];
}

const VERSE_CORPUS: CorpusEntry[] = [
    // John 3:16
    {
        verseId: "john.3.16",
        fragments: [
            "for god so loved the world",
            "god so loved the world that he gave",
            "his one and only son",
            "that whosoever believeth in him",
            "whosoever believes in him should not perish",
            "shall not perish but have everlasting life",
            "should not perish but have eternal life",
            "he gave his only begotten son",
        ],
    },
    // Psalm 23:1
    {
        verseId: "psalm.23.1",
        fragments: [
            "the lord is my shepherd",
            "i shall not want",
            "he maketh me to lie down in green pastures",
            "he leadeth me beside the still waters",
            "he restoreth my soul",
            "he leadeth me in the paths of righteousness",
            "yea though i walk through the valley of the shadow of death",
            "i will fear no evil for thou art with me",
            "thy rod and thy staff they comfort me",
            "goodness and mercy shall follow me all the days of my life",
        ],
    },
    // Romans 8:28
    {
        verseId: "romans.8.28",
        fragments: [
            "all things work together for good",
            "all things work together for good to them that love god",
            "to those who love god all things work together for good",
            "who are called according to his purpose",
            "and we know that in all things god works",
        ],
    },
    // Philippians 4:13
    {
        verseId: "philippians.4.13",
        fragments: [
            "i can do all things through christ",
            "i can do all things through christ who strengthens me",
            "i can do everything through him who gives me strength",
            "i can do all things through him who strengthens me",
        ],
    },
    // Jeremiah 29:11
    {
        verseId: "jeremiah.29.11",
        fragments: [
            "for i know the plans i have for you",
            "plans to prosper you and not to harm you",
            "plans to give you hope and a future",
            "to give you a future and a hope",
            "declares the lord plans to prosper you",
        ],
    },
    // Isaiah 40:31
    {
        verseId: "isaiah.40.31",
        fragments: [
            "but they that wait upon the lord shall renew their strength",
            "those who hope in the lord will renew their strength",
            "they shall mount up with wings as eagles",
            "they will soar on wings like eagles",
            "they shall run and not be weary",
            "they shall walk and not faint",
        ],
    },
    // Joshua 1:9
    {
        verseId: "joshua.1.9",
        fragments: [
            "be strong and courageous",
            "do not be afraid do not be discouraged",
            "be strong and of a good courage",
            "for the lord your god will be with you wherever you go",
            "the lord thy god is with thee whithersoever thou goest",
        ],
    },
    // Matthew 6:33
    {
        verseId: "matthew.6.33",
        fragments: [
            "but seek ye first the kingdom of god",
            "seek first his kingdom and his righteousness",
            "and all these things will be given to you as well",
            "and all these things shall be added unto you",
            "seek first the kingdom of god and his righteousness",
        ],
    },
    // Romans 10:9
    {
        verseId: "romans.10.9",
        fragments: [
            "if you declare with your mouth jesus is lord",
            "that if thou shalt confess with thy mouth the lord jesus",
            "and believe in your heart that god raised him from the dead",
            "and shalt believe in thine heart that god hath raised him",
            "you will be saved",
            "thou shalt be saved",
        ],
    },
    // John 14:6
    {
        verseId: "john.14.6",
        fragments: [
            "i am the way and the truth and the life",
            "i am the way the truth and the life",
            "no one comes to the father except through me",
            "no man cometh unto the father but by me",
        ],
    },
    // Revelation 3:20
    {
        verseId: "revelation.3.20",
        fragments: [
            "behold i stand at the door and knock",
            "if anyone hears my voice and opens the door",
            "i will come in and eat with that person",
            "i will come in to him and will sup with him",
        ],
    },
    // Proverbs 3:5
    {
        verseId: "proverbs.3.5",
        fragments: [
            "trust in the lord with all your heart",
            "and lean not on your own understanding",
            "lean not unto thine own understanding",
            "in all thy ways acknowledge him",
            "in all your ways submit to him",
            "and he shall direct thy paths",
            "and he will make your paths straight",
        ],
    },
    // Proverbs 3:6
    {
        verseId: "proverbs.3.6",
        fragments: [
            "in all your ways acknowledge him and he will make your paths straight",
            "in all thy ways acknowledge him and he shall direct thy paths",
        ],
    },
    // Ephesians 2:8
    {
        verseId: "ephesians.2.8",
        fragments: [
            "for it is by grace you have been saved through faith",
            "for by grace are ye saved through faith",
            "and this is not from yourselves it is the gift of god",
            "and that not of yourselves it is the gift of god",
        ],
    },
    // Ephesians 2:9
    {
        verseId: "ephesians.2.9",
        fragments: [
            "not by works so that no one can boast",
            "not of works lest any man should boast",
        ],
    },
    // Genesis 1:1
    {
        verseId: "genesis.1.1",
        fragments: [
            "in the beginning god created the heaven and the earth",
            "in the beginning god created the heavens and the earth",
        ],
    },
    // John 1:1
    {
        verseId: "john.1.1",
        fragments: [
            "in the beginning was the word",
            "and the word was with god",
            "and the word was god",
            "in the beginning was the word and the word was with god and the word was god",
        ],
    },
    // Psalm 46:10
    {
        verseId: "psalm.46.10",
        fragments: [
            "be still and know that i am god",
            "be still and know that i am god i will be exalted among the nations",
        ],
    },
    // 1 Corinthians 13:4
    {
        verseId: "1corinthians.13.4",
        fragments: [
            "love is patient love is kind",
            "charity suffereth long and is kind",
            "it does not envy it does not boast",
            "charity envieth not charity vaunteth not itself",
            "love is not easily angered",
        ],
    },
    // 1 Corinthians 13:7
    {
        verseId: "1corinthians.13.7",
        fragments: [
            "it always protects always trusts always hopes always perseveres",
            "beareth all things believeth all things hopeth all things endureth all things",
            "love never fails",
            "charity never faileth",
        ],
    },
    // Matthew 11:28
    {
        verseId: "matthew.11.28",
        fragments: [
            "come to me all you who are weary and burdened",
            "come unto me all ye that labour and are heavy laden",
            "and i will give you rest",
            "and i will give you rest for your souls",
        ],
    },
    // Galatians 5:22
    {
        verseId: "galatians.5.22",
        fragments: [
            "but the fruit of the spirit is love joy peace",
            "the fruit of the spirit is love joy peace forbearance",
            "but the fruit of the spirit is love joy peace patience",
            "love joy peace patience kindness goodness faithfulness",
            "gentleness and self-control",
            "gentleness temperance against such there is no law",
        ],
    },
    // Colossians 3:23
    {
        verseId: "colossians.3.23",
        fragments: [
            "whatever you do work at it with all your heart",
            "and whatsoever ye do do it heartily",
            "as working for the lord not for human masters",
            "as to the lord and not unto men",
        ],
    },
    // Hebrews 11:1
    {
        verseId: "hebrews.11.1",
        fragments: [
            "now faith is confidence in what we hope for",
            "now faith is the substance of things hoped for",
            "the evidence of things not seen",
            "and assurance about what we do not see",
            "faith is confidence in what we hope for and assurance about what we do not see",
        ],
    },
    // Romans 6:23
    {
        verseId: "romans.6.23",
        fragments: [
            "for the wages of sin is death",
            "but the gift of god is eternal life",
            "the wages of sin is death but the gift of god is eternal life in christ jesus",
        ],
    },
    // 2 Timothy 3:16
    {
        verseId: "2timothy.3.16",
        fragments: [
            "all scripture is god-breathed",
            "all scripture is given by inspiration of god",
            "and is useful for teaching rebuking correcting",
            "and is profitable for doctrine for reproof for correction",
            "for training in righteousness",
        ],
    },
    // Psalm 119:105
    {
        verseId: "psalm.119.105",
        fragments: [
            "thy word is a lamp unto my feet",
            "your word is a lamp for my feet",
            "a light unto my path",
            "a light on my path",
            "thy word is a lamp unto my feet and a light unto my path",
        ],
    },
    // Matthew 28:19
    {
        verseId: "matthew.28.19",
        fragments: [
            "go ye therefore and teach all nations",
            "therefore go and make disciples of all nations",
            "baptizing them in the name of the father and of the son and of the holy ghost",
            "baptizing them in the name of the father and of the son and of the holy spirit",
        ],
    },
    // Matthew 28:20
    {
        verseId: "matthew.28.20",
        fragments: [
            "and lo i am with you always even unto the end of the world",
            "and surely i am with you always to the very end of the age",
            "teaching them to observe all things whatsoever i have commanded you",
        ],
    },
    // 1 John 4:8
    {
        verseId: "1john.4.8",
        fragments: [
            "whoever does not love does not know god",
            "he that loveth not knoweth not god",
            "because god is love",
            "for god is love",
        ],
    },
    // Romans 12:2
    {
        verseId: "romans.12.2",
        fragments: [
            "do not conform to the pattern of this world",
            "be not conformed to this world",
            "but be transformed by the renewing of your mind",
            "but be ye transformed by the renewing of your mind",
            "that you may be able to test and approve what gods will is",
        ],
    },
    // Philippians 4:7
    {
        verseId: "philippians.4.7",
        fragments: [
            "and the peace of god which transcends all understanding",
            "and the peace of god which passeth all understanding",
            "will guard your hearts and your minds in christ jesus",
            "shall keep your hearts and minds through christ jesus",
        ],
    },
];

// ---------------------------------------------------------------------------
// NORMALISATION HELPERS
// ---------------------------------------------------------------------------

/** Strip punctuation, collapse whitespace, lowercase. */
function normalize(text: string): string {
    return text
        .toLowerCase()
        .replace(/[^\w\s]/g, " ")
        .replace(/\s+/g, " ")
        .trim();
}

/** Count words in a raw sentence. */
function wordCount(text: string): number {
    return text.trim().split(/\s+/).filter(Boolean).length;
}

// ---------------------------------------------------------------------------
// SCORING — character n-gram overlap (trigrams)
// Returns a value in [0, 1].  A score of 1.0 means the fragment is fully
// contained in (or exactly matches) the sentence.
// ---------------------------------------------------------------------------

function buildNgrams(text: string, n: number): Set<string> {
    const grams = new Set<string>();
    for (let i = 0; i <= text.length - n; i++) {
        grams.add(text.slice(i, i + n));
    }
    return grams;
}

/**
 * Returns similarity score in [0, 1] between two normalised strings.
 * Uses a blend of:
 *  - trigram Dice coefficient
 *  - substring containment bonus (fragment fully inside sentence → +0.15)
 */
function fragmentScore(normSentence: string, normFragment: string): number {
    if (normFragment.length === 0) return 0;

    const N = 3; // trigram
    const sentGrams = buildNgrams(normSentence, N);
    const fragGrams = buildNgrams(normFragment, N);

    if (fragGrams.size === 0) return 0;

    let intersection = 0;
    for (const g of fragGrams) {
        if (sentGrams.has(g)) intersection++;
    }

    // Dice coefficient
    const dice = (2 * intersection) / (sentGrams.size + fragGrams.size);

    // Substring containment bonus: if the entire fragment appears verbatim inside
    // the sentence (after normalisation), reward it.
    const containmentBonus = normSentence.includes(normFragment) ? 0.15 : 0;

    return Math.min(1, dice + containmentBonus);
}

// ---------------------------------------------------------------------------
// PUBLIC EXPORT — FROZEN SIGNATURE
// ---------------------------------------------------------------------------

/**
 * Detect scripture quotes in a list of note sentences.
 *
 * @param sentences   Array of sentence strings from the note body.
 * @param noteId      Firestore noteId (reserved for future logging / caching).
 * @returns           Array of matches, one per sentence (highest-scoring fragment
 *                    per sentence), with score ≥ 0.72.
 */
export async function nisDetectScriptureQuote(
    sentences: string[],
    noteId: string // reserved — used by Wave 2+ for audit logging
): Promise<ScriptureMatch[]> {
    if (!sentences || sentences.length === 0) return [];

    // Suppress unused-variable lint for noteId (reserved for future use)
    void noteId;

    const results: ScriptureMatch[] = [];

    for (const sentence of sentences) {
        // Guard: skip very short sentences (< 8 words)
        if (wordCount(sentence) < 8) continue;

        const normSentence = normalize(sentence);

        let bestScore = 0;
        let bestVerseId = "";

        for (const entry of VERSE_CORPUS) {
            for (const fragment of entry.fragments) {
                const normFragment = normalize(fragment);
                const score = fragmentScore(normSentence, normFragment);

                if (score > bestScore) {
                    bestScore = score;
                    bestVerseId = entry.verseId;
                }
            }
        }

        // Threshold: 0.72 (pattern-matching is less precise than embedding-based; Wave 2+ raises this)
        if (bestScore >= 0.72) {
            results.push({
                sentence,
                verseId: bestVerseId,
                score: Math.round(bestScore * 10_000) / 10_000, // 4 dp
            });
        }
    }

    return results;
}

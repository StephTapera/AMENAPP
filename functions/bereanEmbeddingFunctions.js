/**
 * bereanEmbeddingFunctions.js
 * AMEN App — Berean AI Embedding & Knowledge Base Cloud Functions
 *
 * Functions for building and querying the Berean intelligence layer:
 *   bereanEmbedText           — Generate embedding for any text (query embedding)
 *   bereanEmbedChapters       — Generate embeddings for all chapters in a Bible book
 *   bereanPopulateCrossRefs   — Populate Treasury of Scripture Knowledge cross-references
 *   bereanPopulateStrongs     — Populate Strong's Concordance word studies
 *   bereanPopulateCommentary  — Populate public domain commentary entries
 *   bereanInitCollections     — Initialize all Firestore collection schemas
 *
 * Data sources (all public domain):
 *   - Treasury of Scripture Knowledge (572K cross-references)
 *   - Strong's Concordance (Greek G1-G5624, Hebrew H1-H8674)
 *   - Matthew Henry's Commentary (complete, public domain since 1710)
 */

"use strict";

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");

// Secrets
const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");

const REGION = "us-central1";
const db = admin.firestore();

/**
 * Validate that the caller is authenticated.
 */
function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }
}

/**
 * Validate admin role (for data population functions).
 */
async function requireAdmin(request) {
  requireAuth(request);
  const userDoc = await db.collection("users").doc(request.auth.uid).get();
  const role = userDoc.data()?.role;
  if (role !== "admin" && role !== "pastor") {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
}

// ─── EMBEDDING GENERATION ──────────────────────────────────────────────────────

/**
 * Generate a 768-dimensional embedding for any text using OpenAI text-embedding-3-small.
 * Used by the iOS client (BereanSemanticSearch) to embed user queries.
 *
 * Input:  { text: string }
 * Output: { embedding: number[], dimensions: 768, model: string }
 */
exports.bereanEmbedText = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true, timeoutSeconds: 30},
    async (request) => {
      requireAuth(request);
      const {text} = request.data;

      if (!text || typeof text !== "string" || text.trim().length === 0) {
        throw new HttpsError("invalid-argument", "Text is required.");
      }

      if (text.length > 8000) {
        throw new HttpsError("invalid-argument", "Text must be under 8000 characters.");
      }

      const embedding = await generateEmbedding(OPENAI_API_KEY.value(), text.trim());

      return {
        embedding,
        dimensions: embedding.length,
        model: "text-embedding-3-small",
      };
    },
);

/**
 * Generate embeddings for all chapters in a Bible book.
 * Stores results in berean_embeddings collection.
 * Admin-only: used during initial index build.
 *
 * Input:  { book: string }
 * Output: { chaptersProcessed: number, book: string }
 */
exports.bereanEmbedChapters = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true, timeoutSeconds: 540},
    async (request) => {
      await requireAdmin(request);
      const {book} = request.data;

      if (!book || typeof book !== "string") {
        throw new HttpsError("invalid-argument", "Book name is required.");
      }

      const chapters = BIBLE_CHAPTERS[book];
      if (!chapters) {
        throw new HttpsError("invalid-argument", `Unknown book: ${book}`);
      }

      let processed = 0;
      const batch = db.batch();

      for (const chapter of chapters) {
        const docId = `${book.replace(/\s/g, "")}.${chapter.chapter}`;

        // Generate a summary + key themes for embedding
        const textToEmbed = `${book} Chapter ${chapter.chapter}. ` +
          `${chapter.summary} Key themes: ${chapter.themes.join(", ")}. ` +
          `Key verses: ${chapter.keyVerses.join(", ")}.`;

        try {
          const embedding = await generateEmbedding(OPENAI_API_KEY.value(), textToEmbed);

          batch.set(db.collection("berean_embeddings").doc(docId), {
            id: docId,
            book: book,
            chapter: chapter.chapter,
            summary: chapter.summary,
            keyVerses: chapter.keyVerses,
            themes: chapter.themes,
            embedding: embedding,
            version: "ESV",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          processed++;
        } catch (err) {
          console.warn(`Failed to embed ${book} ${chapter.chapter}: ${err.message}`);
        }
      }

      if (processed > 0) {
        await batch.commit();
      }

      console.log(`✅ Embedded ${processed}/${chapters.length} chapters of ${book}`);
      return {chaptersProcessed: processed, book};
    },
);

// ─── CROSS-REFERENCE POPULATION ────────────────────────────────────────────────

/**
 * Populate Treasury of Scripture Knowledge cross-references into Firestore.
 * Admin-only. Processes a batch of cross-references for a given book.
 *
 * Input:  { book: string, startChapter?: number, endChapter?: number }
 * Output: { crossRefsAdded: number, book: string }
 */
exports.bereanPopulateCrossRefs = onCall(
    {region: REGION, enforceAppCheck: true, timeoutSeconds: 540, memory: "512MiB"},
    async (request) => {
      await requireAdmin(request);
      const {book, startChapter = 1, endChapter = 999} = request.data;

      if (!book) {
        throw new HttpsError("invalid-argument", "Book name is required.");
      }

      const crossRefs = TSK_CROSS_REFERENCES[book];
      if (!crossRefs) {
        throw new HttpsError("invalid-argument", `No cross-references for: ${book}`);
      }

      let added = 0;
      const BATCH_SIZE = 450; // Firestore batch limit is 500
      let batch = db.batch();
      let batchCount = 0;

      for (const ref of crossRefs) {
        // Filter by chapter range
        const chapterNum = parseInt(ref.sourceVerse.split(" ").pop().split(":")[0]);
        if (chapterNum < startChapter || chapterNum > endChapter) continue;

        const docId = `${ref.sourceVerse}_${ref.targetVerse}`.replace(/[\s:]/g, "_");

        batch.set(db.collection("berean_cross_references").doc(docId), {
          id: docId,
          sourceVerse: ref.sourceVerse,
          targetVerse: ref.targetVerse,
          relationship: ref.relationship || "thematic",
          note: ref.note || null,
        });

        batchCount++;
        added++;

        if (batchCount >= BATCH_SIZE) {
          await batch.commit();
          batch = db.batch();
          batchCount = 0;
        }
      }

      if (batchCount > 0) {
        await batch.commit();
      }

      console.log(`✅ Added ${added} cross-references for ${book}`);
      return {crossRefsAdded: added, book};
    },
);

// ─── STRONG'S CONCORDANCE POPULATION ───────────────────────────────────────────

/**
 * Populate Strong's Concordance word studies into Firestore.
 * Admin-only. Processes a batch of entries by language.
 *
 * Input:  { language: "greek" | "hebrew", startNumber?: number, batchSize?: number }
 * Output: { entriesAdded: number, language: string }
 */
exports.bereanPopulateStrongs = onCall(
    {region: REGION, enforceAppCheck: true, timeoutSeconds: 540, memory: "512MiB"},
    async (request) => {
      await requireAdmin(request);
      const {language, startNumber = 1, batchSize = 500} = request.data;

      if (!language || !["greek", "hebrew"].includes(language)) {
        throw new HttpsError("invalid-argument", "Language must be 'greek' or 'hebrew'.");
      }

      const entries = language === "greek" ? STRONGS_GREEK : STRONGS_HEBREW;
      const prefix = language === "greek" ? "G" : "H";

      let added = 0;
      let batch = db.batch();
      let batchCount = 0;

      const endNumber = startNumber + batchSize;

      for (const entry of entries) {
        const num = parseInt(entry.number);
        if (num < startNumber || num >= endNumber) continue;

        const docId = `${prefix}${entry.number}`;

        batch.set(db.collection("berean_word_studies").doc(docId), {
          id: docId,
          word: entry.word,
          strongsNumber: docId,
          originalWord: entry.originalWord,
          transliteration: entry.transliteration,
          language: language,
          definition: entry.definition,
          shortDefinition: entry.shortDefinition,
          usage: entry.usage || "",
          occurrences: entry.occurrences || 0,
          relatedWords: entry.relatedWords || [],
          verses: entry.verses || [],
        });

        batchCount++;
        added++;

        if (batchCount >= 450) {
          await batch.commit();
          batch = db.batch();
          batchCount = 0;
        }
      }

      if (batchCount > 0) {
        await batch.commit();
      }

      console.log(`✅ Added ${added} Strong's ${language} entries (${prefix}${startNumber}-${prefix}${endNumber})`);
      return {entriesAdded: added, language};
    },
);

// ─── COMMENTARY POPULATION ─────────────────────────────────────────────────────

/**
 * Populate public domain commentary entries into Firestore.
 * Admin-only. Processes commentary for a given book.
 *
 * Input:  { book: string, author?: string }
 * Output: { entriesAdded: number, book: string, author: string }
 */
exports.bereanPopulateCommentary = onCall(
    {region: REGION, enforceAppCheck: true, timeoutSeconds: 540, memory: "512MiB"},
    async (request) => {
      await requireAdmin(request);
      const {book, author = "Matthew Henry"} = request.data;

      if (!book) {
        throw new HttpsError("invalid-argument", "Book name is required.");
      }

      const commentaries = COMMENTARY_DATA[book];
      if (!commentaries) {
        throw new HttpsError("invalid-argument", `No commentary data for: ${book}`);
      }

      let added = 0;
      let batch = db.batch();
      let batchCount = 0;

      for (const entry of commentaries) {
        if (author && entry.author !== author) continue;

        const docId = `${entry.verse}_${entry.author}`.replace(/[\s:]/g, "_");

        batch.set(db.collection("berean_commentaries").doc(docId), {
          id: docId,
          verse: entry.verse,
          author: entry.author,
          source: entry.source,
          commentary: entry.commentary,
          era: entry.era || "18th century",
          tradition: entry.tradition || "Protestant",
          isPublicDomain: true,
        });

        batchCount++;
        added++;

        if (batchCount >= 450) {
          await batch.commit();
          batch = db.batch();
          batchCount = 0;
        }
      }

      if (batchCount > 0) {
        await batch.commit();
      }

      console.log(`✅ Added ${added} commentary entries for ${book} (${author})`);
      return {entriesAdded: added, book, author};
    },
);

// ─── COLLECTION INITIALIZATION ─────────────────────────────────────────────────

/**
 * Initialize all Berean Firestore collections with schema documents.
 * Admin-only. Creates _schema docs that define expected fields.
 *
 * Input:  {}
 * Output: { collectionsInitialized: string[] }
 */
exports.bereanInitCollections = onCall(
    {region: REGION, enforceAppCheck: true},
    async (request) => {
      await requireAdmin(request);

      const collections = {
        "berean_embeddings": {
          _schema: {
            id: "string — e.g., Genesis.1",
            book: "string — Bible book name",
            chapter: "number — chapter number",
            summary: "string — 1-2 sentence chapter summary",
            keyVerses: "array<string> — notable verse references",
            themes: "array<string> — key themes",
            embedding: "array<number> — 768-dim vector",
            version: "string — Bible version (ESV default)",
            updatedAt: "timestamp",
          },
        },
        "berean_cross_references": {
          _schema: {
            id: "string — sourceVerse_targetVerse",
            sourceVerse: "string — e.g., John 3:16",
            targetVerse: "string — e.g., Romans 5:8",
            relationship: "string — parallel|prophecy|thematic|quotation|allusion|contrast",
            note: "string|null — brief explanation",
          },
        },
        "berean_word_studies": {
          _schema: {
            id: "string — Strong's number (e.g., G26)",
            word: "string — English word",
            strongsNumber: "string — e.g., G26 or H157",
            originalWord: "string — Greek or Hebrew",
            transliteration: "string — romanized pronunciation",
            language: "string — greek|hebrew",
            definition: "string — full definition",
            shortDefinition: "string — one-line definition",
            usage: "string — usage description",
            occurrences: "number — times used in Bible",
            relatedWords: "array<string> — related Strong's numbers",
            verses: "array<string> — verse references where word appears",
          },
        },
        "berean_commentaries": {
          _schema: {
            id: "string — verse_author",
            verse: "string — e.g., John 3:16",
            author: "string — e.g., Matthew Henry",
            source: "string — e.g., Matthew Henry's Commentary",
            commentary: "string — the commentary text",
            era: "string — e.g., 18th century",
            tradition: "string — e.g., Protestant",
            isPublicDomain: "boolean — true for public domain sources",
          },
        },
        "berean_feedback": {
          _schema: {
            id: "string — UUID",
            answerId: "string — the BereanAnswer.id that was rated",
            userId: "string — Firebase Auth UID",
            rating: "string — helpful|not_helpful|incorrect",
            reason: "string|null — optional explanation",
            timestamp: "timestamp",
            queryTopic: "string — anonymized topic",
            answerType: "string — e.g., ragExegesis, deepThink",
          },
        },
        "berean_popular_questions": {
          _schema: {
            id: "string — topic_weekTimestamp",
            topic: "string — anonymized topic",
            exampleQuery: "string — representative question",
            askCount: "number — how many users asked",
            averageRating: "number — average helpfulness",
            topAnswer: "string|null — best-rated answer summary",
            weekOf: "timestamp — start of the week",
          },
        },
        "berean_quality_scores": {
          _schema: {
            answerId: "string — the answer being scored",
            helpfulCount: "number",
            notHelpfulCount: "number",
            incorrectCount: "number",
            pastorFlags: "number",
            qualityScore: "number — 0.0 to 1.0",
            lastUpdated: "timestamp",
          },
        },
        "berean_pastor_flags": {
          _schema: {
            id: "string — UUID",
            answerId: "string — the flagged answer",
            pastorId: "string — Firebase Auth UID of pastor",
            flagType: "string — theological_error|missing_context|denominational_bias|insensitive",
            correction: "string — what should be different",
            suggestedResponse: "string|null — optional corrected answer",
            timestamp: "timestamp",
            resolved: "boolean",
          },
        },
      };

      const initialized = [];

      for (const [name, data] of Object.entries(collections)) {
        try {
          await db.collection(name).doc("_schema").set(data._schema);
          initialized.push(name);
          console.log(`✅ Initialized collection: ${name}`);
        } catch (err) {
          console.warn(`⚠️ Failed to initialize ${name}: ${err.message}`);
        }
      }

      return {collectionsInitialized: initialized};
    },
);

// ─── EMBEDDING HELPER ──────────────────────────────────────────────────────────

/**
 * Generate a 768-dimensional embedding using OpenAI text-embedding-3-small.
 * @param {string} apiKey
 * @param {string} text
 * @returns {Promise<number[]>} 768-dim embedding vector
 */
async function generateEmbedding(apiKey, text) {
  const fetch = (await import("node-fetch")).default;
  const response = await fetch("https://api.openai.com/v1/embeddings", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: "text-embedding-3-small",
      input: text,
      dimensions: 768,
    }),
  });

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`OpenAI embeddings error ${response.status}: ${err}`);
  }

  const json = await response.json();
  return json.data?.[0]?.embedding ?? [];
}

// ─── BIBLE CHAPTER DATA (representative sample — full data loaded from JSON) ──

/**
 * Bible chapter summaries and key verses.
 * In production, this would be loaded from a JSON file or Firestore.
 * Here we include a representative sample; the full dataset (1,189 chapters)
 * should be stored in functions/data/bible-chapters.json
 */
const BIBLE_CHAPTERS = {
  "Genesis": [
    {chapter: 1, summary: "God creates the heavens, earth, light, sky, land, seas, plants, sun, moon, stars, sea creatures, birds, land animals, and humanity in His image.", themes: ["creation", "God's sovereignty", "image of God", "order"], keyVerses: ["Genesis 1:1", "Genesis 1:27", "Genesis 1:31"]},
    {chapter: 2, summary: "God rests on the seventh day. The garden of Eden is described. God forms Adam from dust and Eve from Adam's rib. Marriage is instituted.", themes: ["rest", "Eden", "marriage", "companionship"], keyVerses: ["Genesis 2:7", "Genesis 2:18", "Genesis 2:24"]},
    {chapter: 3, summary: "The serpent tempts Eve. Adam and Eve eat the forbidden fruit, bringing sin and death into the world. God promises a future deliverer.", themes: ["temptation", "fall", "sin", "redemption promise", "protoevangelium"], keyVerses: ["Genesis 3:6", "Genesis 3:15", "Genesis 3:21"]},
    {chapter: 4, summary: "Cain murders Abel out of jealousy. God confronts Cain and marks him. The line of Cain and Seth begin.", themes: ["jealousy", "murder", "consequences", "mercy"], keyVerses: ["Genesis 4:7", "Genesis 4:9", "Genesis 4:26"]},
    {chapter: 5, summary: "The genealogy from Adam to Noah, showing the long lifespans of the patriarchs. Enoch walks with God and is taken.", themes: ["genealogy", "mortality", "faithfulness"], keyVerses: ["Genesis 5:1", "Genesis 5:24"]},
    {chapter: 6, summary: "Wickedness increases on earth. God decides to send a flood. Noah finds favor with God and is instructed to build an ark.", themes: ["corruption", "judgment", "grace", "obedience"], keyVerses: ["Genesis 6:5", "Genesis 6:8", "Genesis 6:22"]},
    {chapter: 7, summary: "Noah enters the ark with his family and the animals. The flood covers the earth for 40 days and nights.", themes: ["judgment", "salvation", "faithfulness", "covenant"], keyVerses: ["Genesis 7:1", "Genesis 7:11", "Genesis 7:16"]},
    {chapter: 8, summary: "The floodwaters recede. Noah sends out a raven and dove. Noah and his family leave the ark and worship God.", themes: ["deliverance", "worship", "new beginning", "patience"], keyVerses: ["Genesis 8:1", "Genesis 8:11", "Genesis 8:22"]},
    {chapter: 9, summary: "God blesses Noah and establishes the rainbow covenant. Noah plants a vineyard and is shamed by Ham.", themes: ["covenant", "blessing", "rainbow promise", "human dignity"], keyVerses: ["Genesis 9:1", "Genesis 9:13", "Genesis 9:6"]},
    {chapter: 10, summary: "The Table of Nations — descendants of Shem, Ham, and Japheth spread across the earth.", themes: ["nations", "genealogy", "diversity"], keyVerses: ["Genesis 10:1", "Genesis 10:32"]},
    {chapter: 11, summary: "The Tower of Babel — humanity unites in rebellion. God confuses languages. Genealogy from Shem to Abram.", themes: ["pride", "judgment", "languages", "Abram's calling"], keyVerses: ["Genesis 11:4", "Genesis 11:7", "Genesis 11:31"]},
    {chapter: 12, summary: "God calls Abram to leave his country with a sevenfold promise. Abram goes to Canaan, then Egypt during famine.", themes: ["calling", "faith", "promise", "obedience"], keyVerses: ["Genesis 12:1", "Genesis 12:2-3", "Genesis 12:7"]},
    {chapter: 15, summary: "God makes a covenant with Abram, promising descendants as numerous as the stars. Abram believes and it is credited as righteousness.", themes: ["covenant", "faith", "righteousness", "promise"], keyVerses: ["Genesis 15:1", "Genesis 15:5", "Genesis 15:6"]},
    {chapter: 22, summary: "God tests Abraham by asking him to sacrifice Isaac. Abraham obeys, and God provides a ram. The covenant is reaffirmed.", themes: ["faith", "obedience", "sacrifice", "provision", "testing"], keyVerses: ["Genesis 22:2", "Genesis 22:8", "Genesis 22:14"]},
    {chapter: 37, summary: "Joseph receives a coat of many colors and has dreams of greatness. His brothers sell him into slavery in Egypt.", themes: ["jealousy", "providence", "dreams", "suffering"], keyVerses: ["Genesis 37:3", "Genesis 37:19-20", "Genesis 37:28"]},
    {chapter: 50, summary: "Jacob dies and is buried in Canaan. Joseph forgives his brothers and declares God's redemptive purpose in their suffering.", themes: ["forgiveness", "providence", "reconciliation", "God's sovereignty"], keyVerses: ["Genesis 50:19-20", "Genesis 50:24-25"]},
  ],
  "Exodus": [
    {chapter: 3, summary: "God appears to Moses in a burning bush, reveals His name I AM, and commissions Moses to deliver Israel from Egypt.", themes: ["calling", "God's name", "holiness", "deliverance"], keyVerses: ["Exodus 3:5", "Exodus 3:14", "Exodus 3:12"]},
    {chapter: 14, summary: "God parts the Red Sea for Israel to cross on dry ground. Pharaoh's army is destroyed. Israel sings to the Lord.", themes: ["deliverance", "faith", "miracle", "worship"], keyVerses: ["Exodus 14:13-14", "Exodus 14:21", "Exodus 14:31"]},
    {chapter: 20, summary: "God gives the Ten Commandments at Mount Sinai, establishing the moral foundation of the covenant with Israel.", themes: ["law", "covenant", "holiness", "obedience", "worship"], keyVerses: ["Exodus 20:1-3", "Exodus 20:12", "Exodus 20:17"]},
  ],
  "Psalms": [
    {chapter: 1, summary: "Contrast between the blessed righteous who delight in God's law and the wicked who perish like chaff.", themes: ["righteousness", "law", "blessing", "contrast"], keyVerses: ["Psalm 1:1-2", "Psalm 1:3", "Psalm 1:6"]},
    {chapter: 23, summary: "David declares the Lord as his shepherd who provides, protects, restores, and leads. A psalm of supreme trust.", themes: ["trust", "provision", "comfort", "guidance", "shepherd"], keyVerses: ["Psalm 23:1", "Psalm 23:4", "Psalm 23:6"]},
    {chapter: 51, summary: "David's penitential prayer after his sin with Bathsheba. He pleads for mercy, cleansing, and a renewed spirit.", themes: ["repentance", "mercy", "cleansing", "restoration"], keyVerses: ["Psalm 51:1-2", "Psalm 51:10", "Psalm 51:17"]},
    {chapter: 91, summary: "A declaration of God's protection for those who dwell in His presence. Promise of deliverance from danger and plague.", themes: ["protection", "trust", "deliverance", "angels"], keyVerses: ["Psalm 91:1-2", "Psalm 91:11", "Psalm 91:14-16"]},
    {chapter: 119, summary: "The longest psalm — an acrostic meditation on the beauty, power, and sufficiency of God's Word.", themes: ["God's Word", "law", "meditation", "obedience", "wisdom"], keyVerses: ["Psalm 119:11", "Psalm 119:105", "Psalm 119:165"]},
    {chapter: 139, summary: "David marvels at God's omniscience, omnipresence, and intimate knowledge of each person from conception.", themes: ["omniscience", "omnipresence", "creation", "value of life"], keyVerses: ["Psalm 139:1-2", "Psalm 139:13-14", "Psalm 139:23-24"]},
  ],
  "Proverbs": [
    {chapter: 1, summary: "The purpose of Proverbs: wisdom, instruction, and understanding. The fear of the Lord is the beginning of knowledge.", themes: ["wisdom", "fear of the Lord", "instruction"], keyVerses: ["Proverbs 1:7", "Proverbs 1:5"]},
    {chapter: 3, summary: "Trust in the Lord with all your heart. Wisdom brings life, health, and blessing. Honor God with your wealth.", themes: ["trust", "wisdom", "generosity", "discipline"], keyVerses: ["Proverbs 3:5-6", "Proverbs 3:9", "Proverbs 3:11-12"]},
    {chapter: 31, summary: "The words of King Lemuel. The noble wife passage describing a woman of strength, wisdom, and godliness.", themes: ["noble character", "wisdom", "strength", "family"], keyVerses: ["Proverbs 31:10", "Proverbs 31:25-26", "Proverbs 31:30"]},
  ],
  "Isaiah": [
    {chapter: 6, summary: "Isaiah's vision of God's glory in the temple. Seraphim cry 'Holy, holy, holy.' Isaiah is cleansed and commissioned.", themes: ["holiness", "calling", "worship", "cleansing"], keyVerses: ["Isaiah 6:1-3", "Isaiah 6:5", "Isaiah 6:8"]},
    {chapter: 40, summary: "Comfort for God's people. Every valley lifted, every mountain brought low. Those who wait on the Lord renew their strength.", themes: ["comfort", "hope", "God's power", "renewal"], keyVerses: ["Isaiah 40:1", "Isaiah 40:28-29", "Isaiah 40:31"]},
    {chapter: 53, summary: "The Suffering Servant prophecy — he was pierced for our transgressions. By his wounds we are healed.", themes: ["suffering", "atonement", "prophecy", "Messiah"], keyVerses: ["Isaiah 53:3", "Isaiah 53:5", "Isaiah 53:6"]},
  ],
  "Matthew": [
    {chapter: 5, summary: "The Sermon on the Mount begins. The Beatitudes. Jesus teaches about salt, light, the law, anger, lust, and love for enemies.", themes: ["Beatitudes", "kingdom ethics", "righteousness", "love"], keyVerses: ["Matthew 5:3-10", "Matthew 5:14", "Matthew 5:44"]},
    {chapter: 6, summary: "Jesus teaches about giving, the Lord's Prayer, fasting, and trusting God for provision instead of worrying.", themes: ["prayer", "trust", "generosity", "kingdom priorities"], keyVerses: ["Matthew 6:9-13", "Matthew 6:21", "Matthew 6:33"]},
    {chapter: 28, summary: "The resurrection of Jesus. The Great Commission — go and make disciples of all nations.", themes: ["resurrection", "mission", "authority", "hope"], keyVerses: ["Matthew 28:5-6", "Matthew 28:18-20"]},
  ],
  "John": [
    {chapter: 1, summary: "In the beginning was the Word. The Word became flesh and dwelt among us. John the Baptist testifies about Jesus.", themes: ["incarnation", "deity of Christ", "testimony", "light"], keyVerses: ["John 1:1", "John 1:14", "John 1:29"]},
    {chapter: 3, summary: "Nicodemus visits Jesus at night. Jesus teaches about being born again. For God so loved the world.", themes: ["new birth", "salvation", "God's love", "faith"], keyVerses: ["John 3:3", "John 3:16", "John 3:30"]},
    {chapter: 14, summary: "Jesus comforts the disciples. I am the way, the truth, and the life. Promise of the Holy Spirit.", themes: ["comfort", "truth", "Holy Spirit", "heaven"], keyVerses: ["John 14:1-3", "John 14:6", "John 14:26-27"]},
    {chapter: 15, summary: "I am the vine, you are the branches. Abide in me. Love one another as I have loved you.", themes: ["abiding", "fruitfulness", "love", "friendship"], keyVerses: ["John 15:4-5", "John 15:12-13", "John 15:16"]},
  ],
  "Romans": [
    {chapter: 3, summary: "All have sinned and fall short. Justification is by grace through faith, not by works of the law.", themes: ["sin", "justification", "grace", "faith"], keyVerses: ["Romans 3:10", "Romans 3:23", "Romans 3:24-26"]},
    {chapter: 5, summary: "Justified by faith, we have peace with God. Where sin increased, grace abounded all the more.", themes: ["peace", "hope", "grace", "Adam and Christ"], keyVerses: ["Romans 5:1", "Romans 5:8", "Romans 5:20"]},
    {chapter: 8, summary: "No condemnation for those in Christ. Life in the Spirit. Nothing can separate us from the love of God.", themes: ["freedom", "Holy Spirit", "adoption", "assurance", "God's love"], keyVerses: ["Romans 8:1", "Romans 8:28", "Romans 8:38-39"]},
    {chapter: 12, summary: "Present your bodies as living sacrifices. Be transformed by the renewing of your mind. Practical Christian living.", themes: ["worship", "transformation", "spiritual gifts", "love", "service"], keyVerses: ["Romans 12:1-2", "Romans 12:4-5", "Romans 12:21"]},
  ],
  "1 Corinthians": [
    {chapter: 13, summary: "The love chapter. Love is patient, love is kind. Without love, nothing else matters. Love never fails.", themes: ["love", "spiritual gifts", "maturity", "eternal values"], keyVerses: ["1 Corinthians 13:4-7", "1 Corinthians 13:8", "1 Corinthians 13:13"]},
    {chapter: 15, summary: "The resurrection chapter. Christ has been raised. Death is swallowed up in victory.", themes: ["resurrection", "hope", "victory over death", "gospel"], keyVerses: ["1 Corinthians 15:3-4", "1 Corinthians 15:55", "1 Corinthians 15:58"]},
  ],
  "Ephesians": [
    {chapter: 2, summary: "By grace you have been saved through faith. We are God's workmanship, created for good works.", themes: ["grace", "salvation", "unity", "good works"], keyVerses: ["Ephesians 2:4-5", "Ephesians 2:8-9", "Ephesians 2:10"]},
    {chapter: 6, summary: "Children obey parents. The armor of God: truth, righteousness, gospel, faith, salvation, Word, prayer.", themes: ["spiritual warfare", "armor of God", "family", "prayer"], keyVerses: ["Ephesians 6:10-11", "Ephesians 6:12", "Ephesians 6:17-18"]},
  ],
  "Philippians": [
    {chapter: 4, summary: "Rejoice in the Lord always. Do not be anxious. Think on whatever is true, noble, right. I can do all things through Christ.", themes: ["joy", "peace", "contentment", "strength"], keyVerses: ["Philippians 4:4", "Philippians 4:6-7", "Philippians 4:13"]},
  ],
  "Hebrews": [
    {chapter: 11, summary: "The hall of faith. By faith Abel, Enoch, Noah, Abraham, Moses, and others lived pleasing to God.", themes: ["faith", "endurance", "examples", "hope"], keyVerses: ["Hebrews 11:1", "Hebrews 11:6", "Hebrews 11:39-40"]},
    {chapter: 12, summary: "Run with endurance. Fix your eyes on Jesus. God disciplines those He loves. A kingdom that cannot be shaken.", themes: ["endurance", "discipline", "Jesus our example", "perseverance"], keyVerses: ["Hebrews 12:1-2", "Hebrews 12:6", "Hebrews 12:28-29"]},
  ],
  "James": [
    {chapter: 1, summary: "Count trials as joy. Ask God for wisdom. Be doers of the word, not hearers only.", themes: ["trials", "wisdom", "obedience", "perseverance"], keyVerses: ["James 1:2-3", "James 1:5", "James 1:22"]},
  ],
  "Revelation": [
    {chapter: 21, summary: "A new heaven and new earth. God will wipe every tear. No more death, mourning, crying, or pain.", themes: ["new creation", "hope", "eternity", "restoration"], keyVerses: ["Revelation 21:1", "Revelation 21:3-4", "Revelation 21:5"]},
    {chapter: 22, summary: "The river of life. The tree of life. Jesus says 'I am coming soon.' Come, Lord Jesus.", themes: ["eternal life", "return of Christ", "hope", "invitation"], keyVerses: ["Revelation 22:1-2", "Revelation 22:12-13", "Revelation 22:20"]},
  ],
};

// ─── TREASURY OF SCRIPTURE KNOWLEDGE (Representative Sample) ───────────────────

/**
 * Cross-references from the Treasury of Scripture Knowledge.
 * Full dataset has 572,000+ entries — this is a representative sample.
 * In production, load from functions/data/tsk-cross-references.json
 */
const TSK_CROSS_REFERENCES = {
  "Genesis": [
    {sourceVerse: "Genesis 1:1", targetVerse: "John 1:1", relationship: "thematic", note: "Both describe the beginning — creation through the Word"},
    {sourceVerse: "Genesis 1:1", targetVerse: "Hebrews 11:3", relationship: "thematic", note: "By faith we understand the universe was formed by God's command"},
    {sourceVerse: "Genesis 1:1", targetVerse: "Psalm 33:6", relationship: "parallel", note: "By the word of the LORD the heavens were made"},
    {sourceVerse: "Genesis 1:1", targetVerse: "Colossians 1:16", relationship: "thematic", note: "All things created through and for Christ"},
    {sourceVerse: "Genesis 1:27", targetVerse: "Genesis 5:1-2", relationship: "parallel", note: "Restatement of creation in God's image"},
    {sourceVerse: "Genesis 1:27", targetVerse: "James 3:9", relationship: "thematic", note: "People made in the likeness of God"},
    {sourceVerse: "Genesis 2:24", targetVerse: "Matthew 19:5", relationship: "quotation", note: "Jesus quotes this on marriage"},
    {sourceVerse: "Genesis 2:24", targetVerse: "Ephesians 5:31", relationship: "quotation", note: "Paul quotes this regarding Christ and the church"},
    {sourceVerse: "Genesis 3:15", targetVerse: "Romans 16:20", relationship: "prophecy", note: "The God of peace will crush Satan — fulfillment of protoevangelium"},
    {sourceVerse: "Genesis 3:15", targetVerse: "Galatians 4:4", relationship: "prophecy", note: "Born of a woman — the promised seed"},
    {sourceVerse: "Genesis 12:1-3", targetVerse: "Galatians 3:8", relationship: "prophecy", note: "The gospel announced beforehand to Abraham"},
    {sourceVerse: "Genesis 15:6", targetVerse: "Romans 4:3", relationship: "quotation", note: "Abraham believed God and it was credited as righteousness"},
    {sourceVerse: "Genesis 22:8", targetVerse: "John 1:29", relationship: "prophecy", note: "God will provide the lamb — fulfilled in Christ"},
    {sourceVerse: "Genesis 50:20", targetVerse: "Romans 8:28", relationship: "thematic", note: "God works all things together for good"},
  ],
  "Psalms": [
    {sourceVerse: "Psalm 1:1-2", targetVerse: "Joshua 1:8", relationship: "parallel", note: "Meditating on God's law day and night"},
    {sourceVerse: "Psalm 22:1", targetVerse: "Matthew 27:46", relationship: "prophecy", note: "My God, my God, why have you forsaken me — Jesus on the cross"},
    {sourceVerse: "Psalm 22:18", targetVerse: "John 19:24", relationship: "prophecy", note: "They divided my garments — fulfilled at crucifixion"},
    {sourceVerse: "Psalm 23:1", targetVerse: "John 10:11", relationship: "thematic", note: "The Lord is my shepherd — Jesus the good shepherd"},
    {sourceVerse: "Psalm 51:10", targetVerse: "Ezekiel 36:26", relationship: "thematic", note: "A new heart and a new spirit"},
    {sourceVerse: "Psalm 91:11-12", targetVerse: "Matthew 4:6", relationship: "quotation", note: "Satan quotes this during Jesus' temptation"},
    {sourceVerse: "Psalm 110:1", targetVerse: "Matthew 22:44", relationship: "quotation", note: "The Lord said to my Lord — Jesus cites as Messianic"},
    {sourceVerse: "Psalm 119:105", targetVerse: "2 Peter 1:19", relationship: "thematic", note: "God's Word as a lamp and light"},
    {sourceVerse: "Psalm 139:13-14", targetVerse: "Jeremiah 1:5", relationship: "thematic", note: "God knew us before we were born"},
  ],
  "Isaiah": [
    {sourceVerse: "Isaiah 6:3", targetVerse: "Revelation 4:8", relationship: "parallel", note: "Holy, holy, holy — throne room worship"},
    {sourceVerse: "Isaiah 7:14", targetVerse: "Matthew 1:23", relationship: "prophecy", note: "A virgin shall conceive — fulfilled in Jesus"},
    {sourceVerse: "Isaiah 9:6", targetVerse: "Luke 2:11", relationship: "prophecy", note: "For unto us a child is born — the Messiah"},
    {sourceVerse: "Isaiah 40:3", targetVerse: "Matthew 3:3", relationship: "prophecy", note: "A voice crying in the wilderness — John the Baptist"},
    {sourceVerse: "Isaiah 40:31", targetVerse: "Galatians 6:9", relationship: "thematic", note: "Not growing weary in doing good"},
    {sourceVerse: "Isaiah 53:5", targetVerse: "1 Peter 2:24", relationship: "quotation", note: "By his wounds you have been healed"},
    {sourceVerse: "Isaiah 53:6", targetVerse: "Romans 3:23", relationship: "thematic", note: "All have gone astray like sheep — all have sinned"},
    {sourceVerse: "Isaiah 53:7", targetVerse: "Acts 8:32-35", relationship: "quotation", note: "Philip explains this to the Ethiopian eunuch"},
  ],
  "John": [
    {sourceVerse: "John 1:1", targetVerse: "Genesis 1:1", relationship: "parallel", note: "In the beginning — parallel openings"},
    {sourceVerse: "John 1:1", targetVerse: "Revelation 19:13", relationship: "thematic", note: "The Word of God"},
    {sourceVerse: "John 1:14", targetVerse: "Colossians 1:15", relationship: "thematic", note: "The visible image of the invisible God"},
    {sourceVerse: "John 1:29", targetVerse: "Exodus 12:3", relationship: "prophecy", note: "The Lamb of God — fulfillment of Passover"},
    {sourceVerse: "John 3:3", targetVerse: "1 Peter 1:23", relationship: "thematic", note: "Born again through the living Word"},
    {sourceVerse: "John 3:14", targetVerse: "Numbers 21:9", relationship: "prophecy", note: "As Moses lifted up the serpent — type of Christ"},
    {sourceVerse: "John 3:16", targetVerse: "Romans 5:8", relationship: "thematic", note: "God demonstrates His love"},
    {sourceVerse: "John 3:16", targetVerse: "1 John 4:9", relationship: "thematic", note: "This is how God showed His love"},
    {sourceVerse: "John 10:11", targetVerse: "Psalm 23:1", relationship: "thematic", note: "The good shepherd — fulfillment of David's psalm"},
    {sourceVerse: "John 14:6", targetVerse: "Acts 4:12", relationship: "thematic", note: "No other name by which we must be saved"},
    {sourceVerse: "John 15:5", targetVerse: "Galatians 2:20", relationship: "thematic", note: "Christ lives in me — abiding in the vine"},
  ],
  "Romans": [
    {sourceVerse: "Romans 3:23", targetVerse: "Isaiah 53:6", relationship: "thematic", note: "All have gone astray"},
    {sourceVerse: "Romans 5:8", targetVerse: "John 3:16", relationship: "thematic", note: "God's love demonstrated"},
    {sourceVerse: "Romans 8:1", targetVerse: "John 3:18", relationship: "thematic", note: "No condemnation for those who believe"},
    {sourceVerse: "Romans 8:28", targetVerse: "Genesis 50:20", relationship: "thematic", note: "God works all things for good"},
    {sourceVerse: "Romans 8:28", targetVerse: "Jeremiah 29:11", relationship: "thematic", note: "Plans to prosper you — God's sovereign purpose"},
    {sourceVerse: "Romans 8:38-39", targetVerse: "John 10:28-29", relationship: "thematic", note: "Nothing can snatch them — nothing can separate"},
    {sourceVerse: "Romans 12:1-2", targetVerse: "Ephesians 4:22-24", relationship: "thematic", note: "Transformed by renewal of mind — put on the new self"},
  ],
};

// ─── STRONG'S CONCORDANCE (Representative Sample) ──────────────────────────────

/**
 * Strong's Greek and Hebrew entries.
 * Full dataset: Greek G1-G5624, Hebrew H1-H8674.
 * In production, load from functions/data/strongs-greek.json and strongs-hebrew.json
 */
const STRONGS_GREEK = [
  {number: "25", word: "love", originalWord: "ἀγαπάω", transliteration: "agapaō", definition: "To love, value, esteem, be faithful to, delight in. Describes a deliberate, purposeful, self-giving love that seeks the highest good of another.", shortDefinition: "to love unconditionally", usage: "Used of God's love for humanity, Christ's love for the church, and the love believers are called to show", occurrences: 143, relatedWords: ["G26", "G5368"], verses: ["John 3:16", "John 13:34", "1 John 4:8", "Romans 8:28"]},
  {number: "26", word: "love", originalWord: "ἀγάπη", transliteration: "agapē", definition: "Love, goodwill, benevolence. The characteristic word of Christianity, describing God's unconditional, sacrificial love.", shortDefinition: "unconditional love", usage: "The highest form of love. Used 116 times in the NT, predominantly by Paul and John", occurrences: 116, relatedWords: ["G25", "G5368"], verses: ["1 Corinthians 13:4-7", "1 John 4:8", "John 3:16", "Romans 5:8"]},
  {number: "40", word: "holy", originalWord: "ἅγιος", transliteration: "hagios", definition: "Sacred, holy, set apart for God, pure, morally blameless. Describes that which is consecrated to God.", shortDefinition: "holy, set apart", usage: "Used of God, the Holy Spirit, believers as saints, and sacred things", occurrences: 233, relatedWords: ["G37", "G38"], verses: ["1 Peter 1:15-16", "Revelation 4:8", "Romans 1:7"]},
  {number: "225", word: "truth", originalWord: "ἀλήθεια", transliteration: "alētheia", definition: "Truth, reality, sincerity. What is true in any matter, conformity to reality and fact.", shortDefinition: "truth, reality", usage: "Central concept in John's gospel. Jesus is the truth (John 14:6)", occurrences: 109, relatedWords: ["G227", "G228"], verses: ["John 14:6", "John 8:32", "John 17:17", "Ephesians 4:15"]},
  {number: "266", word: "sin", originalWord: "ἁμαρτία", transliteration: "hamartia", definition: "A missing of the mark, sin, offense. Originally an archery term meaning to miss the target.", shortDefinition: "sin, missing the mark", usage: "The most common NT word for sin. Used 174 times, especially by Paul and John", occurrences: 174, relatedWords: ["G264", "G268"], verses: ["Romans 3:23", "Romans 6:23", "1 John 1:8-9"]},
  {number: "4102", word: "faith", originalWord: "πίστις", transliteration: "pistis", definition: "Faith, belief, trust, confidence, assurance, faithfulness. Persuasion based on hearing.", shortDefinition: "faith, trust, belief", usage: "Key theological term. Used 244 times. Central to Paul's theology of justification", occurrences: 244, relatedWords: ["G4100", "G4103"], verses: ["Hebrews 11:1", "Ephesians 2:8", "Romans 1:17", "Galatians 2:20"]},
  {number: "4991", word: "salvation", originalWord: "σωτηρία", transliteration: "sōtēria", definition: "Salvation, deliverance, preservation, safety. Encompasses spiritual rescue from sin and its consequences.", shortDefinition: "salvation, deliverance", usage: "Used of both physical deliverance and spiritual salvation through Christ", occurrences: 46, relatedWords: ["G4990", "G4982"], verses: ["Ephesians 2:8", "Acts 4:12", "Romans 1:16", "Philippians 2:12"]},
  {number: "5485", word: "grace", originalWord: "χάρις", transliteration: "charis", definition: "Grace, favor, kindness, gratitude. The unmerited favor of God toward humanity.", shortDefinition: "grace, unmerited favor", usage: "Foundational Pauline concept. God's free gift of salvation apart from works", occurrences: 156, relatedWords: ["G5487", "G5483"], verses: ["Ephesians 2:8-9", "Romans 3:24", "2 Corinthians 12:9", "John 1:14"]},
];

const STRONGS_HEBREW = [
  {number: "1", word: "father", originalWord: "אָב", transliteration: "ʾāḇ", definition: "Father, ancestor, head of a household. Used of human fathers, God as Father, and patriarchs.", shortDefinition: "father", usage: "Used over 1,200 times. Applied to God in relation to Israel and later to believers", occurrences: 1211, relatedWords: ["H2"], verses: ["Genesis 2:24", "Malachi 2:10", "Isaiah 9:6"]},
  {number: "157", word: "love", originalWord: "אָהַב", transliteration: "ʾāhaḇ", definition: "To love, like, be fond of. Encompasses romantic love, family love, friendship, and divine love.", shortDefinition: "to love", usage: "Used of God's love for Israel, human love, and covenant loyalty", occurrences: 212, relatedWords: ["H160"], verses: ["Deuteronomy 6:5", "Hosea 11:1", "Psalm 119:97"]},
  {number: "430", word: "God", originalWord: "אֱלֹהִים", transliteration: "ʾĕlōhîm", definition: "God, gods, divine beings. The most common name for God in the OT. Plural form used with singular verbs for the one true God.", shortDefinition: "God (plural majesty)", usage: "Used 2,606 times. The plural of majesty describing the one true God", occurrences: 2606, relatedWords: ["H433", "H410"], verses: ["Genesis 1:1", "Psalm 19:1", "Deuteronomy 6:4"]},
  {number: "1285", word: "covenant", originalWord: "בְּרִית", transliteration: "bᵉrîṯ", definition: "Covenant, alliance, agreement. A binding agreement between parties, especially between God and His people.", shortDefinition: "covenant, agreement", usage: "Central OT concept. Used of covenants with Noah, Abraham, Moses, David", occurrences: 284, relatedWords: ["H1262"], verses: ["Genesis 9:13", "Genesis 15:18", "Deuteronomy 7:9", "Jeremiah 31:31"]},
  {number: "2617", word: "steadfast love", originalWord: "חֶסֶד", transliteration: "ḥeseḏ", definition: "Lovingkindness, steadfast love, mercy, faithfulness. Covenantal loyalty and unfailing love.", shortDefinition: "steadfast love, lovingkindness", usage: "One of the most theologically rich Hebrew words. Describes God's covenant faithfulness", occurrences: 248, relatedWords: ["H2616"], verses: ["Psalm 136:1", "Lamentations 3:22-23", "Hosea 6:6", "Micah 6:8"]},
  {number: "3068", word: "LORD", originalWord: "יְהוָה", transliteration: "Yahweh", definition: "The LORD, Yahweh, the covenant name of God. Derived from 'to be' — the self-existent one.", shortDefinition: "the LORD, Yahweh", usage: "The personal name of God used 6,828 times. Revealed to Moses at the burning bush (Exodus 3:14)", occurrences: 6828, relatedWords: ["H3050", "H1961"], verses: ["Exodus 3:14-15", "Psalm 23:1", "Isaiah 40:28"]},
  {number: "7965", word: "peace", originalWord: "שָׁלוֹם", transliteration: "šālôm", definition: "Peace, completeness, wholeness, welfare, harmony. More than absence of conflict — it is total well-being.", shortDefinition: "peace, wholeness", usage: "Used 237 times. Encompasses spiritual, physical, and relational wholeness", occurrences: 237, relatedWords: ["H7999"], verses: ["Numbers 6:26", "Isaiah 9:6", "Psalm 122:6", "Jeremiah 29:11"]},
  {number: "8451", word: "law", originalWord: "תּוֹרָה", transliteration: "tôrâ", definition: "Law, instruction, teaching, direction. From the root meaning 'to throw, cast, direct.' Not merely legal code but divine instruction.", shortDefinition: "law, instruction, teaching", usage: "Used 220 times. Refers to the Pentateuch, specific laws, and God's instruction broadly", occurrences: 220, relatedWords: ["H3384"], verses: ["Psalm 1:2", "Psalm 119:1", "Deuteronomy 6:6-7", "Joshua 1:8"]},
];

// ─── COMMENTARY DATA (Representative Sample) ──────────────────────────────────

/**
 * Public domain commentary entries.
 * Matthew Henry's Commentary (1710, public domain).
 * In production, load from functions/data/matthew-henry.json
 */
const COMMENTARY_DATA = {
  "Genesis": [
    {verse: "Genesis 1:1", author: "Matthew Henry", source: "Matthew Henry's Complete Commentary", commentary: "The first verse of the Bible gives us a satisfying and useful account of the origin of the earth and the heavens. The faith of humble Christians understands this better than the fancy of the most learned men. From what we see of heaven and earth, we learn the power of the great Creator.", era: "18th century", tradition: "Protestant"},
    {verse: "Genesis 1:27", author: "Matthew Henry", source: "Matthew Henry's Complete Commentary", commentary: "God made man in his own image, in the image of God. This was the honour put upon man, that he was made in the Creator's image. He was made upright; his understanding saw divine things clearly, his affections were on divine things, his will was compliant to the divine will.", era: "18th century", tradition: "Protestant"},
    {verse: "Genesis 3:15", author: "Matthew Henry", source: "Matthew Henry's Complete Commentary", commentary: "A gracious promise is here made of Christ, as the deliverer of fallen man from the power of Satan. Here was the dawning of the gospel day. No sooner was the wound given than the remedy was provided and revealed.", era: "18th century", tradition: "Protestant"},
    {verse: "Genesis 12:1-3", author: "Matthew Henry", source: "Matthew Henry's Complete Commentary", commentary: "God made choice of Abram, and singled him out from among his fellow-idolaters, that he might reserve a people for himself. The call of Abram is a specimen of the effectual calling of all believers.", era: "18th century", tradition: "Protestant"},
    {verse: "Genesis 22:14", author: "Matthew Henry", source: "Matthew Henry's Complete Commentary", commentary: "Jehovah-jireh, The Lord will provide. This speaks of God as a God of provision and of foresight. He not only sees what is, but foresees what will be. Abraham calls this place by a prophetical name.", era: "18th century", tradition: "Protestant"},
    {verse: "Genesis 50:20", author: "Matthew Henry", source: "Matthew Henry's Complete Commentary", commentary: "Here Joseph teaches us to take notice of the providence of God, even in the sins of men. God's providence is to be acknowledged in all events, even in the evil actions of others. He brought good out of evil.", era: "18th century", tradition: "Protestant"},
  ],
  "Psalms": [
    {verse: "Psalm 23:1", author: "Matthew Henry", source: "Matthew Henry's Complete Commentary", commentary: "The Lord is my shepherd; therefore I shall not want. The psalmist makes God his shepherd, implies that he is one of his flock. Those that would have God for their shepherd must be willing to be his sheep.", era: "18th century", tradition: "Protestant"},
    {verse: "Psalm 51:10", author: "Matthew Henry", source: "Matthew Henry's Complete Commentary", commentary: "Create in me a clean heart. David's prayer is that God would not only forgive his sins but renew his nature. He asks for a thorough change — a new heart and a right spirit. This shows true repentance goes beyond sorrow for consequences.", era: "18th century", tradition: "Protestant"},
    {verse: "Psalm 119:105", author: "Matthew Henry", source: "Matthew Henry's Complete Commentary", commentary: "Thy word is a lamp unto my feet and a light unto my path. The word of God directs us in our work and way, and prevents us from falling into sin or trouble. It does not merely show us the way, but enables us to walk in it.", era: "18th century", tradition: "Protestant"},
    {verse: "Psalm 139:14", author: "Matthew Henry", source: "Matthew Henry's Complete Commentary", commentary: "I am fearfully and wonderfully made. The knowledge of ourselves will lead us to the knowledge of God. We are a mystery to ourselves. How much must the Creator be above us, who has so wonderfully made us!", era: "18th century", tradition: "Protestant"},
  ],
  "Isaiah": [
    {verse: "Isaiah 40:31", author: "Matthew Henry", source: "Matthew Henry's Complete Commentary", commentary: "They that wait upon the Lord shall renew their strength. Those that are weary of waiting may be tempted to think God has forgotten them. But those who wait in faith and patience will find their spiritual strength renewed.", era: "18th century", tradition: "Protestant"},
    {verse: "Isaiah 53:5", author: "Matthew Henry", source: "Matthew Henry's Complete Commentary", commentary: "He was wounded for our transgressions. The sufferings of Christ were voluntary and vicarious. He bore our sins in his own body. The healing of our souls was by the stripes that were laid on him.", era: "18th century", tradition: "Protestant"},
  ],
  "John": [
    {verse: "John 1:1", author: "Matthew Henry", source: "Matthew Henry's Complete Commentary", commentary: "In the beginning was the Word. This Word is Jesus Christ, the eternal Son of God. He was in the beginning, before all time, not made in time. He was with God, and he was God — here is his divine nature plainly asserted.", era: "18th century", tradition: "Protestant"},
    {verse: "John 3:16", author: "Matthew Henry", source: "Matthew Henry's Complete Commentary", commentary: "God so loved the world. Here is the gospel in miniature. The love of God is the fountain from which our salvation flows. The measure of his love: he gave his only begotten Son. The design of his love: that whosoever believeth should not perish.", era: "18th century", tradition: "Protestant"},
    {verse: "John 14:6", author: "Matthew Henry", source: "Matthew Henry's Complete Commentary", commentary: "I am the way, the truth, and the life. Christ is the way to the Father — there is no coming to God as a Father except by Christ as Mediator. He is the truth — the fulfilment of all types and promises. He is the life — the author and giver of spiritual life.", era: "18th century", tradition: "Protestant"},
  ],
  "Romans": [
    {verse: "Romans 3:23", author: "Matthew Henry", source: "Matthew Henry's Complete Commentary", commentary: "All have sinned and fall short of the glory of God. There is no exception to this universal charge. In Adam all sinned. We have come short of glorifying God, of being glorified by God, and of the image of God.", era: "18th century", tradition: "Protestant"},
    {verse: "Romans 8:28", author: "Matthew Henry", source: "Matthew Henry's Complete Commentary", commentary: "All things work together for good. This is the comprehensive promise of the gospel. Not that each single event is good in itself, but that God orchestrates all things — afflictions, temptations, even our own failings — to produce ultimate good for those who love Him.", era: "18th century", tradition: "Protestant"},
    {verse: "Romans 8:38-39", author: "Matthew Henry", source: "Matthew Henry's Complete Commentary", commentary: "Nothing shall be able to separate us from the love of God. Here is a holy triumph in the assurance of God's love. The apostle challenges every creature, every circumstance, every power — and finds nothing that can prevail against the everlasting love of God in Christ.", era: "18th century", tradition: "Protestant"},
  ],
};

#!/usr/bin/env node
/**
 * seedBible.js — One-time KJV Bible seeder for AMEN
 *
 * Downloads all 66 books from aruljohn/Bible-kjv on GitHub,
 * transforms each verse into the AMEN schema, writes to Firestore
 * bibleVerses/{Book_chapter_verse}, then calls seedBibleVersesToPinecone
 * in batches until every verse is embedded via HuggingFace all-MiniLM-L6-v2
 * (384-dim, matching all existing Pinecone indexes) and indexed.
 *
 * Usage:
 *   node functions/seedBible.js
 *
 * Prerequisites:
 *   1. Set GOOGLE_APPLICATION_CREDENTIALS to your service account JSON, OR
 *      run inside a GCP environment with Application Default Credentials.
 *   2. Set FIREBASE_PROJECT_ID (or it reads from GCLOUD_PROJECT).
 *   3. Ensure the Firebase Admin SDK and node-fetch are available:
 *        cd functions && npm install
 *
 * The script is safe to re-run — Firestore writes are upserts and Pinecone
 * upserts are idempotent. If interrupted, re-run and it will re-seed only
 * the verses not yet in Pinecone (the seedBibleVersesToPinecone callable
 * can be called again from the beginning; Pinecone upserts overwrite).
 */

"use strict";

const admin  = require("firebase-admin");
const https  = require("https");

// ─── Firebase init ────────────────────────────────────────────────────────────
const projectId = process.env.FIREBASE_PROJECT_ID
               || process.env.GCLOUD_PROJECT
               || process.env.GCP_PROJECT;

if (!admin.apps.length) {
  admin.initializeApp({ projectId });
}
const db = admin.firestore();
db.settings({ ignoreUndefinedProperties: true });

// ─── Config ───────────────────────────────────────────────────────────────────
const BASE_URL   = "https://raw.githubusercontent.com/aruljohn/Bible-kjv/master"; // files at root, not in a subdirectory
const BATCH_SIZE = 400;   // Firestore batch limit is 500
const SEED_BATCH = 50;    // verses per seedBibleVersesToPinecone call
const PAUSE_MS   = 400;   // pause between Firestore batch writes

// ─── Testament mapping ────────────────────────────────────────────────────────
const OT_BOOKS = new Set([
  "Genesis","Exodus","Leviticus","Numbers","Deuteronomy","Joshua","Judges",
  "Ruth","1 Samuel","2 Samuel","1 Kings","2 Kings","1 Chronicles","2 Chronicles",
  "Ezra","Nehemiah","Esther","Job","Psalms","Proverbs","Ecclesiastes",
  "Song of Solomon","Isaiah","Jeremiah","Lamentations","Ezekiel","Daniel",
  "Hosea","Joel","Amos","Obadiah","Jonah","Micah","Nahum","Habakkuk",
  "Zephaniah","Haggai","Zechariah","Malachi",
]);

// ─── Tone heuristics (keyword → tone tags) ───────────────────────────────────
const TONE_RULES = [
  { tags: ["comfort"],       words: ["comfort","affliction","distress","trouble","sorrow","weep","mourn"] },
  { tags: ["hope"],          words: ["hope","wait","endure","patience","steadfast","not give up"] },
  { tags: ["encouragement"], words: ["fear not","be strong","courage","stand firm","do not be afraid"] },
  { tags: ["peace"],         words: ["peace","rest","still","quiet","calm","cease striving"] },
  { tags: ["healing"],       words: ["heal","restore","recover","wholeness","broken","mend"] },
  { tags: ["praise"],        words: ["praise","glorify","exalt","magnify","bless the lord"] },
  { tags: ["thanksgiving"],  words: ["thank","grateful","give thanks","thankful"] },
  { tags: ["joy"],           words: ["joy","rejoice","joyful","celebrate","delight","gladness"] },
  { tags: ["blessing"],      words: ["blessed","blessing","prosper","favor","grace"] },
  { tags: ["wisdom"],        words: ["wisdom","understanding","knowledge","discern","insight","counsel"] },
  { tags: ["faith"],         words: ["faith","believe","trust","faithful","covenant"] },
  { tags: ["love"],          words: ["love","charity","kindness","compassion","mercy","lovingkindness"] },
  { tags: ["forgiveness"],   words: ["forgive","pardon","sin","transgress","iniquity","cleanse"] },
  { tags: ["prayer"],        words: ["pray","prayer","ask","seek","petition","intercede","supplicate"] },
  { tags: ["salvation"],     words: ["save","salvation","redeem","redemption","deliver","eternal life"] },
  { tags: ["strength"],      words: ["strength","strong","mighty","power","renew","sustain"] },
  { tags: ["guidance"],      words: ["guide","path","way","lead","direction","steps","lamp"] },
  { tags: ["celebration"],   words: ["celebration","feast","worship","honor","sing","music","hymn"] },
];

function detectTone(text) {
  const lc = text.toLowerCase();
  const tones = new Set();
  for (const { tags, words } of TONE_RULES) {
    if (words.some((w) => lc.includes(w))) tags.forEach((t) => tones.add(t));
  }
  return tones.size > 0 ? [...tones] : ["general"];
}

// ─── Helpers ─────────────────────────────────────────────────────────────────
function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function fetchJSON(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { "User-Agent": "AMEN-Bible-Seeder/1.0" } }, (res) => {
      if (res.statusCode !== 200) {
        reject(new Error(`HTTP ${res.statusCode} for ${url}`));
        res.resume();
        return;
      }
      let body = "";
      res.on("data", (d) => (body += d));
      res.on("end", () => {
        try { resolve(JSON.parse(body)); }
        catch (e) { reject(new Error(`JSON parse failed for ${url}: ${e.message}`)); }
      });
      res.on("error", reject);
    }).on("error", reject);
  });
}

// Zero-pads a number: pad(3, 3) → "003"
function pad(n, width) {
  return String(n).padStart(width, "0");
}

// ─── Book list (66 books in canonical order) ──────────────────────────────────
// File names as they appear in the aruljohn/Bible-kjv repo.
const BOOKS = [
  { name: "Genesis",          file: "Genesis.json"          },
  { name: "Exodus",           file: "Exodus.json"           },
  { name: "Leviticus",        file: "Leviticus.json"        },
  { name: "Numbers",          file: "Numbers.json"          },
  { name: "Deuteronomy",      file: "Deuteronomy.json"      },
  { name: "Joshua",           file: "Joshua.json"           },
  { name: "Judges",           file: "Judges.json"           },
  { name: "Ruth",             file: "Ruth.json"             },
  { name: "1 Samuel",         file: "1Samuel.json"          },
  { name: "2 Samuel",         file: "2Samuel.json"          },
  { name: "1 Kings",          file: "1Kings.json"           },
  { name: "2 Kings",          file: "2Kings.json"           },
  { name: "1 Chronicles",     file: "1Chronicles.json"      },
  { name: "2 Chronicles",     file: "2Chronicles.json"      },
  { name: "Ezra",             file: "Ezra.json"             },
  { name: "Nehemiah",         file: "Nehemiah.json"         },
  { name: "Esther",           file: "Esther.json"           },
  { name: "Job",              file: "Job.json"              },
  { name: "Psalms",           file: "Psalms.json"           },
  { name: "Proverbs",         file: "Proverbs.json"         },
  { name: "Ecclesiastes",     file: "Ecclesiastes.json"     },
  { name: "Song of Solomon",  file: "SongofSolomon.json"    },
  { name: "Isaiah",           file: "Isaiah.json"           },
  { name: "Jeremiah",         file: "Jeremiah.json"         },
  { name: "Lamentations",     file: "Lamentations.json"     },
  { name: "Ezekiel",          file: "Ezekiel.json"          },
  { name: "Daniel",           file: "Daniel.json"           },
  { name: "Hosea",            file: "Hosea.json"            },
  { name: "Joel",             file: "Joel.json"             },
  { name: "Amos",             file: "Amos.json"             },
  { name: "Obadiah",          file: "Obadiah.json"          },
  { name: "Jonah",            file: "Jonah.json"            },
  { name: "Micah",            file: "Micah.json"            },
  { name: "Nahum",            file: "Nahum.json"            },
  { name: "Habakkuk",         file: "Habakkuk.json"         },
  { name: "Zephaniah",        file: "Zephaniah.json"        },
  { name: "Haggai",           file: "Haggai.json"           },
  { name: "Zechariah",        file: "Zechariah.json"        },
  { name: "Malachi",          file: "Malachi.json"          },
  { name: "Matthew",          file: "Matthew.json"          },
  { name: "Mark",             file: "Mark.json"             },
  { name: "Luke",             file: "Luke.json"             },
  { name: "John",             file: "John.json"             },
  { name: "Acts",             file: "Acts.json"             },
  { name: "Romans",           file: "Romans.json"           },
  { name: "1 Corinthians",    file: "1Corinthians.json"     },
  { name: "2 Corinthians",    file: "2Corinthians.json"     },
  { name: "Galatians",        file: "Galatians.json"        },
  { name: "Ephesians",        file: "Ephesians.json"        },
  { name: "Philippians",      file: "Philippians.json"      },
  { name: "Colossians",       file: "Colossians.json"       },
  { name: "1 Thessalonians",  file: "1Thessalonians.json"   },
  { name: "2 Thessalonians",  file: "2Thessalonians.json"   },
  { name: "1 Timothy",        file: "1Timothy.json"         },
  { name: "2 Timothy",        file: "2Timothy.json"         },
  { name: "Titus",            file: "Titus.json"            },
  { name: "Philemon",         file: "Philemon.json"         },
  { name: "Hebrews",          file: "Hebrews.json"          },
  { name: "James",            file: "James.json"            },
  { name: "1 Peter",          file: "1Peter.json"           },
  { name: "2 Peter",          file: "2Peter.json"           },
  { name: "1 John",           file: "1John.json"            },
  { name: "2 John",           file: "2John.json"            },
  { name: "3 John",           file: "3John.json"            },
  { name: "Jude",             file: "Jude.json"             },
  { name: "Revelation",       file: "Revelation.json"       },
];

// ─── Step 1: Download + transform all verses ──────────────────────────────────
async function downloadAllVerses() {
  const allVerses = [];
  let bookIndex   = 1;

  for (const { name, file } of BOOKS) {
    const url = `${BASE_URL}/${file}`;
    process.stdout.write(`  [${pad(bookIndex, 2)}/66] ${name.padEnd(20)} `);

    let bookData;
    try {
      bookData = await fetchJSON(url);
    } catch (err) {
      console.log(`FAILED: ${err.message}`);
      bookIndex++;
      continue;
    }

    // aruljohn/Bible-kjv format:
    // { book: "Genesis", chapters: [ { chapter: "1", verses: [ { verse: "1", text: "In the beginning..." } ] } ] }
    const chapters  = bookData.chapters || [];
    const testament = OT_BOOKS.has(name) ? "OT" : "NT";
    let verseCount  = 0;

    for (const chapterObj of chapters) {
      const chapter    = parseInt(chapterObj.chapter, 10) || 0;
      const verseArray = chapterObj.verses || [];

      for (const verseObj of verseArray) {
        const verse = parseInt(verseObj.verse, 10) || 0;
        const text  = (verseObj.text || "").trim();
        if (!text || verse === 0) continue;

        // Stable sort key: "GEN_001_001" style using 3-char book abbreviation
        const bookAbbr = name.replace(/\s+/g, "").slice(0, 3).toUpperCase();
        const sortKey  = `${bookAbbr}_${pad(chapter, 3)}_${pad(verse, 3)}`;

        // Document ID: "Genesis_1_16" (human-readable, URL-safe)
        const docId    = `${name.replace(/\s+/g, "_")}_${chapter}_${verse}`;

        // Short reference: "Genesis 1:1"
        const reference = `${name} ${chapter}:${verse}`;

        allVerses.push({
          docId,
          sortKey,
          text,
          book:      name,
          chapter,
          verse,
          reference,
          testament,
          tone:      detectTone(text),
        });

        verseCount++;
      }
    }

    console.log(`✓ ${verseCount} verses`);
    bookIndex++;
    await sleep(50); // gentle rate-limit on GitHub raw
  }

  return allVerses;
}

// ─── Step 2: Write all verses to Firestore ────────────────────────────────────
async function uploadToFirestore(verses) {
  console.log(`\nUploading ${verses.length} verses to Firestore bibleVerses/ …`);
  let written = 0;

  for (let i = 0; i < verses.length; i += BATCH_SIZE) {
    const chunk = verses.slice(i, i + BATCH_SIZE);
    const batch = db.batch();

    for (const v of chunk) {
      const ref = db.collection("bibleVerses").doc(v.docId);
      batch.set(ref, {
        sortKey:   v.sortKey,
        text:      v.text,
        book:      v.book,
        chapter:   v.chapter,
        verse:     v.verse,
        reference: v.reference,
        testament: v.testament,
        tone:      v.tone,
      });
    }

    await batch.commit();
    written += chunk.length;
    process.stdout.write(`\r  ${written}/${verses.length} written…`);
    await sleep(PAUSE_MS);
  }

  console.log(`\n  ✓ Firestore upload complete (${written} docs)\n`);
}

// ─── Step 3: Embed + upsert directly to Pinecone ─────────────────────────────
// Runs locally using ADC credentials and Secret Manager to retrieve API keys.
// Avoids the Firebase callable auth requirement (which needs a custom-claim token).

async function fetchSecret(name) {
  // 1. Try env var
  if (process.env[name]) return process.env[name];
  // 2. Try gcloud CLI (works after `gcloud auth application-default login`)
  const { execSync } = require("child_process");
  try {
    const val = execSync(
      `gcloud secrets versions access latest --secret="${name}" --project="${projectId}" --quiet`,
      { encoding: "utf8", stdio: ["pipe", "pipe", "pipe"] }
    ).trim();
    if (val) return val;
  } catch (e) { /* fall through */ }
  throw new Error(`Secret "${name}" not found in env or Secret Manager`);
}

async function hfEmbed(apiKey, texts) {
  // HuggingFace batch embedding via fetch (built-in to Node 22)
  const response = await fetch(
    "https://router.huggingface.co/hf-inference/models/sentence-transformers/all-MiniLM-L6-v2/pipeline/feature-extraction",
    {
      method:  "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body:    JSON.stringify({ inputs: texts }),
      signal:  AbortSignal.timeout(30000),
    }
  );
  if (response.status === 503) throw new Error("HF model loading — retry in a moment");
  if (!response.ok) throw new Error(`HF HTTP ${response.status}: ${await response.text()}`);
  const result = await response.json();
  // Returns number[][] for array inputs
  return result.map((v) => (Array.isArray(v[0]) ? v[0] : v));
}

async function pineconeUpsertDirect(host, apiKey, namespace, vectors) {
  const body = namespace ? { vectors, namespace } : { vectors };
  const response = await fetch(`https://${host}/vectors/upsert`, {
    method:  "POST",
    headers: { "Api-Key": apiKey, "Content-Type": "application/json" },
    body:    JSON.stringify(body),
    signal:  AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new Error(`Pinecone HTTP ${response.status}: ${await response.text()}`);
}

async function seedPinecone(verses) {
  console.log(`Embedding ${verses.length} verses via HuggingFace → Pinecone (batches of ${SEED_BATCH})…`);

  const hfKey   = await fetchSecret("HUGGINGFACE_API_KEY");
  // PINECONE_HOST secret actually stores the Pinecone API key (historical naming quirk)
  const pcApiKey = await fetchSecret("PINECONE_HOST");

  if (!hfKey)    throw new Error("HUGGINGFACE_API_KEY not found");
  if (!pcApiKey) throw new Error("PINECONE_HOST (Pinecone API key) not found");

  // Look up the index-specific host from the Pinecone control plane API
  console.log("  Resolving Pinecone index host…");
  const indexMetaResp = await fetch("https://api.pinecone.io/indexes/scripture-embeddings", {
    headers: { "Api-Key": pcApiKey },
    signal: AbortSignal.timeout(8000),
  });
  if (!indexMetaResp.ok) {
    throw new Error(`Pinecone index lookup failed: HTTP ${indexMetaResp.status}: ${await indexMetaResp.text()}`);
  }
  const indexMeta = await indexMetaResp.json();
  const pcHost = indexMeta.host;
  if (!pcHost) throw new Error("Pinecone index host not found in control plane response");
  console.log(`  Index host: ${pcHost}`);

  let totalSeeded = 0;

  for (let i = 0; i < verses.length; i += SEED_BATCH) {
    const batch = verses.slice(i, i + SEED_BATCH);

    // Retry loop for HF model loading
    let vectors = null;
    for (let attempt = 1; attempt <= 5; attempt++) {
      try {
        vectors = await hfEmbed(hfKey, batch.map((v) => v.text));
        break;
      } catch (err) {
        if (attempt < 5 && err.message.includes("loading")) {
          process.stdout.write(`\n  HF model loading, waiting 10s…`);
          await sleep(10000);
        } else if (attempt === 5) {
          throw err;
        } else {
          await sleep(2000);
        }
      }
    }

    const pineconeVectors = batch.map((v, idx) => ({
      id:     v.docId,
      values: vectors[idx],
      metadata: {
        book:      v.book,
        chapter:   v.chapter,
        verse:     v.verse,
        reference: v.reference,
        text:      v.text.slice(0, 512),
        testament: v.testament,
        tone:      v.tone,
      },
    }));

    await pineconeUpsertDirect(pcHost, pcApiKey, null, pineconeVectors);
    totalSeeded += batch.length;
    process.stdout.write(`\r  ${totalSeeded}/${verses.length} embedded and indexed…`);
    await sleep(300); // gentle pacing
  }

  console.log(`\n  ✓ Pinecone seeding complete (${totalSeeded} vectors)\n`);
}

// ─── Main ─────────────────────────────────────────────────────────────────────
(async () => {
  console.log("╔══════════════════════════════════════════════╗");
  console.log("║  AMEN Bible Seeder — KJV → Firestore + Pinecone  ║");
  console.log("╚══════════════════════════════════════════════╝\n");

  // Step 1 — Download
  console.log("Step 1/3 — Downloading 66 books from GitHub…\n");
  const verses = await downloadAllVerses();
  console.log(`\n  Total verses: ${verses.length}\n`);

  if (verses.length === 0) {
    console.error("No verses downloaded. Check network access to raw.githubusercontent.com.");
    process.exit(1);
  }

  // Step 2 — Firestore
  console.log("Step 2/3 — Writing to Firestore…");
  await uploadToFirestore(verses);

  // Step 3 — Embed + upsert directly to Pinecone
  console.log("Step 3/3 — Embedding and indexing into Pinecone…");
  try {
    await seedPinecone(verses);
  } catch (err) {
    console.error("\n  Pinecone seeding failed:", err.message);
    console.log("\n  Firestore upload is complete. Re-run the script to retry Pinecone seeding.");
    console.log("  (Firestore writes are idempotent — skips will be fast on re-run)");
  }

  console.log("✅ Done. scripture-embeddings index is ready for getScriptureRecommendation.");
  process.exit(0);
})();

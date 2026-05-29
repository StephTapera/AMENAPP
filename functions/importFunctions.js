/**
 * importFunctions.js
 * AMEN App — Data-Export Import Pipeline Cloud Functions
 *
 * Functions exported:
 *   ingestImportArchive    — Storage trigger: parse uploaded archive → write ImportCandidates
 *   classifyImportCandidates — Firestore trigger: run Berean conversion gate when status=classifying
 *
 * Flow:
 *   iOS uploads archive.zip → Storage trigger fires ingestImportArchive
 *   → sets status=parsing, extracts archive, writes candidates, sets status=classifying
 *   → Firestore trigger fires classifyImportCandidates
 *   → runs cheap pre-filter + Berean LLM on text-bearing items
 *   → writes bereanClassification to each candidate
 *   → sets status=ready (iOS review UI unlocks)
 *
 * Deploy ONLY these functions:
 *   firebase deploy --only functions:ingestImportArchive,functions:classifyImportCandidates
 */

"use strict";

const {onObjectFinalized} = require("firebase-functions/v2/storage");
const {onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");
const os = require("os");
const crypto = require("crypto");

const REGION = "us-west1"; // must match Storage bucket region
const STORAGE_BUCKET = "amen-5e359.firebasestorage.app";
const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");

// ── Latin-1 mojibake fix ────────────────────────────────────────────────────
// Meta DYI archives double-encode UTF-8 as latin-1 (e.g. "Ã©" → "é").
// Re-interpret the latin-1 string as UTF-8 bytes.
//
// Unit test:
//   const original = "café ☕";
//   const corrupted = Buffer.from(original, "utf8").toString("latin1");
//   assert(fixMojibake(corrupted) === original);
function fixMojibake(str) {
  if (typeof str !== "string") return str;
  try {
    const bytes = Buffer.from(str, "latin1");
    const decoded = bytes.toString("utf8");
    // Only use the decoded version if it round-trips cleanly (avoids breaking
    // strings that were legitimately encoded as latin-1).
    if (Buffer.from(decoded, "utf8").toString("latin1") === str) {
      return decoded;
    }
    return str;
  } catch {
    return str;
  }
}

// ── Archive structure discovery ─────────────────────────────────────────────
// Returns an array of { text, timestamp, mediaLocalPaths, sourceType } objects.
// Discovery is runtime — no hardcoded path assumptions.
function extractItemsFromArchive(zipEntries, tmpDir) {
  const items = [];

  // Build a lookup map: normalizedPath → entry for fast media resolution
  const entryByPath = {};
  for (const entry of zipEntries) {
    entryByPath[entry.entryName.toLowerCase()] = entry;
  }

  // Find JSON files (skip known metadata files)
  const SKIP_NAMES = new Set([
    "manifest.json", "index.json", "ads_information.json",
    "account_information.json", "personal_information.json",
    "profile_information.json", "settings.json", "autofill_information.json",
    "account_privacy_changes.json", "login_activity.json",
    "liked_posts.json", "saved.json", "profile_photos.json",
  ]);

  const jsonEntries = zipEntries.filter((e) =>
    e.entryName.endsWith(".json") &&
    !e.isDirectory &&
    !SKIP_NAMES.has(path.basename(e.entryName).toLowerCase())
  );

  for (const entry of jsonEntries) {
    try {
      const raw = entry.getData().toString("utf8");
      const parsed = JSON.parse(raw);
      const extracted = extractPostsFromJSON(parsed);
      for (const post of extracted) {
        // Resolve media URIs to local temp files
        const mediaLocalPaths = [];
        for (const uri of (post.mediaURIs || [])) {
          const key = uri.toLowerCase();
          const mediaEntry = entryByPath[key];
          if (mediaEntry && !mediaEntry.isDirectory) {
            const localPath = path.join(tmpDir, `media_${crypto.randomBytes(8).toString("hex")}_${path.basename(uri)}`);
            try {
              fs.writeFileSync(localPath, mediaEntry.getData());
              mediaLocalPaths.push(localPath);
            } catch {
              // skip unreadable media
            }
          }
        }
        items.push({
          text: post.text,
          timestamp: post.timestamp,
          mediaLocalPaths,
          sourceType: post.sourceType || "post",
        });
      }
    } catch {
      // Silently skip malformed JSON entries
    }
  }

  return items;
}

// Flexible JSON post extractor — handles multiple DYI schema shapes.
function extractPostsFromJSON(json) {
  const posts = [];

  function makePost(dict) {
    // ── Timestamp ──
    const tsKeys = ["creation_timestamp", "timestamp", "taken_at", "date", "created_at"];
    let ts = null;
    for (const k of tsKeys) {
      const v = dict[k];
      if (typeof v === "number") { ts = new Date(v * 1000); break; }
      if (typeof v === "string") {
        const d = new Date(v);
        if (!isNaN(d.getTime())) { ts = d; break; }
      }
    }

    // ── Text ──
    const textKeys = ["title", "text", "caption", "content", "description", "post"];
    let text = null;
    for (const k of textKeys) {
      if (typeof dict[k] === "string" && dict[k].trim()) {
        text = fixMojibake(dict[k].trim()); break;
      }
    }
    // Instagram-style nested: data: [{post: "text"}]
    if (!text && Array.isArray(dict.data)) {
      for (const entry of dict.data) {
        if (typeof entry.post === "string" && entry.post.trim()) {
          text = fixMojibake(entry.post.trim()); break;
        }
      }
    }

    // ── Media URIs ──
    const mediaURIs = [];
    if (Array.isArray(dict.media)) {
      for (const m of dict.media) {
        if (typeof m.uri === "string") mediaURIs.push(m.uri);
      }
    } else if (typeof dict.uri === "string") {
      mediaURIs.push(dict.uri);
    }

    if (!text && !mediaURIs.length) return null;

    // ── Source type heuristic ──
    let sourceType = "post";
    const entryPath = (dict._sourcePath || "").toLowerCase();
    if (entryPath.includes("reel")) sourceType = "reel";
    else if (entryPath.includes("stor")) sourceType = "story";
    else if (entryPath.includes("thread")) sourceType = "thread";
    else if (entryPath.includes("note")) sourceType = "note";

    return { text, timestamp: ts ? ts.toISOString() : null, mediaURIs, sourceType };
  }

  if (Array.isArray(json)) {
    for (const item of json) {
      const p = makePost(item);
      if (p) posts.push(p);
    }
  } else if (json && typeof json === "object") {
    const arrayKeys = ["posts", "content", "media", "items", "data", "threads_and_replies"];
    let handled = false;
    for (const k of arrayKeys) {
      if (Array.isArray(json[k])) {
        for (const item of json[k]) {
          const p = makePost(item);
          if (p) posts.push(p);
        }
        handled = true;
        break;
      }
    }
    if (!handled) {
      const p = makePost(json);
      if (p) posts.push(p);
    }
  }

  return posts;
}

// ── ingestImportArchive ────────────────────────────────────────────────────

exports.ingestImportArchive = onObjectFinalized(
  {
    region: REGION,
    bucket: STORAGE_BUCKET,
    timeoutSeconds: 540,
    memory: "2GiB",
  },
  async (event) => {
    const filePath = event.data.name; // e.g. "imports/{uid}/{jobId}/archive.zip"
    if (!filePath) return null;

    // Only process archive.zip uploads
    if (!filePath.endsWith("/archive.zip")) return null;
    if (!filePath.startsWith("imports/")) return null;

    const parts = filePath.split("/");
    // Expected: imports / {uid} / {jobId} / archive.zip  → 4 parts
    if (parts.length !== 4) return null;

    const uid = parts[1];
    const jobId = parts[2];

    const db = admin.firestore();
    const storage = admin.storage();
    const jobRef = db.collection("importJobs").doc(uid).collection("jobs").doc(jobId);

    console.log(`[ingestImportArchive] Starting for uid=${uid} jobId=${jobId}`);

    // Mark parsing
    await jobRef.update({ status: "parsing" });

    const tmpDir = os.tmpdir();
    const localZip = path.join(tmpDir, `import_${jobId}.zip`);

    try {
      // ── Download archive from Storage ────────────────────────────────────
      await storage.bucket(STORAGE_BUCKET).file(filePath).download({ destination: localZip });

      // Enforce size cap (600 MB)
      const stat = fs.statSync(localZip);
      if (stat.size > 600 * 1024 * 1024) {
        throw new Error("Archive exceeds 600 MB limit for v1. Request a smaller date range from the platform.");
      }

      // ── Extract with adm-zip ──────────────────────────────────────────────
      const AdmZip = require("adm-zip");
      const zip = new AdmZip(localZip);
      const entries = zip.getEntries();

      console.log(`[ingestImportArchive] Extracted ${entries.length} entries from archive`);

      const items = extractItemsFromArchive(entries, tmpDir);
      console.log(`[ingestImportArchive] Found ${items.length} content items`);

      // Update found count
      await jobRef.update({ "counts.found": items.length });

      // ── Write candidates + upload media ──────────────────────────────────
      let candidateCount = 0;
      const candidatesRef = jobRef.collection("candidates");

      for (const item of items) {
        const candidateId = crypto.randomBytes(16).toString("hex");
        const mediaRefs = [];

        // Upload media files to Storage
        for (const localMediaPath of item.mediaLocalPaths.slice(0, 4)) {
          try {
            const ext = path.extname(localMediaPath).toLowerCase();
            const allowed = [".jpg", ".jpeg", ".png", ".heic", ".mp4", ".mov"];
            if (!allowed.includes(ext)) continue;

            const mediaFilename = `${candidateId}_${path.basename(localMediaPath)}`;
            const storagePath = `imports/${uid}/${jobId}/media/${mediaFilename}`;
            await storage.bucket(STORAGE_BUCKET).upload(localMediaPath, {
              destination: storagePath,
              metadata: {
                contentType: ext.includes("mp4") || ext.includes("mov") ? "video/mp4" : "image/jpeg",
              },
            });
            mediaRefs.push(storagePath);
          } catch (mediaErr) {
            console.warn(`[ingestImportArchive] Media upload failed: ${mediaErr.message}`);
          }
        }

        const candidateData = {
          sourceType: item.sourceType,
          originalText: (item.text || "").slice(0, 1000),
          mediaRefs,
          originalTimestamp: item.timestamp
            ? admin.firestore.Timestamp.fromDate(new Date(item.timestamp))
            : null,
          bereanClassification: null,   // filled by classifyImportCandidates
          provenance: {
            importedFrom: detectSourceFromPath(filePath),
            aiAssisted: false,
          },
          userDecision: "pending",
        };

        await candidatesRef.doc(candidateId).set(candidateData);
        candidateCount++;
      }

      // ── Delete raw archive (data minimization) ────────────────────────────
      try {
        await storage.bucket(STORAGE_BUCKET).file(filePath).delete();
        console.log(`[ingestImportArchive] Deleted raw archive ${filePath}`);
      } catch (deleteErr) {
        console.warn(`[ingestImportArchive] Could not delete archive: ${deleteErr.message}`);
      }

      // ── Update job: ready for classification ──────────────────────────────
      await jobRef.update({
        "counts.candidates": candidateCount,
        status: "classifying",
      });

      console.log(`[ingestImportArchive] Done. ${candidateCount} candidates written.`);
    } catch (err) {
      console.error(`[ingestImportArchive] Error: ${err.message}`);
      const userSafeMessage = err.message.includes("limit")
        ? err.message
        : "Failed to process archive. Please try re-exporting in JSON format (not HTML).";
      await jobRef.update({ status: "failed", error: userSafeMessage });
    } finally {
      // Cleanup temp files
      try { fs.unlinkSync(localZip); } catch { /* ignore */ }
    }

    return null;
  }
);

function detectSourceFromPath(filePath) {
  // Could be improved by reading the archive manifest in a real v2
  return "unknown";
}

// ── classifyImportCandidates ───────────────────────────────────────────────

exports.classifyImportCandidates = onDocumentUpdated(
  {
    document: "importJobs/{uid}/jobs/{jobId}",
    region: REGION,
    secrets: [ANTHROPIC_API_KEY],
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    // Only trigger when status transitions TO classifying
    if (before.status === "classifying" || after.status !== "classifying") return null;

    const uid = event.params.uid;
    const jobId = event.params.jobId;

    const db = admin.firestore();
    const candidatesRef = db.collection("importJobs").doc(uid).collection("jobs").doc(jobId).collection("candidates");

    console.log(`[classifyImportCandidates] Starting for uid=${uid} jobId=${jobId}`);

    const snap = await candidatesRef.get();
    const candidates = snap.docs.map((d) => ({ id: d.id, ...d.data() }));

    let classified = 0;

    for (const candidate of candidates) {
      const classification = await classifyCandidate(candidate);
      await candidatesRef.doc(candidate.id).update({
        bereanClassification: classification,
      });
      classified++;
    }

    // Mark job ready
    await db.collection("importJobs").doc(uid).collection("jobs").doc(jobId).update({
      status: "ready",
    });

    console.log(`[classifyImportCandidates] Classified ${classified} candidates. Job ready.`);
    return null;
  }
);

// ── Cheap pre-filter + Berean classification ────────────────────────────────

async function classifyCandidate(candidate) {
  const text = (candidate.originalText || "").trim();
  const hasMedia = Array.isArray(candidate.mediaRefs) && candidate.mediaRefs.length > 0;

  // ── Cheap pre-filter (no LLM) ──────────────────────────────────────────
  // Skip pure wordless media — not worth running the model
  if (!text && hasMedia) {
    return {
      type: "mundane",
      keepRecommended: false,
      performativeFlag: false,
      reconsecratedDraft: "",
    };
  }

  // Skip near-empty text
  if (text.length < 10) {
    return {
      type: "mundane",
      keepRecommended: false,
      performativeFlag: false,
      reconsecratedDraft: "",
    };
  }

  // Simple heuristic performative flags (pre-filter before LLM)
  const performativePatterns = [
    /\b(follow|like|share|comment|link in bio|swipe up|dm me for|collab|#ad|#sponsored)\b/i,
    /^\s*[🙏😍🔥💯]+\s*$/, // pure emoji posts
    /\bcheck out my\b/i,
    /\b\d+k?\s*(followers|likes|views)\b/i,
  ];

  const cheapPerformativeFlag = performativePatterns.some((re) => re.test(text));

  // ── LLM classification ────────────────────────────────────────────────
  const apiKey = ANTHROPIC_API_KEY.value();
  if (!apiKey) {
    // No API key in this environment — return conservative fallback
    return {
      type: "reflection",
      keepRecommended: !cheapPerformativeFlag,
      performativeFlag: cheapPerformativeFlag,
      reconsecratedDraft: text.slice(0, 500),
    };
  }

  const systemPrompt = `You are Berean, a scripture-grounded content reviewer for AMEN, a faith-centered social app.
A user is importing their old social media posts. Your job is to:
1. Classify each post by content type
2. Flag posts that were primarily performance-driven (engagement farming, humble-bragging, metric-bait)
3. Rewrite posts worth keeping — strip performance framing, state the substance plainly, in the same person's voice
4. Recommend whether each post is worth bringing to AMEN

You MUST respond with ONLY a JSON object. No prose, no markdown fences, no explanation.
Required schema exactly:
{
  "type": "testimony" | "devotional" | "scripture" | "reflection" | "promotional" | "mundane",
  "keepRecommended": boolean,
  "performativeFlag": boolean,
  "reconsecratedDraft": string
}

type definitions:
- testimony: personal story of God's work in someone's life
- devotional: faith-based reflection or teaching moment
- scripture: Bible verse or direct scripture reference
- reflection: thoughtful personal observation, may or may not mention faith
- promotional: selling something, engagement farming, follower growth play
- mundane: generic/trivial content with no meaningful substance worth keeping

performativeFlag: true if the post is primarily about accruing social capital (likes, followers, brand deals), not genuine expression.
reconsecratedDraft: rewrite the post stripped of performance framing. If the post is promotional/mundane and not worth keeping, return empty string.
keepRecommended: true only if the post has genuine substance (testimony, devotional, scripture, meaningful reflection).`;

  const userMessage = `Post to classify:\n\n${text.slice(0, 2000)}`;

  try {
    const Anthropic = require("@anthropic-ai/sdk");
    const client = new Anthropic.Anthropic({ apiKey });

    const response = await client.messages.create({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 600,
      system: systemPrompt,
      messages: [{ role: "user", content: userMessage }],
    });

    const raw = response.content[0]?.text || "";

    // Defensive parse: strip stray markdown fences
    const cleaned = raw
      .replace(/^```(?:json)?\s*/i, "")
      .replace(/\s*```\s*$/, "")
      .trim();

    const parsed = JSON.parse(cleaned);

    // Validate schema — fall back on parse failure
    const validTypes = ["testimony", "devotional", "scripture", "reflection", "promotional", "mundane"];
    if (!validTypes.includes(parsed.type)) throw new Error("Invalid type field");
    if (typeof parsed.keepRecommended !== "boolean") throw new Error("keepRecommended must be boolean");
    if (typeof parsed.performativeFlag !== "boolean") throw new Error("performativeFlag must be boolean");
    if (typeof parsed.reconsecratedDraft !== "string") throw new Error("reconsecratedDraft must be string");

    return {
      type: parsed.type,
      keepRecommended: parsed.keepRecommended,
      performativeFlag: parsed.performativeFlag || cheapPerformativeFlag,
      reconsecratedDraft: (parsed.reconsecratedDraft || "").slice(0, 500),
    };
  } catch (err) {
    console.warn(`[classifyCandidate] Parse/API error: ${err.message}. Using fallback.`);
    // Conservative fallback — don't recommend keeping on classification failure
    return {
      type: "reflection",
      keepRecommended: false,
      performativeFlag: cheapPerformativeFlag,
      reconsecratedDraft: "",
    };
  }
}

// ── Unit test helper ─────────────────────────────────────────────────────────
// Verifies that the latin-1 mojibake fix round-trips correctly.
// Run with: node -e "require('./importFunctions').testMojibake()"
function testMojibake() {
  const cases = [
    "café ☕",
    "naïve",
    "Cöntent with ümlauts",
    "El Niño",
    "plain ascii text",
  ];
  let passed = 0;
  for (const original of cases) {
    const corrupted = Buffer.from(original, "utf8").toString("latin1");
    const restored = fixMojibake(corrupted);
    const ok = restored === original;
    console.log(`${ok ? "✅" : "❌"} "${original}" → mojibake → "${corrupted}" → fix → "${restored}"`);
    if (ok) passed++;
  }
  console.log(`\n${passed}/${cases.length} cases passed.`);
}

exports.testMojibake = testMojibake;

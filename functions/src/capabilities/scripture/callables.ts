// capabilities/scripture/callables.ts — Scripture Intelligence callables (Wave 1: Lane B)
//
// scripture_detectReferences — auth required, no App Check (fast, free, used in Notes)
// scripture_getVerses        — auth required, App Check enforced (external API)
// scripture_searchVerses     — auth required, no App Check (UX search)

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { detectReferencesInBlocks, parseRefs } from "./referenceParser";
import {
  BibleTranslation,
  ScriptureDetectRequest,
  ScriptureDetectResponse,
  ScriptureGetVersesRequest,
  ScriptureGetVersesResponse,
  ScriptureSearchRequest,
  ScriptureSearchResponse,
  VerseResult,
  ScriptureSearchResult,
} from "../types";

const API_BIBLE_KEY = defineSecret("API_BIBLE_KEY");

// API.Bible BSB bible ID (same as used in sanctuary/index.ts)
const BIBLE_IDS: Record<BibleTranslation, string> = {
  BSB: "de4e12af7f28f599-02",
  WEB: "9879dbb7cfe39e4d-04",
  KJV: "de4e12af7f28f599-01",
};

const VALID_TRANSLATIONS: BibleTranslation[] = ["BSB", "WEB", "KJV"];
const CACHE_TTL_MS = 90 * 24 * 60 * 60 * 1000; // 90 days

// ── Helpers ───────────────────────────────────────────────────────────────────

function requireAuth(request: { auth?: { uid?: string } }): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");
  return uid;
}

async function fetchVerseFromApiBible(
  osisRef: string,
  translation: BibleTranslation
): Promise<string | null> {
  const key = API_BIBLE_KEY.value();
  if (!key) {
    logger.warn("[CAP/scripture] API_BIBLE_KEY not configured");
    return null;
  }

  const bibleId = BIBLE_IDS[translation] ?? BIBLE_IDS.BSB;
  const url = `https://api.scripture.api.bible/v1/bibles/${bibleId}/passages/${encodeURIComponent(osisRef)}?content-type=text&include-notes=false&include-titles=false&include-chapter-numbers=false&include-verse-numbers=false`;

  try {
    const response = await fetch(url, {
      headers: { "api-key": key },
    });
    if (!response.ok) {
      logger.warn("[CAP/scripture] API.Bible returned non-200", {
        osisRef,
        status: response.status,
      });
      return null;
    }
    const json = (await response.json()) as { data?: { content?: string } };
    const raw = json.data?.content ?? "";
    // Strip HTML tags and normalize whitespace
    return raw.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim() || null;
  } catch (err) {
    logger.warn("[CAP/scripture] API.Bible fetch failed", { osisRef, error: String(err) });
    return null;
  }
}

function osisRefToDisplay(osisRef: string): string {
  // Convert "Rom.6.1-Rom.6.4" → "Rom 6:1-4" style display
  // Simple conversion: replace dots with spaces/colons
  const parts = osisRef.split("-");
  if (parts.length === 1) {
    // Single ref: "Rom.6.1" → "Rom 6:1" or "Rom.6" → "Rom 6"
    const tokens = parts[0].split(".");
    if (tokens.length === 3) return `${tokens[0]} ${tokens[1]}:${tokens[2]}`;
    if (tokens.length === 2) return `${tokens[0]} ${tokens[1]}`;
    return parts[0];
  }
  // Range: "Rom.6.1-Rom.6.4"
  const startTokens = parts[0].split(".");
  const endTokens = parts[1].split(".");
  if (startTokens.length === 3 && endTokens.length === 3) {
    if (startTokens[0] === endTokens[0] && startTokens[1] === endTokens[1]) {
      // Same book + chapter
      return `${startTokens[0]} ${startTokens[1]}:${startTokens[2]}-${endTokens[2]}`;
    }
    // Cross-chapter
    return `${startTokens[0]} ${startTokens[1]}:${startTokens[2]}-${endTokens[1]}:${endTokens[2]}`;
  }
  return osisRef;
}

// ── scripture_detectReferences ────────────────────────────────────────────────

export const scripture_detectReferences = onCall(
  { enforceAppCheck: false }, // fast, free, must work in Notes without App Check
  async (request): Promise<ScriptureDetectResponse> => {
    requireAuth(request);
    const body = request.data as Partial<ScriptureDetectRequest>;

    if (!Array.isArray(body.blocks) || body.blocks.length === 0) {
      throw new HttpsError("invalid-argument", "blocks must be a non-empty array.");
    }
    if (body.blocks.length > 50) {
      throw new HttpsError("invalid-argument", "blocks must not exceed 50 items.");
    }

    for (let i = 0; i < body.blocks.length; i++) {
      const block = body.blocks[i];
      if (!block || typeof block.blockId !== "string" || typeof block.text !== "string") {
        throw new HttpsError("invalid-argument", `blocks[${i}] must have blockId and text strings.`);
      }
    }

    logger.info("[CAP/scripture] detectReferences", { blockCount: body.blocks.length });

    const detections = detectReferencesInBlocks(body.blocks);
    return { detections };
  }
);

// ── scripture_getVerses ───────────────────────────────────────────────────────

export const scripture_getVerses = onCall(
  {
    enforceAppCheck: true,
    secrets: [API_BIBLE_KEY],
  },
  async (request): Promise<ScriptureGetVersesResponse> => {
    requireAuth(request);
    const body = request.data as Partial<ScriptureGetVersesRequest>;

    if (!Array.isArray(body.osisRefs) || body.osisRefs.length === 0) {
      throw new HttpsError("invalid-argument", "osisRefs must be a non-empty array.");
    }
    if (body.osisRefs.length > 20) {
      throw new HttpsError("invalid-argument", "osisRefs must not exceed 20 items.");
    }

    const translation: BibleTranslation =
      body.translation && VALID_TRANSLATIONS.includes(body.translation)
        ? body.translation
        : "BSB";

    logger.info("[CAP/scripture] getVerses", {
      refCount: body.osisRefs.length,
      translation,
    });

    const db = getFirestore();
    const verses: VerseResult[] = [];

    for (const osisRef of body.osisRefs) {
      if (typeof osisRef !== "string" || !osisRef) continue;

      // Check cache first
      const cacheRef = db.doc(`scriptureCache/${translation}/${osisRef}`);
      const cacheSnap = await cacheRef.get();

      if (cacheSnap.exists) {
        const cacheData = cacheSnap.data()!;
        // Check expiry
        const expiresAt = cacheData.expiresAt as FirebaseFirestore.Timestamp | undefined;
        if (expiresAt && expiresAt.toMillis() > Date.now()) {
          verses.push({
            osisRef,
            text: cacheData.text ?? "",
            translation,
            display: cacheData.display ?? osisRefToDisplay(osisRef),
          });
          continue;
        }
      }

      // Cache miss or expired — fetch from API.Bible
      const text = await fetchVerseFromApiBible(osisRef, translation);
      const display = osisRefToDisplay(osisRef);

      if (text) {
        const now = Date.now();
        // Cache the result for 90 days
        await cacheRef.set({
          text,
          translation,
          osisRef,
          display,
          cachedAt: FieldValue.serverTimestamp(),
          expiresAt: Timestamp.fromMillis(now + CACHE_TTL_MS),
        });
      }

      verses.push({
        osisRef,
        text: text ?? `[Verse text not available for ${osisRef}]`,
        translation,
        display,
      });
    }

    return { verses };
  }
);

// ── scripture_searchVerses ────────────────────────────────────────────────────

export const scripture_searchVerses = onCall(
  { enforceAppCheck: false },
  async (request): Promise<ScriptureSearchResponse> => {
    requireAuth(request);
    const body = request.data as Partial<ScriptureSearchRequest>;

    const query = String(body.query ?? "").trim();
    if (!query || query.length > 200) {
      throw new HttpsError("invalid-argument", "query must be 1-200 chars.");
    }

    const rawLimit = Number(body.limit ?? 5);
    const limit = Math.min(Math.max(1, rawLimit), 10);

    logger.info("[CAP/scripture] searchVerses", { queryLength: query.length, limit });

    const db = getFirestore();

    // First: try to parse query as a direct scripture reference
    const directRefs = parseRefs(query);
    if (directRefs.length > 0) {
      // It's a direct reference — look up the verses
      const translation: BibleTranslation = "BSB";
      const results: ScriptureSearchResult[] = [];

      for (const ref of directRefs.slice(0, limit)) {
        // Check cache
        const cacheRef = db.doc(`scriptureCache/${translation}/${ref.osisRef}`);
        const cacheSnap = await cacheRef.get();
        let text: string | null = null;

        if (cacheSnap.exists) {
          const expiresAt = cacheSnap.data()?.expiresAt as FirebaseFirestore.Timestamp | undefined;
          if (expiresAt && expiresAt.toMillis() > Date.now()) {
            text = cacheSnap.data()?.text ?? null;
          }
        }

        if (!text) {
          text = await fetchVerseFromApiBible(ref.osisRef, translation);
          if (text) {
            await cacheRef.set({
              text,
              translation,
              osisRef: ref.osisRef,
              display: ref.display,
              cachedAt: FieldValue.serverTimestamp(),
              expiresAt: Timestamp.fromMillis(Date.now() + CACHE_TTL_MS),
            });
          }
        }

        results.push({
          osisRef: ref.osisRef,
          display: ref.display,
          snippet: (text ?? `[${ref.display} — verse text not available]`).slice(0, 120),
        });
      }

      return { results };
    }

    // Not a direct reference — keyword search.
    // Try scriptureCatalog collection if it exists.
    const catalogSnap = await db
      .collection("scriptureCatalog")
      .limit(1)
      .get();

    if (!catalogSnap.empty) {
      // scriptureCatalog exists — do simple keyword search
      const queryLower = query.toLowerCase();
      const keywords = queryLower.split(/\s+/).filter((k) => k.length > 2);

      if (keywords.length === 0) {
        return { results: [] };
      }

      // Firestore doesn't support full-text search, so we fetch a reasonable
      // sample and filter client-side. This is a degraded path; production
      // should use Algolia/Pinecone.
      const allSnap = await db
        .collection("scriptureCatalog")
        .limit(200)
        .get();

      const scored: Array<{ doc: FirebaseFirestore.DocumentData; score: number; id: string }> = [];
      for (const doc of allSnap.docs) {
        const data = doc.data();
        const textLower = String(data.text ?? "").toLowerCase();
        const hits = keywords.filter((kw) => textLower.includes(kw)).length;
        if (hits > 0) {
          scored.push({ doc: data, score: hits / keywords.length, id: doc.id });
        }
      }

      scored.sort((a, b) => b.score - a.score);

      const results: ScriptureSearchResult[] = scored.slice(0, limit).map((item) => ({
        osisRef: item.doc.osisRef ?? item.id,
        display: item.doc.display ?? osisRefToDisplay(item.doc.osisRef ?? item.id),
        snippet: String(item.doc.text ?? "").slice(0, 120),
      }));

      return { results };
    }

    // No scriptureCatalog and not a direct reference — return empty with note
    logger.info("[CAP/scripture] searchVerses: no catalog index and query is not a reference", { query });
    return { results: [] };
  }
);

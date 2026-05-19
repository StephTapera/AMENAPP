// berean/repositories/CacheRepository.ts
// Firestore study_cache read/write. TTL-based passage study caching.

import * as admin from "firebase-admin";
import { StudyCacheDoc } from "../models/scripture";

const db = () => admin.firestore();
const CACHE_TTL_HOURS = 24;

export class CacheRepository {
  async get(cacheKey: string): Promise<Record<string, unknown> | null> {
    const doc = await db().collection("study_cache").doc(cacheKey).get();
    if (!doc.exists) return null;
    const data = doc.data() as StudyCacheDoc;
    // Check TTL
    if (data.expiresAt.toDate() < new Date()) {
      // Expired — delete async, return null
      doc.ref.delete().catch(() => {});
      return null;
    }
    return data.payload;
  }

  async set(
    cacheKey: string,
    payload: Record<string, unknown>,
    cacheType: StudyCacheDoc["cacheType"],
    sourceId: string
  ): Promise<void> {
    const now = admin.firestore.Timestamp.now();
    const expiresAt = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + CACHE_TTL_HOURS * 60 * 60 * 1000)
    );
    const doc: StudyCacheDoc = {
      cacheType,
      sourceId,
      locale: "en",
      translation: "ESV",
      payload,
      createdAt: now,
      expiresAt,
      version: 1,
    };
    await db().collection("study_cache").doc(cacheKey).set(doc);
  }

  cacheKeyForPassage(passageId: string, translation = "ESV"): string {
    return `passage_${passageId}_${translation.toLowerCase()}`;
  }

  cacheKeyForImmersion(passageId: string): string {
    return `immersion_${passageId}`;
  }
}

export const cacheRepository = new CacheRepository();

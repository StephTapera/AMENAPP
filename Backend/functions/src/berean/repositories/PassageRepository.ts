// berean/repositories/PassageRepository.ts
// Firestore read layer for the scripture_* collections.

import * as admin from "firebase-admin";
import {
  ScripturePassageDoc,
  ScriptureCrossRefDoc,
  ScriptureWordInsightDoc,
  ScriptureChristConnectionDoc,
  ScriptureThemeDoc,
  ScriptureApplicationPathDoc,
  ScriptureSceneContextDoc,
  ScriptureCharacterLensDoc,
  HistoricalAnnotationDoc,
  ImmersionReflectionPromptDoc,
} from "../models/scripture";

const db = () => admin.firestore();

export class PassageRepository {
  // ── Passages ────────────────────────────────────────────────────────────────

  async getPassage(passageId: string): Promise<ScripturePassageDoc | null> {
    const doc = await db().collection("scripture_passages").doc(passageId).get();
    return doc.exists ? (doc.data() as ScripturePassageDoc) : null;
  }

  /** Find passage by reference string (e.g. "Romans 5:3" → "romans_5_3") */
  async findPassageByReference(reference: string): Promise<{ id: string; data: ScripturePassageDoc } | null> {
    const normalized = this.normalizeReference(reference);
    // Try direct ID lookup first
    const direct = await db().collection("scripture_passages").doc(normalized).get();
    if (direct.exists) {
      return { id: direct.id, data: direct.data() as ScripturePassageDoc };
    }
    // Fallback: query by book + chapter + verse
    // This is a best-effort fuzzy lookup for cases where the ID format differs
    return null;
  }

  // ── Cross References ────────────────────────────────────────────────────────

  async getCrossRefs(passageId: string): Promise<Array<{ id: string; data: ScriptureCrossRefDoc }>> {
    const snap = await db()
      .collection("scripture_cross_refs")
      .where("sourcePassageId", "==", passageId)
      .orderBy("strengthScore", "desc")
      .limit(10)
      .get();
    return snap.docs.map((d) => ({ id: d.id, data: d.data() as ScriptureCrossRefDoc }));
  }

  // ── Word Insights ───────────────────────────────────────────────────────────

  async getWordInsights(passageId: string): Promise<Array<{ id: string; data: ScriptureWordInsightDoc }>> {
    const snap = await db()
      .collection("scripture_word_insights")
      .where("passageId", "==", passageId)
      .limit(8)
      .get();
    return snap.docs.map((d) => ({ id: d.id, data: d.data() as ScriptureWordInsightDoc }));
  }

  // ── Christ Connections ──────────────────────────────────────────────────────

  async getChristConnections(passageId: string): Promise<Array<{ id: string; data: ScriptureChristConnectionDoc }>> {
    const snap = await db()
      .collection("scripture_christ_connections")
      .where("sourcePassageId", "==", passageId)
      .limit(3)
      .get();
    return snap.docs.map((d) => ({ id: d.id, data: d.data() as ScriptureChristConnectionDoc }));
  }

  // ── Themes ──────────────────────────────────────────────────────────────────

  async getThemesByIds(themeIds: string[]): Promise<Array<{ id: string; data: ScriptureThemeDoc }>> {
    if (!themeIds.length) return [];
    const chunks = this.chunkArray(themeIds, 10);
    const results: Array<{ id: string; data: ScriptureThemeDoc }> = [];
    for (const chunk of chunks) {
      const snap = await db()
        .collection("scripture_themes")
        .where(admin.firestore.FieldPath.documentId(), "in", chunk)
        .get();
      snap.docs.forEach((d) => results.push({ id: d.id, data: d.data() as ScriptureThemeDoc }));
    }
    return results;
  }

  // ── Application Paths ───────────────────────────────────────────────────────

  async getApplicationPaths(pathIds: string[]): Promise<Array<{ id: string; data: ScriptureApplicationPathDoc }>> {
    if (!pathIds.length) return [];
    const chunks = this.chunkArray(pathIds, 10);
    const results: Array<{ id: string; data: ScriptureApplicationPathDoc }> = [];
    for (const chunk of chunks) {
      const snap = await db()
        .collection("scripture_application_paths")
        .where(admin.firestore.FieldPath.documentId(), "in", chunk)
        .get();
      snap.docs.forEach((d) => results.push({ id: d.id, data: d.data() as ScriptureApplicationPathDoc }));
    }
    return results;
  }

  // ── Scene Context ───────────────────────────────────────────────────────────

  async getSceneContext(passageId: string): Promise<{ id: string; data: ScriptureSceneContextDoc } | null> {
    const snap = await db()
      .collection("scripture_scene_context")
      .where("passageId", "==", passageId)
      .limit(1)
      .get();
    if (snap.empty) return null;
    const doc = snap.docs[0];
    return { id: doc.id, data: doc.data() as ScriptureSceneContextDoc };
  }

  // ── Character Lenses ────────────────────────────────────────────────────────

  async getCharacterLenses(passageId: string): Promise<Array<{ id: string; data: ScriptureCharacterLensDoc }>> {
    const snap = await db()
      .collection("scripture_character_lenses")
      .where("passageId", "==", passageId)
      .limit(6)
      .get();
    return snap.docs.map((d) => ({ id: d.id, data: d.data() as ScriptureCharacterLensDoc }));
  }

  // ── Historical Annotations ──────────────────────────────────────────────────

  async getHistoricalAnnotations(passageId: string): Promise<Array<{ id: string; data: HistoricalAnnotationDoc }>> {
    const snap = await db()
      .collection("historical_annotations")
      .where("passageId", "==", passageId)
      .limit(8)
      .get();
    return snap.docs.map((d) => ({ id: d.id, data: d.data() as HistoricalAnnotationDoc }));
  }

  // ── Immersion Prompts ───────────────────────────────────────────────────────

  async getImmersionPrompts(passageId: string): Promise<Array<{ id: string; data: ImmersionReflectionPromptDoc }>> {
    const snap = await db()
      .collection("immersion_reflection_prompts")
      .where("passageId", "==", passageId)
      .limit(10)
      .get();
    return snap.docs.map((d) => ({ id: d.id, data: d.data() as ImmersionReflectionPromptDoc }));
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  normalizeReference(ref: string): string {
    return ref
      .toLowerCase()
      .replace(/\s+/g, "_")
      .replace(/:/g, "_")
      .replace(/[–-]/g, "_")
      .replace(/[^a-z0-9_]/g, "");
  }

  private chunkArray<T>(arr: T[], size: number): T[][] {
    const chunks: T[][] = [];
    for (let i = 0; i < arr.length; i += size) {
      chunks.push(arr.slice(i, i + size));
    }
    return chunks;
  }
}

export const passageRepository = new PassageRepository();

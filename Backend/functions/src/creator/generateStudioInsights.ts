/**
 * generateStudioInsights.ts
 *
 * Computes the Creator Studio "stewardship" insights from a creator's OWN real
 * content and persists them to `creatorStudioInsights`. A creator only ever
 * generates their own insights (creatorId is derived from auth.uid — never trusted
 * from the client).
 *
 * CONSTITUTION LOCK (mirrors CreatorStudioView / CreatorSpotlightContracts):
 *   - No growth charts, no streaks, no "post more to grow" nudges.
 *   - Raw numbers are never the hero — they live in supportingMetricContext, the
 *     narrative carries the meaning.
 *   - Insights are OMITTED when there is no real signal. Nothing is fabricated:
 *     a creator with no published work simply gets no stewardship-summary card.
 *
 * Source of truth: users/{creatorId}/creatorProjects (the real editor projects;
 * `status: "published"` marks shared teachings).
 *
 * Export: exports.generateStudioInsights
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

type StudioInsightKind =
  | "formation_trend"
  | "search_discovery"
  | "passage_resonance"
  | "stewardship_summary";

interface StudioInsightDoc {
  id: string;
  creatorId: string;
  kind: StudioInsightKind;
  narrativeText: string;
  supportingMetricLabel: string | null;
  supportingMetricValue: string | null;
  supportingMetricContext: string | null;
  periodLabel: string;
  // Seconds since epoch — stored as a number so the Swift Codable model
  // (StudioInsight.generatedAt: TimeInterval) decodes it directly.
  generatedAt: number;
}

export const generateStudioInsights = onCall(
  {
    region: "us-east1",
    enforceAppCheck: true,
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (request): Promise<{ insights: StudioInsightDoc[] }> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Auth required.");
    }
    if (!request.app) {
      throw new HttpsError("failed-precondition", "App Check attestation required.");
    }

    const creatorId = request.auth.uid;
    const db = admin.firestore();
    const nowSec = Math.floor(Date.now() / 1000);

    // ── Real source: the creator's own projects ──────────────────────────────
    let projects: FirebaseFirestore.DocumentData[] = [];
    try {
      const snap = await db
        .collection("users")
        .doc(creatorId)
        .collection("creatorProjects")
        .orderBy("createdAt", "desc")
        .limit(200)
        .get();
      projects = snap.docs.map((d) => d.data());
    } catch (err) {
      console.warn("[generateStudioInsights] project read failed", { creatorId, err });
      projects = [];
    }

    const published = projects.filter((p) => p.status === "published");
    const insights: StudioInsightDoc[] = [];

    // ── Stewardship summary — grounded in real published work ────────────────
    if (published.length > 0) {
      const mostRecent = published[0];
      const title =
        typeof mostRecent.title === "string" && mostRecent.title.trim()
          ? mostRecent.title.trim()
          : "your latest teaching";
      insights.push({
        id: "stewardship_summary",
        creatorId,
        kind: "stewardship_summary",
        narrativeText:
          published.length === 1
            ? `You've shared one teaching with your community. The most recent is "${title}".`
            : `You're faithfully stewarding your teachings. Your most recent is "${title}".`,
        supportingMetricLabel: "Published teachings",
        supportingMetricValue: String(published.length),
        supportingMetricContext: "shared so far",
        periodLabel: "Ongoing",
        generatedAt: nowSec,
      });
    }

    // ── Formation trend — real distribution of what they're making ───────────
    if (projects.length > 0) {
      const byType: Record<string, number> = {};
      for (const p of projects) {
        const t =
          typeof p.projectType === "string" && p.projectType.trim()
            ? p.projectType.trim()
            : "other";
        byType[t] = (byType[t] ?? 0) + 1;
      }
      const top = Object.entries(byType).sort((a, b) => b[1] - a[1])[0];
      if (top && top[1] > 0) {
        insights.push({
          id: "formation_trend",
          creatorId,
          kind: "formation_trend",
          narrativeText: `Most of your recent work takes the form of ${top[0]} content.`,
          supportingMetricLabel: null,
          supportingMetricValue: null,
          supportingMetricContext: null,
          periodLabel: "Recent",
          generatedAt: nowSec,
        });
      }
    }

    // NOTE: search_discovery / passage_resonance are intentionally NOT emitted here.
    // There is no real per-creator search-appearance or passage-engagement source wired
    // yet, and this function will never fabricate one. They are added in a later wave
    // when that telemetry exists.

    // ── Persist: replace this creator's prior insights ───────────────────────
    try {
      const batch = db.batch();
      const existing = await db
        .collection("creatorStudioInsights")
        .where("creatorId", "==", creatorId)
        .get();
      for (const doc of existing.docs) {
        batch.delete(doc.ref);
      }
      for (const ins of insights) {
        const ref = db.collection("creatorStudioInsights").doc(`${creatorId}_${ins.id}`);
        batch.set(ref, ins);
      }
      await batch.commit();
    } catch (err) {
      // Non-fatal — still return what we computed so the client can render immediately.
      console.error("[generateStudioInsights] persist failed", { creatorId, err });
    }

    console.log("[generateStudioInsights] computed", {
      creatorId,
      projectCount: projects.length,
      publishedCount: published.length,
      insightCount: insights.length,
    });

    return { insights };
  }
);

// berean/repositories/DiscipleshipRepository.ts
// Firestore read/write for discipleship_* collections.
// All data is under /users/{uid}/ for privacy enforcement.

import * as admin from "firebase-admin";
import {
  DiscipleshipProfile,
  PracticeRecommendation,
  FollowUpPrompt,
  ReflectionEntry,
  LeadershipReferral,
} from "../models/berean";

const db = () => admin.firestore();

export class DiscipleshipRepository {
  private userPath(userId: string) {
    return db().collection("users").doc(userId);
  }

  // ── Profile ─────────────────────────────────────────────────────────────────

  async getProfile(userId: string): Promise<DiscipleshipProfile | null> {
    const doc = await this.userPath(userId)
      .collection("discipleshipProfile")
      .doc(userId)
      .get();
    return doc.exists ? (doc.data() as DiscipleshipProfile) : null;
  }

  async updateProfile(userId: string, updates: Partial<DiscipleshipProfile>): Promise<void> {
    await this.userPath(userId)
      .collection("discipleshipProfile")
      .doc(userId)
      .set(
        { ...updates, updatedAt: admin.firestore.Timestamp.now() },
        { merge: true }
      );
  }

  // ── Practice Recommendations ────────────────────────────────────────────────

  async saveRecommendation(userId: string, rec: Omit<PracticeRecommendation, "id">): Promise<string> {
    const ref = this.userPath(userId).collection("practiceRecommendations").doc();
    await ref.set(rec);
    return ref.id;
  }

  async getOpenRecommendations(userId: string): Promise<PracticeRecommendation[]> {
    const snap = await this.userPath(userId)
      .collection("practiceRecommendations")
      .where("status", "==", "open")
      .orderBy("createdAt", "desc")
      .limit(5)
      .get();
    return snap.docs.map((d) => ({ id: d.id, ...d.data() } as PracticeRecommendation));
  }

  // ── Follow-Up Prompts ───────────────────────────────────────────────────────

  async saveFollowUp(userId: string, prompt: Omit<FollowUpPrompt, "id">): Promise<string> {
    const ref = this.userPath(userId).collection("followUpPrompts").doc();
    await ref.set(prompt);
    return ref.id;
  }

  async getPendingFollowUps(userId: string): Promise<FollowUpPrompt[]> {
    const snap = await this.userPath(userId)
      .collection("followUpPrompts")
      .where("status", "==", "pending")
      .orderBy("createdAt", "desc")
      .limit(5)
      .get();
    return snap.docs.map((d) => ({ id: d.id, ...d.data() } as FollowUpPrompt));
  }

  // ── Reflection Entries ──────────────────────────────────────────────────────

  async saveReflection(userId: string, entry: Omit<ReflectionEntry, "id">): Promise<string> {
    const ref = this.userPath(userId).collection("reflectionEntries").doc();
    await ref.set(entry);
    return ref.id;
  }

  // ── Leadership Referrals ────────────────────────────────────────────────────

  async saveReferral(referral: Omit<LeadershipReferral, "id">): Promise<string> {
    const ref = db().collection("leadership_referrals").doc();
    await ref.set(referral);
    return ref.id;
  }

  // ── Discipleship Events ─────────────────────────────────────────────────────

  async logEvent(
    userId: string,
    eventType: string,
    metadata: Record<string, unknown>
  ): Promise<void> {
    const ref = this.userPath(userId).collection("discipleshipEvents").doc();
    await ref.set({
      userId,
      eventType,
      ...metadata,
      createdAt: admin.firestore.Timestamp.now(),
    });
  }
}

export const discipleshipRepository = new DiscipleshipRepository();

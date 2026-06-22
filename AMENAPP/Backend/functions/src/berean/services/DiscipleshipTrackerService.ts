// berean/services/DiscipleshipTrackerService.ts
// Manages the longitudinal discipleship formation system.
// Non-negotiable: opt-in only, no gamification, no shame mechanics.

import * as admin from "firebase-admin";
import { discipleshipRepository } from "../repositories/DiscipleshipRepository";
import {
  DiscipleshipProfile,
  PracticeRecommendation,
  FollowUpPrompt,
} from "../models/berean";

export class DiscipleshipTrackerService {
  // ── Journal a study event ────────────────────────────────────────────────────

  async recordStudySession(
    userId: string,
    conversationId: string,
    passageId: string | null,
    themeIds: string[]
  ): Promise<void> {
    await discipleshipRepository.logEvent(userId, "study_session_completed", {
      conversationId,
      passageId,
      themeIds,
      occurredAt: admin.firestore.Timestamp.now(),
    });

    // Update profile themes
    if (themeIds.length > 0) {
      const profile = await discipleshipRepository.getProfile(userId);
      const recent = [...(profile?.recentThemes ?? []), ...themeIds]
        .slice(-20)
        .filter((v, i, a) => a.indexOf(v) === i);
      await discipleshipRepository.updateProfile(userId, { recentThemes: recent });
    }
  }

  // ── Generate next-step recommendations ──────────────────────────────────────

  async generateNextSteps(
    userId: string,
    conversationId: string,
    themeIds: string[],
    passageIds: string[]
  ): Promise<{
    recommendations: PracticeRecommendation[];
    followUps: FollowUpPrompt[];
  }> {
    const profile = await discipleshipRepository.getProfile(userId);

    // Build lightweight recommendations based on themes
    const recommendations: Omit<PracticeRecommendation, "id">[] = [];
    const followUps: Omit<FollowUpPrompt, "id">[] = [];

    // If user hasn't prayed in a while, recommend prayer
    if (!profile?.recentThemes?.includes("prayer")) {
      recommendations.push({
        userId,
        sourceThemeIds: themeIds,
        sourcePassageIds: passageIds,
        recommendationType: "prayer",
        title: "Take This to God in Prayer",
        body: "What you just studied is worth sitting with in prayer. Even a few minutes of quiet can deepen what you've learned.",
        status: "open",
        createdAt: admin.firestore.Timestamp.now(),
        completedAt: null,
      });
    }

    // Always offer a reflection follow-up
    followUps.push({
      userId,
      sourceConversationId: conversationId,
      sourceThemeIds: themeIds,
      sourcePassageIds: passageIds,
      promptType: "reflection",
      title: "Continue Your Study",
      body: "How has what you studied started showing up in your week? A few minutes of reflection can anchor it more deeply.",
      scheduledFor: admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + 3 * 24 * 60 * 60 * 1000) // 3 days from now
      ),
      status: "pending",
      createdAt: admin.firestore.Timestamp.now(),
    });

    // Save to Firestore
    const savedRecs: PracticeRecommendation[] = [];
    for (const rec of recommendations) {
      const id = await discipleshipRepository.saveRecommendation(userId, rec);
      savedRecs.push({ id, ...rec });
    }

    const savedFollowUps: FollowUpPrompt[] = [];
    for (const fu of followUps) {
      const id = await discipleshipRepository.saveFollowUp(userId, fu);
      savedFollowUps.push({ id, ...fu });
    }

    return { recommendations: savedRecs, followUps: savedFollowUps };
  }

  // ── Get journey snapshot ─────────────────────────────────────────────────────

  async getJourneySnapshot(userId: string): Promise<{
    profile: DiscipleshipProfile | null;
    recommendations: PracticeRecommendation[];
    followUps: FollowUpPrompt[];
  }> {
    const [profile, recommendations, followUps] = await Promise.all([
      discipleshipRepository.getProfile(userId),
      discipleshipRepository.getOpenRecommendations(userId),
      discipleshipRepository.getPendingFollowUps(userId),
    ]);

    return { profile, recommendations, followUps };
  }
}

export const discipleshipTrackerService = new DiscipleshipTrackerService();

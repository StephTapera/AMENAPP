// callable.ts
// AMEN Conversation OS — Firebase Cloud Functions Callables
//
// All callables enforce: App Check, Auth, Permissions, Moderation.
// Pipeline: validate → retrieve → rank → compress → summarize → moderate → persist → return.
// NEVER send raw full message history to LLMs.

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { defineSecret } from "firebase-functions/params";

import { validatePermissions, validatePersonalizedSummaryAccess } from "./permissionsValidationEngine";
import { retrieveMessagesForWindow, retrieveUnreadMessages, retrieveThreadMessages, rankMessagesBySignal } from "./semanticRetrievalEngine";
import { compressMessages, fitChunksTobudget } from "./conversationCompressionEngine";
import { summarizeChunks, persistSummary, buildSummaryId } from "./summarizationEngine";
import { clusterMessages } from "./topicClusteringEngine";
import { extractActions, extractDecisions, extractUnresolvedQuestions, extractBlockers } from "./actionExtractionEngine";
import { rankPrioritySignals } from "./priorityRankingEngine";
import { personalizeForRole, buildUnreadContext } from "./personalizedSummaryEngine";
import { saveUnresolvedItems, getOpenItems } from "./unresolvedDiscussionEngine";
import { queryOrgMemory, saveWeeklyMemory, buildWeekLabel, detectCollaborationPatterns } from "./organizationalMemoryEngine";
import { moderateOutput, sanitizeOutput, applyConfidenceWording, buildCrisisWarning } from "./moderationValidationEngine";
import {
  ConversationOSSurface, OrgType, UserRole, ConversationSummary,
  DEFAULT_SUMMARY_BUDGET, SummaryProvenance,
} from "./types";
import { v4 as uuidv4 } from "uuid";

const db = admin.firestore();

const OPENAI_KEY = defineSecret("OPENAI_API_KEY");
const CLAUDE_KEY = defineSecret("CLAUDE_API_KEY");

// MARK: - Generate Catch-Up Recap

export const generateCatchUpRecap = functions.https.onCall(
  { enforceAppCheck: true, secrets: [OPENAI_KEY, CLAUDE_KEY] },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in required.");

    const { spaceId, surface, unreadCount, lastVisitedAt } = request.data as {
      spaceId: string; surface: ConversationOSSurface;
      unreadCount: number; lastVisitedAt?: string;
    };

    if (!spaceId || !surface) {
      throw new functions.https.HttpsError("invalid-argument", "spaceId and surface required.");
    }

    // 1. Validate permissions
    const perms = await validatePermissions({ userId: uid, spaceId, surface, requestedAction: "summarize" });
    if (!perms.allowed) {
      throw new functions.https.HttpsError("permission-denied", perms.reason ?? "Access denied.");
    }

    // 2. Retrieve messages
    const windowEnd = new Date();
    const windowStart = lastVisitedAt ? new Date(lastVisitedAt) : new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const rawMessages = await retrieveUnreadMessages(spaceId, undefined, surface, windowStart);

    if (rawMessages.length === 0) {
      return { id: null, summaryText: "No new messages since your last visit.", messageCount: 0 };
    }

    // 3. Compress (rank → compress)
    const ranked = rankMessagesBySignal(rawMessages);
    const chunks = compressMessages(ranked);
    const fittedChunks = fitChunksTobudget(chunks, DEFAULT_SUMMARY_BUDGET.maxInputTokens);

    // 4. Extract structured items
    const threadId = `${spaceId}_catchup`;
    const decisions = extractDecisions(rawMessages, threadId);
    const actions = extractActions(rawMessages, chunks, threadId);
    const unresolvedQuestions = extractUnresolvedQuestions(rawMessages, threadId);
    const blockers = extractBlockers(rawMessages, threadId);
    const topicClusters = clusterMessages(rawMessages, chunks);

    // 5. Summarize
    const ctx = {
      spaceId, surface, orgType: "church" as OrgType, userRole: "group_member" as UserRole,
      isSensitive: false, participantCount: new Set(rawMessages.map((m) => m.senderId)).size,
      messageCount: rawMessages.length, windowStart, windowEnd,
    };

    const { summaryText: rawText, confidence, provenance } = await summarizeChunks(
      fittedChunks, ctx, "catch_up",
      OPENAI_KEY.value(), CLAUDE_KEY.value()
    );

    // 6. Moderate output
    const modResult = await moderateOutput(rawText, surface, ctx.orgType);
    if (!modResult.passed) {
      if (modResult.crisisDetected) {
        return { crisisWarning: buildCrisisWarning(surface) };
      }
      throw new functions.https.HttpsError("internal", "Output failed moderation.");
    }

    const summaryText = applyConfidenceWording(sanitizeOutput(rawText), confidence);

    // 7. Build and persist summary
    const summary: ConversationSummary = {
      id: buildSummaryId(),
      spaceId, surface, threadId: undefined,
      summaryText, summaryType: "catch_up",
      topicClusters, decisions, actionItems: actions,
      unresolvedQuestions, blockers,
      generatedAt: new Date(),
      coverageWindowStart: windowStart,
      coverageWindowEnd: windowEnd,
      messageCount: rawMessages.length,
      confidence,
      provenance: { ...provenance, moderationPassed: modResult.passed, permissionsValidated: true },
    };

    await persistSummary(summary);

    // 8. Save unresolved items
    if (unresolvedQuestions.length > 0 || blockers.length > 0) {
      await saveUnresolvedItems(threadId, spaceId, unresolvedQuestions, blockers, surface);
    }

    return summary;
  }
);

// MARK: - Generate Topic Clusters

export const generateTopicClusters = functions.https.onCall(
  { enforceAppCheck: true, secrets: [OPENAI_KEY] },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in required.");

    const { spaceId, surface, threadId } = request.data as {
      spaceId: string; surface: ConversationOSSurface; threadId?: string;
    };

    const perms = await validatePermissions({ userId: uid, spaceId, surface, requestedAction: "cluster" });
    if (!perms.allowed) throw new functions.https.HttpsError("permission-denied", perms.reason ?? "Access denied.");

    const windowStart = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const rawMessages = await retrieveMessagesForWindow(spaceId, threadId, surface, windowStart, new Date(), 200);

    if (rawMessages.length === 0) return { clusters: [] };

    const chunks = compressMessages(rawMessages);
    const clusters = clusterMessages(rawMessages, chunks);

    return { clusters };
  }
);

// MARK: - Extract Conversation Actions

export const extractConversationActions = functions.https.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in required.");

    const { threadId, spaceId } = request.data as { threadId: string; spaceId: string };

    const perms = await validatePermissions({ userId: uid, spaceId, requestedAction: "extract_actions", surface: "group_messages" });
    if (!perms.allowed) throw new functions.https.HttpsError("permission-denied", perms.reason ?? "Access denied.");

    const messages = await retrieveThreadMessages(threadId, 100);
    const chunks = compressMessages(messages);
    const actions = extractActions(messages, chunks, threadId);
    const decisions = extractDecisions(messages, threadId);
    const questions = extractUnresolvedQuestions(messages, threadId);

    return { actions, decisions, questions };
  }
);

// MARK: - Get Personalized Summary

export const getPersonalizedSummary = functions.https.onCall(
  { enforceAppCheck: true, secrets: [OPENAI_KEY, CLAUDE_KEY] },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in required.");

    const { spaceId, surface, userRole, orgType, unreadCount, lastVisitedAt, followedTopics, preferredLength } = request.data as {
      spaceId: string; surface: ConversationOSSurface; userRole: UserRole;
      orgType: OrgType; unreadCount: number; lastVisitedAt?: string;
      followedTopics: string[]; preferredLength: "brief" | "balanced" | "deep";
    };

    const perms = await validatePermissions({ userId: uid, spaceId, surface, requestedAction: "personalize" });
    if (!perms.allowed) throw new functions.https.HttpsError("permission-denied", perms.reason ?? "Access denied.");

    const windowStart = lastVisitedAt ? new Date(lastVisitedAt) : new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const rawMessages = await retrieveUnreadMessages(spaceId, undefined, surface, windowStart);

    if (rawMessages.length === 0) {
      return { summaryText: buildUnreadContext(0), messageCount: 0 };
    }

    const ranked = rankMessagesBySignal(rawMessages);
    const chunks = compressMessages(ranked);
    const fittedChunks = fitChunksTobudget(chunks, DEFAULT_SUMMARY_BUDGET.maxInputTokens);

    const ctx = {
      spaceId, surface, orgType, userRole, isSensitive: false,
      participantCount: new Set(rawMessages.map((m) => m.senderId)).size,
      messageCount: rawMessages.length,
      windowStart, windowEnd: new Date(),
    };

    const { summaryText: rawText, confidence, provenance } = await summarizeChunks(
      fittedChunks, ctx, "catch_up", OPENAI_KEY.value(), CLAUDE_KEY.value()
    );

    const modResult = await moderateOutput(rawText, surface, orgType);
    if (!modResult.passed && !modResult.crisisDetected) {
      throw new functions.https.HttpsError("internal", "Output failed moderation.");
    }

    const baseSummary: ConversationSummary = {
      id: buildSummaryId(), spaceId, surface, threadId: undefined,
      summaryText: sanitizeOutput(rawText),
      summaryType: "catch_up",
      topicClusters: clusterMessages(rawMessages, chunks),
      decisions: extractDecisions(rawMessages, `${spaceId}_personalized`),
      actionItems: extractActions(rawMessages, chunks, `${spaceId}_personalized`),
      unresolvedQuestions: extractUnresolvedQuestions(rawMessages, `${spaceId}_personalized`),
      blockers: extractBlockers(rawMessages, `${spaceId}_personalized`),
      generatedAt: new Date(), coverageWindowStart: windowStart, coverageWindowEnd: new Date(),
      messageCount: rawMessages.length, confidence,
      provenance: { ...provenance, moderationPassed: modResult.passed, permissionsValidated: true },
    };

    const personalized = personalizeForRole(baseSummary, {
      userId: uid, spaceId, surface, userRole, orgType,
      unreadCount, lastVisitedAt: lastVisitedAt ? new Date(lastVisitedAt) : undefined,
      followedTopics, preferredLength,
    });

    // Persist personalized summary for user
    await db.collection("users").doc(uid)
      .collection("personalizedSummaries").doc(personalized.id)
      .set({ ...personalized, generatedAt: admin.firestore.FieldValue.serverTimestamp() });

    return personalized;
  }
);

// MARK: - Query Organizational Memory

export const queryOrganizationalMemory = functions.https.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in required.");

    const { orgId, query } = request.data as { orgId: string; query: string };

    const perms = await validatePermissions({ userId: uid, orgId, requestedAction: "memory_query", surface: "org_hub" });
    if (!perms.allowed) throw new functions.https.HttpsError("permission-denied", perms.reason ?? "Access denied.");

    const memory = await queryOrgMemory(orgId, query ?? "What changed this week?");
    return { memory };
  }
);

// MARK: - Update Conversation Action Status

export const updateConversationActionStatus = functions.https.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in required.");

    const { actionId, status, spaceId } = request.data as { actionId: string; status: string; spaceId: string };
    if (!["pending", "in_progress", "resolved", "dismissed"].includes(status)) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid status.");
    }

    // Verify the user is a member of the space
    const perms = await validatePermissions({ userId: uid, spaceId, requestedAction: "extract_actions", surface: "group_messages" });
    if (!perms.allowed) throw new functions.https.HttpsError("permission-denied", perms.reason ?? "Access denied.");

    // Update across summaries
    const summarySnap = await db.collection("spaces").doc(spaceId).collection("summaries").limit(5).get();
    const batch = db.batch();
    for (const doc of summarySnap.docs) {
      const items = (doc.data().actionItems ?? []).map((a: any) =>
        a.id === actionId ? { ...a, status } : a
      );
      batch.update(doc.ref, { actionItems: items });
    }
    await batch.commit();

    return { updated: true };
  }
);

// MARK: - Update Conversation Decision

export const updateConversationDecision = functions.https.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in required.");

    const { decisionId, action, spaceId } = request.data as { decisionId: string; action: "confirm" | "challenge"; spaceId: string };

    const perms = await validatePermissions({ userId: uid, spaceId, requestedAction: "summarize", surface: "group_messages" });
    if (!perms.allowed) throw new functions.https.HttpsError("permission-denied", perms.reason ?? "Access denied.");

    const newStatus = action === "confirm" ? "confirmed" : "challenged";
    const summarySnap = await db.collection("spaces").doc(spaceId).collection("summaries").limit(5).get();
    const batch = db.batch();
    for (const doc of summarySnap.docs) {
      const decisions = (doc.data().decisions ?? []).map((d: any) =>
        d.id === decisionId ? { ...d, status: newStatus, confirmedBy: action === "confirm" ? [...(d.confirmedBy ?? []), uid] : d.confirmedBy } : d
      );
      batch.update(doc.ref, { decisions });
    }
    await batch.commit();

    return { updated: true };
  }
);

// MARK: - Dismiss Conversation Summary

export const dismissConversationSummary = functions.https.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in required.");

    const { summaryId, spaceId } = request.data as { summaryId: string; spaceId: string };

    // Track dismiss in the user's personalized summary subcollection
    await db.collection("users").doc(uid)
      .collection("personalizedSummaries").doc(summaryId)
      .set({ dismissed: true, dismissedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });

    return { dismissed: true };
  }
);

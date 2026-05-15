// biblicalAlignmentFunctions.ts
// Firebase gen2 callable functions for the Berean AI Alignment + Spiritual Protection system.
// All functions require Firebase Auth + App Check.
// Stores only hashes/previews — never raw text in audit records.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {
    runBiblicalAlignmentPipeline,
    getDiscernmentPromptData,
    buildRewriteSuggestion,
    buildScriptureSuggestions,
    classifyLocalRisk,
    hashContent,
    previewContent,
} from "./alignmentPipeline";

const db = admin.firestore();

// ─── checkBiblicalAlignment ───────────────────────────────────────────────────

export const checkBiblicalAlignment = onCall(
    { region: "us-central1", timeoutSeconds: 15 },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
        if (!request.app)  throw new HttpsError("failed-precondition", "App Check required.");

        const uid = request.auth.uid;
        const { text, targetType, targetId, sourceSurface, requestedLens, hasMedia } =
            request.data as {
                text: string; targetType: string; targetId?: string;
                sourceSurface: string; requestedLens?: string; hasMedia?: boolean;
            };

        if (!text || typeof text !== "string") throw new HttpsError("invalid-argument", "text is required.");
        if (!targetType) throw new HttpsError("invalid-argument", "targetType is required.");
        if (text.trim().length > 50000) throw new HttpsError("invalid-argument", "text exceeds maximum length.");

        // Fetch user protection preferences (non-fatal if missing)
        let userProfile: {
            explicitContentProtectionEnabled?: boolean;
            exploitationProtectionEnabled?: boolean;
            discernmentMode?: string;
        } = {};
        try {
            const snap = await db.collection("user_alignment_profiles").doc(uid).get();
            if (snap.exists) userProfile = snap.data() as typeof userProfile;
        } catch { /* use defaults */ }

        const result = await runBiblicalAlignmentPipeline({
            text, targetType, sourceSurface, requestedLens, hasMedia, userProfile,
        });

        // Write private audit record — hash + preview only, never raw text
        try {
            const expiresAt = admin.firestore.Timestamp.fromDate(
                new Date(Date.now() + 90 * 24 * 60 * 60 * 1000)
            );
            await db.collection("ai_alignment_checks").doc(result.checkId).set({
                userId: uid,
                targetType,
                targetId: targetId ?? null,
                sourceSurface,
                inputHash: hashContent(text),
                inputPreview: previewContent(text),
                status: result.status,
                alignmentScore: result.alignmentScore,
                confidence: result.confidence,
                flags: result.flags,
                suggestedAction: result.suggestedAction,
                userVisibleSummary: result.userVisibleSummary,
                scriptureSuggestions: result.scriptureSuggestions,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                expiresAt,
                modelMetadata: result.modelMetadata,
            });
        } catch { /* audit failure is non-fatal */ }

        return result;
    }
);

// ─── suggestBiblicalRewrite ───────────────────────────────────────────────────

export const suggestBiblicalRewrite = onCall(
    { region: "us-central1", timeoutSeconds: 15 },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
        if (!request.app)  throw new HttpsError("failed-precondition", "App Check required.");

        const { originalText, lens, targetType } = request.data as {
            originalText: string; lens: string; targetType: string;
        };
        if (!originalText) throw new HttpsError("invalid-argument", "originalText is required.");

        const { flags } = classifyLocalRisk(originalText, { targetType });
        const rewrittenText = buildRewriteSuggestion(originalText, flags);
        const scriptureSuggestions = buildScriptureSuggestions(flags);

        return {
            rewrittenText,
            explanation: "This rewrite aims to share your perspective with humility, grace, and biblical grounding.",
            scriptureSuggestions,
        };
    }
);

// ─── saveAICorrection ─────────────────────────────────────────────────────────

export const saveAICorrection = onCall(
    { region: "us-central1", timeoutSeconds: 10 },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
        if (!request.app)  throw new HttpsError("failed-precondition", "App Check required.");

        const uid = request.auth.uid;
        const {
            originalCheckId, targetType, targetId, originalText,
            correctionText, selectedLens, correctionIntent, savedToProfile,
        } = request.data as {
            originalCheckId?: string; targetType: string; targetId?: string;
            originalText?: string; correctionText: string; selectedLens: string;
            correctionIntent: string; savedToProfile: boolean;
        };

        if (!correctionText) throw new HttpsError("invalid-argument", "correctionText is required.");

        const ref = await db.collection("ai_corrections").add({
            userId: uid,
            originalCheckId: originalCheckId ?? null,
            targetType,
            targetId: targetId ?? null,
            originalTextHash: originalText ? hashContent(originalText) : null,
            correctionText: correctionText.slice(0, 2000),
            selectedLens,
            correctionIntent,
            savedToProfile,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        let profileUpdated = false;
        if (savedToProfile) {
            try {
                await db.collection("user_alignment_profiles").doc(uid).set({
                    userId: uid,
                    defaultLens: selectedLens,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    "aggregateStats.correctionCount": admin.firestore.FieldValue.increment(1),
                }, { merge: true });
                profileUpdated = true;
            } catch { /* non-fatal */ }
        }

        return { ok: true, correctionId: ref.id, profileUpdated };
    }
);

// ─── getDiscernmentPrompt ─────────────────────────────────────────────────────

export const getDiscernmentPrompt = onCall(
    { region: "us-central1", timeoutSeconds: 10 },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
        if (!request.app)  throw new HttpsError("failed-precondition", "App Check required.");

        const { text } = request.data as { text: string; surface?: string };
        if (!text) return { shouldPrompt: false, promptTitle: "", promptMessage: "", options: [] };

        const { flags } = classifyLocalRisk(text, {});
        return getDiscernmentPromptData(flags);
    }
);

// ─── attachSharedKnowledgeIntegrity ──────────────────────────────────────────

export const attachSharedKnowledgeIntegrity = onCall(
    { region: "us-central1", timeoutSeconds: 10 },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
        if (!request.app)  throw new HttpsError("failed-precondition", "App Check required.");

        const uid = request.auth.uid;
        const { targetType, targetId, checkId } = request.data as {
            targetType: string; targetId: string; checkId: string;
        };
        if (!targetType || !targetId || !checkId) {
            throw new HttpsError("invalid-argument", "targetType, targetId, and checkId are required.");
        }

        let badge = "context_check";
        let summary = "This content has been reviewed for biblical alignment.";
        let scriptureContext: Array<{ reference: string; reason: string }> = [];

        try {
            const snap = await db.collection("ai_alignment_checks").doc(checkId).get();
            if (snap.exists) {
                const d = snap.data()!;
                if (d.userId !== uid) throw new HttpsError("permission-denied", "Check does not belong to this user.");
                const s = d.status as string;
                if (s === "aligned")          badge = "berean_verified";
                else if (s === "context_needed") badge = "context_check";
                else if (s === "needs_discernment") badge = "needs_discernment";
                summary = d.userVisibleSummary ?? summary;
                scriptureContext = d.scriptureSuggestions ?? [];
            }
        } catch (err) {
            if (err instanceof HttpsError) throw err;
        }

        const docId = `${targetType}_${targetId}`;
        await db.collection("shared_knowledge_integrity").doc(docId).set({
            targetType, targetId, ownerId: uid,
            status: "active", badge,
            userVisibleSummary: summary,
            scriptureContext,
            communitySignals: { upvotes: 0, downvotes: 0 },
            isPublic: true,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        return { ok: true, docId };
    }
);

// ─── voteKnowledgeIntegrity ───────────────────────────────────────────────────

export const voteKnowledgeIntegrity = onCall(
    { region: "us-central1", timeoutSeconds: 10 },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
        if (!request.app)  throw new HttpsError("failed-precondition", "App Check required.");

        const uid = request.auth.uid;
        const { targetType, targetId, vote } = request.data as {
            targetType: string; targetId: string; vote: "up" | "down" | "remove";
        };
        if (!targetType || !targetId) {
            throw new HttpsError("invalid-argument", "targetType and targetId are required.");
        }

        const docId = `${targetType}_${targetId}`;
        const integrityRef = db.collection("shared_knowledge_integrity").doc(docId);
        const voteRef = integrityRef.collection("votes").doc(uid);

        await db.runTransaction(async (tx) => {
            const existing = await tx.get(voteRef);
            const prev = existing.exists ? (existing.data()?.vote as string) : null;
            if (prev === vote) return;

            const inc = admin.firestore.FieldValue.increment;
            const updates: Record<string, unknown> = {
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            };
            if (prev === "up")   updates["communitySignals.upvotes"]   = inc(-1);
            if (prev === "down") updates["communitySignals.downvotes"] = inc(-1);
            if (vote === "up")   updates["communitySignals.upvotes"]   = inc(1);
            if (vote === "down") updates["communitySignals.downvotes"] = inc(1);

            tx.set(integrityRef, updates, { merge: true });
            vote === "remove"
                ? tx.delete(voteRef)
                : tx.set(voteRef, { vote, votedAt: admin.firestore.FieldValue.serverTimestamp() });
        });

        return { ok: true };
    }
);

// ─── getWeeklyAlignmentSummary ────────────────────────────────────────────────

export const getWeeklyAlignmentSummary = onCall(
    { region: "us-central1", timeoutSeconds: 20 },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
        if (!request.app)  throw new HttpsError("failed-precondition", "App Check required.");

        const uid = request.auth.uid;
        const { weekStart } = request.data as { weekStart?: string };

        const now = new Date();
        const weekStartDate = weekStart
            ? new Date(weekStart)
            : new Date(now.getFullYear(), now.getMonth(), now.getDate() - now.getDay());
        const weekEndDate = new Date(weekStartDate.getTime() + 7 * 24 * 60 * 60 * 1000);

        const summaryId = `${uid}_${weekStartDate.toISOString().slice(0, 10)}`;
        const cached = await db.collection("ai_engagement_summaries").doc(summaryId).get();
        if (cached.exists) return { summary: cached.data() };

        const checksSnap = await db.collection("ai_alignment_checks")
            .where("userId", "==", uid)
            .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(weekStartDate))
            .where("createdAt", "<",  admin.firestore.Timestamp.fromDate(weekEndDate))
            .get();

        const checks = checksSnap.docs.map(d => d.data());
        const total   = checks.length;
        const aligned = checks.filter(c => c.status === "aligned").length;
        const discernment = checks.filter(c =>
            c.status === "needs_discernment" || c.status === "context_needed"
        ).length;
        const blocked = checks.filter(c =>
            c.status === "blocked" || c.status === "human_review"
        ).length;

        const correctionsSnap = await db.collection("ai_corrections")
            .where("userId", "==", uid)
            .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(weekStartDate))
            .where("createdAt", "<",  admin.firestore.Timestamp.fromDate(weekEndDate))
            .get();

        // Aggregate scripture themes from flags (privacy-safe — no raw text)
        const flagCounts: Record<string, number> = {};
        for (const c of checks) {
            for (const f of (c.flags ?? []) as string[]) {
                flagCounts[f] = (flagCounts[f] ?? 0) + 1;
            }
        }
        const flagLabels: Record<string, string> = {
            wrath: "Patience & Anger", pride: "Humility", lust: "Purity",
            scripture_misuse: "Biblical Accuracy", shame_language: "Grace",
            theological_sensitivity: "Wisdom", harassment: "Respect",
        };
        const topScriptureThemes = Object.entries(flagCounts)
            .sort((a, b) => b[1] - a[1])
            .slice(0, 3)
            .map(([f]) => flagLabels[f] ?? f);

        const protectionMoments = checks.filter(c =>
            (c.flags ?? []).some((f: string) =>
                ["trafficking", "grooming", "explicit_sexual", "sexual_blackmail", "lust"].includes(f)
            )
        ).length;

        const summary = {
            userId: uid,
            weekStart: weekStartDate.toISOString(),
            weekEnd:   weekEndDate.toISOString(),
            stats: {
                totalInteractions: total,
                alignedPercent: total > 0 ? Math.round((aligned / total) * 100) : 100,
                correctionsMade: correctionsSnap.size,
                discernmentMoments: discernment,
                contextChecksAdded: checks.filter(c => c.status === "context_needed").length,
                blockedOrHeldItems: blocked,
                spiritualProtectionMoments: protectionMoments,
            },
            insights: total === 0
                ? ["No Berean activity this week. Consider exploring a scripture passage."]
                : aligned / total > 0.9
                    ? ["Your interactions this week showed strong biblical alignment."]
                    : discernment > 2
                        ? ["Several moments this week called for discernment — that is wisdom at work."]
                        : ["Keep exploring scripture and growing in discernment."],
            suggestedPractices: ([
                discernment > 0     ? "Pause before posting when something feels spiritually charged." : null,
                correctionsSnap.size > 0 ? "Your AI corrections are shaping Berean for you — keep going." : null,
                blocked > 0         ? "Amen protected you this week. Consider speaking with a pastor if helpful." : null,
                "Read one Psalm this week and reflect on what it means for your community.",
            ] as (string | null)[]).filter((x): x is string => x !== null),
            topScriptureThemes: topScriptureThemes.length > 0
                ? topScriptureThemes : ["Wisdom", "Faith", "Community"],
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        try {
            await db.collection("ai_engagement_summaries").doc(summaryId).set(summary);
        } catch { /* non-fatal */ }

        return { summary };
    }
);

// ─── updateAlignmentProfile ───────────────────────────────────────────────────

export const updateAlignmentProfile = onCall(
    { region: "us-central1", timeoutSeconds: 10 },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
        if (!request.app)  throw new HttpsError("failed-precondition", "App Check required.");

        const uid = request.auth.uid;
        const {
            defaultLens, discernmentMode, scripturePreference,
            correctionMemoryEnabled, weeklySummaryEnabled, simpleModeEnabled,
            explicitContentProtectionEnabled, exploitationProtectionEnabled, preferredTone,
        } = request.data as Record<string, unknown>;

        const updates: Record<string, unknown> = {
            userId: uid,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        if (defaultLens !== undefined) updates.defaultLens = defaultLens;
        if (discernmentMode !== undefined) updates.discernmentMode = discernmentMode;
        if (scripturePreference !== undefined) updates.scripturePreference = scripturePreference;
        if (correctionMemoryEnabled !== undefined) updates.correctionMemoryEnabled = correctionMemoryEnabled;
        if (weeklySummaryEnabled !== undefined) updates.weeklySummaryEnabled = weeklySummaryEnabled;
        if (simpleModeEnabled !== undefined) updates.simpleModeEnabled = simpleModeEnabled;
        if (explicitContentProtectionEnabled !== undefined) updates.explicitContentProtectionEnabled = explicitContentProtectionEnabled;
        if (exploitationProtectionEnabled !== undefined) updates.exploitationProtectionEnabled = exploitationProtectionEnabled;
        if (preferredTone !== undefined) updates.preferredTone = preferredTone;

        await db.collection("user_alignment_profiles").doc(uid).set(
            { ...updates, createdAt: admin.firestore.FieldValue.serverTimestamp() },
            { merge: true }
        );

        const snap = await db.collection("user_alignment_profiles").doc(uid).get();
        return { ok: true, profile: snap.data() };
    }
);

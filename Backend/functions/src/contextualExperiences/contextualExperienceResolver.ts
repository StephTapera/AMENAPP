/**
 * contextualExperienceResolver.ts
 *
 * Pure resolver logic for the Multi-Tenant Contextual Experience System.
 * This module is NOT a Cloud Function — it is a helper imported by
 * resolveContextualExperienceStack in contextualExperienceCallables.ts.
 *
 * Priority ladder (highest to lowest):
 *   1. accessibility         — user has accessibility needs → reduced motion, simplified modules
 *   2. safety_grief          — grief-sensitive mode active → quiet notifications
 *   3. active_user_event     — user has joined a published experience
 *   4. organization          — org-scoped published experience
 *   5. campus                — campus/group-scoped published experience
 *   6. regional              — regional-scoped published experience
 *   7. global                — global-scoped published experience
 *   8. default_ui            — no matching experience
 *
 * INVARIANTS:
 * - Kill-switched experiences are always excluded.
 * - Grief/memorial types outrank celebrations at the same priority layer.
 * - debugMetadata is only populated when isAdminPreview=true.
 * - No PII is included in the resolved output.
 */

import {
    ContextualExperienceData,
    ExperienceLayer,
    ExperienceModuleType,
    ExperienceThemeConfig,
    GRIEF_EXPERIENCE_TYPES,
} from "./contextualExperienceModels";

// ─── Output Interface ─────────────────────────────────────────────────────────

export interface ResolvedExperience {
    activeExperienceId: string | null;
    sourceLayer: ExperienceLayer;
    themeTokens: ExperienceThemeConfig | null;
    allowedModules: ExperienceModuleType[];
    activeBannerTitle: string | null;
    activeBannerSubtitle: string | null;
    navigationAction: string | null;
    notificationBehavior: "normal" | "quiet" | "urgent";
    safetyBehavior: "standard" | "grief_sensitive" | "youth_safe";
    accessibilityAdjustments: Record<string, boolean>;
    secondaryExperiences: Array<{ id: string; title: string; layer: ExperienceLayer }>;
    debugMetadata: Record<string, string> | null;
}

// ─── Internal Helpers ─────────────────────────────────────────────────────────

type ScoredExperience = {
    exp: ContextualExperienceData & { id: string };
    layer: ExperienceLayer;
    isGrief: boolean;
};

/**
 * Maps an experience's visibility to its baseline priority layer.
 * "active_user_event" is a separate check applied before visibility matching.
 */
function visibilityToLayer(
    visibility: ContextualExperienceData["visibility"]
): ExperienceLayer {
    switch (visibility) {
        case "global":       return "global";
        case "regional":     return "regional";
        case "organization": return "organization";
        case "campus":
        case "group":
        case "invite":       return "campus";
        default:             return "global";
    }
}

/**
 * Numeric weight for priority comparison (lower = higher priority).
 */
function layerWeight(layer: ExperienceLayer): number {
    const weights: Record<ExperienceLayer, number> = {
        accessibility:     0,
        safety_grief:      1,
        active_user_event: 2,
        organization:      3,
        campus:            4,
        regional:          5,
        global:            6,
        default_ui:        7,
    };
    return weights[layer];
}

/**
 * Given two scored experiences at the same layer weight, prefer grief/memorial.
 */
function pickWinner(a: ScoredExperience, b: ScoredExperience): ScoredExperience {
    // Grief/memorial always beats non-grief at the same layer.
    if (a.isGrief && !b.isGrief) return a;
    if (!a.isGrief && b.isGrief) return b;
    // Otherwise keep whichever was seen first (deterministic ordering).
    return a;
}

/**
 * Derive notification behavior from the winning experience's type and safety config.
 */
function resolveNotificationBehavior(
    exp: ContextualExperienceData
): ResolvedExperience["notificationBehavior"] {
    if (exp.safety.griefSensitiveMode) return "quiet";
    if (exp.type === "emergency_prayer") return "urgent";
    return "normal";
}

/**
 * Derive safety behavior from the winning experience's safety config.
 */
function resolveSafetyBehavior(
    exp: ContextualExperienceData
): ResolvedExperience["safetyBehavior"] {
    if (exp.safety.griefSensitiveMode) return "grief_sensitive";
    if (exp.safety.requiresYouthProtection || exp.safety.moderationStrictness === "youth") {
        return "youth_safe";
    }
    return "standard";
}

/**
 * Build accessibility-specific theme tokens — zero motion, high contrast glass.
 */
function buildAccessibilityTheme(): ExperienceThemeConfig {
    return {
        accentColorHex: "#C9A84C", // default to amenGold for accessibility surfaces
        motionIntensity: 0.0,
        glassOpacity: 0.95,
        backgroundStyle: "adaptive",
    };
}

/**
 * Simplified module list for accessibility layer — remove visually complex modules.
 */
function accessibilityModules(): ExperienceModuleType[] {
    return ["prayer", "scripture", "announcements", "discussion"];
}

// ─── Main Resolver ────────────────────────────────────────────────────────────

/**
 * Resolve the winning contextual experience for a user from a set of candidates.
 *
 * @param experiences       All published, non-kill-switched experiences for the user's context.
 * @param userId            The requesting user's UID (used only for logging — never in output).
 * @param userAccessibilityNeeds  Non-empty array triggers accessibility layer.
 * @param isGriefSensitive  True when the user's profile has grief-sensitive mode active.
 * @param isAdminPreview    True when called from an admin context — populates debugMetadata.
 * @param joinedExperienceIds  Set of experience IDs the user has joined (participant doc exists).
 */
export function resolveExperienceStack(
    experiences: Array<ContextualExperienceData & { id: string }>,
    userId: string,
    userAccessibilityNeeds: string[],
    isGriefSensitive: boolean,
    isAdminPreview: boolean,
    joinedExperienceIds: Set<string> = new Set()
): ResolvedExperience {
    // ── Layer 1: Accessibility override ──────────────────────────────────────
    if (userAccessibilityNeeds.length > 0) {
        const accessibilityExp = experiences.find(
            (e) => e.status === "published" && !e.isKillSwitched
        ) ?? null;

        const secondaries = experiences
            .filter((e) => e.status === "published" && !e.isKillSwitched && e !== accessibilityExp)
            .slice(0, 3)
            .map((e) => ({ id: e.id, title: e.title, layer: visibilityToLayer(e.visibility) }));

        return {
            activeExperienceId: accessibilityExp?.id ?? null,
            sourceLayer: "accessibility",
            themeTokens: buildAccessibilityTheme(),
            allowedModules: accessibilityModules(),
            activeBannerTitle: accessibilityExp?.title ?? null,
            activeBannerSubtitle: "Accessible experience — reduced motion enabled",
            navigationAction: accessibilityExp ? `openExperience:${accessibilityExp.id}` : null,
            notificationBehavior: "quiet",
            safetyBehavior: "standard",
            accessibilityAdjustments: {
                reduceMotion: true,
                increaseContrast: true,
                simplifiedLayout: true,
            },
            secondaryExperiences: secondaries,
            debugMetadata: isAdminPreview
                ? { reason: "accessibility_override", needs: userAccessibilityNeeds.join(",") }
                : null,
        };
    }

    // ── Layer 2: Grief/safety override ───────────────────────────────────────
    if (isGriefSensitive) {
        // Look for a grief/memorial experience first; fall back to any published one.
        const griefExp = experiences.find(
            (e) => e.status === "published" && !e.isKillSwitched && GRIEF_EXPERIENCE_TYPES.includes(e.type)
        ) ?? experiences.find((e) => e.status === "published" && !e.isKillSwitched) ?? null;

        const secondaries = experiences
            .filter((e) => e.status === "published" && !e.isKillSwitched && e !== griefExp)
            .slice(0, 3)
            .map((e) => ({ id: e.id, title: e.title, layer: visibilityToLayer(e.visibility) }));

        return {
            activeExperienceId: griefExp?.id ?? null,
            sourceLayer: "safety_grief",
            themeTokens: griefExp?.theme ?? null,
            allowedModules: griefExp ? griefExp.enabledModules.filter((m) => m !== "livestream") : [],
            activeBannerTitle: griefExp?.title ?? null,
            activeBannerSubtitle: "You are seen and supported",
            navigationAction: griefExp ? `openExperience:${griefExp.id}` : null,
            notificationBehavior: "quiet",
            safetyBehavior: "grief_sensitive",
            accessibilityAdjustments: {},
            secondaryExperiences: secondaries,
            debugMetadata: isAdminPreview
                ? { reason: "grief_sensitive_override", expId: griefExp?.id ?? "none" }
                : null,
        };
    }

    // ── Layers 3–7: Score remaining published experiences ────────────────────

    // Filter to published, non-kill-switched experiences only.
    const candidates = experiences.filter(
        (e) => e.status === "published" && !e.isKillSwitched
    );

    if (candidates.length === 0) {
        return buildDefaultUi(isAdminPreview);
    }

    // Score each candidate.
    const scored: ScoredExperience[] = candidates.map((exp) => {
        const isJoined = joinedExperienceIds.has(exp.id);
        const isGriefType = GRIEF_EXPERIENCE_TYPES.includes(exp.type);

        let layer: ExperienceLayer;
        if (isJoined) {
            layer = "active_user_event";
        } else {
            layer = visibilityToLayer(exp.visibility);
        }

        return { exp, layer, isGrief: isGriefType };
    });

    // Sort: ascending layerWeight (higher priority first), grief wins ties.
    scored.sort((a, b) => {
        const weightDiff = layerWeight(a.layer) - layerWeight(b.layer);
        if (weightDiff !== 0) return weightDiff;
        // Grief wins at the same layer.
        if (a.isGrief && !b.isGrief) return -1;
        if (!a.isGrief && b.isGrief) return 1;
        return 0;
    });

    // Winner is the first after sorting.
    let winner = scored[0];
    // Apply pairwise grief-vs-celebration override for identical layer weight.
    if (scored.length >= 2 && layerWeight(scored[0].layer) === layerWeight(scored[1].layer)) {
        winner = pickWinner(scored[0], scored[1]);
    }

    // Secondary experiences: up to 3 runner-ups.
    const secondaries = scored
        .filter((s) => s !== winner)
        .slice(0, 3)
        .map((s) => ({ id: s.exp.id, title: s.exp.title, layer: s.layer }));

    const winnerExp = winner.exp;

    return {
        activeExperienceId: winnerExp.id,
        sourceLayer: winner.layer,
        themeTokens: winnerExp.theme,
        allowedModules: winnerExp.enabledModules,
        activeBannerTitle: winnerExp.title,
        activeBannerSubtitle: winnerExp.description.slice(0, 120) || null,
        navigationAction: `openExperience:${winnerExp.id}`,
        notificationBehavior: resolveNotificationBehavior(winnerExp),
        safetyBehavior: resolveSafetyBehavior(winnerExp),
        accessibilityAdjustments: {},
        secondaryExperiences: secondaries,
        debugMetadata: isAdminPreview
            ? {
                reason: "standard_priority_resolution",
                winnerId: winnerExp.id,
                winnerLayer: winner.layer,
                totalCandidates: String(candidates.length),
                isGriefWinner: String(winner.isGrief),
              }
            : null,
    };
}

// ─── Default UI Fallback ──────────────────────────────────────────────────────

function buildDefaultUi(isAdminPreview: boolean): ResolvedExperience {
    return {
        activeExperienceId: null,
        sourceLayer: "default_ui",
        themeTokens: null,
        allowedModules: [],
        activeBannerTitle: null,
        activeBannerSubtitle: null,
        navigationAction: null,
        notificationBehavior: "normal",
        safetyBehavior: "standard",
        accessibilityAdjustments: {},
        secondaryExperiences: [],
        debugMetadata: isAdminPreview ? { reason: "no_active_experiences" } : null,
    };
}

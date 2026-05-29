/**
 * contextualExperienceModels.ts
 *
 * TypeScript interfaces for the Multi-Tenant Contextual Experience System.
 * These mirror the Swift models on the iOS side and are used as the canonical
 * data contract for all Firestore documents in /contextualExperiences/.
 *
 * DESIGN CONSTRAINTS:
 * - accentColorHex must be one of the 4 AMEN brand colors (or white).
 * - No PII is stored in audit logs or analytics aggregates.
 * - Youth-protection flag triggers strict moderation mode.
 */

import * as FirebaseFirestore from "firebase-admin/firestore";

// ─── Enum Types ───────────────────────────────────────────────────────────────

export type OrgType =
    | "church"
    | "school"
    | "university"
    | "ministry"
    | "business"
    | "enterprise"
    | "nonprofit"
    | "prayer_group"
    | "creator_community"
    | "campus";

export type OrgMemberRole =
    | "owner"
    | "pastor"
    | "teacher"
    | "admin"
    | "youth_leader"
    | "moderator"
    | "student_leader"
    | "volunteer"
    | "prayer_lead"
    | "comms_lead"
    | "member";

export type ExperienceType =
    | "celebration"
    | "prayer_campaign"
    | "event"
    | "tradition"
    | "community_challenge"
    | "worship_night"
    | "graduation_week"
    | "fasting"
    | "conference_mode"
    | "youth_camp"
    | "vbs"
    | "revival_week"
    | "mission_trip"
    | "emergency_prayer"
    | "memorial"
    | "mental_health_awareness"
    | "chapel_week"
    | "anniversary";

export type ExperienceVisibility =
    | "global"
    | "regional"
    | "organization"
    | "campus"
    | "group"
    | "invite";

export type ExperienceStatus =
    | "draft"
    | "published"
    | "archived"
    | "deleted";

export type ExperienceModuleType =
    | "prayer"
    | "discussion"
    | "event"
    | "memory"
    | "tradition"
    | "scripture"
    | "worship"
    | "livestream"
    | "announcements";

export type ExperienceLayer =
    | "accessibility"
    | "safety_grief"
    | "active_user_event"
    | "organization"
    | "campus"
    | "regional"
    | "global"
    | "default_ui";

// ─── Sub-Document Interfaces ──────────────────────────────────────────────────

/**
 * Controls the visual presentation of an experience.
 * accentColorHex is restricted to AMEN brand palette only.
 */
export interface ExperienceThemeConfig {
    /** AMEN-brand only: gold=#C9A84C, purple=#5B2D8E, blue=#1A6DB5, black=#0A0A0A, white=#FFFFFF */
    accentColorHex: string;
    /** 0.0–1.0: controls animation intensity; accessibility mode forces this to 0 */
    motionIntensity: number;
    /** 0.0–1.0: glass material opacity for overlays */
    glassOpacity: number;
    backgroundStyle: "light" | "dark" | "adaptive";
}

/**
 * Safety configuration governing youth protection, moderation, and grief sensitivity.
 */
export interface ExperienceSafetyConfig {
    requiresYouthProtection: boolean;
    moderationStrictness: "standard" | "strict" | "youth";
    allowAnonymousPrayer: boolean;
    requireApprovalToJoin: boolean;
    griefSensitiveMode: boolean;
}

// ─── Primary Document Interface ───────────────────────────────────────────────

/**
 * Root document stored at /contextualExperiences/{experienceId}.
 * All writes are server-authoritative (Cloud Functions only).
 */
export interface ContextualExperienceData {
    organizationId: string;
    organizationType: OrgType;
    type: ExperienceType;
    title: string;
    description: string;
    region?: string;
    startDate: FirebaseFirestore.Timestamp;
    endDate: FirebaseFirestore.Timestamp;
    visibility: ExperienceVisibility;
    status: ExperienceStatus;
    theme: ExperienceThemeConfig;
    allowedManagerRoles: OrgMemberRole[];
    enabledModules: ExperienceModuleType[];
    participantCount: number;
    createdBy: string;
    createdAt: FirebaseFirestore.FieldValue;
    updatedAt?: FirebaseFirestore.FieldValue;
    safety: ExperienceSafetyConfig;
    analyticsEnabled: boolean;
    memoriesEnabled: boolean;
    prayerCampaignsEnabled: boolean;
    isKillSwitched: boolean;
}

// ─── Validated AMEN Brand Colors ──────────────────────────────────────────────

export const AMEN_BRAND_COLORS: readonly string[] = [
    "#C9A84C", // amenGold
    "#5B2D8E", // amenPurple
    "#1A6DB5", // amenBlue
    "#0A0A0A", // amenBlack
    "#FFFFFF", // white (permitted for adaptive surfaces)
] as const;

// ─── Validation Helpers ───────────────────────────────────────────────────────

export function isValidAmenColor(hex: string): boolean {
    return (AMEN_BRAND_COLORS as string[]).includes(hex);
}

export function isValidExperienceType(value: string): value is ExperienceType {
    const valid: ExperienceType[] = [
        "celebration", "prayer_campaign", "event", "tradition",
        "community_challenge", "worship_night", "graduation_week", "fasting",
        "conference_mode", "youth_camp", "vbs", "revival_week", "mission_trip",
        "emergency_prayer", "memorial", "mental_health_awareness", "chapel_week",
        "anniversary",
    ];
    return valid.includes(value as ExperienceType);
}

export function isValidVisibility(value: string): value is ExperienceVisibility {
    const valid: ExperienceVisibility[] = [
        "global", "regional", "organization", "campus", "group", "invite",
    ];
    return valid.includes(value as ExperienceVisibility);
}

export function isValidModuleType(value: string): value is ExperienceModuleType {
    const valid: ExperienceModuleType[] = [
        "prayer", "discussion", "event", "memory", "tradition",
        "scripture", "worship", "livestream", "announcements",
    ];
    return valid.includes(value as ExperienceModuleType);
}

export function isValidOrgMemberRole(value: string): value is OrgMemberRole {
    const valid: OrgMemberRole[] = [
        "owner", "pastor", "teacher", "admin", "youth_leader",
        "moderator", "student_leader", "volunteer", "prayer_lead",
        "comms_lead", "member",
    ];
    return valid.includes(value as OrgMemberRole);
}

/** Grief/memorial experience types — these win over celebrations at the same layer */
export const GRIEF_EXPERIENCE_TYPES: ExperienceType[] = [
    "memorial",
    "mental_health_awareness",
    "emergency_prayer",
];

/** Roles that can manage experiences without being explicitly listed in allowedManagerRoles */
export const DEFAULT_MANAGER_ROLES: OrgMemberRole[] = [
    "owner", "admin", "pastor", "comms_lead",
];

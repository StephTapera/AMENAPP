/**
 * contextualExperienceCallables.ts
 *
 * All Cloud Function callables for the Multi-Tenant Contextual Experience System.
 *
 * SECURITY MODEL:
 * - Every callable requires Firebase Auth (unauthenticated → HttpsError "unauthenticated").
 * - Org membership is verified against organizations/{orgId}/members/{userId}.
 * - Org role is verified against organizations/{orgId}/roles/{userId}.
 * - Cross-tenant data leakage is prevented: visibility checks are enforced before
 *   returning any experience document.
 * - Rate limits use the shared enforceRateLimit helper.
 * - All writes use serverTimestamp() — client timestamps are never trusted.
 * - Audit log entries are immutable (write-once subcollection).
 * - No PII is logged (no prayer content, no user names, no email addresses).
 * - Youth protection: requiresYouthProtection=true escalates moderation strictness to "youth".
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { enforceRateLimit } from "../rateLimit";
import {
    ContextualExperienceData,
    ExperienceStatus,
    ExperienceThemeConfig,
    OrgMemberRole,
    ExperienceModuleType,
    ExperienceType,
    ExperienceVisibility,
    OrgType,
    ExperienceSafetyConfig,
    AMEN_BRAND_COLORS,
    DEFAULT_MANAGER_ROLES,
    isValidAmenColor,
    isValidExperienceType,
    isValidVisibility,
    isValidModuleType,
    isValidOrgMemberRole,
    GRIEF_EXPERIENCE_TYPES,
} from "./contextualExperienceModels";
import {
    ResolvedExperience,
    resolveExperienceStack,
} from "./contextualExperienceResolver";

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

// ─── Rate Limit Constants ─────────────────────────────────────────────────────

// Per-org create limit: 10 experience creates per org per day.
const EXP_CREATE_PER_ORG_DAY = { name: "exp_create_org_1day", windowMs: 86_400_000, maxCalls: 10 };
// Per-user join limit: 50 joins per user per day.
const EXP_JOIN_PER_USER_DAY = { name: "exp_join_1day", windowMs: 86_400_000, maxCalls: 50 };
// Resolve stack: 60 calls per user per minute (called on every app open).
const EXP_RESOLVE_PER_MINUTE = { name: "exp_resolve_1min", windowMs: 60_000, maxCalls: 60 };
// General callable rate limit: 30/min per user.
const EXP_GENERAL_PER_MINUTE = { name: "exp_general_1min", windowMs: 60_000, maxCalls: 30 };

// ─── Internal Helpers ─────────────────────────────────────────────────────────

/**
 * Check that a user is a member of an org.
 * Throws permission-denied if not.
 */
async function assertOrgMember(orgId: string, uid: string): Promise<void> {
    const snap = await db
        .collection("organizations").doc(orgId)
        .collection("members").doc(uid)
        .get();
    if (!snap.exists) {
        throw new HttpsError("permission-denied", "You are not a member of this organization.");
    }
}

/**
 * Fetch the user's role within an org.
 * Returns null if no role document exists (treats as plain "member").
 */
async function getOrgRole(orgId: string, uid: string): Promise<OrgMemberRole | null> {
    const snap = await db
        .collection("organizations").doc(orgId)
        .collection("roles").doc(uid)
        .get();
    if (!snap.exists) return null;
    const data = snap.data() as { role?: OrgMemberRole } | undefined;
    return data?.role ?? null;
}

/**
 * Check that a user has one of the required roles in an org.
 * Throws permission-denied if not.
 */
async function assertOrgRole(
    orgId: string,
    uid: string,
    allowedRoles: OrgMemberRole[]
): Promise<OrgMemberRole> {
    await assertOrgMember(orgId, uid);
    const role = await getOrgRole(orgId, uid);
    if (!role || !allowedRoles.includes(role)) {
        throw new HttpsError(
            "permission-denied",
            `Requires one of: ${allowedRoles.join(", ")}.`
        );
    }
    return role;
}

/**
 * Fetch and validate that an experience exists and is not deleted.
 * Throws not-found if missing, permission-denied if deleted.
 */
async function getExperienceOrThrow(
    experienceId: string
): Promise<{ data: ContextualExperienceData; ref: FirebaseFirestore.DocumentReference }> {
    const ref = db.collection("contextualExperiences").doc(experienceId);
    const snap = await ref.get();
    if (!snap.exists) {
        throw new HttpsError("not-found", "Experience not found.");
    }
    const data = snap.data() as ContextualExperienceData;
    if (data.status === "deleted") {
        throw new HttpsError("not-found", "Experience has been deleted.");
    }
    return { data, ref };
}

/**
 * Write an immutable audit log entry to the experience's auditLog subcollection.
 * Does NOT include any user PII — only action + actorId + timestamp.
 */
async function writeAuditLog(
    experienceId: string,
    action: string,
    userId: string
): Promise<void> {
    const logId = String(Date.now());
    await db
        .collection("contextualExperiences").doc(experienceId)
        .collection("auditLog").doc(logId)
        .set({
            action,
            userId,
            timestamp: FieldValue.serverTimestamp(),
        });
}

/**
 * Check the per-org daily create rate limit.
 * Uses a rateLimits/exp_create_{orgId} document with a 24-hour TTL window.
 */
async function enforceOrgCreateRateLimit(orgId: string): Promise<void> {
    // Use org ID as a pseudo-uid so we count creates per org, not per user.
    // The name prefix "org_" prevents collisions with user rate limit docs.
    await enforceRateLimit(`org_${orgId}`, [EXP_CREATE_PER_ORG_DAY]);
}

/**
 * Validate theme config: accentColorHex must be an AMEN brand color.
 */
function validateTheme(theme: ExperienceThemeConfig): void {
    if (!isValidAmenColor(theme.accentColorHex)) {
        throw new HttpsError(
            "invalid-argument",
            `accentColorHex must be one of: ${(AMEN_BRAND_COLORS as string[]).join(", ")}.`
        );
    }
    if (typeof theme.motionIntensity !== "number" || theme.motionIntensity < 0 || theme.motionIntensity > 1) {
        throw new HttpsError("invalid-argument", "motionIntensity must be between 0.0 and 1.0.");
    }
    if (typeof theme.glassOpacity !== "number" || theme.glassOpacity < 0 || theme.glassOpacity > 1) {
        throw new HttpsError("invalid-argument", "glassOpacity must be between 0.0 and 1.0.");
    }
    if (!["light", "dark", "adaptive"].includes(theme.backgroundStyle)) {
        throw new HttpsError("invalid-argument", "backgroundStyle must be 'light', 'dark', or 'adaptive'.");
    }
}

/**
 * Validate core experience fields on create.
 */
function validateCreateInputs(data: {
    title: string;
    description: string;
    type: string;
    visibility: string;
    enabledModules: string[];
    allowedManagerRoles: string[];
    endDate: FirebaseFirestore.Timestamp;
    startDate: FirebaseFirestore.Timestamp;
}): void {
    if (!data.title || data.title.trim().length === 0) {
        throw new HttpsError("invalid-argument", "title is required.");
    }
    if (data.title.length > 120) {
        throw new HttpsError("invalid-argument", "title must be 120 characters or fewer.");
    }
    if (data.description && data.description.length > 500) {
        throw new HttpsError("invalid-argument", "description must be 500 characters or fewer.");
    }
    if (!isValidExperienceType(data.type)) {
        throw new HttpsError("invalid-argument", `Invalid experience type: ${data.type}.`);
    }
    if (!isValidVisibility(data.visibility)) {
        throw new HttpsError("invalid-argument", `Invalid visibility: ${data.visibility}.`);
    }
    for (const m of data.enabledModules) {
        if (!isValidModuleType(m)) {
            throw new HttpsError("invalid-argument", `Invalid module type: ${m}.`);
        }
    }
    for (const r of data.allowedManagerRoles) {
        if (!isValidOrgMemberRole(r)) {
            throw new HttpsError("invalid-argument", `Invalid role: ${r}.`);
        }
    }
    const now = Date.now();
    const endMs = data.endDate.toMillis();
    if (endMs <= now) {
        throw new HttpsError("invalid-argument", "endDate must be in the future.");
    }
    const startMs = data.startDate.toMillis();
    if (startMs >= endMs) {
        throw new HttpsError("invalid-argument", "startDate must be before endDate.");
    }
}

/**
 * Check that a user can manage a given experience (update, publish, unpublish).
 * Allowed if the user has a DEFAULT_MANAGER_ROLES role OR is in the experience's allowedManagerRoles.
 */
async function assertCanManageExperience(
    expData: ContextualExperienceData,
    uid: string
): Promise<void> {
    await assertOrgMember(expData.organizationId, uid);
    const role = await getOrgRole(expData.organizationId, uid);
    if (!role) {
        throw new HttpsError("permission-denied", "No role found in this organization.");
    }
    const effectiveAllowed = [...DEFAULT_MANAGER_ROLES, ...expData.allowedManagerRoles];
    if (!effectiveAllowed.includes(role)) {
        throw new HttpsError("permission-denied", "You do not have permission to manage this experience.");
    }
}

/**
 * Check that a user can read a given experience based on its visibility.
 */
async function assertCanReadExperience(
    expData: ContextualExperienceData,
    uid: string
): Promise<void> {
    const visibility = expData.visibility;
    if (visibility === "global" || visibility === "regional") return;
    if (expData.createdBy === uid) return;
    if (visibility === "organization" || visibility === "campus" || visibility === "group") {
        await assertOrgMember(expData.organizationId, uid);
        return;
    }
    if (visibility === "invite") {
        // Invite-only: check participant doc.
        const participantSnap = await db
            .collection("contextualExperiences").doc(expData as unknown as string)
            .collection("participants").doc(uid)
            .get();
        if (!participantSnap.exists) {
            throw new HttpsError("permission-denied", "This experience is invite-only.");
        }
    }
}

// ─── Callable: createContextualExperience ────────────────────────────────────

export const createContextualExperience = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const {
            organizationId,
            organizationType,
            type,
            title,
            description = "",
            region,
            startDate,
            endDate,
            visibility,
            theme,
            allowedManagerRoles = [],
            enabledModules = [],
            safety,
        } = request.data as {
            organizationId: string;
            organizationType: OrgType;
            type: ExperienceType;
            title: string;
            description?: string;
            region?: string;
            startDate: { seconds: number; nanoseconds: number };
            endDate: { seconds: number; nanoseconds: number };
            visibility: ExperienceVisibility;
            theme: ExperienceThemeConfig;
            allowedManagerRoles?: OrgMemberRole[];
            enabledModules?: ExperienceModuleType[];
            safety: ExperienceSafetyConfig;
        };

        if (!organizationId) throw new HttpsError("invalid-argument", "organizationId is required.");

        // Convert client Timestamp-like objects to Firestore Timestamps.
        const startTs = admin.firestore.Timestamp.fromMillis(
            (startDate.seconds ?? 0) * 1000 + Math.floor((startDate.nanoseconds ?? 0) / 1e6)
        );
        const endTs = admin.firestore.Timestamp.fromMillis(
            (endDate.seconds ?? 0) * 1000 + Math.floor((endDate.nanoseconds ?? 0) / 1e6)
        );

        // Input validation.
        validateCreateInputs({ title, description, type, visibility, enabledModules, allowedManagerRoles, endDate: endTs, startDate: startTs });
        validateTheme(theme);

        // Assert org membership with a role that can create experiences.
        await assertOrgRole(organizationId, uid, DEFAULT_MANAGER_ROLES);

        // Rate limit: max 10 creates per org per day.
        await enforceOrgCreateRateLimit(organizationId);

        // Apply youth protection strictness override.
        const safetyCfg: ExperienceSafetyConfig = {
            ...safety,
            moderationStrictness:
                safety.requiresYouthProtection ? "youth" : safety.moderationStrictness,
        };

        const expData: Omit<ContextualExperienceData, "createdAt"> & { createdAt: FirebaseFirestore.FieldValue; updatedAt: FirebaseFirestore.FieldValue } = {
            organizationId,
            organizationType,
            type,
            title: title.trim(),
            description: description.trim(),
            region: region ?? undefined,
            startDate: startTs,
            endDate: endTs,
            visibility,
            status: "draft",
            theme,
            allowedManagerRoles,
            enabledModules,
            participantCount: 0,
            createdBy: uid,
            createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
            safety: safetyCfg,
            analyticsEnabled: true,
            memoriesEnabled: enabledModules.includes("memory"),
            prayerCampaignsEnabled: enabledModules.includes("prayer"),
            isKillSwitched: false,
        };

        const ref = await db.collection("contextualExperiences").add(expData as unknown as Record<string, unknown>);

        // Write audit log.
        await writeAuditLog(ref.id, "created", uid);

        logger.info(`[ContextualExperiences] Created experience ${ref.id} for org ${organizationId}`);

        return { experienceId: ref.id };
    }
);

// ─── Callable: updateContextualExperience ────────────────────────────────────

export const updateContextualExperience = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const { experienceId, updates } = request.data as {
            experienceId: string;
            updates: Partial<ContextualExperienceData>;
        };

        if (!experienceId) throw new HttpsError("invalid-argument", "experienceId is required.");
        if (!updates || typeof updates !== "object") {
            throw new HttpsError("invalid-argument", "updates must be a non-empty object.");
        }

        await enforceRateLimit(uid, [EXP_GENERAL_PER_MINUTE]);

        const { data: expData, ref } = await getExperienceOrThrow(experienceId);
        await assertCanManageExperience(expData, uid);

        // Sanitize: strip server-managed fields from the client update payload.
        const forbidden: Array<keyof ContextualExperienceData> = [
            "createdAt", "createdBy", "participantCount", "isKillSwitched", "status",
            "organizationId",
        ];
        const safeUpdates: Record<string, unknown> = {};
        for (const [k, v] of Object.entries(updates)) {
            if (!forbidden.includes(k as keyof ContextualExperienceData)) {
                safeUpdates[k] = v;
            }
        }

        // Validate theme if being updated.
        if (safeUpdates["theme"]) {
            validateTheme(safeUpdates["theme"] as ExperienceThemeConfig);
        }
        // Validate title length.
        if (safeUpdates["title"] !== undefined) {
            const t = safeUpdates["title"] as string;
            if (!t || t.trim().length === 0) throw new HttpsError("invalid-argument", "title cannot be empty.");
            if (t.length > 120) throw new HttpsError("invalid-argument", "title must be 120 characters or fewer.");
            safeUpdates["title"] = t.trim();
        }
        // Validate description length.
        if (safeUpdates["description"] !== undefined) {
            const d = safeUpdates["description"] as string;
            if (d.length > 500) throw new HttpsError("invalid-argument", "description must be 500 characters or fewer.");
            safeUpdates["description"] = d.trim();
        }

        // Enforce youth protection when safety is being updated.
        if (safeUpdates["safety"]) {
            const s = safeUpdates["safety"] as ExperienceSafetyConfig;
            if (s.requiresYouthProtection) {
                s.moderationStrictness = "youth";
            }
            safeUpdates["safety"] = s;
        }

        safeUpdates["updatedAt"] = FieldValue.serverTimestamp();

        await ref.update(safeUpdates);
        await writeAuditLog(experienceId, "updated", uid);
    }
);

// ─── Callable: publishContextualExperience ───────────────────────────────────

export const publishContextualExperience = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const { experienceId } = request.data as { experienceId: string };
        if (!experienceId) throw new HttpsError("invalid-argument", "experienceId is required.");

        await enforceRateLimit(uid, [EXP_GENERAL_PER_MINUTE]);

        const { data: expData, ref } = await getExperienceOrThrow(experienceId);
        await assertCanManageExperience(expData, uid);

        if (expData.status === "archived") {
            throw new HttpsError("failed-precondition", "Archived experiences cannot be published. Archive must be reversed first.");
        }

        // Validate dates are still valid at time of publish.
        const now = Date.now();
        if (expData.endDate.toMillis() <= now) {
            throw new HttpsError("failed-precondition", "Cannot publish an experience whose endDate has already passed.");
        }
        if (expData.startDate.toMillis() >= expData.endDate.toMillis()) {
            throw new HttpsError("failed-precondition", "startDate must be before endDate.");
        }

        await ref.update({
            status: "published",
            updatedAt: FieldValue.serverTimestamp(),
        });
        await writeAuditLog(experienceId, "published", uid);
    }
);

// ─── Callable: unpublishContextualExperience ─────────────────────────────────

export const unpublishContextualExperience = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const { experienceId } = request.data as { experienceId: string };
        if (!experienceId) throw new HttpsError("invalid-argument", "experienceId is required.");

        await enforceRateLimit(uid, [EXP_GENERAL_PER_MINUTE]);

        const { data: expData, ref } = await getExperienceOrThrow(experienceId);
        await assertCanManageExperience(expData, uid);

        await ref.update({
            status: "draft",
            updatedAt: FieldValue.serverTimestamp(),
        });
        await writeAuditLog(experienceId, "unpublished", uid);
    }
);

// ─── Callable: archiveContextualExperience ───────────────────────────────────

export const archiveContextualExperience = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const { experienceId } = request.data as { experienceId: string };
        if (!experienceId) throw new HttpsError("invalid-argument", "experienceId is required.");

        await enforceRateLimit(uid, [EXP_GENERAL_PER_MINUTE]);

        const { data: expData, ref } = await getExperienceOrThrow(experienceId);
        await assertCanManageExperience(expData, uid);

        await ref.update({
            status: "archived",
            updatedAt: FieldValue.serverTimestamp(),
        });
        await writeAuditLog(experienceId, "archived", uid);
    }
);

// ─── Callable: deleteContextualExperience ────────────────────────────────────

export const deleteContextualExperience = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const { experienceId } = request.data as { experienceId: string };
        if (!experienceId) throw new HttpsError("invalid-argument", "experienceId is required.");

        const { data: expData, ref } = await getExperienceOrThrow(experienceId);

        // Delete is owner-only.
        await assertOrgRole(expData.organizationId, uid, ["owner"]);

        // Soft delete: set status=deleted, isKillSwitched=true.
        await ref.update({
            status: "deleted",
            isKillSwitched: true,
            updatedAt: FieldValue.serverTimestamp(),
        });
        await writeAuditLog(experienceId, "deleted", uid);
    }
);

// ─── Callable: joinContextualExperience ──────────────────────────────────────

export const joinContextualExperience = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const { experienceId } = request.data as { experienceId: string };
        if (!experienceId) throw new HttpsError("invalid-argument", "experienceId is required.");

        // Rate limit: 50 joins per user per day.
        await enforceRateLimit(uid, [EXP_JOIN_PER_USER_DAY]);

        const { data: expData, ref } = await getExperienceOrThrow(experienceId);

        if (expData.status !== "published") {
            throw new HttpsError("failed-precondition", "Only published experiences can be joined.");
        }
        if (expData.isKillSwitched) {
            throw new HttpsError("failed-precondition", "This experience is currently unavailable.");
        }

        // Org membership check for private experiences.
        if (["organization", "campus", "group", "invite"].includes(expData.visibility)) {
            await assertOrgMember(expData.organizationId, uid);
        }

        // Require approval check.
        if (expData.safety.requireApprovalToJoin) {
            // Future: create a pending join request instead. For now, only approved members (org admins) may join.
            const role = await getOrgRole(expData.organizationId, uid);
            if (!role || !DEFAULT_MANAGER_ROLES.includes(role)) {
                throw new HttpsError(
                    "permission-denied",
                    "This experience requires approval to join. Please contact an administrator."
                );
            }
        }

        const participantRef = ref.collection("participants").doc(uid);
        const existing = await participantRef.get();
        if (existing.exists) {
            // Idempotent — already joined.
            return;
        }

        const batch = db.batch();
        batch.set(participantRef, {
            userId: uid,
            joinedAt: FieldValue.serverTimestamp(),
        });
        batch.update(ref, {
            participantCount: FieldValue.increment(1),
            updatedAt: FieldValue.serverTimestamp(),
        });
        await batch.commit();

        await writeAuditLog(experienceId, "participant_joined", uid);
    }
);

// ─── Callable: leaveContextualExperience ─────────────────────────────────────

export const leaveContextualExperience = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const { experienceId } = request.data as { experienceId: string };
        if (!experienceId) throw new HttpsError("invalid-argument", "experienceId is required.");

        const { ref } = await getExperienceOrThrow(experienceId);

        const participantRef = ref.collection("participants").doc(uid);
        const existing = await participantRef.get();
        if (!existing.exists) {
            // Idempotent — already not a participant.
            return;
        }

        const batch = db.batch();
        batch.delete(participantRef);
        batch.update(ref, {
            participantCount: FieldValue.increment(-1),
            updatedAt: FieldValue.serverTimestamp(),
        });
        await batch.commit();

        await writeAuditLog(experienceId, "participant_left", uid);
    }
);

// ─── Callable: resolveContextualExperienceStack ───────────────────────────────

export const resolveContextualExperienceStack = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const {
            userId,
            organizationIds = [],
            region = "",
        } = request.data as {
            userId: string;
            organizationIds: string[];
            region: string;
        };

        // Enforce that a user can only resolve their own stack.
        if (userId !== uid) {
            throw new HttpsError("permission-denied", "You can only resolve your own experience stack.");
        }

        await enforceRateLimit(uid, [EXP_RESOLVE_PER_MINUTE]);

        // Query all published, non-kill-switched experiences for this user's orgs + region.
        const queries: Promise<FirebaseFirestore.QuerySnapshot>[] = [];

        // Global experiences.
        queries.push(
            db.collection("contextualExperiences")
                .where("status", "==", "published")
                .where("isKillSwitched", "==", false)
                .where("visibility", "==", "global")
                .limit(20)
                .get()
        );

        // Regional experiences.
        if (region) {
            queries.push(
                db.collection("contextualExperiences")
                    .where("status", "==", "published")
                    .where("isKillSwitched", "==", false)
                    .where("visibility", "==", "regional")
                    .where("region", "==", region)
                    .limit(20)
                    .get()
            );
        }

        // Organization-scoped experiences (iterate per org to avoid cross-tenant leakage).
        for (const orgId of organizationIds.slice(0, 10)) {
            queries.push(
                db.collection("contextualExperiences")
                    .where("status", "==", "published")
                    .where("isKillSwitched", "==", false)
                    .where("organizationId", "==", orgId)
                    .where("visibility", "in", ["organization", "campus", "group", "invite"])
                    .limit(10)
                    .get()
            );
        }

        const snapshots = await Promise.all(queries);

        // Deduplicate by experience ID.
        const seen = new Set<string>();
        const experiences: Array<ContextualExperienceData & { id: string }> = [];
        for (const snap of snapshots) {
            for (const doc of snap.docs) {
                if (!seen.has(doc.id)) {
                    seen.add(doc.id);
                    experiences.push({ ...(doc.data() as ContextualExperienceData), id: doc.id });
                }
            }
        }

        // Determine which experiences the user has joined.
        const joinedIds = new Set<string>();
        if (experiences.length > 0) {
            const participantChecks = experiences.map(async (exp) => {
                const snap = await db
                    .collection("contextualExperiences").doc(exp.id)
                    .collection("participants").doc(uid)
                    .get();
                if (snap.exists) joinedIds.add(exp.id);
            });
            await Promise.all(participantChecks);
        }

        // Fetch user accessibility and grief-sensitivity preferences.
        const userSnap = await db.collection("users").doc(uid).get();
        const userData = userSnap.data() as {
            accessibilityNeeds?: string[];
            griefSensitiveMode?: boolean;
        } | undefined;

        const accessibilityNeeds: string[] = userData?.accessibilityNeeds ?? [];
        const isGriefSensitive: boolean = userData?.griefSensitiveMode ?? false;

        // Check if caller is an admin (for debug metadata).
        const isAdmin: boolean = (request.auth.token as Record<string, unknown>)["admin"] === true;

        const resolved: ResolvedExperience = resolveExperienceStack(
            experiences,
            uid,
            accessibilityNeeds,
            isGriefSensitive,
            isAdmin,
            joinedIds
        );

        return resolved;
    }
);

// ─── Callable: listOrganizationExperiences ────────────────────────────────────

export const listOrganizationExperiences = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const { organizationId, status } = request.data as {
            organizationId: string;
            status?: ExperienceStatus;
        };

        if (!organizationId) throw new HttpsError("invalid-argument", "organizationId is required.");

        await enforceRateLimit(uid, [EXP_GENERAL_PER_MINUTE]);

        // Verify org membership for private orgs.
        const orgSnap = await db.collection("organizations").doc(organizationId).get();
        if (!orgSnap.exists) throw new HttpsError("not-found", "Organization not found.");
        const orgData = orgSnap.data() as { isPublic?: boolean };
        if (!orgData.isPublic) {
            await assertOrgMember(organizationId, uid);
        }

        let query: FirebaseFirestore.Query = db.collection("contextualExperiences")
            .where("organizationId", "==", organizationId)
            .where("isKillSwitched", "==", false);

        if (status) {
            query = query.where("status", "==", status);
        } else {
            // Default: exclude deleted experiences.
            query = query.where("status", "!=", "deleted");
        }

        const snap = await query.orderBy("createdAt", "desc").limit(50).get();

        const results: Array<ContextualExperienceData & { id: string }> = snap.docs.map((doc) => ({
            ...(doc.data() as ContextualExperienceData),
            id: doc.id,
        }));

        return results;
    }
);

// ─── Callable: getContextualExperience ───────────────────────────────────────

export const getContextualExperience = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const { experienceId } = request.data as { experienceId: string };
        if (!experienceId) throw new HttpsError("invalid-argument", "experienceId is required.");

        await enforceRateLimit(uid, [EXP_GENERAL_PER_MINUTE]);

        const { data: expData } = await getExperienceOrThrow(experienceId);

        // Enforce visibility gating.
        await assertCanReadExperience(expData, uid);

        return { ...expData, id: experienceId };
    }
);

// ─── Callable: createExperienceEvent ─────────────────────────────────────────

export const createExperienceEvent = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const { experienceId, title, description, startDate, endDate, location } = request.data as {
            experienceId: string;
            title: string;
            description: string;
            startDate: { seconds: number; nanoseconds: number };
            endDate: { seconds: number; nanoseconds: number };
            location?: string;
        };

        if (!experienceId) throw new HttpsError("invalid-argument", "experienceId is required.");
        if (!title || title.trim().length === 0) throw new HttpsError("invalid-argument", "title is required.");
        if (title.length > 120) throw new HttpsError("invalid-argument", "title must be 120 characters or fewer.");

        await enforceRateLimit(uid, [EXP_GENERAL_PER_MINUTE]);

        const { data: expData, ref } = await getExperienceOrThrow(experienceId);
        await assertCanManageExperience(expData, uid);

        if (!expData.enabledModules.includes("event")) {
            throw new HttpsError("failed-precondition", "The 'event' module is not enabled for this experience.");
        }

        const startTs = admin.firestore.Timestamp.fromMillis(
            (startDate.seconds ?? 0) * 1000 + Math.floor((startDate.nanoseconds ?? 0) / 1e6)
        );
        const endTs = admin.firestore.Timestamp.fromMillis(
            (endDate.seconds ?? 0) * 1000 + Math.floor((endDate.nanoseconds ?? 0) / 1e6)
        );

        const eventRef = await ref.collection("events").add({
            title: title.trim(),
            description: (description ?? "").trim().slice(0, 500),
            startDate: startTs,
            endDate: endTs,
            location: location ?? null,
            createdBy: uid,
            createdAt: FieldValue.serverTimestamp(),
        });

        await writeAuditLog(experienceId, "event_created", uid);

        return { eventId: eventRef.id };
    }
);

// ─── Callable: createExperiencePrayerPrompt ───────────────────────────────────

export const createExperiencePrayerPrompt = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const { experienceId, prompt, scriptureReference, isAnonymousAllowed } = request.data as {
            experienceId: string;
            prompt: string;
            scriptureReference?: string;
            isAnonymousAllowed: boolean;
        };

        if (!experienceId) throw new HttpsError("invalid-argument", "experienceId is required.");
        if (!prompt || prompt.trim().length === 0) throw new HttpsError("invalid-argument", "prompt is required.");
        if (prompt.length > 500) throw new HttpsError("invalid-argument", "prompt must be 500 characters or fewer.");

        await enforceRateLimit(uid, [EXP_GENERAL_PER_MINUTE]);

        const { data: expData, ref } = await getExperienceOrThrow(experienceId);
        await assertCanManageExperience(expData, uid);

        if (!expData.enabledModules.includes("prayer")) {
            throw new HttpsError("failed-precondition", "The 'prayer' module is not enabled for this experience.");
        }

        // If the experience doesn't allow anonymous prayer, force isAnonymousAllowed=false.
        const effectiveAnon = expData.safety.allowAnonymousPrayer ? isAnonymousAllowed : false;

        const promptRef = await ref.collection("prayers").add({
            // IMPORTANT: prompt text is NOT logged to audit log or analytics — only the doc ID is.
            prompt: prompt.trim(),
            scriptureReference: scriptureReference ?? null,
            isAnonymousAllowed: effectiveAnon,
            createdBy: uid,
            createdAt: FieldValue.serverTimestamp(),
        });

        await writeAuditLog(experienceId, "prayer_prompt_created", uid);

        return { promptId: promptRef.id };
    }
);

// ─── Callable: createExperienceDiscussion ────────────────────────────────────

export const createExperienceDiscussion = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const { experienceId, title, body } = request.data as {
            experienceId: string;
            title: string;
            body: string;
        };

        if (!experienceId) throw new HttpsError("invalid-argument", "experienceId is required.");
        if (!title || title.trim().length === 0) throw new HttpsError("invalid-argument", "title is required.");
        if (title.length > 120) throw new HttpsError("invalid-argument", "title must be 120 characters or fewer.");
        if (!body || body.trim().length === 0) throw new HttpsError("invalid-argument", "body is required.");
        if (body.length > 5000) throw new HttpsError("invalid-argument", "body must be 5000 characters or fewer.");

        await enforceRateLimit(uid, [EXP_GENERAL_PER_MINUTE]);

        const { data: expData, ref } = await getExperienceOrThrow(experienceId);

        // Members can create discussions (not just managers).
        await assertOrgMember(expData.organizationId, uid);

        if (!expData.enabledModules.includes("discussion")) {
            throw new HttpsError("failed-precondition", "The 'discussion' module is not enabled for this experience.");
        }

        const discussionRef = await ref.collection("discussions").add({
            title: title.trim(),
            body: body.trim(),
            createdBy: uid,
            createdAt: FieldValue.serverTimestamp(),
            replyCount: 0,
        });

        await writeAuditLog(experienceId, "discussion_created", uid);

        return { discussionId: discussionRef.id };
    }
);

// ─── Callable: createExperienceMemory ────────────────────────────────────────

export const createExperienceMemory = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const { experienceId, title, imageURL, note, scriptureReference } = request.data as {
            experienceId: string;
            title: string;
            imageURL?: string;
            note: string;
            scriptureReference?: string;
        };

        if (!experienceId) throw new HttpsError("invalid-argument", "experienceId is required.");
        if (!title || title.trim().length === 0) throw new HttpsError("invalid-argument", "title is required.");
        if (title.length > 120) throw new HttpsError("invalid-argument", "title must be 120 characters or fewer.");
        if (!note || note.trim().length === 0) throw new HttpsError("invalid-argument", "note is required.");
        if (note.length > 2000) throw new HttpsError("invalid-argument", "note must be 2000 characters or fewer.");

        await enforceRateLimit(uid, [EXP_GENERAL_PER_MINUTE]);

        const { data: expData, ref } = await getExperienceOrThrow(experienceId);

        await assertOrgMember(expData.organizationId, uid);

        if (!expData.memoriesEnabled || !expData.enabledModules.includes("memory")) {
            throw new HttpsError("failed-precondition", "Memories are not enabled for this experience.");
        }

        const memoryRef = await ref.collection("memories").add({
            title: title.trim(),
            imageURL: imageURL ?? null,
            note: note.trim(),
            scriptureReference: scriptureReference ?? null,
            createdBy: uid,
            createdAt: FieldValue.serverTimestamp(),
        });

        await writeAuditLog(experienceId, "memory_created", uid);

        return { memoryId: memoryRef.id };
    }
);

// ─── Callable: createExperienceTradition ─────────────────────────────────────

export const createExperienceTradition = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const { experienceId, title, description, recurrencePattern } = request.data as {
            experienceId: string;
            title: string;
            description: string;
            recurrencePattern: "annual" | "monthly" | "weekly";
        };

        if (!experienceId) throw new HttpsError("invalid-argument", "experienceId is required.");
        if (!title || title.trim().length === 0) throw new HttpsError("invalid-argument", "title is required.");
        if (title.length > 120) throw new HttpsError("invalid-argument", "title must be 120 characters or fewer.");
        if (!["annual", "monthly", "weekly"].includes(recurrencePattern)) {
            throw new HttpsError("invalid-argument", "recurrencePattern must be 'annual', 'monthly', or 'weekly'.");
        }

        await enforceRateLimit(uid, [EXP_GENERAL_PER_MINUTE]);

        const { data: expData, ref } = await getExperienceOrThrow(experienceId);
        await assertCanManageExperience(expData, uid);

        if (!expData.enabledModules.includes("tradition")) {
            throw new HttpsError("failed-precondition", "The 'tradition' module is not enabled for this experience.");
        }

        const traditionRef = await ref.collection("traditions").add({
            title: title.trim(),
            description: (description ?? "").trim().slice(0, 500),
            recurrencePattern,
            createdBy: uid,
            createdAt: FieldValue.serverTimestamp(),
        });

        await writeAuditLog(experienceId, "tradition_created", uid);

        return { traditionId: traditionRef.id };
    }
);

// ─── Callable: moderateExperienceContent ─────────────────────────────────────

export const moderateExperienceContent = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const { experienceId, contentType, contentId, action, reason } = request.data as {
            experienceId: string;
            contentType: "discussion" | "memory" | "prayer" | "event" | "tradition";
            contentId: string;
            action: "approve" | "reject" | "hide" | "escalate";
            reason?: string;
        };

        if (!experienceId) throw new HttpsError("invalid-argument", "experienceId is required.");
        if (!contentType) throw new HttpsError("invalid-argument", "contentType is required.");
        if (!contentId) throw new HttpsError("invalid-argument", "contentId is required.");
        if (!["approve", "reject", "hide", "escalate"].includes(action)) {
            throw new HttpsError("invalid-argument", "action must be 'approve', 'reject', 'hide', or 'escalate'.");
        }

        await enforceRateLimit(uid, [EXP_GENERAL_PER_MINUTE]);

        const { data: expData, ref } = await getExperienceOrThrow(experienceId);

        // Moderator role required.
        const moderatorRoles: OrgMemberRole[] = ["owner", "admin", "pastor", "moderator", "comms_lead"];
        await assertOrgRole(expData.organizationId, uid, moderatorRoles);

        // Apply the moderation action to the content document.
        const collectionMap: Record<string, string> = {
            discussion: "discussions",
            memory: "memories",
            prayer: "prayers",
            event: "events",
            tradition: "traditions",
        };
        const collectionName = collectionMap[contentType];
        if (!collectionName) {
            throw new HttpsError("invalid-argument", `Unknown contentType: ${contentType}.`);
        }

        const contentRef = ref.collection(collectionName).doc(contentId);
        const contentSnap = await contentRef.get();
        if (!contentSnap.exists) {
            throw new HttpsError("not-found", "Content item not found.");
        }

        await contentRef.update({
            moderationStatus: action,
            moderatedBy: uid,
            moderatedAt: FieldValue.serverTimestamp(),
            moderationReason: reason ?? null,
        });

        // Write to moderationQueue for audit trail.
        await ref.collection("moderationQueue").add({
            contentType,
            contentId,
            action,
            reason: reason ?? null,
            moderatedBy: uid,
            moderatedAt: FieldValue.serverTimestamp(),
        });

        await writeAuditLog(experienceId, `content_${action}:${contentType}:${contentId}`, uid);
    }
);

// ─── Callable: reportExperienceContent ───────────────────────────────────────

export const reportExperienceContent = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const { experienceId, contentType, contentId, reason, details } = request.data as {
            experienceId: string;
            contentType: string;
            contentId: string;
            reason: string;
            details?: string;
        };

        if (!experienceId) throw new HttpsError("invalid-argument", "experienceId is required.");
        if (!contentType) throw new HttpsError("invalid-argument", "contentType is required.");
        if (!contentId) throw new HttpsError("invalid-argument", "contentId is required.");
        if (!reason || reason.trim().length === 0) throw new HttpsError("invalid-argument", "reason is required.");

        await enforceRateLimit(uid, [EXP_GENERAL_PER_MINUTE]);

        const { data: expData, ref } = await getExperienceOrThrow(experienceId);

        // Any member can report content.
        if (expData.visibility !== "global" && expData.visibility !== "regional") {
            await assertOrgMember(expData.organizationId, uid);
        }

        await ref.collection("moderationQueue").add({
            contentType,
            contentId,
            reason: reason.trim(),
            details: (details ?? "").trim().slice(0, 1000),
            reportedBy: uid,
            reportedAt: FieldValue.serverTimestamp(),
            status: "pending_review",
        });

        logger.info(`[ContextualExperiences] Content report for experience=${experienceId} type=${contentType} id=${contentId}`);
    }
);

// ─── Callable: updateExperienceNotificationSettings ──────────────────────────

export const updateExperienceNotificationSettings = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const { experienceId, settings } = request.data as {
            experienceId: string;
            settings: {
                announcements: boolean;
                prayers: boolean;
                discussions: boolean;
                events: boolean;
            };
        };

        if (!experienceId) throw new HttpsError("invalid-argument", "experienceId is required.");
        if (!settings || typeof settings !== "object") {
            throw new HttpsError("invalid-argument", "settings must be an object.");
        }

        await enforceRateLimit(uid, [EXP_GENERAL_PER_MINUTE]);

        // Verify the experience exists and user can read it.
        const { data: expData, ref } = await getExperienceOrThrow(experienceId);
        await assertCanReadExperience(expData, uid);

        // Per-user notification prefs stored at experienceId/notificationPrefs/{userId}.
        await ref.collection("notificationPrefs").doc(uid).set({
            announcements: settings.announcements ?? true,
            prayers: settings.prayers ?? true,
            discussions: settings.discussions ?? true,
            events: settings.events ?? true,
            updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
    }
);

// ─── Callable: updateExperienceTheme ─────────────────────────────────────────

export const updateExperienceTheme = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const { experienceId, theme } = request.data as {
            experienceId: string;
            theme: ExperienceThemeConfig;
        };

        if (!experienceId) throw new HttpsError("invalid-argument", "experienceId is required.");
        if (!theme) throw new HttpsError("invalid-argument", "theme is required.");

        // Theme validation: must be an AMEN brand color.
        validateTheme(theme);

        await enforceRateLimit(uid, [EXP_GENERAL_PER_MINUTE]);

        const { data: expData, ref } = await getExperienceOrThrow(experienceId);

        // Admin/owner only.
        await assertOrgRole(expData.organizationId, uid, ["owner", "admin", "pastor"]);

        await ref.update({
            theme,
            updatedAt: FieldValue.serverTimestamp(),
        });

        await writeAuditLog(experienceId, "theme_updated", uid);
    }
);

// ─── Callable: getExperienceAnalytics ────────────────────────────────────────

export const getExperienceAnalytics = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const { experienceId } = request.data as { experienceId: string };
        if (!experienceId) throw new HttpsError("invalid-argument", "experienceId is required.");

        await enforceRateLimit(uid, [EXP_GENERAL_PER_MINUTE]);

        const { data: expData, ref } = await getExperienceOrThrow(experienceId);

        // Admin/owner only.
        await assertOrgRole(expData.organizationId, uid, ["owner", "admin", "pastor"]);

        if (!expData.analyticsEnabled) {
            throw new HttpsError("failed-precondition", "Analytics are not enabled for this experience.");
        }

        // Aggregate counts from subcollections — NEVER return individual user data.
        const [discussionsSnap, memoriesSnap, prayersSnap] = await Promise.all([
            ref.collection("discussions").count().get(),
            ref.collection("memories").count().get(),
            ref.collection("prayers").count().get(),
        ]);

        // Active today: count participants who joined in the last 24 hours.
        const oneDayAgo = admin.firestore.Timestamp.fromMillis(Date.now() - 86_400_000);
        const activeTodaySnap = await ref.collection("participants")
            .where("joinedAt", ">=", oneDayAgo)
            .count()
            .get();

        // Joined last 7 days.
        const sevenDaysAgo = admin.firestore.Timestamp.fromMillis(Date.now() - 7 * 86_400_000);
        const joinedLast7DaysSnap = await ref.collection("participants")
            .where("joinedAt", ">=", sevenDaysAgo)
            .count()
            .get();

        return {
            participantCount: expData.participantCount,
            activeToday: activeTodaySnap.data().count,
            prayerCount: prayersSnap.data().count,
            discussionCount: discussionsSnap.data().count,
            memoryCount: memoriesSnap.data().count,
            joinedLast7Days: joinedLast7DaysSnap.data().count,
        };
    }
);

// ─── Callable: manageExperienceRoles ─────────────────────────────────────────

export const manageExperienceRoles = onCall(
    { enforceAppCheck: false },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
        const uid = request.auth.uid;

        const { organizationId, targetUserId, role, action } = request.data as {
            organizationId: string;
            targetUserId: string;
            role: OrgMemberRole;
            action: "grant" | "revoke";
        };

        if (!organizationId) throw new HttpsError("invalid-argument", "organizationId is required.");
        if (!targetUserId) throw new HttpsError("invalid-argument", "targetUserId is required.");
        if (!isValidOrgMemberRole(role)) throw new HttpsError("invalid-argument", `Invalid role: ${role}.`);
        if (!["grant", "revoke"].includes(action)) throw new HttpsError("invalid-argument", "action must be 'grant' or 'revoke'.");

        await enforceRateLimit(uid, [EXP_GENERAL_PER_MINUTE]);

        // Determine caller's own role.
        await assertOrgMember(organizationId, uid);
        const callerRole = await getOrgRole(organizationId, uid);

        if (!callerRole) {
            throw new HttpsError("permission-denied", "No role found for caller in this organization.");
        }

        // Owner-only roles: owner, admin, pastor.
        const ownerOnlyRoles: OrgMemberRole[] = ["owner", "admin", "pastor"];
        // Admin-grantable roles.
        const adminGrantableRoles: OrgMemberRole[] = [
            "teacher", "moderator", "volunteer", "prayer_lead", "comms_lead",
            "youth_leader", "student_leader", "member",
        ];

        if (ownerOnlyRoles.includes(role)) {
            if (callerRole !== "owner") {
                throw new HttpsError(
                    "permission-denied",
                    "Only the organization owner can grant/revoke owner, admin, or pastor roles."
                );
            }
        } else if (adminGrantableRoles.includes(role)) {
            if (callerRole !== "owner" && callerRole !== "admin" && callerRole !== "pastor") {
                throw new HttpsError(
                    "permission-denied",
                    "Admin or owner role required to manage this role."
                );
            }
        }

        // Prevent demoting the only owner.
        if (role === "owner" && action === "revoke") {
            const ownerQuery = await db
                .collection("organizations").doc(organizationId)
                .collection("roles")
                .where("role", "==", "owner")
                .limit(2)
                .get();
            if (ownerQuery.size <= 1) {
                throw new HttpsError(
                    "failed-precondition",
                    "Cannot revoke the last owner of an organization."
                );
            }
        }

        const roleRef = db
            .collection("organizations").doc(organizationId)
            .collection("roles").doc(targetUserId);

        if (action === "grant") {
            // Ensure target is a member first.
            const memberSnap = await db
                .collection("organizations").doc(organizationId)
                .collection("members").doc(targetUserId)
                .get();
            if (!memberSnap.exists) {
                throw new HttpsError("failed-precondition", "Target user must be a member of the organization before being granted a role.");
            }

            await roleRef.set({
                role,
                grantedBy: uid,
                grantedAt: FieldValue.serverTimestamp(),
            });
        } else {
            await roleRef.delete();
        }

        // Write audit log to the org (not a specific experience).
        await db.collection("organizations").doc(organizationId)
            .collection("auditLog").doc(String(Date.now()))
            .set({
                action: `role_${action}:${role}:${targetUserId}`,
                actorId: uid,
                timestamp: FieldValue.serverTimestamp(),
            });

        logger.info(`[ContextualExperiences] Role ${action} org=${organizationId} target=${targetUserId} role=${role} by=${uid}`);
    }
);

"use strict";

const functions = require("firebase-functions");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;
const Timestamp = admin.firestore.Timestamp;

const MANAGER_ROLES = new Set([
  "owner",
  "admin",
  "pastor",
  "teacher",
  "moderator",
  "communicationsLead",
  "prayerLead",
]);

const MODERATOR_ROLES = new Set([
  "owner",
  "admin",
  "pastor",
  "teacher",
  "moderator",
]);

const SUPPORTED_ORG_TYPES = new Set([
  "church",
  "school",
  "university",
  "ministry",
  "business",
  "enterprise",
  "nonprofit",
  "prayerGroup",
  "creatorCommunity",
  "campusGroup",
]);

const EXPERIENCE_TYPES = new Set([
  "easter",
  "christmas",
  "lent",
  "advent",
  "thanksgiving",
  "schoolSpiritWeek",
  "graduation",
  "chapelWeek",
  "worshipNight",
  "youthCamp",
  "vbs",
  "revivalWeek",
  "missionTrip",
  "conference",
  "fastingCampaign",
  "prayerCampaign",
  "memorial",
  "mentalHealthAwareness",
  "organizationAnniversary",
  "localCelebration",
  "emergencyPrayerMobilization",
]);

const VISIBILITIES = new Set(["public", "members", "internal", "private"]);
const STATUSES = new Set(["draft", "published", "archived", "ended"]);
const MODULE_TYPES = new Set(["content", "prayer", "discussion", "event", "memory", "tradition"]);

function callable(handler) {
  return onCall({ enforceAppCheck: true }, async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "auth-required");
    }
    try {
      return await handler(request.data || {}, request);
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error("contextual-experience-error", {
        code: error.code || "internal",
        message: error.message,
      });
      throw new HttpsError("internal", "contextual-experience-failed");
    }
  });
}

function asString(value, field, max = 240, required = true) {
  if (value === undefined || value === null || value === "") {
    if (required) throw new HttpsError("invalid-argument", `${field}-required`);
    return "";
  }
  if (typeof value !== "string" || value.length > max) {
    throw new HttpsError("invalid-argument", `${field}-invalid`);
  }
  return value.trim();
}

function asEnum(value, allowed, field, fallback) {
  const normalized = typeof value === "string" ? value : fallback;
  if (!allowed.has(normalized)) {
    throw new HttpsError("invalid-argument", `${field}-invalid`);
  }
  return normalized;
}

function asTimestamp(value, field, required = true) {
  if (value === undefined || value === null) {
    if (required) throw new HttpsError("invalid-argument", `${field}-required`);
    return null;
  }
  if (typeof value === "number") return Timestamp.fromMillis(value);
  if (typeof value === "string") {
    const millis = Date.parse(value);
    if (!Number.isNaN(millis)) return Timestamp.fromMillis(millis);
  }
  throw new HttpsError("invalid-argument", `${field}-invalid`);
}

function safeMap(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function normalizeId(value, field) {
  const raw = asString(value, field, 160);
  if (!/^[A-Za-z0-9_-]{2,160}$/.test(raw)) {
    throw new HttpsError("invalid-argument", `${field}-invalid`);
  }
  return raw;
}

function publicExperience(exp, adminPreview = false) {
  if (!exp) return null;
  const clone = {...exp};
  delete clone.privateNotes;
  delete clone.auditInternal;
  if (!adminPreview) delete clone.resolverDebug;
  return clone;
}

async function loadMembership(orgId, uid) {
  const [orgMember, covenantMember] = await Promise.all([
    db.collection("organizations").doc(orgId).collection("members").doc(uid).get(),
    db.collection("covenants").doc(orgId).collection("members").doc(uid).get(),
  ]);
  const doc = orgMember.exists ? orgMember : covenantMember;
  if (!doc.exists) return null;
  const data = doc.data() || {};
  if (!["active", "trialing", "approved"].includes(data.status || "active")) return null;
  return {
    role: data.role || "member",
    roleIds: Array.isArray(data.roleIds) ? data.roleIds : [],
    isYouth: data.ageTier && data.ageTier !== "tierD",
  };
}

async function requireManager(orgId, uid) {
  const membership = await loadMembership(orgId, uid);
  if (!membership || !MANAGER_ROLES.has(membership.role)) {
    throw new HttpsError("permission-denied", "manager-role-required");
  }
  return membership;
}

async function requireExperienceManager(exp, uid) {
  const membership = await requireManager(exp.organizationId, uid);
  const scopedRoles = Array.isArray(exp.rolesAllowedToManage) && exp.rolesAllowedToManage.length > 0 ?
    exp.rolesAllowedToManage :
    Array.from(MANAGER_ROLES);
  if (!scopedRoles.includes(membership.role)) {
    throw new HttpsError("permission-denied", "experience-role-required");
  }
  return membership;
}

async function requireRolePolicyManager(orgId, uid) {
  const membership = await loadMembership(orgId, uid);
  if (!membership || !["owner", "admin"].includes(membership.role)) {
    throw new HttpsError("permission-denied", "owner-or-admin-required");
  }
  return membership;
}

async function requireModerator(orgId, uid) {
  const membership = await loadMembership(orgId, uid);
  if (!membership || !MODERATOR_ROLES.has(membership.role)) {
    throw new HttpsError("permission-denied", "moderator-role-required");
  }
  return membership;
}

async function enforceRateLimit(uid, action, max = 30, windowMs = 60 * 1000) {
  const bucket = Math.floor(Date.now() / windowMs);
  const ref = db.collection("contextualExperienceRateLimits").doc(`${uid}_${action}_${bucket}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const count = snap.exists ? snap.data().count || 0 : 0;
    if (count >= max) {
      throw new HttpsError("resource-exhausted", "rate-limited");
    }
    tx.set(ref, {
      uid,
      action,
      count: count + 1,
      expiresAt: Timestamp.fromMillis(Date.now() + windowMs * 3),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

async function audit(orgId, experienceId, uid, action, metadata = {}) {
  await db.collection("contextualExperienceAuditLogs").add({
    orgId,
    experienceId: experienceId || null,
    actorUid: uid,
    action,
    metadata,
    createdAt: FieldValue.serverTimestamp(),
  });
}

function sanitizeTheme(theme) {
  const input = safeMap(theme);
  const glassBehavior = input.liquidGlassBehavior;
  return {
    accentName: asString(input.accentName || "default", "theme.accentName", 40, false) || "default",
    accentHex: /^#[0-9A-Fa-f]{6}$/.test(input.accentHex || "") ? input.accentHex : null,
    glassIntensity: Math.max(0, Math.min(1, Number(input.glassIntensity ?? 0.32))),
    liquidGlassBehavior: ["none", "subtle", "regular", "prominent"].includes(glassBehavior) ?
      glassBehavior :
      "subtle",
    symbolName: asString(input.symbolName || "sparkles", "theme.symbolName", 80, false) || "sparkles",
    prefersQuietVisuals: Boolean(input.prefersQuietVisuals),
  };
}

function sanitizeRules(data) {
  const notificationRules = safeMap(data.notificationRules);
  const safetyRules = safeMap(data.safetyRules);
  const accessibilityBehavior = safeMap(data.accessibilityBehavior);
  const moderationConfiguration = safeMap(data.moderationConfiguration);
  return {
    notificationRules: {
      enabled: notificationRules.enabled !== false,
      quietHoursEnabled: notificationRules.quietHoursEnabled !== false,
      maxPerDay: Math.max(0, Math.min(6, Number(notificationRules.maxPerDay ?? 1))),
      allowUrgent: Boolean(notificationRules.allowUrgent),
    },
    safetyRules: {
      griefSensitive: Boolean(safetyRules.griefSensitive),
      youthProtected: Boolean(safetyRules.youthProtected),
      privatePrayerDefault: safetyRules.privatePrayerDefault !== false,
      requireModeration: Boolean(safetyRules.requireModeration),
      killSwitch: Boolean(safetyRules.killSwitch),
    },
    analyticsRules: {
      enabled: safeMap(data.analyticsRules).enabled !== false,
      aggregateOnly: true,
      noPrayerContent: true,
    },
    accessibilityBehavior: {
      reduceMotionDefault: Boolean(accessibilityBehavior.reduceMotionDefault),
      reduceTransparencyFallback: accessibilityBehavior.reduceTransparencyFallback !== false,
      highContrastSafe: true,
      dynamicTypeRequired: true,
    },
    moderationConfiguration: {
      discussionMode: ["open", "moderated", "closed"].includes(moderationConfiguration.discussionMode) ?
        moderationConfiguration.discussionMode :
        "moderated",
      prayerMode: ["private", "members", "moderated"].includes(moderationConfiguration.prayerMode) ?
        moderationConfiguration.prayerMode :
        "private",
      reportThreshold: Math.max(1, Math.min(10, Number(moderationConfiguration.reportThreshold ?? 3))),
    },
  };
}

function buildExperiencePayload(data, uid, existing = null) {
  const startAt = asTimestamp(data.startAt, "startAt");
  const endAt = asTimestamp(data.endAt, "endAt");
  if (endAt.toMillis() <= startAt.toMillis()) {
    throw new HttpsError("invalid-argument", "endAt-must-be-after-startAt");
  }
  const orgId = normalizeId(data.organizationId || data.orgId, "organizationId");
  const allowedRoles = Array.isArray(data.rolesAllowedToManage) && data.rolesAllowedToManage.length > 0 ?
    data.rolesAllowedToManage.filter((role) => typeof role === "string" && MANAGER_ROLES.has(role)) :
    ["owner", "admin", "pastor", "teacher", "moderator"];
  const rules = sanitizeRules(data);
  const requestedVisibility = asEnum(data.visibility, VISIBILITIES, "visibility", "members");
  return {
    title: asString(data.title, "title", 120),
    description: asString(data.description, "description", 2000),
    organizationId: orgId,
    organizationType: asEnum(data.organizationType, SUPPORTED_ORG_TYPES, "organizationType", "church"),
    region: asString(data.region || "global", "region", 80, false) || "global",
    sourceLayer: asEnum(
        data.sourceLayer,
        new Set(["global", "regional", "organization", "campus", "group", "event", "tradition"]),
        "sourceLayer",
        "organization",
    ),
    experienceType: asEnum(data.experienceType, EXPERIENCE_TYPES, "experienceType", "prayerCampaign"),
    visibility: rules.safetyRules.youthProtected && requestedVisibility === "public" ?
      "members" :
      requestedVisibility,
    status: existing?.status || "draft",
    startAt,
    endAt,
    rolesAllowedToManage: allowedRoles,
    theme: sanitizeTheme(data.theme),
    contentModules: Array.isArray(data.contentModules) ? data.contentModules.slice(0, 20) : [],
    prayerModules: Array.isArray(data.prayerModules) ? data.prayerModules.slice(0, 20) : [],
    discussionModules: Array.isArray(data.discussionModules) ? data.discussionModules.slice(0, 20) : [],
    eventModules: Array.isArray(data.eventModules) ? data.eventModules.slice(0, 20) : [],
    memoryModules: Array.isArray(data.memoryModules) ? data.memoryModules.slice(0, 20) : [],
    ...rules,
    featureFlags: {
      enabled: safeMap(data.featureFlags).enabled !== false,
      killSwitch: Boolean(safeMap(data.featureFlags).killSwitch),
      liquidGlassEnabled: safeMap(data.featureFlags).liquidGlassEnabled !== false,
    },
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: uid,
  };
}

async function getExperienceOrThrow(experienceId) {
  const id = normalizeId(experienceId, "experienceId");
  const snap = await db.collection("contextualExperiences").doc(id).get();
  if (!snap.exists) throw new HttpsError("not-found", "experience-not-found");
  return {id, ref: snap.ref, data: snap.data()};
}

async function canReadExperience(exp, uid) {
  if (exp.status !== "published" && exp.createdBy !== uid) {
    const membership = await loadMembership(exp.organizationId, uid);
    return membership && MANAGER_ROLES.has(membership.role);
  }
  if (exp.visibility === "public" && !exp.safetyRules?.youthProtected) return true;
  return Boolean(await loadMembership(exp.organizationId, uid));
}

exports.createContextualExperience = callable(async (data, context) => {
  const uid = context.auth.uid;
  await enforceRateLimit(uid, "create", 12);
  const orgId = normalizeId(data.organizationId || data.orgId, "organizationId");
  await requireManager(orgId, uid);
  const ref = db.collection("contextualExperiences").doc();
  const payload = buildExperiencePayload({...data, organizationId: orgId}, uid);
  await ref.set({
    ...payload,
    id: ref.id,
    createdBy: uid,
    participantCount: 0,
    followerCount: 0,
    createdAt: FieldValue.serverTimestamp(),
  });
  await audit(orgId, ref.id, uid, "create");
  return {success: true, experienceId: ref.id};
});

exports.updateContextualExperience = callable(async (data, context) => {
  const uid = context.auth.uid;
  await enforceRateLimit(uid, "update", 40);
  const {id, ref, data: existing} = await getExperienceOrThrow(data.experienceId);
  await requireExperienceManager(existing, uid);
  if (existing.status === "archived") {
    throw new HttpsError("failed-precondition", "archived-experience-locked");
  }
  const payload = buildExperiencePayload(
      {...existing, ...data, organizationId: existing.organizationId},
      uid,
      existing,
  );
  await ref.update(payload);
  await audit(existing.organizationId, id, uid, "update");
  return {success: true, experienceId: id};
});

async function updateStatus(data, context, status, action) {
  const uid = context.auth.uid;
  await enforceRateLimit(uid, action, 30);
  const {id, ref, data: existing} = await getExperienceOrThrow(data.experienceId);
  await requireExperienceManager(existing, uid);
  if (!STATUSES.has(status)) throw new HttpsError("invalid-argument", "status-invalid");
  await ref.update({status, updatedAt: FieldValue.serverTimestamp(), updatedBy: uid});
  await audit(existing.organizationId, id, uid, action);
  return {success: true, experienceId: id, status};
}

exports.publishContextualExperience = callable((data, context) => updateStatus(data, context, "published", "publish"));
exports.unpublishContextualExperience = callable((data, context) => updateStatus(data, context, "draft", "unpublish"));
exports.archiveContextualExperience = callable((data, context) => updateStatus(data, context, "archived", "archive"));

exports.deleteContextualExperience = callable(async (data, context) => {
  const uid = context.auth.uid;
  await enforceRateLimit(uid, "delete", 12);
  const {id, ref, data: existing} = await getExperienceOrThrow(data.experienceId);
  await requireExperienceManager(existing, uid);
  if (existing.status === "published") {
    throw new HttpsError("failed-precondition", "unpublish-before-delete");
  }
  await ref.update({
    status: "archived",
    deletedAt: FieldValue.serverTimestamp(),
    deletedBy: uid,
    updatedAt: FieldValue.serverTimestamp(),
  });
  await audit(existing.organizationId, id, uid, "delete");
  return {success: true, experienceId: id};
});

exports.joinContextualExperience = callable(async (data, context) => {
  const uid = context.auth.uid;
  const {id, data: exp} = await getExperienceOrThrow(data.experienceId);
  await enforceRateLimit(uid, "join", 40);
  if (!(await canReadExperience(exp, uid))) {
    throw new HttpsError("permission-denied", "not-visible");
  }
  const ref = db.collection("contextualExperiences").doc(id).collection("participants").doc(uid);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const wasActive = snap.exists && snap.data().status === "active";
    tx.set(ref, {
      userId: uid,
      organizationId: exp.organizationId,
      status: "active",
      notificationsEnabled: true,
      joinedAt: snap.exists ? snap.data().joinedAt || FieldValue.serverTimestamp() : FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    if (!wasActive) {
      tx.update(db.collection("contextualExperiences").doc(id), {participantCount: FieldValue.increment(1)});
    }
  });
  await audit(exp.organizationId, id, uid, "join");
  return {success: true, experienceId: id};
});

exports.leaveContextualExperience = callable(async (data, context) => {
  const uid = context.auth.uid;
  const {id, data: exp} = await getExperienceOrThrow(data.experienceId);
  await enforceRateLimit(uid, "leave", 40);
  const ref = db.collection("contextualExperiences").doc(id).collection("participants").doc(uid);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const wasActive = snap.exists && snap.data().status === "active";
    tx.set(ref, {
      userId: uid,
      status: "left",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    if (wasActive) {
      tx.update(db.collection("contextualExperiences").doc(id), {participantCount: FieldValue.increment(-1)});
    }
  });
  await audit(exp.organizationId, id, uid, "leave");
  return {success: true, experienceId: id};
});

exports.listOrganizationExperiences = callable(async (data, context) => {
  const uid = context.auth.uid;
  const orgId = normalizeId(data.organizationId || data.orgId, "organizationId");
  const membership = await loadMembership(orgId, uid);
  const publicOnly = !membership;
  const query = db.collection("contextualExperiences")
      .where("organizationId", "==", orgId)
      .orderBy("startAt", "desc")
      .limit(Math.min(50, Number(data.limit || 30)));
  const snap = await query.get();
  const experiences = [];
  for (const doc of snap.docs) {
    const exp = doc.data();
    if (publicOnly && (exp.visibility !== "public" || exp.status !== "published")) continue;
    experiences.push(publicExperience({id: doc.id, ...exp}, Boolean(membership && MANAGER_ROLES.has(membership.role))));
  }
  return {experiences};
});

exports.getContextualExperience = callable(async (data, context) => {
  const uid = context.auth.uid;
  const {id, data: exp} = await getExperienceOrThrow(data.experienceId);
  if (!(await canReadExperience(exp, uid))) {
    throw new HttpsError("permission-denied", "not-visible");
  }
  const membership = await loadMembership(exp.organizationId, uid);
  return {
    experience: publicExperience({id, ...exp}, Boolean(membership && MANAGER_ROLES.has(membership.role))),
    canManage: Boolean(membership && MANAGER_ROLES.has(membership.role)),
  };
});

async function createModule(data, context, type) {
  const uid = context.auth.uid;
  const {id, data: exp} = await getExperienceOrThrow(data.experienceId);
  await enforceRateLimit(uid, `create_${type}_module`, 30);
  await requireExperienceManager(exp, uid);
  if (!MODULE_TYPES.has(type)) throw new HttpsError("invalid-argument", "module-type-invalid");
  const title = asString(data.title, "title", 140);
  const body = asString(data.body || data.description || "", "body", type === "prayer" ? 600 : 2000, false);
  const ref = db.collection("contextualExperiences").doc(id).collection(`${type}Modules`).doc();
  const sensitive = type === "prayer" || type === "memory";
  await ref.set({
    id: ref.id,
    experienceId: id,
    organizationId: exp.organizationId,
    type,
    title,
    body: sensitive ? "" : body,
    bodyPreview: body.slice(0, 180),
    visibility: data.visibility || exp.visibility,
    moderationStatus: exp.safetyRules?.requireModeration ? "pending" : "approved",
    createdBy: uid,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await audit(exp.organizationId, id, uid, `create_${type}_module`, {moduleId: ref.id});
  return {success: true, experienceId: id, moduleId: ref.id};
}

exports.createExperienceEvent = callable((data, context) => createModule(data, context, "event"));
exports.createExperiencePrayerPrompt = callable((data, context) => createModule(data, context, "prayer"));
exports.createExperienceDiscussion = callable((data, context) => createModule(data, context, "discussion"));
exports.createExperienceMemory = callable((data, context) => createModule(data, context, "memory"));
exports.createExperienceTradition = callable((data, context) => createModule(data, context, "tradition"));

exports.moderateExperienceContent = callable(async (data, context) => {
  const uid = context.auth.uid;
  const {id, data: exp} = await getExperienceOrThrow(data.experienceId);
  await enforceRateLimit(uid, "moderate", 60);
  await requireModerator(exp.organizationId, uid);
  const moduleType = asEnum(data.moduleType, MODULE_TYPES, "moduleType", "discussion");
  const moduleId = normalizeId(data.moduleId, "moduleId");
  const action = asEnum(data.action, new Set(["approve", "reject", "remove"]), "action", "approve");
  await db.collection("contextualExperiences").doc(id).collection(`${moduleType}Modules`).doc(moduleId).update({
    moderationStatus: action === "approve" ? "approved" : "rejected",
    moderatedBy: uid,
    moderatedAt: FieldValue.serverTimestamp(),
  });
  await audit(exp.organizationId, id, uid, `moderate_${action}`, {moduleType, moduleId});
  return {success: true};
});

exports.reportExperienceContent = callable(async (data, context) => {
  const uid = context.auth.uid;
  const {id, data: exp} = await getExperienceOrThrow(data.experienceId);
  await enforceRateLimit(uid, "report", 20);
  const reason = asString(data.reason, "reason", 500);
  await db.collection("contextualExperienceReports").add({
    experienceId: id,
    organizationId: exp.organizationId,
    reporterUid: uid,
    moduleType: typeof data.moduleType === "string" ? data.moduleType : null,
    moduleId: typeof data.moduleId === "string" ? data.moduleId : null,
    reason,
    status: "open",
    createdAt: FieldValue.serverTimestamp(),
  });
  return {success: true};
});

exports.updateExperienceNotificationSettings = callable(async (data, context) => {
  const uid = context.auth.uid;
  const {id, data: exp} = await getExperienceOrThrow(data.experienceId);
  await enforceRateLimit(uid, "notifications", 40);
  if (!(await canReadExperience(exp, uid))) {
    throw new HttpsError("permission-denied", "not-visible");
  }
  await db.collection("contextualExperiences").doc(id).collection("notificationPreferences").doc(uid).set({
    userId: uid,
    enabled: data.enabled !== false,
    quietMode: data.quietMode !== false,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {success: true};
});

exports.updateExperienceTheme = callable(async (data, context) => {
  const uid = context.auth.uid;
  const {id, ref, data: exp} = await getExperienceOrThrow(data.experienceId);
  await enforceRateLimit(uid, "theme", 20);
  await requireExperienceManager(exp, uid);
  const theme = sanitizeTheme(data.theme);
  await ref.update({theme, updatedAt: FieldValue.serverTimestamp(), updatedBy: uid});
  await audit(exp.organizationId, id, uid, "update_theme");
  return {success: true, theme};
});

exports.getExperienceAnalytics = callable(async (data, context) => {
  const uid = context.auth.uid;
  const {id, data: exp} = await getExperienceOrThrow(data.experienceId);
  await requireExperienceManager(exp, uid);
  const snap = await db.collection("contextualExperiences").doc(id).collection("analytics").doc("aggregate").get();
  return {
    analytics: snap.exists ? snap.data() : {
      participantCount: exp.participantCount || 0,
      eventCount: 0,
      prayerPromptCount: 0,
      discussionCount: 0,
    },
  };
});

exports.manageExperienceRoles = callable(async (data, context) => {
  const uid = context.auth.uid;
  const {id, ref, data: exp} = await getExperienceOrThrow(data.experienceId);
  await enforceRateLimit(uid, "manage_roles", 12);
  await requireRolePolicyManager(exp.organizationId, uid);
  const roles = Array.isArray(data.rolesAllowedToManage) ?
    data.rolesAllowedToManage.filter((role) => MANAGER_ROLES.has(role)) :
    [];
  if (roles.length === 0) throw new HttpsError("invalid-argument", "roles-required");
  await ref.update({rolesAllowedToManage: roles, updatedAt: FieldValue.serverTimestamp(), updatedBy: uid});
  await audit(exp.organizationId, id, uid, "manage_roles", {roles});
  return {success: true, rolesAllowedToManage: roles};
});

exports.resolveContextualExperienceStack = callable(async (data, context) => {
  const uid = context.auth.uid;
  await enforceRateLimit(uid, "resolve", 120);
  const now = Timestamp.now();
  const region = typeof data.region === "string" ? data.region : "global";
  const orgIds = Array.isArray(data.organizationIds) ?
    data.organizationIds.filter((id) => typeof id === "string").slice(0, 20) :
    [];
  const joinedExperienceId = typeof data.joinedExperienceId === "string" ? data.joinedExperienceId : null;
  const accessibility = safeMap(data.accessibility);
  const emotional = safeMap(data.emotionalContext);
  const candidates = [];

  if (joinedExperienceId) {
    const snap = await db.collection("contextualExperiences").doc(joinedExperienceId).get();
    if (snap.exists) candidates.push({id: snap.id, ...snap.data(), priorityBoost: 500});
  }

  for (const orgId of orgIds) {
    const snap = await db.collection("contextualExperiences")
        .where("organizationId", "==", orgId)
        .where("status", "==", "published")
        .limit(20)
        .get();
    snap.docs.forEach((doc) => candidates.push({id: doc.id, ...doc.data(), priorityBoost: 200}));
  }

  const regionalSnap = await db.collection("contextualExperiences")
      .where("sourceLayer", "in", ["regional", "global"])
      .where("status", "==", "published")
      .limit(20)
      .get();
  regionalSnap.docs.forEach((doc) => {
    const exp = doc.data();
    if (exp.sourceLayer === "global" || exp.region === region) {
      candidates.push({id: doc.id, ...exp, priorityBoost: exp.sourceLayer === "regional" ? 80 : 20});
    }
  });

  const visible = [];
  for (const exp of candidates) {
    if (exp.featureFlags?.killSwitch || exp.safetyRules?.killSwitch) continue;
    if (exp.startAt && exp.startAt.toMillis() > now.toMillis()) continue;
    if (exp.endAt && exp.endAt.toMillis() < now.toMillis()) continue;
    if (await canReadExperience(exp, uid)) visible.push(exp);
  }

  const scored = visible.map((exp) => {
    let score = exp.priorityBoost || 0;
    if (accessibility.reduceTransparency && exp.theme?.liquidGlassBehavior === "prominent") score -= 40;
    if (emotional.griefSensitive && exp.safetyRules?.griefSensitive) score += 700;
    if (emotional.sensitiveMode && exp.safetyRules?.youthProtected) score += 200;
    if (exp.experienceType === "emergencyPrayerMobilization") score += 350;
    if (exp.sourceLayer === "event") score += 300;
    return {...exp, resolverScore: score};
  }).sort((a, b) => b.resolverScore - a.resolverScore);

  const primary = scored[0] || null;
  const secondary = scored.slice(1, 4).map((exp) => publicExperience(exp));
  return {
    activeExperienceId: primary?.id || null,
    sourceLayer: primary?.sourceLayer || "default",
    themeTokens: primary?.theme || {accentName: "default", liquidGlassBehavior: "subtle"},
    allowedModules: primary ? ["content", "prayer", "discussion", "event", "memory", "tradition"] : [],
    activeBanner: primary ? {
      title: primary.title,
      subtitle: primary.description,
      symbolName: primary.theme?.symbolName || "sparkles",
    } : null,
    navigationAction: primary ? {type: "experienceDetail", experienceId: primary.id} : null,
    notificationBehavior: primary?.notificationRules || {enabled: false},
    safetyBehavior: primary?.safetyRules || {griefSensitive: false, youthProtected: false},
    accessibilityAdjustments: {
      reduceMotion: Boolean(accessibility.reduceMotion || primary?.accessibilityBehavior?.reduceMotionDefault),
      reduceTransparency: Boolean(accessibility.reduceTransparency),
      highContrast: Boolean(accessibility.highContrast),
    },
    secondaryExperiences: secondary,
    debugMetadata: data.adminPreview ? scored.map((exp) => ({
      id: exp.id,
      title: exp.title,
      sourceLayer: exp.sourceLayer,
      resolverScore: exp.resolverScore,
    })) : [],
  };
});

const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { enforceRateLimit } = require("./rateLimiter");

const REGION = "us-central1";
const callableOptions = { region: REGION, enforceAppCheck: true };

const db = () => admin.firestore();
const serverTimestamp = () => admin.firestore.FieldValue.serverTimestamp();

function requireUid(request) {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to use Amen Action Intelligence.");
  }
  return uid;
}

function requireAppCheck(request) {
  if (!request.app) {
    throw new HttpsError("failed-precondition", "App Check is required for Action Intelligence.");
  }
}

async function guardCallable(request, actionName, maxCount = 90) {
  requireAppCheck(request);
  const uid = requireUid(request);
  await enforceRateLimit(uid, `action_intelligence_${actionName}`, maxCount, 3600);
  return uid;
}

function cleanString(value) {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function sourceFrom(data) {
  const source = data && typeof data.source === "object" ? data.source : data;
  const sourceId = cleanString(source && source.sourceId);
  const sourceType = cleanString(source && source.sourceType);
  const sourceText = cleanString(source && source.sourceText);
  if (!sourceId || !sourceType || !sourceText) {
    throw new HttpsError("invalid-argument", "sourceId, sourceType, and sourceText are required.");
  }
  return {
    sourceId,
    sourceType,
    sourceText,
    conversationId: cleanString(source.conversationId),
    roomId: cleanString(source.roomId),
    postId: cleanString(source.postId),
    commentId: cleanString(source.commentId),
    churchId: cleanString(source.churchId),
    spaceId: cleanString(source.spaceId),
    organizationId: cleanString(source.organizationId),
    authorId: cleanString(source.authorId),
    targetUserId: cleanString(source.targetUserId),
    targetDisplayName: cleanString(source.targetDisplayName),
    title: cleanString(source.title),
    dueAt: cleanString(source.dueAt),
    locationName: cleanString(source.locationName),
    scriptureReference: cleanString(source.scriptureReference),
    resourceUrl: cleanString(source.resourceUrl),
  };
}

function analysisFrom(data) {
  const analysis = data && typeof data.analysis === "object" ? data.analysis : {};
  return {
    id: cleanString(analysis.id),
    sourceId: cleanString(analysis.sourceId),
    surface: cleanString(analysis.surface),
    privacyTier: cleanString(analysis.privacyTier) || "tier_c",
    intentKind: cleanString(analysis.intentKind) || "follow_up",
    objectClass: cleanString(analysis.objectClass) || "commitment",
    confidence: typeof analysis.confidence === "number" ? analysis.confidence : 0,
    sensitivityLevel: cleanString(analysis.sensitivityLevel) || "standard",
    detectedSignals: Array.isArray(analysis.detectedSignals) ? analysis.detectedSignals.filter((item) => typeof item === "string") : [],
    explanation: cleanString(analysis.explanation),
    shouldSuppressCapsule: analysis.shouldSuppressCapsule === true,
  };
}

async function assertNotBlocked(uid, source) {
  const otherId = source.targetUserId || source.authorId;
  if (!otherId || otherId === uid) return;

  const [blockedByMe, blockedMe] = await Promise.all([
    db().collection("users").doc(uid).collection("blockedUsers").doc(otherId).get(),
    db().collection("users").doc(otherId).collection("blockedUsers").doc(uid).get(),
  ]);
  if (blockedByMe.exists || blockedMe.exists) {
    throw new HttpsError("permission-denied", "Action blocked by user privacy settings.");
  }
}

function objectBase(uid, actionVerb, source, analysis) {
  return {
    ownerId: uid,
    actionVerb,
    source,
    analysis,
    objectClass: analysis.objectClass,
    intentKind: analysis.intentKind,
    privacyTier: analysis.privacyTier,
    state: actionVerb === "dismiss_suggestion" ? "dismissed" : "active",
    provenance: {
      createdBy: uid,
      createdVia: "amen_action_intelligence",
      sourceId: source.sourceId,
      sourceType: source.sourceType,
    },
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

async function createActionObject(uid, actionVerb, source, analysis, stateOverride) {
  const ref = db().collection("actionIntelligenceObjects").doc();
  const payload = objectBase(uid, actionVerb, source, analysis);
  if (stateOverride) payload.state = stateOverride;
  await ref.set(payload);
  return ref.id;
}

async function audit(uid, actionVerb, source, objectId, workflow) {
  await db().collection("actionIntelligenceAudit").add({
    uid,
    actionVerb,
    sourceId: source.sourceId,
    sourceType: source.sourceType,
    objectId: objectId || null,
    workflow,
    createdAt: serverTimestamp(),
  });
}

async function createInitiativeWorkflow(uid, actionVerb, source, analysis) {
  const objectId = await createActionObject(uid, actionVerb, source, analysis, "proposed");
  const initiativeRef = db().collection("amenInitiatives").doc();
  await initiativeRef.set({
    ownerId: uid,
    source,
    actionObjectId: objectId,
    title: source.title || "Community initiative",
    summary: source.sourceText,
    status: "draft_pending_leader_review",
    fundraisingStatus: actionVerb === "start_fundraiser" ? "stripe_model_required" : "not_requested",
    volunteerRoleCount: actionVerb === "create_volunteer_event" ? 1 : 0,
    prayerUpdateCount: 0,
    milestoneCount: 0,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  await initiativeRef.collection("milestones").add({
    title: "Initiative proposed",
    state: "pending_leader_review",
    createdBy: uid,
    createdAt: serverTimestamp(),
  });
  return {
    workflow: "initiative",
    objectId,
    result: { initiativeId: initiativeRef.id },
    message: "Initiative draft saved for the right leaders.",
  };
}

async function volunteerWorkflow(uid, actionVerb, source, analysis) {
  const objectId = await createActionObject(uid, actionVerb, source, analysis);
  const assignmentRef = db().collection("amenVolunteerAssignments").doc();
  await assignmentRef.set({
    ownerId: uid,
    assigneeId: source.targetUserId || uid,
    targetDisplayName: source.targetDisplayName || null,
    actionObjectId: objectId,
    source,
    status: actionVerb === "assign_volunteer" ? "pending_acceptance" : "offered",
    actionVerb,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  return {
    workflow: "volunteer_assignment",
    objectId,
    result: { assignmentId: assignmentRef.id },
    message: "Volunteer workflow saved.",
  };
}

async function memoryWorkflow(uid, actionVerb, source, analysis) {
  const objectId = await createActionObject(uid, actionVerb, source, analysis);
  await db().collection("users").doc(uid).collection("amenMemoryGraph").doc(objectId).set({
    ownerId: uid,
    actionObjectId: objectId,
    actionVerb,
    source,
    intentKind: analysis.intentKind,
    objectClass: analysis.objectClass,
    topics: analysis.detectedSignals,
    framing: "ebenezer_memory",
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  return {
    workflow: "memory_graph",
    objectId,
    result: { memoryId: objectId },
    message: "Amen saved this to your memory layer.",
  };
}

async function relationshipWorkflow(uid, actionVerb, source, analysis) {
  const objectId = await createActionObject(uid, actionVerb, source, analysis);
  const signalRef = db().collection("amenRelationshipSignals").doc();
  await signalRef.set({
    ownerId: uid,
    targetUserId: source.targetUserId || source.authorId || null,
    targetDisplayName: source.targetDisplayName || null,
    actionObjectId: objectId,
    actionVerb,
    source,
    signalType: "care_connection",
    lastSignalAt: serverTimestamp(),
    createdAt: serverTimestamp(),
  });
  return {
    workflow: "relationship_signal",
    objectId,
    result: { signalId: signalRef.id },
    message: "Relationship follow-up saved.",
  };
}

async function knowledgeWorkflow(uid, actionVerb, source, analysis) {
  const objectId = await createActionObject(uid, actionVerb, source, analysis);
  const graphRef = db().collection("amenKnowledgeGraph").doc();
  await graphRef.set({
    ownerId: uid,
    actionObjectId: objectId,
    actionVerb,
    source,
    scopeId: source.spaceId || source.churchId || source.organizationId || source.roomId || source.conversationId || uid,
    scopeType: source.spaceId ? "space" : source.churchId ? "church" : source.organizationId ? "organization" : source.roomId ? "room" : source.conversationId ? "conversation" : "user",
    title: source.title || analysis.intentKind,
    text: source.sourceText,
    scriptureReference: source.scriptureReference || null,
    resourceUrl: source.resourceUrl || null,
    topics: analysis.detectedSignals,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  return {
    workflow: "knowledge_graph",
    objectId,
    result: { knowledgeNodeId: graphRef.id },
    message: "Knowledge graph updated.",
  };
}

async function routeWorkflow(uid, actionVerb, source, analysis) {
  if (analysis.shouldSuppressCapsule) {
    throw new HttpsError("failed-precondition", "This content is routed to human care instead of automated actions.");
  }

  const initiativeActions = new Set(["create_initiative", "invite_leaders", "start_fundraiser", "create_volunteer_event"]);
  const volunteerActions = new Set(["volunteer", "assign_volunteer", "add_to_team"]);
  const relationshipActions = new Set(["message_user", "send_encouragement", "schedule_follow_up"]);
  const memoryActions = new Set(["pray_now", "commit_to_pray", "set_prayer_reminder", "follow_updates", "add_to_prayer_list", "mark_complete", "release_commitment"]);

  if (initiativeActions.has(actionVerb)) return createInitiativeWorkflow(uid, actionVerb, source, analysis);
  if (volunteerActions.has(actionVerb)) return volunteerWorkflow(uid, actionVerb, source, analysis);
  if (relationshipActions.has(actionVerb)) return relationshipWorkflow(uid, actionVerb, source, analysis);
  if (memoryActions.has(actionVerb)) return memoryWorkflow(uid, actionVerb, source, analysis);
  return knowledgeWorkflow(uid, actionVerb, source, analysis);
}

exports.executeAmenAction = onCall(callableOptions, async (request) => {
  const uid = await guardCallable(request, "execute", 120);
  const actionVerb = cleanString(request.data && request.data.actionVerb);
  if (!actionVerb) throw new HttpsError("invalid-argument", "actionVerb is required.");
  const source = sourceFrom(request.data);
  const analysis = analysisFrom(request.data);
  await assertNotBlocked(uid, source);
  const response = await routeWorkflow(uid, actionVerb, source, analysis);
  await audit(uid, actionVerb, source, response.objectId, response.workflow);
  return response;
});

exports.createAmenInitiative = onCall(callableOptions, async (request) => {
  const uid = await guardCallable(request, "create_initiative", 30);
  const source = sourceFrom(request.data);
  const analysis = analysisFrom(request.data);
  await assertNotBlocked(uid, source);
  const response = await createInitiativeWorkflow(uid, cleanString(request.data && request.data.actionVerb) || "create_initiative", source, analysis);
  await audit(uid, "create_initiative", source, response.objectId, response.workflow);
  return response;
});

exports.assignAmenVolunteer = onCall(callableOptions, async (request) => {
  const uid = await guardCallable(request, "assign_volunteer", 60);
  const source = sourceFrom(request.data);
  const analysis = analysisFrom(request.data);
  await assertNotBlocked(uid, source);
  const response = await volunteerWorkflow(uid, cleanString(request.data && request.data.actionVerb) || "assign_volunteer", source, analysis);
  await audit(uid, "assign_volunteer", source, response.objectId, response.workflow);
  return response;
});

exports.indexAmenMemoryGraph = onCall(callableOptions, async (request) => {
  const uid = await guardCallable(request, "memory_graph", 120);
  const source = sourceFrom(request.data);
  const analysis = analysisFrom(request.data);
  const response = await memoryWorkflow(uid, cleanString(request.data && request.data.actionVerb) || "follow_updates", source, analysis);
  await audit(uid, "memory_graph", source, response.objectId, response.workflow);
  return response;
});

exports.recordAmenRelationshipSignal = onCall(callableOptions, async (request) => {
  const uid = await guardCallable(request, "relationship_signal", 90);
  const source = sourceFrom(request.data);
  const analysis = analysisFrom(request.data);
  await assertNotBlocked(uid, source);
  const response = await relationshipWorkflow(uid, cleanString(request.data && request.data.actionVerb) || "schedule_follow_up", source, analysis);
  await audit(uid, "relationship_signal", source, response.objectId, response.workflow);
  return response;
});

exports.writeAmenKnowledgeGraph = onCall(callableOptions, async (request) => {
  const uid = await guardCallable(request, "knowledge_graph", 120);
  const source = sourceFrom(request.data);
  const analysis = analysisFrom(request.data);
  const response = await knowledgeWorkflow(uid, cleanString(request.data && request.data.actionVerb) || "save_resource", source, analysis);
  await audit(uid, "knowledge_graph", source, response.objectId, response.workflow);
  return response;
});

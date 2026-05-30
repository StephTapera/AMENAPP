import * as admin from "firebase-admin";

export type PulsePermissionSource =
  | "amenActivity"
  | "bereanChatHistory"
  | "savedPosts"
  | "prayerJournal"
  | "churchActivity"
  | "location"
  | "calendar"
  | "contacts"
  | "notifications"
  | "wellnessHealth"
  | "workProjectContext"
  | "appUsageBehavior";

export type PulseIntent =
  | "spiritualFormation"
  | "founderBuilder"
  | "workFollowUp"
  | "creativeContinuation"
  | "churchDiscovery"
  | "prayerContinuation"
  | "wellnessCheckIn"
  | "openLoopResolution"
  | "learningContinuation"
  | "relationshipFollowUp";

export type PulseCardMode =
  | "spiritual"
  | "founder"
  | "business"
  | "work"
  | "creative"
  | "wellness"
  | "church"
  | "prayer"
  | "learning"
  | "relationships"
  | "openLoops";

export type PulseActionType =
  | "askBerean"
  | "startReflection"
  | "continueChat"
  | "openPost"
  | "openSavedPost"
  | "openChurch"
  | "openGroup"
  | "openPrayerJournal"
  | "createPrayer"
  | "createPost"
  | "draftMessage"
  | "openFindChurch"
  | "openDiscoverSearch"
  | "openReadingPlan"
  | "openProjectBrief"
  | "openWellnessCheckIn";

export type PulseEventType =
  | "viewed"
  | "expanded"
  | "liked"
  | "disliked"
  | "saved"
  | "shared"
  | "hidden"
  | "actionTapped"
  | "permissionRequested"
  | "permissionGranted"
  | "permissionDenied"
  | "curateOpened"
  | "sourceSuppressed"
  | "topicSuppressed"
  | "modeSuppressed"
  | "followUpAsked";

export interface BereanPulsePermissionDocument {
  amenActivity?: boolean;
  bereanChatHistory?: boolean;
  savedPosts?: boolean;
  prayerJournal?: boolean;
  churchActivity?: boolean;
  location?: boolean;
  calendar?: boolean;
  contacts?: boolean;
  notifications?: boolean;
  wellnessHealth?: boolean;
  workProjectContext?: boolean;
  appUsageBehavior?: boolean;
}

export interface BereanPulsePreferenceDocument {
  enabled?: boolean;
  preferredModes?: PulseCardMode[];
  suppressedModes?: PulseCardMode[];
  preferredTone?: string;
  preferredLength?: string;
  morningDeliveryEnabled?: boolean;
  notificationsEnabled?: boolean;
  appContextAccess?: boolean;
  calendarAccess?: boolean;
  locationAccess?: boolean;
  healthAccess?: boolean;
  contactsAccess?: boolean;
  churchActivityAccess?: boolean;
  prayerJournalAccess?: boolean;
  savedPostsAccess?: boolean;
  workModeEnabled?: boolean;
}

export interface BereanPulseSignal {
  id: string;
  source: PulsePermissionSource;
  sourceRecordId: string;
  title: string;
  summary: string;
  timestamp: admin.firestore.Timestamp;
  sensitivity: "low" | "personal" | "sensitive";
  permissionRequired: boolean;
  permissionGranted: boolean;
  hashForDeduplication: string;
  isUserVisible: boolean;
  entityType?: "conversation" | "post" | "church" | "project" | "notification" | "reflection" | "messageThread";
  entityId?: string;
  metadata?: Record<string, string>;
}

export interface BereanPulseEventRecord {
  id: string;
  cardId: string;
  eventType: PulseEventType;
  mode?: PulseCardMode;
  metadata?: Record<string, string>;
  timestamp: admin.firestore.Timestamp;
}

export interface BereanPulseCardRecord {
  id: string;
  userId: string;
  dateKey: string;
  mode: PulseCardMode;
  secondaryModes: PulseCardMode[];
  title: string;
  subtitle: string;
  whyNow: string;
  whyNowEvidence: string[];
  insight: string;
  expandedBody: string;
  recommendedActionTitle: string;
  actionType: PulseActionType;
  actionPayload: Record<string, string>;
  primaryIntent: PulseIntent;
  sourceSignalIds: string[];
  confidenceScore: number;
  urgencyScore: number;
  relevanceScore: number;
  matchScore: number;
  sourceSignals: BereanPulseSignal[];
  permissionRequirements: PulsePermissionSource[];
  privacyLevel: "low" | "personal" | "sensitive";
  createdAt: admin.firestore.Timestamp;
  updatedAt: admin.firestore.Timestamp;
  expiresAt: admin.firestore.Timestamp;
  isSaved: boolean;
  isHidden: boolean;
  feedbackState: "neutral" | "liked" | "disliked";
}

interface CandidateCard {
  mode: PulseCardMode;
  secondaryModes: PulseCardMode[];
  title: string;
  subtitle: string;
  insight: string;
  expandedBody: string;
  recommendedActionTitle: string;
  actionType: PulseActionType;
  actionPayload: Record<string, string>;
  primaryIntent: PulseIntent;
  sourceSignals: BereanPulseSignal[];
  permissionRequirements: PulsePermissionSource[];
  privacyLevel: "low" | "personal" | "sensitive";
  confidenceScore: number;
  urgencyScore: number;
  relevanceScore: number;
  topicKey: string;
}

export interface BuildBereanPulseCardsInput {
  userId: string;
  dateKey: string;
  permissions: BereanPulsePermissionDocument;
  preferences: BereanPulsePreferenceDocument;
  signals: BereanPulseSignal[];
  feedback: BereanPulseEventRecord[];
  now?: admin.firestore.Timestamp;
}

const modeByIntent: Record<PulseIntent, PulseCardMode> = {
  spiritualFormation: "spiritual",
  founderBuilder: "founder",
  workFollowUp: "work",
  creativeContinuation: "creative",
  churchDiscovery: "church",
  prayerContinuation: "prayer",
  wellnessCheckIn: "wellness",
  openLoopResolution: "openLoops",
  learningContinuation: "learning",
  relationshipFollowUp: "relationships",
};

const signalSourceToIntent: Partial<Record<PulsePermissionSource, PulseIntent[]>> = {
  bereanChatHistory: ["spiritualFormation", "prayerContinuation", "learningContinuation", "openLoopResolution"],
  savedPosts: ["learningContinuation", "creativeContinuation", "openLoopResolution"],
  churchActivity: ["churchDiscovery", "relationshipFollowUp", "openLoopResolution"],
  notifications: ["relationshipFollowUp", "openLoopResolution"],
  workProjectContext: ["founderBuilder", "workFollowUp", "creativeContinuation", "openLoopResolution"],
  prayerJournal: ["prayerContinuation", "spiritualFormation"],
};

const defaultPermissions: Record<PulsePermissionSource, boolean> = {
  amenActivity: true,
  bereanChatHistory: false,
  savedPosts: true,
  prayerJournal: false,
  churchActivity: true,
  location: false,
  calendar: false,
  contacts: false,
  notifications: false,
  wellnessHealth: false,
  workProjectContext: false,
  appUsageBehavior: true,
};

export function normalizePermissions(
  input: BereanPulsePermissionDocument | undefined
): Record<PulsePermissionSource, boolean> {
  return {
    amenActivity: input?.amenActivity ?? defaultPermissions.amenActivity,
    bereanChatHistory: input?.bereanChatHistory ?? defaultPermissions.bereanChatHistory,
    savedPosts: input?.savedPosts ?? defaultPermissions.savedPosts,
    prayerJournal: input?.prayerJournal ?? defaultPermissions.prayerJournal,
    churchActivity: input?.churchActivity ?? defaultPermissions.churchActivity,
    location: input?.location ?? defaultPermissions.location,
    calendar: input?.calendar ?? defaultPermissions.calendar,
    contacts: input?.contacts ?? defaultPermissions.contacts,
    notifications: input?.notifications ?? defaultPermissions.notifications,
    wellnessHealth: input?.wellnessHealth ?? defaultPermissions.wellnessHealth,
    workProjectContext: input?.workProjectContext ?? defaultPermissions.workProjectContext,
    appUsageBehavior: input?.appUsageBehavior ?? defaultPermissions.appUsageBehavior,
  };
}

export function suppressedSources(events: BereanPulseEventRecord[]): Set<PulsePermissionSource> {
  return new Set(
    events
      .filter((event) => event.eventType === "sourceSuppressed")
      .map((event) => event.metadata?.source as PulsePermissionSource | undefined)
      .filter((source): source is PulsePermissionSource => Boolean(source))
  );
}

export function suppressedTopics(events: BereanPulseEventRecord[]): Set<string> {
  return new Set(
    events
      .filter((event) => event.eventType === "topicSuppressed")
      .map((event) => event.metadata?.topicKey)
      .filter((topicKey): topicKey is string => Boolean(topicKey))
  );
}

export function feedbackAdjustments(events: BereanPulseEventRecord[]) {
  const likedTopics = new Set<string>();
  const dislikedTopics = new Set<string>();
  const hiddenTopics = new Set<string>();
  const suppressedModes = new Set<PulseCardMode>();

  for (const event of events) {
    const topicKey = event.metadata?.topicKey;
    if (event.eventType === "liked" && topicKey) likedTopics.add(topicKey);
    if (event.eventType === "disliked" && topicKey) dislikedTopics.add(topicKey);
    if (event.eventType === "hidden" && topicKey) hiddenTopics.add(topicKey);
    if (event.eventType === "modeSuppressed") {
      const mode = event.metadata?.mode as PulseCardMode | undefined;
      if (mode) suppressedModes.add(mode);
    }
  }

  return { likedTopics, dislikedTopics, hiddenTopics, suppressedModes };
}

export function buildBereanPulseCards(input: BuildBereanPulseCardsInput): BereanPulseCardRecord[] {
  const now = input.now ?? admin.firestore.Timestamp.now();
  const permissions = normalizePermissions(input.permissions);
  const sourceBlocks = suppressedSources(input.feedback);
  const topicBlocks = suppressedTopics(input.feedback);
  const feedback = feedbackAdjustments(input.feedback);
  const preferredModes = new Set(input.preferences.preferredModes ?? []);
  const suppressedModes = new Set([...(input.preferences.suppressedModes ?? []), ...feedback.suppressedModes]);

  const dedupedSignals = dedupeSignals(
    input.signals.filter((signal) =>
      permissions[signal.source] &&
      !sourceBlocks.has(signal.source)
    )
  );

  const candidates = detectCandidates(dedupedSignals)
    .filter((candidate) => !suppressedModes.has(candidate.mode))
    .filter((candidate) => !topicBlocks.has(candidate.topicKey))
    .filter((candidate) => candidate.sourceSignals.length > 0)
    .map((candidate) => finalizeCandidate(candidate, input.userId, input.dateKey, now, preferredModes, feedback));

  return candidates
    .filter((candidate): candidate is BereanPulseCardRecord => candidate !== null)
    .sort((lhs, rhs) => rhs.matchScore - lhs.matchScore)
    .slice(0, 8);
}

export function detectOpenLoops(signals: BereanPulseSignal[]): BereanPulseSignal[] {
  return signals.filter((signal) => signal.metadata?.openLoop === "true");
}

function dedupeSignals(signals: BereanPulseSignal[]): BereanPulseSignal[] {
  const latestByHash = new Map<string, BereanPulseSignal>();
  for (const signal of signals) {
    const existing = latestByHash.get(signal.hashForDeduplication);
    if (!existing || existing.timestamp.toMillis() < signal.timestamp.toMillis()) {
      latestByHash.set(signal.hashForDeduplication, signal);
    }
  }
  return Array.from(latestByHash.values()).sort((lhs, rhs) => rhs.timestamp.toMillis() - lhs.timestamp.toMillis());
}

function detectCandidates(signals: BereanPulseSignal[]): CandidateCard[] {
  const candidates: CandidateCard[] = [];
  const groupedByIntent = new Map<PulseIntent, BereanPulseSignal[]>();

  for (const signal of signals) {
    const intents = inferIntents(signal);
    for (const intent of intents) {
      const bucket = groupedByIntent.get(intent) ?? [];
      bucket.push(signal);
      groupedByIntent.set(intent, bucket);
    }
  }

  for (const [intent, intentSignals] of groupedByIntent.entries()) {
    const signalsForCard = intentSignals
      .sort((lhs, rhs) => rhs.timestamp.toMillis() - lhs.timestamp.toMillis())
      .slice(0, 3);

    switch (intent) {
      case "founderBuilder":
        candidates.push(buildProjectCandidate(intent, signalsForCard, "founder"));
        break;
      case "workFollowUp":
        candidates.push(buildProjectCandidate(intent, signalsForCard, "work"));
        break;
      case "creativeContinuation":
        candidates.push(buildProjectCandidate(intent, signalsForCard, "creative"));
        break;
      case "churchDiscovery":
        candidates.push(buildChurchCandidate(signalsForCard));
        break;
      case "prayerContinuation":
        candidates.push(buildPrayerCandidate(signalsForCard));
        break;
      case "spiritualFormation":
        candidates.push(buildSpiritualCandidate(signalsForCard));
        break;
      case "learningContinuation":
        candidates.push(buildSavedPostCandidate(signalsForCard));
        break;
      case "relationshipFollowUp":
        candidates.push(buildRelationshipCandidate(signalsForCard));
        break;
      case "openLoopResolution":
        candidates.push(buildOpenLoopCandidate(signalsForCard));
        break;
      case "wellnessCheckIn":
        candidates.push(buildWellnessCandidate(signalsForCard));
        break;
    }
  }

  return candidates;
}

function inferIntents(signal: BereanPulseSignal): PulseIntent[] {
  if (signal.metadata?.intent) {
    return [signal.metadata.intent as PulseIntent];
  }
  return signalSourceToIntent[signal.source] ?? ["openLoopResolution"];
}

function buildProjectCandidate(intent: PulseIntent, signals: BereanPulseSignal[], mode: PulseCardMode): CandidateCard {
  const lead = signals[0];
  const projectTitle = lead.metadata?.projectTitle ?? lead.title;
  const actionPayload = lead.entityId ? { projectId: lead.entityId, projectTitle } : {};
  return {
    mode,
    secondaryModes: mode === "founder" ? ["work", "creative"] : ["founder"],
    title: mode === "creative" ? "Continue the idea while it still has momentum" : `${projectTitle} needs a next move`,
    subtitle: mode === "creative" ? "Creative continuation" : "Project follow-up",
    insight: summarizeSignals(signals),
    expandedBody: buildExpandedBody(signals),
    recommendedActionTitle: lead.entityId ? "Open project brief" : "Action unavailable",
    actionType: "openProjectBrief",
    actionPayload: actionPayload as Record<string, string>,
    primaryIntent: intent,
    sourceSignals: signals,
    permissionRequirements: ["workProjectContext"],
    privacyLevel: "personal",
    confidenceScore: 0.84,
    urgencyScore: scoreUrgency(signals),
    relevanceScore: 0.82,
    topicKey: `project:${lead.entityId ?? lead.hashForDeduplication}`,
  };
}

function buildChurchCandidate(signals: BereanPulseSignal[]): CandidateCard {
  const lead = signals[0];
  const churchName = lead.metadata?.churchName ?? "church follow-up";
  const churchId = lead.entityId ?? lead.metadata?.churchId ?? "";
  return {
    mode: "church",
    secondaryModes: ["relationships", "prayer"],
    title: `Follow through on ${churchName}`,
    subtitle: "Church discovery",
    insight: summarizeSignals(signals),
    expandedBody: buildExpandedBody(signals),
    recommendedActionTitle: churchId ? "Open church profile" : "Church profile unavailable",
    actionType: "openChurch",
    actionPayload: churchId ? { churchId, churchName } : {},
    primaryIntent: "churchDiscovery",
    sourceSignals: signals,
    permissionRequirements: ["churchActivity"],
    privacyLevel: "personal",
    confidenceScore: 0.83,
    urgencyScore: scoreUrgency(signals),
    relevanceScore: 0.84,
    topicKey: `church:${churchId || lead.hashForDeduplication}`,
  };
}

function buildPrayerCandidate(signals: BereanPulseSignal[]): CandidateCard {
  const lead = signals[0];
  const entryId = lead.entityId ?? "";
  return {
    mode: "prayer",
    secondaryModes: ["spiritual", "learning"],
    title: "Continue the prayer you already started",
    subtitle: "Prayer follow-up",
    insight: summarizeSignals(signals),
    expandedBody: buildExpandedBody(signals),
    recommendedActionTitle: entryId ? "Open prayer journal" : "Prayer journal unavailable",
    actionType: "openPrayerJournal",
    actionPayload: entryId ? { entryId } : {},
    primaryIntent: "prayerContinuation",
    sourceSignals: signals,
    permissionRequirements: ["prayerJournal"],
    privacyLevel: "sensitive",
    confidenceScore: 0.8,
    urgencyScore: scoreUrgency(signals),
    relevanceScore: 0.81,
    topicKey: `prayer:${entryId || lead.hashForDeduplication}`,
  };
}

function buildSpiritualCandidate(signals: BereanPulseSignal[]): CandidateCard {
  const lead = signals[0];
  const conversationId = lead.entityId ?? lead.metadata?.conversationId ?? "";
  return {
    mode: "spiritual",
    secondaryModes: ["learning", "prayer"],
    title: "Turn your recent study into one concrete response",
    subtitle: "Spiritual formation",
    insight: summarizeSignals(signals),
    expandedBody: buildExpandedBody(signals),
    recommendedActionTitle: "Ask Berean",
    actionType: "askBerean",
    actionPayload: {
      prompt: `Continue this thread with practical next steps: ${lead.summary}`,
      conversationId,
      mode: "shepherd",
    },
    primaryIntent: "spiritualFormation",
    sourceSignals: signals,
    permissionRequirements: ["bereanChatHistory"],
    privacyLevel: "personal",
    confidenceScore: 0.79,
    urgencyScore: scoreUrgency(signals),
    relevanceScore: 0.78,
    topicKey: `spiritual:${conversationId || lead.hashForDeduplication}`,
  };
}

function buildSavedPostCandidate(signals: BereanPulseSignal[]): CandidateCard {
  const lead = signals[0];
  const postId = lead.entityId ?? "";
  return {
    mode: "learning",
    secondaryModes: ["creative", "openLoops"],
    title: "You saved this for a reason",
    subtitle: "Saved post continuation",
    insight: summarizeSignals(signals),
    expandedBody: buildExpandedBody(signals),
    recommendedActionTitle: postId ? "Open saved post" : "Saved post unavailable",
    actionType: "openSavedPost",
    actionPayload: postId ? { postId } : {},
    primaryIntent: "learningContinuation",
    sourceSignals: signals,
    permissionRequirements: ["savedPosts"],
    privacyLevel: "low",
    confidenceScore: 0.78,
    urgencyScore: scoreUrgency(signals),
    relevanceScore: 0.8,
    topicKey: `savedPost:${postId || lead.hashForDeduplication}`,
  };
}

function buildRelationshipCandidate(signals: BereanPulseSignal[]): CandidateCard {
  const lead = signals[0];
  const conversationId = lead.entityId ?? "";
  const recipientId = lead.metadata?.recipientId ?? "";
  return {
    mode: "relationships",
    secondaryModes: ["church", "openLoops"],
    title: "There is a follow-up waiting on you",
    subtitle: "Relationship follow-up",
    insight: summarizeSignals(signals),
    expandedBody: buildExpandedBody(signals),
    recommendedActionTitle: conversationId || recipientId ? "Draft message" : "Message context unavailable",
    actionType: "draftMessage",
    actionPayload: {
      ...(conversationId ? { conversationId } : {}),
      ...(recipientId ? { recipientId } : {}),
      prompt: lead.summary,
    },
    primaryIntent: "relationshipFollowUp",
    sourceSignals: signals,
    permissionRequirements: ["notifications"],
    privacyLevel: "personal",
    confidenceScore: 0.76,
    urgencyScore: scoreUrgency(signals),
    relevanceScore: 0.77,
    topicKey: `relationship:${conversationId || recipientId || lead.hashForDeduplication}`,
  };
}

function buildOpenLoopCandidate(signals: BereanPulseSignal[]): CandidateCard {
  const lead = signals[0];
  const payload = lead.entityType === "post" && lead.entityId ? { postId: lead.entityId } :
    lead.entityType === "conversation" && lead.entityId ? { conversationId: lead.entityId } :
    lead.entityType === "church" && lead.entityId ? { churchId: lead.entityId } :
    lead.entityType === "project" && lead.entityId ? { projectId: lead.entityId } : {};

  const actionType: PulseActionType =
    "postId" in payload ? "openPost" :
    "conversationId" in payload ? "draftMessage" :
    "churchId" in payload ? "openChurch" :
    "projectId" in payload ? "openProjectBrief" :
    "continueChat";

  return {
    mode: "openLoops",
    secondaryModes: ["work", "creative", "learning"],
    title: "Finish what is already pulling on you",
    subtitle: "Open loop resolution",
    insight: summarizeSignals(signals),
    expandedBody: buildExpandedBody(signals),
    recommendedActionTitle: Object.keys(payload).length > 0 ? "Resolve open loop" : "Explain in chat",
    actionType,
    actionPayload: (Object.keys(payload).length > 0 ? payload : { prompt: lead.summary, mode: "strategist" }) as Record<string, string>,
    primaryIntent: "openLoopResolution",
    sourceSignals: signals,
    permissionRequirements: [lead.source],
    privacyLevel: lead.sensitivity === "sensitive" ? "sensitive" : "personal",
    confidenceScore: 0.85,
    urgencyScore: scoreUrgency(signals) + 0.08,
    relevanceScore: 0.84,
    topicKey: `openLoop:${lead.hashForDeduplication}`,
  };
}

function buildWellnessCandidate(signals: BereanPulseSignal[]): CandidateCard {
  const lead = signals[0];
  const checkInId = lead.entityId ?? "";
  return {
    mode: "wellness",
    secondaryModes: ["spiritual"],
    title: "Pause for a quick check-in",
    subtitle: "Wellness check-in",
    insight: summarizeSignals(signals),
    expandedBody: buildExpandedBody(signals),
    recommendedActionTitle: checkInId ? "Open check-in" : "Check-in unavailable",
    actionType: "openWellnessCheckIn",
    actionPayload: checkInId ? { checkInId } : {},
    primaryIntent: "wellnessCheckIn",
    sourceSignals: signals,
    permissionRequirements: ["wellnessHealth"],
    privacyLevel: "personal",
    confidenceScore: 0.72,
    urgencyScore: scoreUrgency(signals),
    relevanceScore: 0.7,
    topicKey: `wellness:${checkInId || lead.hashForDeduplication}`,
  };
}

function finalizeCandidate(
  candidate: CandidateCard,
  userId: string,
  dateKey: string,
  now: admin.firestore.Timestamp,
  preferredModes: Set<PulseCardMode>,
  feedback: ReturnType<typeof feedbackAdjustments>
): BereanPulseCardRecord | null {
  const lead = candidate.sourceSignals[0];
  const whyNowEvidence = candidate.sourceSignals.map((signal) => signal.summary).slice(0, 3);
  const whyNow = whyNowEvidence.length > 0
    ? `Why now: ${whyNowEvidence.join(" ")}`
    : "Why now: Berean found a timely next step from your recent AMEN activity.";

  let matchScore = clamp01(
    candidate.confidenceScore * 0.34 +
    candidate.urgencyScore * 0.33 +
    candidate.relevanceScore * 0.33 +
    (preferredModes.has(candidate.mode) ? 0.08 : 0) +
    (feedback.likedTopics.has(candidate.topicKey) ? 0.1 : 0) -
    (feedback.dislikedTopics.has(candidate.topicKey) ? 0.16 : 0) -
    (feedback.hiddenTopics.has(candidate.topicKey) ? 0.28 : 0)
  );

  if (feedback.hiddenTopics.has(candidate.topicKey)) {
    return null;
  }

  if (candidate.recommendedActionTitle.startsWith("Action unavailable") ||
      candidate.recommendedActionTitle.includes("unavailable")) {
    matchScore = Math.min(matchScore, 0.45);
  }

  return {
    id: `${candidate.mode}_${lead.id}`,
    userId,
    dateKey,
    mode: candidate.mode,
    secondaryModes: candidate.secondaryModes,
    title: candidate.title,
    subtitle: candidate.subtitle,
    whyNow,
    whyNowEvidence,
    insight: candidate.insight,
    expandedBody: candidate.expandedBody,
    recommendedActionTitle: candidate.recommendedActionTitle,
    actionType: candidate.actionType,
    actionPayload: candidate.actionPayload,
    primaryIntent: candidate.primaryIntent,
    sourceSignalIds: candidate.sourceSignals.map((signal) => signal.id),
    confidenceScore: clamp01(candidate.confidenceScore),
    urgencyScore: clamp01(candidate.urgencyScore),
    relevanceScore: clamp01(candidate.relevanceScore),
    matchScore,
    sourceSignals: candidate.sourceSignals,
    permissionRequirements: Array.from(new Set(candidate.permissionRequirements)),
    privacyLevel: candidate.privacyLevel,
    createdAt: now,
    updatedAt: now,
    expiresAt: admin.firestore.Timestamp.fromMillis(now.toMillis() + 86_400_000),
    isSaved: false,
    isHidden: false,
    feedbackState: "neutral",
  };
}

function summarizeSignals(signals: BereanPulseSignal[]): string {
  return signals.map((signal) => signal.title).slice(0, 2).join(" + ");
}

function buildExpandedBody(signals: BereanPulseSignal[]): string {
  return signals
    .map((signal) => signal.summary)
    .filter(Boolean)
    .join(" ");
}

function scoreUrgency(signals: BereanPulseSignal[]): number {
  const newest = signals[0]?.timestamp.toMillis() ?? Date.now();
  const ageHours = Math.max(1, (Date.now() - newest) / 3_600_000);
  const openLoopBias = signals.some((signal) => signal.metadata?.openLoop === "true") ? 0.16 : 0;
  return clamp01((1 / ageHours) + openLoopBias + 0.42);
}

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

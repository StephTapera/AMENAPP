import { defineBoolean } from "firebase-functions/params";
import { HttpsError, CallableRequest } from "firebase-functions/v2/https";

export const MOMENT_REGION = "us-east1";

export type MomentType =
  | "prayer"
  | "scripture"
  | "sermon"
  | "event"
  | "creator"
  | "study"
  | "mission"
  | "thread";

export type TemporalState = "upcoming" | "live" | "recap" | "evergreen";

export type DeepenActionKind =
  | "summarize"
  | "crossReference"
  | "generatePrayer"
  | "generateStudyGuide"
  | "generateDiscussion"
  | "generateDevotional"
  | "saveTo";

export type BereanMode = "ask" | "discern" | "build";

export type SaveTarget =
  | "prayerJournal"
  | "studyJournal"
  | "churchNotes"
  | "sermonCollection"
  | "savedTeachings";

export interface Moment {
  id: string;
  type: MomentType;
  temporalState: TemporalState;
  refId: string;
  ownerId: string;
  createdAt: number;
}

export interface DeepenRequest {
  moment: Moment;
  action: DeepenActionKind;
  requesterId: string;
  bereanMode: BereanMode;
  saveTarget?: SaveTarget;
  locale?: string;
}

export interface DeepenResult {
  momentId: string;
  action: DeepenActionKind;
  output: string;
  citations: string[];
  savedTo?: SaveTarget;
  guardian: {
    passed: boolean;
    policyVersion: string;
    reason?: string;
  };
  createdAt: number;
}

interface MomentDeepenAdapter {
  runMomentDeepen(request: DeepenRequest, dependencies: MomentDeepenDependencies): Promise<DeepenResult>;
}

type MomentDeepenDependencies = Record<string, unknown>;

const momentSystemEnabled = defineBoolean("moment_system_enabled", { default: false });
const deepenActionsEnabled = defineBoolean("deepen_actions_enabled", { default: false });
let momentDeepenDependencies: MomentDeepenDependencies | undefined;

const validMomentTypes = new Set<MomentType>([
  "prayer",
  "scripture",
  "sermon",
  "event",
  "creator",
  "study",
  "mission",
  "thread",
]);

const validTemporalStates = new Set<TemporalState>(["upcoming", "live", "recap", "evergreen"]);
const validBereanModes = new Set<BereanMode>(["ask", "discern", "build"]);
const validSaveTargets = new Set<SaveTarget>([
  "prayerJournal",
  "studyJournal",
  "churchNotes",
  "sermonCollection",
  "savedTeachings",
]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function parseMoment(value: unknown): Moment {
  if (!isRecord(value)) {
    throw new HttpsError("invalid-argument", "moment is required.");
  }

  const { id, type, temporalState, refId, ownerId, createdAt } = value;
  if (typeof id !== "string" || !id.trim()) {
    throw new HttpsError("invalid-argument", "moment.id is required.");
  }
  if (typeof type !== "string" || !validMomentTypes.has(type as MomentType)) {
    throw new HttpsError("invalid-argument", "moment.type is invalid.");
  }
  if (typeof temporalState !== "string" || !validTemporalStates.has(temporalState as TemporalState)) {
    throw new HttpsError("invalid-argument", "moment.temporalState is invalid.");
  }
  if (typeof refId !== "string" || !refId.trim()) {
    throw new HttpsError("invalid-argument", "moment.refId is required.");
  }
  if (typeof ownerId !== "string" || !ownerId.trim()) {
    throw new HttpsError("invalid-argument", "moment.ownerId is required.");
  }
  if (typeof createdAt !== "number" || !Number.isFinite(createdAt)) {
    throw new HttpsError("invalid-argument", "moment.createdAt is required.");
  }

  return {
    id,
    type: type as MomentType,
    temporalState: temporalState as TemporalState,
    refId,
    ownerId,
    createdAt,
  };
}

function parseDeepenRequest(request: CallableRequest<unknown>, action: DeepenActionKind): DeepenRequest {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  if (!isRecord(request.data)) {
    throw new HttpsError("invalid-argument", "request body is required.");
  }

  const moment = parseMoment(request.data.moment);
  const requesterId = typeof request.data.requesterId === "string" && request.data.requesterId.trim()
    ? request.data.requesterId
    : uid;

  if (requesterId !== uid) {
    throw new HttpsError("permission-denied", "requesterId must match the authenticated user.");
  }

  const bereanMode = typeof request.data.bereanMode === "string" && validBereanModes.has(request.data.bereanMode as BereanMode)
    ? request.data.bereanMode as BereanMode
    : "ask";

  const saveTarget = request.data.saveTarget;
  if (saveTarget !== undefined && (typeof saveTarget !== "string" || !validSaveTargets.has(saveTarget as SaveTarget))) {
    throw new HttpsError("invalid-argument", "saveTarget is invalid.");
  }

  const locale = request.data.locale;
  if (locale !== undefined && typeof locale !== "string") {
    throw new HttpsError("invalid-argument", "locale must be a string.");
  }

  return {
    moment,
    action,
    requesterId,
    bereanMode,
    saveTarget: saveTarget as SaveTarget | undefined,
    locale: locale as string | undefined,
  };
}

function disabledDeepenResult(request: DeepenRequest): DeepenResult {
  return {
    momentId: request.moment.id,
    action: request.action,
    output: "",
    citations: [],
    savedTo: request.action === "saveTo" ? request.saveTarget : undefined,
    guardian: {
      passed: false,
      policyVersion: "moment-v1",
      reason: "flagDisabled",
    },
    createdAt: Date.now(),
  };
}

function adapterFromModule(moduleExports: unknown): MomentDeepenAdapter | undefined {
  if (!isRecord(moduleExports)) {
    return undefined;
  }

  const adapter = moduleExports.momentAdapter;
  if (isRecord(adapter) && typeof adapter.runMomentDeepen === "function") {
    return adapter as unknown as MomentDeepenAdapter;
  }

  if (typeof moduleExports.runMomentDeepen === "function") {
    return { runMomentDeepen: moduleExports.runMomentDeepen as MomentDeepenAdapter["runMomentDeepen"] };
  }

  return undefined;
}

function loadMomentAdapter(): MomentDeepenAdapter | undefined {
  try {
    // A3 owns this module. Keep only the narrow call expectation here.
    return adapterFromModule(require("../../berean/momentAdapter"));
  } catch (error) {
    const code = isRecord(error) ? error.code : undefined;
    if (code === "MODULE_NOT_FOUND") {
      return undefined;
    }
    throw error;
  }
}

export function makeDeepenHandler(action: DeepenActionKind) {
  return async (callableRequest: CallableRequest<unknown>): Promise<DeepenResult> => {
    const deepenRequest = parseDeepenRequest(callableRequest, action);

    if (!momentSystemEnabled.value() || !deepenActionsEnabled.value()) {
      return disabledDeepenResult(deepenRequest);
    }

    const adapter = loadMomentAdapter();
    if (!adapter) {
      throw new HttpsError("failed-precondition", "Moment Deepen adapter is not available.");
    }

    if (!momentDeepenDependencies) {
      throw new HttpsError("failed-precondition", "Moment Deepen dependencies are not wired.");
    }

    try {
      return await adapter.runMomentDeepen(deepenRequest, momentDeepenDependencies);
    } catch (error) {
      throw mapMomentAdapterError(error);
    }
  };
}

export function configureMomentDeepenDependencies(dependencies: MomentDeepenDependencies): void {
  momentDeepenDependencies = dependencies;
}

function mapMomentAdapterError(error: unknown): HttpsError {
  if (error instanceof HttpsError) {
    return error;
  }

  if (isRecord(error)) {
    const code = error.code;
    const message = typeof error.message === "string" ? error.message : "Moment Deepen adapter failed.";

    if (code === "moment-adapter/invalid-request") {
      return new HttpsError("invalid-argument", message);
    }
    if (code === "moment-adapter/dependency-required") {
      return new HttpsError("failed-precondition", message);
    }
    if (code === "moment-adapter/guardian-blocked") {
      return new HttpsError("failed-precondition", message);
    }
  }

  return new HttpsError("internal", "Moment Deepen adapter failed.");
}

import { selectMomentDeepenRoute } from "./actionRouting";
import {
  MomentAdapterDependencyError,
  MomentAdapterGuardError,
  MomentAdapterValidationError,
} from "./errors";
import {
  LivingMemoryHit,
  MomentDeepenDependencies,
  MomentDeepenRequest,
  MomentDeepenResult,
  MomentSaveTarget,
} from "./types";

const validActions = new Set([
  "summarize",
  "crossReference",
  "generatePrayer",
  "generateStudyGuide",
  "generateDiscussion",
  "generateDevotional",
  "saveTo",
]);

const validSaveTargets = new Set<MomentSaveTarget>([
  "prayerJournal",
  "studyJournal",
  "churchNotes",
  "sermonCollection",
  "savedTeachings",
]);

export async function runMomentDeepen(
  request: MomentDeepenRequest,
  dependencies: MomentDeepenDependencies,
): Promise<MomentDeepenResult> {
  validateRequest(request);
  validateDependencies(request, dependencies);

  const route = selectMomentDeepenRoute(request);
  const livingMemory = await resolveLivingMemory(request, dependencies, route.requiresLivingMemory);

  const bereanDraft = await dependencies.berean.run({
    request,
    route,
    livingMemory,
  });

  const constitutional = await dependencies.constitutionalIntelligence.review({
    request,
    route,
    draft: bereanDraft,
  });

  const guardian = await dependencies.guardianAegis.review({
    request,
    route,
    constitutional,
  });

  if (!guardian.passed) {
    throw new MomentAdapterGuardError(request.action, guardian);
  }

  const result: MomentDeepenResult = {
    momentId: request.moment.id,
    action: request.action,
    output: constitutional.output,
    citations: constitutional.citations,
    savedTo: request.action === "saveTo" ? request.saveTarget : undefined,
    guardian,
    createdAt: dependencies.now?.() ?? Date.now(),
  };

  if (request.action === "saveTo") {
    await dependencies.save?.save({ request, result });
  }

  return result;
}

function validateRequest(request: MomentDeepenRequest): void {
  if (!request || typeof request !== "object") {
    throw new MomentAdapterValidationError("Moment Deepen request is required.");
  }
  if (!request.moment?.id) {
    throw new MomentAdapterValidationError("moment.id is required.");
  }
  if (!request.requesterId) {
    throw new MomentAdapterValidationError("requesterId is required.");
  }
  if (!validActions.has(request.action)) {
    throw new MomentAdapterValidationError(`Unsupported Moment Deepen action: ${request.action}`);
  }
  if (request.action === "saveTo") {
    if (!request.saveTarget || !validSaveTargets.has(request.saveTarget)) {
      throw new MomentAdapterValidationError("saveTarget is required for saveTo.");
    }
  }
}

function validateDependencies(
  request: MomentDeepenRequest,
  dependencies: MomentDeepenDependencies,
): void {
  if (!dependencies?.berean) {
    throw new MomentAdapterDependencyError("berean", request.action);
  }
  if (!dependencies.constitutionalIntelligence) {
    throw new MomentAdapterDependencyError("constitutionalIntelligence", request.action);
  }
  if (!dependencies.guardianAegis) {
    throw new MomentAdapterDependencyError("guardianAegis", request.action);
  }
  if (request.action === "saveTo" && !dependencies.save) {
    throw new MomentAdapterDependencyError("save", request.action);
  }
}

async function resolveLivingMemory(
  request: MomentDeepenRequest,
  dependencies: MomentDeepenDependencies,
  required: boolean,
): Promise<LivingMemoryHit[]> {
  if (!required) {
    return [];
  }
  if (!dependencies.livingMemory) {
    throw new MomentAdapterDependencyError(
      "livingMemory",
      request.action,
      "crossReference requires a Living Memory/Pinecone adapter dependency.",
    );
  }

  return dependencies.livingMemory.crossReference({
    requesterId: request.requesterId,
    moment: request.moment,
    action: "crossReference",
    locale: request.locale,
  });
}

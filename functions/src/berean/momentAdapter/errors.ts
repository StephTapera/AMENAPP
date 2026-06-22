import {
  MomentAdapterDependency,
  MomentDeepenAction,
  MomentGuardianReview,
} from "./types";

export class MomentAdapterDependencyError extends Error {
  readonly code = "moment-adapter/dependency-required";
  readonly dependency: MomentAdapterDependency;
  readonly action: MomentDeepenAction;

  constructor(dependency: MomentAdapterDependency, action: MomentDeepenAction, message?: string) {
    super(message ?? `Moment Deepen action ${action} requires ${dependency}.`);
    this.name = "MomentAdapterDependencyError";
    this.dependency = dependency;
    this.action = action;
  }
}

export class MomentAdapterGuardError extends Error {
  readonly code = "moment-adapter/guardian-blocked";
  readonly guardian: MomentGuardianReview;
  readonly action: MomentDeepenAction;

  constructor(action: MomentDeepenAction, guardian: MomentGuardianReview) {
    super(guardian.reason ?? `Moment Deepen action ${action} was blocked by GUARDIAN/Aegis.`);
    this.name = "MomentAdapterGuardError";
    this.guardian = guardian;
    this.action = action;
  }
}

export class MomentAdapterValidationError extends Error {
  readonly code = "moment-adapter/invalid-request";

  constructor(message: string) {
    super(message);
    this.name = "MomentAdapterValidationError";
  }
}

"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MomentAdapterValidationError = exports.MomentAdapterGuardError = exports.MomentAdapterDependencyError = void 0;
class MomentAdapterDependencyError extends Error {
    code = "moment-adapter/dependency-required";
    dependency;
    action;
    constructor(dependency, action, message) {
        super(message ?? `Moment Deepen action ${action} requires ${dependency}.`);
        this.name = "MomentAdapterDependencyError";
        this.dependency = dependency;
        this.action = action;
    }
}
exports.MomentAdapterDependencyError = MomentAdapterDependencyError;
class MomentAdapterGuardError extends Error {
    code = "moment-adapter/guardian-blocked";
    guardian;
    action;
    constructor(action, guardian) {
        super(guardian.reason ?? `Moment Deepen action ${action} was blocked by GUARDIAN/Aegis.`);
        this.name = "MomentAdapterGuardError";
        this.guardian = guardian;
        this.action = action;
    }
}
exports.MomentAdapterGuardError = MomentAdapterGuardError;
class MomentAdapterValidationError extends Error {
    code = "moment-adapter/invalid-request";
    constructor(message) {
        super(message);
        this.name = "MomentAdapterValidationError";
    }
}
exports.MomentAdapterValidationError = MomentAdapterValidationError;

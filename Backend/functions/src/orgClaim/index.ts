/**
 * orgClaim/index.ts
 *
 * Barrel export for all Organization Claim Cloud Functions.
 * Imported by Backend/functions/src/index.ts.
 *
 * Exported callables:
 *   requestOrgClaim  — submit a claim (authenticated users)
 *   approveClaim     — approve a pending claim (admin only)
 *   rejectClaim      — reject a pending claim (admin only)
 *   createOrgStub    — create a new org listing and immediately claim it
 */

export { requestOrgClaim } from "./requestOrgClaim";
export { approveClaim }    from "./approveClaim";
export { rejectClaim }     from "./rejectClaim";
export { createOrgStub }   from "./createOrgStub";

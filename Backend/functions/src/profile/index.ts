/**
 * profile/index.ts
 *
 * Barrel export for all Profile Header v2 Cloud Functions.
 *
 * Exports:
 *   getProfileHeaderPayload   — fetch full profile header payload for any user
 *   updatePinSlots            — owner: set up to 3 pinned post IDs
 *   inferUserRoles            — admin/owner: compute and persist roleFlags
 *   scheduledInferRoles       — daily scheduled sweep of all users' roleFlags
 *   assembleBereanAboutContext — assemble Berean AI context for opted-in profiles
 */

export { getProfileHeaderPayload } from "./getProfileHeaderPayload";
export { updatePinSlots } from "./updatePinSlots";
export { inferUserRoles, scheduledInferRoles } from "./inferUserRoles";
export { assembleBereanAboutContext } from "./assembleBereanAboutContext";

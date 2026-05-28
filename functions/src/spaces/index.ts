// index.ts
// AMEN Spaces — Cloud Functions Module Exports
//
// Re-exports all Spaces Cloud Functions for registration in functions/index.js.
// Agent A owns: grantSpaceAccess, handleStripeSpaceWebhook, revokeSpaceLinkAccess
// Agent E owns: createSpaceCheckoutSession, createStripeConnectAccount

export { grantSpaceAccess } from "./grantSpaceAccess";
export { handleStripeSpaceWebhook } from "./stripeWebhookEntitlement";
export { revokeSpaceLinkAccess } from "./revokeSpaceLinkAccess";
export { createSpaceCheckoutSession } from "./createSpaceCheckoutSession";
export { createStripeConnectAccount } from "./createStripeConnectAccount";
// Agent F: cross-community link invite notification trigger
export { notifyCommunityLinkInvite } from "./notifyCommunityLinkInvite";
// Agent D: Berean AI scaffolding for Space creation wizard
export { scaffoldSpaceWithBerean } from "./scaffoldSpaceWithBerean";

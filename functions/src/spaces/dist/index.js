"use strict";
// index.ts
// AMEN Spaces — Cloud Functions Module Exports
//
// Re-exports all Spaces Cloud Functions for registration in functions/index.js.
// Agent A owns: grantSpaceAccess, handleStripeSpaceWebhook, revokeSpaceLinkAccess
// Agent E owns: createSpaceCheckoutSession, createStripeConnectAccount
Object.defineProperty(exports, "__esModule", { value: true });
exports.scaffoldSpaceWithBerean = exports.notifyCommunityLinkInvite = exports.createStripeConnectAccount = exports.createSpaceCheckoutSession = exports.revokeSpaceLinkAccess = exports.handleStripeSpaceWebhook = exports.grantSpaceAccess = void 0;
var grantSpaceAccess_1 = require("./grantSpaceAccess");
Object.defineProperty(exports, "grantSpaceAccess", { enumerable: true, get: function () { return grantSpaceAccess_1.grantSpaceAccess; } });
var stripeWebhookEntitlement_1 = require("./stripeWebhookEntitlement");
Object.defineProperty(exports, "handleStripeSpaceWebhook", { enumerable: true, get: function () { return stripeWebhookEntitlement_1.handleStripeSpaceWebhook; } });
var revokeSpaceLinkAccess_1 = require("./revokeSpaceLinkAccess");
Object.defineProperty(exports, "revokeSpaceLinkAccess", { enumerable: true, get: function () { return revokeSpaceLinkAccess_1.revokeSpaceLinkAccess; } });
var createSpaceCheckoutSession_1 = require("./createSpaceCheckoutSession");
Object.defineProperty(exports, "createSpaceCheckoutSession", { enumerable: true, get: function () { return createSpaceCheckoutSession_1.createSpaceCheckoutSession; } });
var createStripeConnectAccount_1 = require("./createStripeConnectAccount");
Object.defineProperty(exports, "createStripeConnectAccount", { enumerable: true, get: function () { return createStripeConnectAccount_1.createStripeConnectAccount; } });
// Agent F: cross-community link invite notification trigger
var notifyCommunityLinkInvite_1 = require("./notifyCommunityLinkInvite");
Object.defineProperty(exports, "notifyCommunityLinkInvite", { enumerable: true, get: function () { return notifyCommunityLinkInvite_1.notifyCommunityLinkInvite; } });
// Agent D: Berean AI scaffolding for Space creation wizard
var scaffoldSpaceWithBerean_1 = require("./scaffoldSpaceWithBerean");
Object.defineProperty(exports, "scaffoldSpaceWithBerean", { enumerable: true, get: function () { return scaffoldSpaceWithBerean_1.scaffoldSpaceWithBerean; } });

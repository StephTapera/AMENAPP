"use strict";
// index.ts — Find a Church v2 module exports (callables, us-east1).
//
// Wired into the root functions/index.js via `require("./lib/church")` after
// `npm run build:church`. Deploy per-function only (never bare):
//   firebase deploy --only functions:assembleChurchDiscovery
//   firebase deploy --only functions:searchChurches
//   firebase deploy --only functions:getChurchProfile
//   firebase deploy --only functions:toggleSavedChurch
//   firebase deploy --only functions:recordChurchSearch
//   firebase deploy --only functions:planVisit
//   firebase deploy --only functions:reportChurch
//   firebase deploy --only functions:requestChurchVerification
//   firebase deploy --only functions:submitChurchClaim
Object.defineProperty(exports, "__esModule", { value: true });
exports.submitChurchClaim = exports.requestChurchVerification = exports.reportChurch = exports.planVisit = exports.recordChurchSearch = exports.toggleSavedChurch = exports.getChurchProfile = exports.searchChurches = exports.assembleChurchDiscovery = void 0;
var callable_1 = require("./callable");
Object.defineProperty(exports, "assembleChurchDiscovery", { enumerable: true, get: function () { return callable_1.assembleChurchDiscovery; } });
Object.defineProperty(exports, "searchChurches", { enumerable: true, get: function () { return callable_1.searchChurches; } });
Object.defineProperty(exports, "getChurchProfile", { enumerable: true, get: function () { return callable_1.getChurchProfile; } });
Object.defineProperty(exports, "toggleSavedChurch", { enumerable: true, get: function () { return callable_1.toggleSavedChurch; } });
Object.defineProperty(exports, "recordChurchSearch", { enumerable: true, get: function () { return callable_1.recordChurchSearch; } });
Object.defineProperty(exports, "planVisit", { enumerable: true, get: function () { return callable_1.planVisit; } });
Object.defineProperty(exports, "reportChurch", { enumerable: true, get: function () { return callable_1.reportChurch; } });
Object.defineProperty(exports, "requestChurchVerification", { enumerable: true, get: function () { return callable_1.requestChurchVerification; } });
Object.defineProperty(exports, "submitChurchClaim", { enumerable: true, get: function () { return callable_1.submitChurchClaim; } });

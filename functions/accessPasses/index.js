"use strict";
// accessPasses/index.ts — Export all Access Pass callable functions
Object.defineProperty(exports, "__esModule", { value: true });
exports.listAccessRequestsForTarget = exports.listAccessPassesForTarget = exports.denyAccessRequest = exports.approveAccessRequest = exports.rotateAccessPassToken = exports.resumeAccessPass = exports.pauseAccessPass = exports.revokeAccessPass = exports.acceptAccessPass = exports.resolveAccessPass = exports.createAccessPass = void 0;
var accessPassFunctions_1 = require("./accessPassFunctions");
Object.defineProperty(exports, "createAccessPass", { enumerable: true, get: function () { return accessPassFunctions_1.createAccessPass; } });
Object.defineProperty(exports, "resolveAccessPass", { enumerable: true, get: function () { return accessPassFunctions_1.resolveAccessPass; } });
Object.defineProperty(exports, "acceptAccessPass", { enumerable: true, get: function () { return accessPassFunctions_1.acceptAccessPass; } });
Object.defineProperty(exports, "revokeAccessPass", { enumerable: true, get: function () { return accessPassFunctions_1.revokeAccessPass; } });
Object.defineProperty(exports, "pauseAccessPass", { enumerable: true, get: function () { return accessPassFunctions_1.pauseAccessPass; } });
Object.defineProperty(exports, "resumeAccessPass", { enumerable: true, get: function () { return accessPassFunctions_1.resumeAccessPass; } });
Object.defineProperty(exports, "rotateAccessPassToken", { enumerable: true, get: function () { return accessPassFunctions_1.rotateAccessPassToken; } });
Object.defineProperty(exports, "approveAccessRequest", { enumerable: true, get: function () { return accessPassFunctions_1.approveAccessRequest; } });
Object.defineProperty(exports, "denyAccessRequest", { enumerable: true, get: function () { return accessPassFunctions_1.denyAccessRequest; } });
Object.defineProperty(exports, "listAccessPassesForTarget", { enumerable: true, get: function () { return accessPassFunctions_1.listAccessPassesForTarget; } });
Object.defineProperty(exports, "listAccessRequestsForTarget", { enumerable: true, get: function () { return accessPassFunctions_1.listAccessRequestsForTarget; } });
//# sourceMappingURL=index.js.map
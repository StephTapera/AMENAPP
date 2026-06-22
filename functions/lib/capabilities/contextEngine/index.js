"use strict";
// contextEngine/index.ts — Context Engine module exports (Wave 1: Lane A)
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolveContextAccess = exports.contextEngine_getAuditLog = exports.contextEngine_setGrant = exports.contextEngine_getGrants = void 0;
var callables_1 = require("./callables");
Object.defineProperty(exports, "contextEngine_getGrants", { enumerable: true, get: function () { return callables_1.contextEngine_getGrants; } });
Object.defineProperty(exports, "contextEngine_setGrant", { enumerable: true, get: function () { return callables_1.contextEngine_setGrant; } });
Object.defineProperty(exports, "contextEngine_getAuditLog", { enumerable: true, get: function () { return callables_1.contextEngine_getAuditLog; } });
var resolveContextAccess_1 = require("./resolveContextAccess");
Object.defineProperty(exports, "resolveContextAccess", { enumerable: true, get: function () { return resolveContextAccess_1.resolveContextAccess; } });

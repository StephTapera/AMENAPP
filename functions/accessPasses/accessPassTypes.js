"use strict";
// accessPassTypes.ts — Amen Access Pass type definitions
Object.defineProperty(exports, "__esModule", { value: true });
exports.RESTRICTED_DIRECT_JOIN_TYPES = exports.SENSITIVE_TARGET_TYPES = void 0;
// Sensitive target types that default to Request mode
exports.SENSITIVE_TARGET_TYPES = [
    "prayerRoom",
    "smallGroup",
];
// Target types that never allow direct Join without explicit admin override
exports.RESTRICTED_DIRECT_JOIN_TYPES = [
    "prayerRoom",
];
//# sourceMappingURL=accessPassTypes.js.map